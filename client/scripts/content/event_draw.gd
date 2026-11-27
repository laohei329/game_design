class_name EventDraw
extends RefCounted
## 区段 onSegmentBuild 一次性抽卡（06 §2.3 薄实现）；已建段不重抽。
##
## @return 结果字典；缺失语义键时可能为空 {}。
static func draw_rules() -> Dictionary:
	return ConfigDb.get_table("event_draw_rules")


static func _rule_f(key: String) -> float:
	return float(ConfigDb.require("event_draw_rules." + key))


static func _rule_dict(key: String) -> Dictionary:
	var raw: Variant = ConfigDb.require("event_draw_rules." + key)
	return raw if typeof(raw) == TYPE_DICTIONARY else {}

## 新段掷天气并写入 segment。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param segment 区段 `Segment`
static func on_segment_build(state: RunState, segment: Segment) -> void:
	if not state.tutorial_done:
		return
	if segment == null or segment.event_id != "":
		return
	segment.event_id = draw_event_id(state, segment)
	if segment.event_id != "":
		EventService.try_open_new_segment_event(state)

## 加权抽卡；空池则随机一项。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param segment 区段 `Segment`
## @return 空串=成功；非空=机器错误码。
static func draw_event_id(state: RunState, segment: Segment = null) -> String:
	var pool: Array = EventCatalog.eligible_ids(state.season, state.year)
	if pool.is_empty():
		return ""
	var ctx := _build_ctx(state, segment)
	var weights: Dictionary = {}
	for eid in pool:
		var card := EventCatalog.get_card(str(eid))
		if card.is_empty():
			continue
		var w := _weight_for_card(card, ctx)
		if w > 0.0:
			weights[str(eid)] = w
	if weights.is_empty():
		return str(pool[RngService.randi() % pool.size()])
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var pick := RngService.randf() * total
	var acc := 0.0
	for eid in weights.keys():
		acc += float(weights[eid])
		if pick <= acc:
			return str(eid)
	return str(weights.keys()[0])

## 组装抽卡上下文：季节、区域、节点、`eventTagWeights`、难度 scenario 倍率等。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param segment 区段 `Segment`
## @return 结果字典；缺失语义键时可能为空 {}。
static func _build_ctx(state: RunState, segment: Segment = null) -> Dictionary:
	var onboard := TrainService.onboard_count(state)
	var fpc := _rule_f("foodNeedPerCapita")
	var wpc := _rule_f("waterNeedPerCapita")
	var tag_weights := {}
	var raid_delta := 0.0
	var seg_ref: Segment = segment
	if seg_ref == null and state.region_run:
		seg_ref = state.region_run.active_segment()
	if seg_ref != null:
		tag_weights = seg_ref.event_tag_weights.duplicate()
		raid_delta = seg_ref.raid_weight_delta
	return {
		"scenario_event_rate": scenario_event_rate(),
		"food": state.food,
		"water": state.water,
		"food_need": float(onboard) * fpc,
		"water_need": float(onboard) * wpc,
		"onboard": onboard,
		"beds": TrainService.bed_count(state),
		"fuel": state.fuel,
		"fuel_cap": maxf(state.fuel_cap(), 1.0),
		"event_tag_weights": tag_weights,
		"raid_weight_delta": raid_delta,
		"recent_weight_event_ids": state.event_weight_history.duplicate(),
		"last_segment_primary_tag": state.last_event_primary_tag,
		"region_id": state.region_run.region_id if state.region_run else "urban",
		"forced_low_content": _forced_low_content(state),
		"has_pharmacist_on_duty": MemberRoster.staff_on_duty(state, "pharmacist"),
		"has_guard_on_duty": MemberRoster.staff_on_duty(state, "guard"),
		"has_unclaimed_loot": _has_unclaimed_loot(state, seg_ref),
	}


## `balance.eventDraw.scenarioEventRate` × 当前难度 `eventDrawRate`。
##
## @return 浮点结果（量/比率/工时）。
static func scenario_event_rate() -> float:
	var base := float(ConfigDb.require("balance.eventDraw.scenarioEventRate"))
	var tier_id := str(ConfigDb.require("difficulty.defaultId"))
	base *= float(ConfigDb.require("difficulty.tiers.%s.multipliers.eventDrawRate" % tier_id))
	return base

## 单卡最终权重：基础 × 标签重复惩罚 × 段内 `eventTagWeights` 修正。
##
## @param card 事件卡 JSON（EventCatalog）
## @param ctx EventDraw 抽卡上下文
## @return 浮点结果（量/比率/工时）。
static func _weight_for_card(card: Dictionary, ctx: Dictionary) -> float:
	if not card.has("weight") or not card.has("yieldScale"):
		push_error("EventDraw: card missing weight or yieldScale")
		return 0.0
	var w := float(card["weight"]) * float(card["yieldScale"]) * float(ctx.get("scenario_event_rate", 1.0))
	var tags: Array = []
	for t in card.get("tags", []):
		tags.append(str(t))
	var ptag := EventCatalog.primary_tag(card)

	if tags.has("supply"):
		if float(ctx.get("food", 0)) < float(ctx.get("food_need", 0)):
			w += _rule_f("supplyFoodBoost")
		if float(ctx.get("water", 0)) < float(ctx.get("water_need", 0)):
			w += _rule_f("supplyWaterBoost")

	if tags.has("recruit"):
		var beds: int = int(ctx.get("beds", 0))
		var onboard: int = int(ctx.get("onboard", 0))
		if onboard >= beds and beds > 0:
			w *= _rule_f("recruitBedsFullMult")
		else:
			w *= _rule_f("recruitHasBedsMult")
		if float(ctx.get("food", 0)) < float(ctx.get("food_need", 0)) and onboard < beds:
			w *= _rule_f("recruitLowFoodMult")

	var tag_weights: Dictionary = ctx.get("event_tag_weights", {})
	for t in tags:
		if str(t) == "raid":
			continue
		w += float(tag_weights.get(str(t), 0.0))

	var raid_tags: Array = ConfigDb.require("event_draw_rules.raidDeltaTags")
	var raid_hit := false
	for rt in raid_tags:
		if tags.has(str(rt)):
			raid_hit = true
			break
	if raid_hit:
		w += float(ctx.get("raid_weight_delta", 0.0))
		if bool(ctx.get("has_unclaimed_loot", false)):
			w += _rule_f("unclaimedLootRaidBoost")
		if bool(ctx.get("has_guard_on_duty", false)):
			w *= _rule_f("guardOnDutyRaidMult")

	if tags.has("mood") and w > 0.0:
		w *= _rule_f("moodTagDampenMult")

	var pharma: Dictionary = _rule_dict("pharmacistOnDutyTagBoost")
	if (
		bool(ctx.get("has_pharmacist_on_duty", false))
		and str(ctx.get("region_id", "")) == str(pharma["regionOnly"])
	):
		var boost_tags: Array = pharma.get("tags", [])
		for bt in boost_tags:
			if tags.has(str(bt)):
				w += float(pharma["delta"])
				break

	if bool(ctx.get("forced_low_content", false)):
		var flp: Dictionary = _rule_dict("forcedLowPressure")
		var boost_tags_f: Array = flp.get("boostTags", [])
		if ptag in boost_tags_f:
			w += float(flp["tagBoost"])
		var suppress: Dictionary = flp.get("suppressTagMult", {})
		for t in tags:
			if suppress.has(str(t)):
				w *= float(suppress[str(t)])

	var low_fuel: Dictionary = _rule_dict("lowFuelSupplyBoost")
	var fuel_cap: float = float(ctx.get("fuel_cap", 1.0))
	var fuel_fill := float(ctx.get("fuel", 0.0)) / fuel_cap if fuel_cap > 0.0 else 1.0
	if fuel_fill < float(low_fuel["fuelFillBelow"]):
		var lf_tags: Array = low_fuel["tags"]
		for lt in lf_tags:
			if tags.has(str(lt)):
				w += float(low_fuel["tagBoost"])
				break

	var wid := str(card.get("weightEventId", card.get("id", "")))
	var nr: Dictionary = _rule_dict("noRepeatWeightEventId")
	var window: int = int(nr["windowSegmentsInRun"])
	var recent: Array = ctx.get("recent_weight_event_ids", [])
	var tail: Array = []
	if recent.size() > 0:
		var from_i := maxi(0, recent.size() - window)
		for i in range(from_i, recent.size()):
			tail.append(recent[i])
	if wid in tail:
		w *= float(nr["weightMult"])

	var trp: Dictionary = _rule_dict("tagRepeatPenalty")
	if str(ctx.get("last_segment_primary_tag", "")) != "" and ptag == str(ctx.get("last_segment_primary_tag", "")):
		w *= float(trp["lastPrimaryTagMult"])

	return maxf(0.0, w)


static func _forced_low_content(state: RunState) -> bool:
	var ph := state.pressure_history
	if ph.size() < 2:
		return false
	return str(ph[0]) == "high" and str(ph[1]) == "high"


static func _has_unclaimed_loot(state: RunState, segment: Segment) -> bool:
	if segment == null:
		return false
	for pt in segment.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		if LootPileService.total_amount(pt) > 0.001:
			return true
	return false