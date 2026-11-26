class_name DriveService
extends RefCounted
## 03 §6.2 · S1a 按「日」推进：END_DAY 前 accrue，F04 用 driveHoursToday / reverseHoursToday。


static func hours_cap() -> float:
	return float(ConfigDb.require("balance.time.driveHoursPerDayCap"))


static func travel_budget_exhausted(state: RunState) -> bool:
	return state.drive_hours_today >= hours_cap() - 0.0001


static func set_intent(state: RunState, mode: String) -> void:
	var m := str(mode).to_lower()
	match m:
		"forward", "cruise":
			state.drive_intent = "forward"
		"reverse", "slow":
			state.drive_intent = "reverse"
		"stop", "dock":
			state.drive_intent = "stop"
		_:
			push_warning("DriveService: unknown intent " + mode)
			return


static func travel_speed_kmh(state: RunState) -> float:
	# 03 §6.2：综合旅行速度 = 2.5 × (瞬时速度/30)；S1a 灰盒取巡航 60×speedClimate
	var tactical := 60.0 * maxf(0.1, state.speed_climate)
	return 2.5 * (tactical / 30.0)


static func active_segment(state: RunState) -> Segment:
	if state.region_run == null:
		return null
	return state.region_run.active_segment()


static func accrue_end_of_day(state: RunState) -> void:
	## 本游戏日结束：写入将参与下一步 day_settle F04 的小时与里程（日结后清零）。
	var cap := hours_cap()
	match state.drive_intent:
		"forward":
			if not travel_budget_exhausted(state):
				var room := maxf(0.0, cap - state.drive_hours_today)
				var eff := minf(room, cap)
				state.drive_hours_today += eff
				_apply_forward_km(state, eff)
			# 额度用尽：不加 km；F04 仍由 fuel_f04 按小时拆分（余下时间视同停靠系数）
		"reverse":
			# 返程不占额度；S1a 每日折合 1 游戏小时返程油耗（可调）
			var rev := minf(cap, 1.0)
			state.reverse_hours_today += rev
			_apply_reverse_km(state, rev * travel_speed_kmh(state))
		_:
			pass


static func _apply_forward_km(state: RunState, eff_hours: float) -> void:
	var seg := active_segment(state)
	if seg == null or eff_hours <= 0.0:
		return
	var delta := travel_speed_kmh(state) * eff_hours
	seg.progress_km = minf(seg.length_km, seg.progress_km + delta)


static func _apply_reverse_km(state: RunState, delta_km: float) -> void:
	var remain := delta_km
	if remain <= 0.0 or state.region_run == null:
		return
	var idx := state.region_run.segment_index
	while remain > 0.0 and idx >= 0:
		var seg: Variant = state.region_run.segments[idx]
		if not (seg is Segment):
			break
		var s := seg as Segment
		if s.progress_km >= remain:
			s.progress_km -= remain
			remain = 0.0
		else:
			remain -= s.progress_km
			s.progress_km = 0.0
			idx -= 1
			if idx >= 0:
				state.region_run.segment_index = idx
			else:
				break