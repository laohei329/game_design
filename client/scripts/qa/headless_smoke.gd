extends Node
## 无头冒烟主场景（tools/run_godot_smoke.ps1 → scenes/qa/headless_smoke.tscn）。
##
## 流程：ConfigDb → 场景存在性 → NEW_RUN → 多日 Intent 链 → SmokeAssertions 终检 → quit。
## 失败累积到 _errors，结束时 print 并以非零退出码标记（§12.5/12.7 自动化证据）。


var _errors: PackedStringArray = []
func _ready() -> void:
	call_deferred("_run")

## 记录一条冒烟失败：追加 `_errors` 并 `push_error`（Godot 日志可见）。
func _fail(msg: String) -> void:
	_errors.append(msg)
	push_error("[smoke] " + msg)

## 合并 `SmokeAssertions` 返回的 `PackedStringArray` 到 `_errors`。
func _absorb(errs: PackedStringArray) -> void:
	for e in errs:
		_fail(e)

## 主冒烟编排：配置与场景 → NEW_RUN → 三日结审计 → 教程进站挂车 →
## 战斗/搜索/气候/遗弃/事件 op → 8 日日活软锁探测 → 存档往返 → `_finish`。
func _run() -> void:
	await get_tree().process_frame
	_clear_telemetry_log()

	if ConfigDb.tables.is_empty() and not ConfigDb.load_all():
		for e in ConfigDb.load_errors:
			_fail("ConfigDb: " + e)
		_finish()
		return

	_absorb(SmokeAssertions.errors_main_scenes_load())
	_absorb(SmokeAssertions.errors_config_paths())

	IntentBus.emit_intent("NEW_RUN")
	await get_tree().process_frame
	var state := GameSession.state
	if state == null:
		_fail("NEW_RUN did not create RunState")
		_finish()
		return

	_absorb(SmokeAssertions.errors_start_crew(state))
	_absorb(SmokeAssertions.errors_fuel_uses_config(state))
	_absorb(SmokeAssertions.errors_start_precision(state))
	_absorb(SmokeAssertions.errors_member_mood_day_settle(state))
	_absorb(SmokeAssertions.errors_tech_power_lv1(state))
	IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "stop"})
	await get_tree().process_frame
	state = GameSession.state
	_absorb(SmokeAssertions.errors_combat_l1(state))
	_absorb(SmokeAssertions.errors_min_power_rule(state))
	var d0 := state.day_total
	var f0 := state.food
	var w0 := state.water
	var fuel0 := state.fuel
	for _i in 3:
		IntentBus.emit_intent("END_DAY")
		await get_tree().process_frame
	_absorb(SmokeAssertions.audit_after_triplet_end_day(d0, f0, w0, fuel0))
	state = GameSession.state
	await _test_tutorial_station_hang(state)
	state = GameSession.state
	_test_last_locomotive(state)
	_absorb(SmokeAssertions.errors_guarantee_offer(state))
	_absorb(SmokeAssertions.errors_search_telemetry(state, GameSession.search_telemetry))
	GameSession.search_telemetry.clear()
	state = GameSession.state
	if state:
		IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "stop"})
		await get_tree().process_frame
		var telem_outdoor: Dictionary = {}
		_absorb(SmokeAssertions.errors_outdoor_day_clock_p0_a(state, telem_outdoor))
		_absorb(SmokeAssertions.errors_runtime_day_clock_save_roundtrip(state))
		GameSession.search_telemetry.clear()
	_test_search_cap(state)
	_absorb(SmokeAssertions.errors_climate_region_mult(state))
	_absorb(SmokeAssertions.errors_abandon_cargo(state))
	state = GameSession.state
	_absorb(SmokeAssertions.errors_region_pick_tundra(state))
	state = GameSession.state
	var seg_ev := state.region_run.active_segment() if state.region_run else null
	if seg_ev != null and not seg_ev.event_resolved:
		_absorb(SmokeAssertions.errors_event_snapshot_and_load_pending(state))
		state = GameSession.state
	_absorb(SmokeAssertions.errors_event_and_point_encounter(state))
	_absorb(SmokeAssertions.errors_event_ops_full(state))
	_absorb(SmokeAssertions.errors_recruit_morale_save(state))
	state = GameSession.state
	if state:
		state.search_tasks.clear()
		state.haul_tasks.clear()
		for m in state.members:
			if typeof(m) == TYPE_DICTIONARY:
				m["taskState"] = "idle"
		IntentBus.emit_intent("CLOSE_COMBAT")
	await _advance_days(8)
	_test_save_loot_pile_roundtrip()
	_test_save_dict_precision_roundtrip()
	_finish()

## 删除 `user://telemetry.jsonl`，避免前次运行污染 `errors_search_telemetry`。
func _clear_telemetry_log() -> void:
	var path := "user://telemetry.jsonl"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## 教程链：前进驾驶 8 日 → 停靠 → `ENTER_STATION` → 审计挂车节数与 parts。
## 结束后清空成员户外任务与搜索/搬运任务，防止污染后续用例。
func _test_tutorial_station_hang(state: RunState) -> void:
	var cars_before := state.carriages.size()
	var parts_before := state.parts
	IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "forward"})
	for _i in 8:
		IntentBus.emit_intent("END_DAY")
		await get_tree().process_frame
	state = GameSession.state
	IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "stop"})
	IntentBus.emit_intent("ENTER_STATION")
	await get_tree().process_frame
	state = GameSession.state
	_absorb(SmokeAssertions.audit_tutorial_hang(state, cars_before, parts_before))
	for m in state.members:
		if typeof(m) == TYPE_DICTIONARY:
			m["taskState"] = "idle"
	state.search_tasks.clear()
	state.haul_tasks.clear()

## 断言唯一动力节 `car_pwr` 不可遗弃时返回 `last_locomotive`（TrainService）。
func _test_last_locomotive(state: RunState) -> void:
	var reason := TrainService.can_abandon(state, "car_pwr")
	if reason != "last_locomotive":
		_fail("末节动力应为 last_locomotive, got=%s" % reason)

## 对教程区首点反复 assign/recall，第 `SearchRules.cap()+1` 次应 `cap_exceeded`。
func _test_search_cap(state: RunState) -> void:
	var st := GameSession.state
	var seg := st.region_run.active_segment() if st.region_run else null
	if seg == null or seg.points.is_empty():
		_fail("教程区无搜索点")
		return
	var point_id := str(seg.points[0].get("id", ""))
	var telem := GameSession.search_telemetry
	var mid := SmokeAssertions.first_member_id(st, "labor")
	if mid.is_empty():
		_fail("搜索 cap 测试无 labor 成员")
		return
	var picked: Array = [mid]
	var cap := SearchRules.cap()
	for i in cap:
		for m in st.members:
			if typeof(m) == TYPE_DICTIONARY:
				m["taskState"] = "idle"
		var err := SearchService.assign_search(st, point_id, picked, telem)
		if err != "":
			_fail("搜索 %d/%d 意外失败: %s" % [i + 1, cap, err])
			return
		SearchService.recall_search(st, {"pointId": point_id})
	var err := SearchService.assign_search(st, point_id, picked, telem)
	if err != "cap_exceeded":
		_fail("第 %d 次搜索应 cap_exceeded, got=%s" % [cap + 1, err])

## 连续 `END_DAY` 最多 `n` 次；每日跑 `SoftLockProbe` 并拒绝负库存/过早 `failed`。
## `day_total >= 15` 时提前结束（覆盖 15 日长局目标）。
func _advance_days(n: int) -> void:
	for i in n:
		IntentBus.emit_intent("END_DAY")
		await get_tree().process_frame
		var st := GameSession.state
		if st == null:
			_fail("day %d: RunState null" % (i + 1))
			return
		var rep := SoftLockProbe.audit(st)
		if not bool(rep.get("ok", false)):
			for line in rep.get("lines", []):
				if str(line).begins_with("FAIL"):
					_fail("day %d probe: %s" % [st.day_total, line])
		if st.food < 0 or st.water < 0 or st.fuel < 0 or st.parts < 0:
			_fail("day %d: 负库存" % st.day_total)
		if st.failed != "" and i < n - 1:
			_fail("day %d: 过早 failed=%s" % [st.day_total, st.failed])
		if st.day_total >= 15:
			break

## 槽 90：向现场堆写入 food → 写档 → 读档，比对 `LootPileService.export_piles` 条数。
func _test_save_loot_pile_roundtrip() -> void:
	const SLOT := 90
	var st := GameSession.state
	var seg := st.region_run.active_segment() if st.region_run else null
	if seg == null or seg.points.is_empty():
		return
	var pid := str(seg.points[0].get("id", ""))
	LootPileService.add(st, pid, "food", 3.5)
	var before := LootPileService.export_piles(st).size()
	if not SaveService.write_state(st, SLOT):
		_fail("存档槽 %d 写入失败" % SLOT)
		return
	var loaded := SaveService.read_state(SLOT)
	if loaded == null:
		_fail("读档槽 %d 失败" % SLOT)
		return
	var after := LootPileService.export_piles(loaded).size()
	if after != before or after < 1:
		_fail("lootPile 存读不一致 before=%d after=%d" % [before, after])

## 内存 `SaveSchema.to_save_dict` ↔ `from_save_dict`：`precision`/`morale_offset` 浮点保真。
func _test_save_dict_precision_roundtrip() -> void:
	var st := GameSession.state
	if st == null:
		return
	st.morale_offset = -5.0
	st.precision = 41.0
	var raw := SaveSchema.to_save_dict(st)
	var loaded := SaveSchema.from_save_dict(raw)
	if not is_equal_approx(loaded.precision, 41.0):
		_fail("SaveSchema precision 往返失败")
	if not is_equal_approx(loaded.morale_offset, -5.0):
		_fail("SaveSchema morale_offset 往返失败")

## 汇总 `_errors`：空则 `[smoke] PASS` exit 0，否则逐条打印 FAIL exit 1。
func _finish() -> void:
	if _errors.is_empty():
		print("[smoke] PASS (config + §12.7 + tutorial hang + 15-day)")
		get_tree().quit(0)
	else:
		for e in _errors:
			print("[smoke] FAIL: ", e)
		get_tree().quit(1)