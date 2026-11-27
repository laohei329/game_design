class_name EventOps
extends RefCounted

const _PopulationRules := preload("res://scripts/domain/population_rules.gd")
## 事件选项 `op` / `immediate` 结算（权威客户端；Python 对照 `sim/event_ops_sim.py`）；延迟入 `state.delayed_events`。
## 写 `RunState` 的权威：`choose_option` / `fire_delayed` / `apply_op` / `process_due_delayed_events`。


const KNOWN_OPS: PackedStringArray = [
	"grant_item",
	"grant_blueprint",
	"remove_item",
	"mood_delta",
	"grant_influence",
	"clear_influence",
	"spawn_threat",
	"weight_mod",
	"flag_set",
	"recruit_roll",
	"loot_halve",
]

## 结算选项 immediate/延迟 op；写 segment 事件态。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param event_id 事件卡 id
## @param option_id 事件选项 id
## @return 空串=成功；非空=机器错误码。
static func choose_option(state: RunState, event_id: String, option_id: String) -> String:
	if event_id.is_empty() or option_id.is_empty():
		return "missing_choice"
	var card := EventCatalog.get_card(event_id)
	if card.is_empty():
		return "unknown_event"
	var option: Dictionary = {}
	for raw in card.get("options", []):
		if typeof(raw) == TYPE_DICTIONARY and str(raw.get("id", "")) == option_id:
			option = raw
			break
	if option.is_empty():
		return "unknown_option"
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null:
		return "no_segment"
	if seg.event_resolved or seg.event_option_id != "":
		state.event_modal_open = false
		return "already_resolved"

	var imm: Variant = option.get("immediate", {})
	if typeof(imm) == TYPE_DICTIONARY and imm.has("op"):
		var r := apply_op(
			state,
			imm,
			str(imm.get("targetType", option.get("targetType", "global"))),
			seg,
			event_id,
			option_id
		)
		if r != "" and r != "combat_opened" and r != "delayed_target_skip":
			return r

	var delay_days := int(option.get("delayDays", 0))
	var late_op := str(option.get("op", ""))
	if delay_days > 0 and late_op != "":
		_queue_delayed(state, delay_days, late_op, option, seg, event_id, option_id)
	elif late_op != "" and not imm.has("op"):
		var r2 := apply_op(
			state,
			{"op": late_op, "args": option.get("args", {})},
			str(option.get("targetType", "global")),
			seg,
			event_id,
			option_id
		)
		if r2 != "" and r2 != "combat_opened" and r2 != "delayed_target_skip":
			return r2

	seg.event_resolved = true
	seg.event_option_id = option_id
	_push_draw_history(state, card)
	state.event_modal_open = false
	TelemetryService.record(
		"event_choice",
		{"eventId": event_id, "optionId": option_id, "dayTotal": state.day_total}
	)
	return ""


## 日结步骤 −1：触发 `fireOnDay==next_day`，同 `sourceEventId+fireOnDay` 去重（09 §3）。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param fire_on_day（int）
static func process_due_delayed_events(state: RunState, fire_on_day: int) -> void:
	var keep: Array = []
	var fired: Dictionary = {}
	for ev in state.delayed_events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var fire := int(ev.get("fireOnDay", -1))
		if fire != fire_on_day:
			keep.append(ev)
			continue
		var eid := str(ev.get("sourceEventId", ""))
		var dedupe := "%s@%d" % [eid, fire_on_day]
		if fired.has(dedupe):
			TelemetryService.record("event_delayed_duplicate_skip", {"key": dedupe})
			continue
		fired[dedupe] = true
		fire_delayed(state, ev)
	state.delayed_events = keep

## 执行单条 delayedEvents 行（段解析后 apply_op）。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param entry delayed_events 单行
static func fire_delayed(state: RunState, entry: Dictionary) -> void:
	var seg_id := str(entry.get("segmentId", ""))
	var seg := _segment_in_run(state, seg_id)
	if seg == null and seg_id != "" and _needs_segment(str(entry.get("op", ""))):
		TelemetryService.record("event_delayed_segment_skip", {"segmentId": seg_id, "op": entry.get("op", "")})
		return
	if seg == null:
		seg = _resolve_segment(state, seg_id)
	apply_op(
		state,
		entry,
		str(entry.get("targetType", "global")),
		seg,
		str(entry.get("sourceEventId", "")),
		str(entry.get("sourceOptionId", ""))
	)

## 延迟 op 是否必须绑定具体 `segmentId`（spawn_threat / weight_mod / loot_halve）。
##
## @param op（String）
## @return 是否成功或条件成立。
static func _needs_segment(op: String) -> bool:
	return op in ["spawn_threat", "weight_mod", "loot_halve"]

## 单步事件 op；返回空=成功，否则机器码。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param op_row 事件 op 行（含 op/args/target）
## @param target_type（String）
## @param seg 当前区段 `Segment`
## @param source_event（String）
## @param _source_option（String）
## @return 空串=成功；非空=机器错误码。
static func apply_op(
	state: RunState,
	op_row: Dictionary,
	target_type: String,
	seg: Segment,
	source_event: String,
	_source_option: String
) -> String:
	var op := str(op_row.get("op", ""))
	if op == "":
		return ""
	var args: Dictionary = op_row.get("args", {}) if typeof(op_row.get("args", {})) == TYPE_DICTIONARY else {}
	var target_id := str(op_row.get("targetId", ""))
	var capture := str(op_row.get("capture", "live"))
	match op:
		"grant_item":
			var res := InventoryService.normalize_key(str(args.get("res", "")))
			var amt := float(args.get("amount", 0))
			if res == "" or amt <= 0.0:
				return "bad_grant"
			InventoryService.add(state, res, amt)
			return ""
		"grant_blueprint":
			var line := str(args.get("line", ""))
			if line == "":
				return "bad_blueprint"
			if TechService.grant_blueprint(state, line):
				return ""
			return "bad_blueprint"
		"remove_item":
			var res2 := InventoryService.normalize_key(str(args.get("res", "")))
			var amt2 := float(args.get("amount", 0))
			if res2 == "" or amt2 <= 0.0:
				return "bad_remove"
			InventoryService.remove(state, res2, amt2)
			return ""
		"mood_delta":
			if target_type == "party":
				return _apply_mood_party(state, args)
			return _apply_mood_delta(state, args, target_type, target_id)
		"grant_influence":
			var inf: Dictionary = args.duplicate(true)
			inf["source"] = str(inf.get("source", "event"))
			if inf.get("id", "") == "":
				inf["id"] = "event.%s.%s" % [source_event, str(Time.get_ticks_usec() % 100000)]
			state.climate_influences.append(inf)
			ClimateService.refresh(state)
			TelemetryService.record("event_grant_influence", {"id": inf.get("id", "")})
			return ""
		"clear_influence":
			var iid := str(args.get("id", target_id))
			if iid == "":
				return ""
			var before := state.climate_influences.size()
			var kept: Array = []
			for raw in state.climate_influences:
				if typeof(raw) != TYPE_DICTIONARY:
					continue
				if str(raw.get("id", "")) != iid:
					kept.append(raw)
			state.climate_influences = kept
			if kept.size() != before:
				ClimateService.refresh(state)
			return ""
		"spawn_threat":
			var want_seg := str(op_row.get("segmentId", ""))
			if want_seg != "" and (seg == null or str(seg.segment_id) != want_seg):
				return "delayed_target_skip"
			var tpl := str(args.get("threatTemplateId", "shambler"))
			var meta := {
				"source": "event",
				"eventId": source_event,
				"pointId": target_id,
			}
			var err := CombatL1.open_from_template(state, tpl, meta)
			if err == "must_stop" or err == "outdoor_busy":
				CombatL1.queue_pending_threat(state, tpl, meta)
				TelemetryService.record("event_spawn_threat_deferred", {"error": err, "template": tpl})
				return ""
			if err != "":
				return err
			state.event_modal_open = false
			return "combat_opened"
		"weight_mod":
			if seg == null or (
				str(op_row.get("segmentId", "")) != "" and str(seg.segment_id) != str(op_row.get("segmentId", ""))
			):
				return "delayed_target_skip"
			var delta := float(args.get("delta", 0.0))
			var tag := str(args.get("eventTag", "raid"))
			seg.apply_event_tag_weight(tag, delta)
			return ""
		"flag_set":
			var key := str(args.get("key", ""))
			if key != "":
				state.event_flags[key] = args.get("value", true)
			return ""
		"recruit_roll":
			var prob := (
				float(args["p"])
				if args.has("p")
				else float(ConfigDb.require("balance.eventOps.defaultRecruitRollP"))
			)
			if TrainService.onboard_count(state) < TrainService.bed_count(state) and RngService.randf() < prob:
				MemberRoster.try_recruit_one(state)
				TelemetryService.record("event_recruit_success", {"eventId": source_event})
			else:
				TelemetryService.record("event_recruit_fail", {"eventId": source_event})
			return ""
		"loot_halve":
			var raw_ratio := (
				float(args["ratio"])
				if args.has("ratio")
				else float(ConfigDb.require("balance.eventOps.defaultLootHalveRatio"))
			)
			var ratio := clampf(raw_ratio, 0.0, 1.0)
			if seg == null:
				return "delayed_target_skip"
			var point_halve := target_id != "" and target_type != "segment"
			if point_halve:
				if capture == "snapshot":
					var snap: Variant = op_row.get("snapshot", {})
					if typeof(snap) != TYPE_DICTIONARY:
						return "delayed_target_skip"
					var snap_pile: Variant = (snap as Dictionary).get("pile", {})
					if typeof(snap_pile) != TYPE_DICTIONARY or (snap_pile as Dictionary).is_empty():
						TelemetryService.record(
							"event_delayed_loot_empty_skip",
							{"pointId": target_id, "capture": capture}
						)
						return "delayed_target_skip"
					_apply_snapshot_loot_halve(target_id, seg, ratio, snap_pile as Dictionary)
				else:
					if not _live_point_pile_has_loot(state, target_id):
						TelemetryService.record(
							"event_delayed_loot_empty_skip",
							{"pointId": target_id, "capture": capture}
						)
						return "delayed_target_skip"
					_halve_point_pile(target_id, seg, ratio)
			else:
				if capture == "snapshot":
					var snap2: Variant = op_row.get("snapshot", {})
					if typeof(snap2) != TYPE_DICTIONARY:
						return "delayed_target_skip"
					var snap_pile2: Variant = (snap2 as Dictionary).get("pile", {})
					if typeof(snap_pile2) == TYPE_DICTIONARY and not (snap_pile2 as Dictionary).is_empty():
						_apply_snapshot_loot_halve(target_id, seg, ratio, snap_pile2 as Dictionary)
						return ""
				if not _segment_has_loot(seg):
					TelemetryService.record("event_delayed_loot_empty_skip", {"segment": seg.segment_id})
					return "delayed_target_skip"
				_halve_segment_piles(seg, ratio)
			return ""
		_:
			push_warning("EventOps unhandled op: " + op)
			return "unknown_op"

## 段推进时递减 `expiresSegment` 气候影响。
##
## @param state 当前局 `RunState`（就地修改字段）
static func expire_segment_influences(state: RunState) -> void:
	var kept: Array = []
	var removed := false
	for raw in state.climate_influences:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var inf: Dictionary = raw.duplicate(true)
		if not inf.has("expiresSegment"):
			kept.append(inf)
			continue
		var left := int(inf.get("expiresSegment", 0)) - 1
		inf["expiresSegment"] = left
		if left <= 0:
			removed = true
			continue
		kept.append(inf)
	state.climate_influences = kept
	if removed:
		ClimateService.refresh(state)

## `mood_delta` 全队：对存活成员加 mood；无人存活返回 `delayed_target_skip`。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param args（Dictionary）
## @return 空串=成功；非空=机器错误码。
static func _apply_mood_party(state: RunState, args: Dictionary) -> String:
	var delta := float(args.get("delta", 0))
	var any := false
	for i in state.members.size():
		var m: Variant = state.members[i]
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if float(m.get("hp", 0.0)) <= 0.0:
			continue
		_add_member_mood(m, delta)
		any = true
	return "" if any else "delayed_target_skip"

## `mood_delta` 单人或全局：`member` 找名册；否则累加 `state.morale_offset` 并夹紧。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param args（Dictionary）
## @param target_type（String）
## @param target_id（String）
## @return 空串=成功；非空=机器错误码。
static func _apply_mood_delta(
	state: RunState,
	args: Dictionary,
	target_type: String,
	target_id: String
) -> String:
	var delta := float(args.get("delta", 0))
	if target_type == "member" or args.has("memberId"):
		var mid := str(args.get("memberId", target_id))
		for i in state.members.size():
			var m: Variant = state.members[i]
			if typeof(m) != TYPE_DICTIONARY or str(m.get("id", "")) != mid:
				continue
			if float(m.get("hp", 0.0)) <= 0.0:
				return "delayed_target_skip"
			_add_member_mood(m, delta)
			return ""
		return "delayed_target_skip"
	state.morale_offset = clampf(
		state.morale_offset + delta,
		_PopulationRules.morale_party_delta_min(),
		_PopulationRules.morale_party_delta_max()
	)
	return ""

## 成员字典 mood += delta，夹紧 [0, 100]。
##
## @param member 成员字典引用
## @param delta 增减量
static func _add_member_mood(member: Dictionary, delta: float) -> void:
	member["mood"] = _PopulationRules.clamp_mood(
		float(member.get("mood", _PopulationRules.mood_default())) + delta
	)

## 在段内按 `point_id` 找到点并 `_scale_pile`（掠夺减半类事件）。
##
## @param point_id 搜索点 id（段内 points[].id）
## @param seg 当前区段 `Segment`
## @param ratio 比例 0~1
## 按延迟入队时快照的 pile 结算减半（忽略触发前活堆改动）。
static func _apply_snapshot_loot_halve(
	point_id: String,
	seg: Segment,
	ratio: float,
	snap_pile: Dictionary
) -> void:
	var fac := 1.0 - ratio
	for pt in seg.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		if str(pt.get("id", "")) != point_id:
			continue
		var pile := LootPileService.pile_dict(pt)
		for k in snap_pile.keys():
			var base_amt := maxf(0.0, float(snap_pile[k]))
			var v := base_amt * fac
			if v < 0.01:
				pile.erase(k)
			else:
				pile[str(k)] = v
		return


static func _halve_point_pile(point_id: String, seg: Segment, ratio: float) -> void:
	for pt in seg.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		if str(pt.get("id", "")) != point_id:
			continue
		_scale_pile(pt, ratio)
		return

## 对段内全部搜索点 loot 按 ratio 缩放。
##
## @param seg 当前区段 `Segment`
## @param ratio 比例 0~1
static func _halve_segment_piles(seg: Segment, ratio: float) -> void:
	for pt in seg.points:
		if typeof(pt) == TYPE_DICTIONARY:
			_scale_pile(pt, ratio)

## 点位 `lootPile` 各键 × (1-ratio)；近零键删除。
##
## @param pt 点位字典 points[] 元素
## @param ratio 比例 0~1
static func _scale_pile(pt: Dictionary, ratio: float) -> void:
	var pile: Variant = pt.get("lootPile", {})
	if typeof(pile) != TYPE_DICTIONARY:
		return
	var fac := 1.0 - ratio
	for k in pile.keys():
		var v := maxf(0.0, float(pile[k]) * fac)
		if v < 0.01:
			pile.erase(k)
		else:
			pile[k] = v

## 选项带 `delayDays` 时写入 `state.delayed_events`；snapshot 捕获时附 `_build_snapshot`。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param delay_days 延迟触发距今游戏日数
## @param op（String）
## @param option（Dictionary）
## @param seg 当前区段 `Segment`
## @param event_id 事件卡 id
## @param option_id 事件选项 id
static func _queue_delayed(
	state: RunState,
	delay_days: int,
	op: String,
	option: Dictionary,
	seg: Segment,
	event_id: String,
	option_id: String
) -> void:
	var target_type := str(option.get("targetType", "global"))
	var target_id := _resolve_target_id(state, seg, target_type)
	var capture := str(option.get("capture", "live"))
	var row := {
		"fireOnDay": state.day_total + delay_days,
		"op": op,
		"targetType": target_type,
		"targetId": target_id,
		"args": option.get("args", {}),
		"segmentId": seg.segment_id if seg else "",
		"sourceEventId": event_id,
		"sourceOptionId": option_id,
		"capture": capture,
	}
	if capture == "snapshot":
		row["snapshot"] = _build_snapshot(state, target_id)
	state.delayed_events.append(row)

## 按 `targetType` 解析 point/segment/member/party 的默认 targetId。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param seg 当前区段 `Segment`
## @param target_type（String）
## @return 空串=成功；非空=机器错误码。
static func _resolve_target_id(state: RunState, seg: Segment, target_type: String) -> String:
	match target_type:
		"point":
			if seg != null and not seg.points.is_empty():
				return str(seg.points[0].get("id", ""))
		"segment":
			if seg != null and not seg.points.is_empty():
				return str(seg.points[0].get("id", ""))
		"member", "party":
			var living: Array = []
			for m in state.members:
				if typeof(m) == TYPE_DICTIONARY:
					living.append(m)
			if living.is_empty():
				return ""
			return str(living[RngService.randi() % living.size()].get("id", ""))
	return ""

## 延迟 loot 用的资源快照：整车库存 + 可选点位 pile 拷贝。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @return 结果字典；缺失语义键时可能为空 {}。
static func _build_snapshot(state: RunState, point_id: String) -> Dictionary:
	var snap := {
		"food": state.food,
		"water": state.water,
		"fuel": state.fuel,
		"parts": state.parts,
		"medicine": state.medicine,
		"pile": {},
	}
	if point_id.is_empty():
		return snap
	var hit := LootPileService.find_point(state, point_id)
	if hit.is_empty():
		return snap
	var pile: Dictionary = LootPileService.pile_dict(hit.point)
	for k in pile.keys():
		snap["pile"][str(k)] = float(pile[k])
	return snap

## 运行时堆：经 `LootPileService.find_point` 判断该点总量 > 0。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @return 是否成功或条件成立。
static func _live_point_pile_has_loot(state: RunState, point_id: String) -> bool:
	var hit := LootPileService.find_point(state, point_id)
	if hit.is_empty():
		return false
	return LootPileService.total_amount(hit.point) > 0.001

## 段内任一点 `LootPileService.total_amount` > 0 则 true。
##
## @param seg 当前区段 `Segment`
## @return 是否成功或条件成立。
static func _segment_has_loot(seg: Segment) -> bool:
	if seg == null:
		return false
	for pt in seg.points:
		if typeof(pt) == TYPE_DICTIONARY and LootPileService.total_amount(pt) > 0.001:
			return true
	return false

## 在 `region_run.segments` 中按 id 查找 `Segment`；无则 null。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param segment_id（String）
## @return 段实例；不存在时为 null。
static func _segment_in_run(state: RunState, segment_id: String) -> Segment:
	if state.region_run == null or segment_id.is_empty():
		return null
	for raw in state.region_run.segments:
		if raw is Segment and str(raw.segment_id) == segment_id:
			return raw
	return null

## 延迟结算解析段：显式 id 优先，否则回退 `active_segment()`。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param segment_id（String）
## @return 段实例；不存在时为 null。
static func _resolve_segment(state: RunState, segment_id: String) -> Segment:
	if state.region_run == null or segment_id == "":
		return state.region_run.active_segment() if state.region_run else null
	for raw in state.region_run.segments:
		if raw is Segment and str(raw.segment_id) == segment_id:
			return raw
	return state.region_run.active_segment()

## 记录 weightEventId 与 primary_tag，队列超 8 截断（重复惩罚用）。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param card 事件卡 JSON（EventCatalog）
static func _push_draw_history(state: RunState, card: Dictionary) -> void:
	var wid := str(card.get("weightEventId", card.get("id", "")))
	state.event_weight_history.append(wid)
	state.last_event_primary_tag = EventCatalog.primary_tag(card)
	if state.event_weight_history.size() > 8:
		state.event_weight_history = state.event_weight_history.slice(-8)