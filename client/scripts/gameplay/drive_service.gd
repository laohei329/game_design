class_name DriveService
extends RefCounted
## 驾驶意图与日里程（S1a **按日薄模型**，非分时 UI）。
##
## `set_intent`：forward / reverse / stop（HUD 三按钮）。
## `accrue_end_of_day`：END_DAY 时根据意图把本日小时与 km 写入 state，供 F04 与段末判定。
##   - forward：用尽 `driveHoursPerDayCap` 额度并前进 km；段首次越过终点触发 RegionService。
##   - reverse：每日固定折合 1h 返程位移（可跨段回退 index）。
## `travel_speed_kmh`：巡航 60 × speed_climate 再按 03 §6.2 公式折算走廊速度。


static func hours_cap() -> float:
	return float(ConfigDb.require("balance.time.driveHoursPerDayCap"))


## 本日 forward 额度是否已用尽（HUD 显示「额度用尽」）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func travel_budget_exhausted(state: RunState) -> bool:
	return state.drive_hours_today >= hours_cap() - 0.0001


## 写入 state.drive_intent；接受 cruise/dock 等同义词。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param mode 驾驶意图 forward/reverse/stop（含同义词）
static func set_intent(state: RunState, mode: String) -> void:
	var m := str(mode).to_lower()
	if (
		m in ["forward", "cruise", "reverse", "slow"]
		and state.breakdown_stop_hours_remaining > 0.001
	):
		state.drive_intent = "stop"
		return
	match m:
		"forward", "cruise":
			state.drive_intent = "forward"
		"reverse", "slow":
			state.drive_intent = "reverse"
		"stop", "dock":
			state.drive_intent = "stop"
			CombatL1.try_open_pending_threat(state)
		_:
			push_warning("DriveService: unknown intent " + mode)
			return


## 03 §6.2：`balance.travel` × speedClimate 走廊速度 km/h。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 浮点结果（量/比率/工时）。
static func travel_speed_kmh(state: RunState) -> float:
	var mult := float(ConfigDb.require("balance.travel.corridorMult"))
	var tactical_base := float(ConfigDb.require("balance.travel.tacticalBaseKmh"))
	var div := float(ConfigDb.require("balance.travel.tacticalDivisor"))
	if div <= 0.0:
		push_warning("DriveService: balance.travel.tacticalDivisor invalid")
		div = 1.0
	var tactical := tactical_base * maxf(0.1, state.speed_climate)
	return mult * (tactical / div)


## RegionRun.segment_index 指向的 Segment 或 null。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 段实例；不存在时为 null。
static func active_segment(state: RunState) -> Segment:
	if state.region_run == null:
		return null
	return state.region_run.active_segment()


## 本游戏日结束：写入将参与下一步 day_settle F04 的小时与里程（日结后清零）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
static func accrue_end_of_day(state: RunState) -> void:
	var cap := hours_cap()
	match state.drive_intent:
		"forward":
			if not travel_budget_exhausted(state):
				var room := maxf(0.0, cap - state.drive_hours_today)
				if room > 0.001:
					state.drive_hours_today += room
					_apply_forward_km(state, room)
			# 额度用尽：不加 km；F04 仍由 fuel_f04 按小时拆分（余下时间视同停靠系数）
		"reverse":
			var max_rev := minf(cap, 1.0)
			var room_rev := maxf(0.0, max_rev - state.reverse_hours_today)
			if room_rev > 0.001:
				state.reverse_hours_today += room_rev
				_apply_reverse_km(state, room_rev * travel_speed_kmh(state))
		_:
			pass


## 抛锚强制停：按 `day_delta×24` 递减剩余游戏小时，未耗尽前保持 `stop`。
static func tick_breakdown_stop(state: RunState, day_delta: float) -> void:
	if day_delta <= 0.0 or state.breakdown_stop_hours_remaining <= 0.001:
		return
	state.breakdown_stop_hours_remaining = maxf(
		0.0,
		state.breakdown_stop_hours_remaining - day_delta * 24.0
	)
	if state.breakdown_stop_hours_remaining > 0.001:
		state.drive_intent = "stop"


## 日钟 tick：`day_delta` 为已流逝的「游戏日份额」0~1（forward 按额度线性折合小时）。
##
## 公开 API：由 `GameSession` 日钟驱动；日结边界仍 `accrue_end_of_day` 补足未 tick 部分。
## @param state 当前局 `RunState`（就地修改字段）
## @param day_delta 本帧流逝的游戏日比例
static func tick_travel(state: RunState, day_delta: float) -> void:
	if day_delta <= 0.0:
		return
	tick_breakdown_stop(state, day_delta)
	var cap := hours_cap()
	match state.drive_intent:
		"forward":
			if not travel_budget_exhausted(state):
				var want := day_delta * cap
				var room := maxf(0.0, cap - state.drive_hours_today)
				var eff := minf(want, room)
				if eff > 0.0:
					state.drive_hours_today += eff
					_apply_forward_km(state, eff)
		"reverse":
			var max_rev := minf(cap, 1.0)
			var want_rev := day_delta * max_rev
			var room_rev := maxf(0.0, max_rev - state.reverse_hours_today)
			var rev := minf(want_rev, room_rev)
			if rev > 0.0:
				state.reverse_hours_today += rev
				_apply_reverse_km(state, rev * travel_speed_kmh(state))
		_:
			pass


## 增加 active_segment.progress_km；首次越过 length 调 RegionService.after_travel_day。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param eff_hours（float）
static func _apply_forward_km(state: RunState, eff_hours: float) -> void:
	var seg := active_segment(state)
	if seg == null or eff_hours <= 0.0:
		return
	var delta := travel_speed_kmh(state) * eff_hours
	var before := seg.progress_km
	seg.progress_km = minf(seg.length_km, seg.progress_km + delta)
	if seg.progress_km >= seg.length_km - 0.05 and before < seg.length_km - 0.05:
		RegionService.after_travel_day(state)


## 返程可跨段回退 segment_index 并扣 progress_km。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param delta_km（float）
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