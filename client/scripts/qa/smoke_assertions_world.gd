class_name SmokeAssertionsWorld
extends RefCounted
## 冒烟：气候/车站/搜索 cap/战斗/科技/区域。

const _Helpers := preload("res://scripts/qa/smoke_assertions_helpers.gd")

static func errors_climate_region_mult(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	var before_fuel_c := state.fuel_climate
	ClimateService.refresh(state)
	if not is_equal_approx(state.fuel_climate, before_fuel_c) and state.day_total == 1:
		pass
	var old_mult := state.region_fuel_mult
	state.region_fuel_mult = 1.3
	ClimateService.refresh(state)
	var f04_high := FuelF04.compute_day_burn_percent(state)
	state.region_fuel_mult = 1.0
	ClimateService.refresh(state)
	var f04_norm := FuelF04.compute_day_burn_percent(state)
	state.region_fuel_mult = old_mult
	ClimateService.refresh(state)
	if f04_high <= f04_norm:
		errs.append("region_fuel_mult 1.3 应提高 F04")
	return errs

## 冒烟：guarantee 链路可出 offer。
static func errors_guarantee_offer(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null:
		errs.append("无 segment 测保底")
		return errs
	var station := {
		"hasPool": true,
		"nonePool": false,
		"tutorialHook": false,
		"visit_missed": false,
		"size": "small",
	}
	state.guarantee_fail_streak = StationService.guarantee_after()
	StationService.generate_offer(state, seg, station)
	var offer: Variant = station.get("offer", {})
	if typeof(offer) != TYPE_DICTIONARY or offer.is_empty():
		errs.append("保底 streak 下应有 offer")
	elif not bool(offer.get("guaranteeForced", false)):
		errs.append("保底应 guaranteeForced=true")
	return errs

## 冒烟：教程挂车节数/parts。
static func audit_tutorial_hang(state: RunState, cars_before: int, parts_before: float) -> PackedStringArray:
	var errs: PackedStringArray = []
	if state == null:
		errs.append("进站冒烟无 state")
		return errs
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null or seg.progress_km < 20.0:
		errs.append("教程站前 progress 不足 got=%.1f" % (seg.progress_km if seg else 0.0))
	if state.pending_station.is_empty():
		errs.append("进站后无 pending_station")
		return errs
	var err := StationService.resolve_offer(state, true)
	if err != "":
		errs.append("教程挂车失败: " + err)
		return errs
	if state.carriages.size() != cars_before + 1:
		errs.append("挂车后节数应为 %d got=%d" % [cars_before + 1, state.carriages.size()])
	if state.parts >= parts_before:
		errs.append("教程挂车应扣零件")
	if not state.tutorial_done:
		errs.append("教程挂车后 tutorial_done 应为 true")
	return errs

## 冒烟：末节动力不可遗弃。
static func errors_min_power_rule(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	if TrainService.power_count(state) < 1:
		errs.append("开局应有至少 1 节动力")
		return errs
	for car in state.carriages:
		if typeof(car) != TYPE_DICTIONARY:
			continue
		var cid := str(car.get("id", ""))
		var tid := str(car.get("templateId", ""))
		if tid == "power":
			if not TrainService.violates_min_power(state, cid):
				errs.append("仅 1 节动力时应标记 violates_min_power")
			if TrainService.can_abandon(state, cid) != "last_locomotive":
				errs.append("仅 1 节动力 can_abandon 应为 last_locomotive")
		elif tid in ["cargo", "living", "greenhouse", "water"]:
			if TrainService.violates_min_power(state, cid):
				errs.append("%s 不应触发动力红线" % tid)
	return errs

## 冒烟：遗弃货舱扣件/节数。
static func errors_abandon_cargo(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	state.drive_intent = "stop"
	state.search_tasks.clear()
	state.haul_tasks.clear()
	for m in state.members:
		if typeof(m) == TYPE_DICTIONARY:
			m["taskState"] = "idle"
	state.drive_hours_today = 0.0
	var parts_before := state.parts
	if TrainService.can_abandon(state, "car_cgo") != "":
		errs.append("货舱应可遗弃 precheck")
		return errs
	if not TrainService.abandon_carriage(state, "car_cgo"):
		errs.append("abandon car_cgo 失败")
		return errs
	if state.parts >= parts_before:
		errs.append("遗弃应扣零件")
	if not _Helpers._telemetry_has("carriage_abandon"):
		errs.append("telemetry 缺 carriage_abandon")
	return errs


## 首名匹配岗位成员 id；无岗位偏好时返回第一个有效 id。
static func errors_search_telemetry(state: RunState, telem: Dictionary) -> PackedStringArray:
	var errs: PackedStringArray = []
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null or seg.points.is_empty():
		return errs
	var point_id := str(seg.points[0].get("id", ""))
	_Helpers._clear_search_tasks(state)
	var mid := _Helpers.first_member_id(state, "labor")
	if mid.is_empty():
		errs.append("search_telemetry 无 labor 成员")
		return errs
	var err := _Helpers._intent_assign_search(point_id, [mid], telem)
	if err != "":
		errs.append("search_assign 失败: " + err)
	elif not _Helpers._telemetry_has("search_assign"):
		errs.append("telemetry 缺 search_assign")
	SearchService.recall_search(state, {"pointId": point_id})
	return errs


## P0-A：forward 全日无补课；无日钟补满工日；停 0.5 + 行 0.5 ≈ 半工日进度。
static func errors_combat_l1(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "stop"})
	if CombatL1.can_l1_check(state) == "no_encounter":
		var oerr: String = CombatL1.open_encounter(state, 3)
		if oerr != "":
			errs.append("open_encounter: " + oerr)
			return errs
	var ck := CombatL1.can_l1_check(state)
	if ck != "":
		errs.append("默认编队应可 L1 检定: " + ck)
	else:
		var ch: float = CombatL1.l1_success_chance(state, 5)
		if ch > 0.91:
			errs.append("L1 成功率应≤0.9, got=%.2f" % ch)
	var saved_fmt := state.active_formation_id
	state.active_formation_id = ""
	if CombatL1.can_l1_check(state) != "no_formation":
		errs.append("无编队应禁止 L1")
	if CombatL1.can_non_combat_path(state, "bypass") != "":
		errs.append("无编队仍应可走绕行")
	var rep := CombatL1.resolve_non_combat(state, "bypass")
	if not bool(rep.get("ok", false)):
		errs.append("绕行检定失败: " + str(rep.get("error", "")))
	state.active_formation_id = saved_fmt
	return errs

## 冒烟：动力 Lv1 扣件。
static func errors_tech_power_lv1(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "stop"})
	var before_parts := state.parts
	var err: String = TechService.buy_upgrade(state, "power")
	if err != "":
		errs.append("动力 Lv1: " + err)
		return errs
	if state.power_tech != 1:
		errs.append("power_tech 应为 1")
	if not is_equal_approx(state.parts, before_parts - 2.0):
		errs.append("动力 Lv1 应扣 2 件")
	return errs

## 冒烟：开局 precision。
static func errors_region_pick_tundra(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	var opts: Array = RegionService.roll_pick_options(state, 3)
	if opts.size() < 3:
		errs.append("三选一应至少 3 项, got=%d" % opts.size())
		return errs
	var set := {}
	for o in opts:
		set[str(o)] = true
	if set.size() < 3:
		errs.append("三选一选项应互不重复")
	var err: String = RegionService.pick_region(state, "tundra")
	if err != "":
		errs.append("pick_region tundra: " + err)
		return errs
	if state.region_run == null or state.region_run.region_id != "tundra":
		errs.append("RegionRun 应为 tundra")
	if not is_equal_approx(state.region_fuel_mult, 1.3):
		errs.append("雪原 region_fuel_mult 应为 1.3")
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null or not seg.built or seg.points.size() < 2:
		errs.append("新跨度第 0 段应已 build 且有点位")
	return errs


## 段事件抽卡 + 点位搜索遭遇（S2 薄切片）。
