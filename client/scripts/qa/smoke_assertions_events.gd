class_name SmokeAssertionsEvents
extends RefCounted
## 冒烟：事件链、op 全量、读档与招募 morale。

const _Helpers := preload("res://scripts/qa/smoke_assertions_helpers.gd")

static func errors_event_and_point_encounter(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	if not state.tutorial_done:
		errs.append("事件/遭遇测试需 tutorial_done")
		return errs
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null:
		errs.append("无 active segment")
		return errs
	if seg.event_id.is_empty():
		errs.append("段 built 后应有 event_id")
		return errs
	var card: Dictionary = EventCatalog.get_card(seg.event_id)
	if card.is_empty():
		errs.append("event card 加载失败: " + seg.event_id)
	if not seg.event_resolved and seg.event_option_id == "":
		var opt_id := ""
		for raw in card.get("options", []):
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			if int(raw.get("delayDays", 0)) > 0:
				continue
			var imm: Variant = raw.get("immediate", {})
			if typeof(imm) == TYPE_DICTIONARY and str(imm.get("op", "")) == "grant_item":
				opt_id = str(raw.get("id", ""))
				break
		if opt_id == "":
			for raw in card.get("options", []):
				if typeof(raw) != TYPE_DICTIONARY:
					continue
				if int(raw.get("delayDays", 0)) == 0 and str(raw.get("op", "")) == "":
					opt_id = str(raw.get("id", ""))
					break
		if opt_id == "":
			for raw in card.get("options", []):
				if typeof(raw) == TYPE_DICTIONARY:
					opt_id = str(raw.get("id", ""))
					break
		var before_parts := state.parts
		var ch_err: String = EventOps.choose_option(state, seg.event_id, opt_id)
		if ch_err != "":
			errs.append("CHOOSE_EVENT: " + ch_err)
		elif not seg.event_resolved:
			errs.append("选项后 event_resolved 应为 true")
		else:
			EventService.sync_after_load(state)
			if state.event_modal_open:
				errs.append("已选事件 sync_after_load 不应重开弹窗")
			if opt_id != "":
				var chosen: Dictionary = {}
				for raw in card.get("options", []):
					if typeof(raw) == TYPE_DICTIONARY and str(raw.get("id", "")) == opt_id:
						chosen = raw
						break
				var imm: Variant = chosen.get("immediate", {})
				var had_grant := (
					typeof(imm) == TYPE_DICTIONARY and str(imm.get("op", "")) == "grant_item"
				)
				var imm_res := ""
				if had_grant:
					imm_res = InventoryService.normalize_key(str(imm.get("args", {}).get("res", "")))
				if had_grant and imm_res == "parts" and state.parts <= before_parts:
					errs.append("grant_item 应增加 parts")
		state.delayed_events.clear()
	IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "stop"})
	var target := ""
	for pt in seg.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		if str(pt.get("type", "")) == "scrapyard":
			target = str(pt.get("id", ""))
			break
	if target.is_empty() and not seg.points.is_empty():
		var pt0: Dictionary = seg.points[0]
		target = str(pt0.get("id", ""))
	if target.is_empty():
		errs.append("无搜索点可测遭遇")
		return errs
	state.combat_panel_open = false
	state.pending_combat.clear()
	var enc_err: String = PointEncounterService.try_on_search_assign(
		state, target, GameSession.search_telemetry, true
	)
	if enc_err != "":
		errs.append("点位遭遇: " + enc_err)
	elif not state.combat_panel_open:
		errs.append("强制点位遭遇应打开 combat_panel")
	IntentBus.emit_intent("CLOSE_COMBAT")
	state.search_tasks.clear()
	for m in state.members:
		if typeof(m) == TYPE_DICTIONARY:
			m["taskState"] = "idle"
	return errs


## DEV-S2-02：全量 op 烟测（grant_influence / remove_item / loot_halve / weight_mod）。
static func errors_event_ops_full(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null:
		errs.append("event ops 需要 active segment")
		return errs
	var temp_before := ClimateService._sum_influence_temp(state)
	var inf_args := {
		"id": "event.smoke.temp",
		"source": "event",
		"tempMod": -0.4,
		"expiresSegment": 1,
	}
	var row := {"op": "grant_influence", "args": inf_args}
	if EventOps.apply_op(state, row, "global", seg, "smoke", "test") != "":
		errs.append("grant_influence 失败")
	if is_equal_approx(ClimateService._sum_influence_temp(state), temp_before):
		errs.append("grant_influence 应改 temp 合计")
	var parts_before := state.parts
	EventOps.apply_op(
		state,
		{"op": "remove_item", "args": {"res": "parts", "amount": 1.0}},
		"global",
		seg,
		"smoke",
		"r"
	)
	if not is_equal_approx(state.parts, parts_before - 1.0):
		errs.append("remove_item 应扣 parts")
	if not seg.points.is_empty():
		var pt: Dictionary = seg.points[0]
		var pile: Dictionary = LootPileService.pile_dict(pt)
		pile["food"] = 10.0
		EventOps.apply_op(
			state,
			{"op": "loot_halve", "args": {"ratio": 0.5}, "targetId": str(pt.get("id", ""))},
			"segment",
			seg,
			"smoke",
			"h"
		)
		var after := float(LootPileService.pile_dict(pt).get("food", -1))
		if not is_equal_approx(after, 5.0):
			errs.append("loot_halve 应为 5 food, got=%.2f" % after)
	var raid0 := float(seg.event_tag_weights.get("raid", 0.0))
	EventOps.apply_op(
		state,
		{"op": "weight_mod", "args": {"eventTag": "raid", "delta": 0.1}},
		"segment",
		seg,
		"smoke",
		"w"
	)
	if not is_equal_approx(float(seg.event_tag_weights.get("raid", -1.0)), raid0 + 0.1):
		errs.append("weight_mod 应写入 eventTagWeights.raid")
	if not is_equal_approx(seg.raid_weight_delta, raid0 + 0.1):
		errs.append("weight_mod 应同步 raid_weight_delta")
	seg.apply_event_tag_weight("supply", 0.2)
	var w_supply := EventDraw._weight_for_card(
		{"weight": 1.0, "yieldScale": 1.0, "tags": ["supply"]},
		EventDraw._build_ctx(state, seg)
	)
	seg.event_tag_weights.erase("supply")
	var w_base := EventDraw._weight_for_card(
		{"weight": 1.0, "yieldScale": 1.0, "tags": ["supply"]},
		EventDraw._build_ctx(state, seg)
	)
	seg.apply_event_tag_weight("supply", 0.2)
	if w_supply <= w_base:
		errs.append("supply eventTag 权重应抬高 supply 卡")
	for m in state.members:
		if typeof(m) == TYPE_DICTIONARY:
			m["taskState"] = "idle"
	state.search_tasks.clear()
	state.haul_tasks.clear()
	TrainService.reconcile_outdoor_tasks(state)
	state.combat_panel_open = false
	state.pending_combat.clear()
	state.event_modal_open = false
	_Helpers._intent_drive("forward")
	var queue_err := EventOps.apply_op(
		state,
		{"op": "spawn_threat", "args": {"threatTemplateId": "horde_small"}},
		"segment",
		seg,
		"smoke",
		"q"
	)
	if queue_err != "":
		errs.append("spawn_threat 前进应入队: " + queue_err)
	if state.pending_threat.is_empty():
		errs.append("前进 spawn_threat 应写 pending_threat")
	TrainService.reconcile_outdoor_tasks(state)
	_Helpers._intent_drive("stop")
	if not state.combat_panel_open and not state.pending_threat.is_empty():
		CombatL1.try_open_pending_threat(state)
	if not state.pending_threat.is_empty():
		errs.append("停靠后 pending_threat 应已消费")
	if not state.combat_panel_open:
		errs.append("停靠应打开战斗面板")
	state.combat_panel_open = false
	state.pending_combat.clear()
	state.pending_threat.clear()
	EventOps.apply_op(
		state,
		{"op": "clear_influence", "args": {"id": "event.smoke.temp"}},
		"global",
		seg,
		"smoke",
		"c"
	)
	return errs


## 未决段事件读档恢复弹窗 + 延迟 snapshot 不写回空堆。
static func errors_event_snapshot_and_load_pending(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null or seg.event_id.is_empty():
		errs.append("需要已抽 event_id 的段")
		return errs
	if seg.event_resolved:
		errs.append("本测需未选事件")
		return errs
	const SLOT := 93
	if not SaveService.write_state(state, SLOT):
		errs.append("存档失败 slot 93")
		return errs
	state.event_modal_open = false
	if not SaveService.load_into_game_session(SLOT):
		errs.append("读档失败")
		return errs
	var loaded := GameSession.state
	if loaded == null:
		errs.append("读档后 state 为空")
		return errs
	if not loaded.event_modal_open:
		errs.append("读档后未决事件应恢复 event_modal_open")
	if not EventService.has_pending_segment_event(loaded):
		errs.append("has_pending_segment_event 应为 true")
	var snap_seg := loaded.region_run.active_segment() if loaded.region_run else null
	if snap_seg == null or snap_seg.points.is_empty():
		errs.append("snapshot 测需要搜索点")
		return errs
	var pt: Dictionary = snap_seg.points[0]
	var pid := str(pt.get("id", ""))
	var pile: Dictionary = LootPileService.pile_dict(pt)
	pile["food"] = 8.0
	loaded.delayed_events.append(
		{
			"fireOnDay": loaded.day_total,
			"op": "loot_halve",
			"targetType": "segment",
			"targetId": pid,
			"args": {"ratio": 0.5},
			"segmentId": snap_seg.segment_id,
			"sourceEventId": "smoke_snap",
			"sourceOptionId": "x",
			"capture": "snapshot",
			"snapshot": {"pile": {"food": 8.0}},
		}
	)
	pile.clear()
	EventOps.process_due_delayed_events(loaded, loaded.day_total)
	if float(LootPileService.pile_dict(pt).get("food", -1)) > 0.01:
		errs.append("snapshot：堆空时不应凭快照恢复再减半")
	GameSession.state = state
	return errs


## 日结收留门闩 · 难度事件率 · moraleZeroStreak 存档。
static func errors_recruit_morale_save(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	if not is_equal_approx(EventDraw.scenario_event_rate(), 1.0):
		errs.append("scenario_event_rate 默认应为 1.0 (got=%.3f)" % EventDraw.scenario_event_rate())
	var day := state.day_total
	var saved_last := state.last_recruit_success_day
	state.last_recruit_success_day = day
	if (
		TrainService.onboard_count(state) < TrainService.bed_count(state)
		and MemberRoster.try_day_end_recruit(state)
	):
		errs.append("lastRecruitSuccessDay==dayTotal 不应日结补抽")
	state.last_recruit_success_day = saved_last
	var streak0 := state.morale_zero_streak
	state.morale_zero_streak = 2
	const SLOT := 94
	if not SaveService.write_state(state, SLOT):
		errs.append("moraleZeroStreak 写档失败")
	else:
		var loaded := SaveService.read_state(SLOT)
		if loaded == null:
			errs.append("moraleZeroStreak 读档失败")
		elif loaded.morale_zero_streak != 2:
			errs.append("moraleZeroStreak 读档应=2 got=%d" % loaded.morale_zero_streak)
	state.morale_zero_streak = streak0
	return errs

## 扫描 `user://telemetry.jsonl` 是否出现过指定 `event` 键（每行 JSON）。
