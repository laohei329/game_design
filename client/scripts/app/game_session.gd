extends Node

const _BalanceStart := preload("res://scripts/data/balance_start.gd")
## 当前局状态与意图分发（Autoload GameSession）。

const _GameClock := preload("res://scripts/rhythm/game_clock.gd")
const _PopulationConsumption := preload("res://scripts/economy/population_consumption.gd")
const _IntentRouter := preload("res://scripts/app/session_intent_router.gd")
##
## - 持有唯一 `state: RunState`；`state_changed` 后 UI 从 GameSession 只读刷新。
## - 所有玩法入口：IntentBus → `_on_intent` → 各 *Service（见下 match）。
## - `search_telemetry`：按日统计每点搜索次数，供 SearchRules 上限；读档/新局会清空。
##
## 权威日结顺序：`_advance_one_day`（与 [02 §8](../../modules/02-resources.md) 对齐）。

signal state_changed
## UI 刷新：静态度用 `state_changed`；搜索/搬运进度另有 `search_panel._process` 高频条（M5 约定）。

var state: RunState = null
## 键：day_total 字符串 → { pointId → 当日搜索次数 }；写盘 `telemetry.searchByPointDay`。
var search_telemetry: Dictionary = {}
## 当日时钟进度 0~1（HUD）；写盘见 `runtime.dayClockFraction`（SaveService）。
var day_clock_fraction: float = 0.0
## 饥渴驱动 `state_changed` 最小间隔（秒，真实时间）。
const _VITALS_EMIT_INTERVAL_SEC: float = 0.25
var _vitals_emit_at_sec: float = 0.0
## 时间倍速 1 / 2 / 4（01 §2）。
var time_speed: float = 1.0
## 玩家手动暂停（与弹窗 `get_tree().paused` 叠加为停表）。
var time_paused: bool = false

## 订阅 IntentBus；全局限单例在 project.godot Autoload 阶段已就绪。
##
## 应用层 Autoload；串联 Intent 与各 Service。
## 无返回值。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	IntentBus.intent_emitted.connect(_on_intent)


func _process(delta: float) -> void:
	if state == null or state.failed != "":
		return
	if sim_time_frozen():
		return
	if time_speed <= 0.0:
		return
	var day_delta: float = _GameClock.day_delta_from_real_seconds(delta, time_speed)
	if day_delta <= 0.0:
		return
	var drv_before := state.drive_hours_today
	var frac_before := day_clock_fraction
	var food_before := state.food
	var water_before := state.water
	var outdoor_before := _outdoor_hours_done(state)
	var vitals_before := _members_vitals_sum(state)
	var crossed := false
	var remaining := day_delta
	var guard := 0
	while remaining > 0.000001 and guard < 8:
		guard += 1
		var room := maxf(0.0, 1.0 - day_clock_fraction)
		var chunk := minf(remaining, room)
		if chunk <= 0.0:
			break
		_apply_sim_day_chunk(chunk)
		remaining -= chunk
		if day_clock_fraction >= 1.0 - 0.0001:
			day_clock_fraction -= 1.0
			_advance_one_day()
			crossed = true
	var vitals_now := _members_vitals_sum(state)
	var vitals_moved := not is_equal_approx(vitals_before, vitals_now)
	var other_moved := (
		crossed
		or not is_equal_approx(drv_before, state.drive_hours_today)
		or not is_equal_approx(frac_before, day_clock_fraction)
		or not is_equal_approx(food_before, state.food)
		or not is_equal_approx(water_before, state.water)
		or not is_equal_approx(outdoor_before, _outdoor_hours_done(state))
	)
	if other_moved:
		state_changed.emit()
	elif vitals_moved and _should_emit_vitals_now():
		state_changed.emit()


func _members_vitals_sum(state: RunState) -> float:
	var sum := 0.0
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if float(m.get("hp", 0.0)) <= 0.0:
			continue
		sum += float(m.get("hunger", 0.0)) + float(m.get("thirst", 0.0))
	return sum


func _apply_sim_day_chunk(chunk: float) -> void:
	_GameClock.accrue_sim_day_fraction(chunk)
	if _GameClock.outdoor_work_active(state):
		_GameClock.accrue_outdoor_eligible_fraction(chunk)
	DriveService.tick_travel(state, chunk)
	_PopulationConsumption.tick(state, chunk)
	SearchService.tick(state, chunk)
	HaulService.tick(state, chunk)
	day_clock_fraction += chunk


func _should_emit_vitals_now() -> bool:
	var t := Time.get_ticks_msec() * 0.001
	if t - _vitals_emit_at_sec < _VITALS_EMIT_INTERVAL_SEC:
		return false
	_vitals_emit_at_sec = t
	return true


## 无头 `END_DAY` 或调试：若 HUD 进度>0 则补满本日 tick；否则只日结（避免与 reconcile 双扣粮）。
func _force_end_game_day() -> void:
	if day_clock_fraction > 0.001:
		var rem := maxf(0.0, 1.0 - day_clock_fraction)
		if rem > 0.000001:
			_apply_sim_day_chunk(rem)
		while day_clock_fraction >= 1.0 - 0.0001:
			day_clock_fraction -= 1.0
			_advance_one_day()
	else:
		day_clock_fraction = 0.0
		_advance_one_day()


func _outdoor_hours_done(state: RunState) -> float:
	var sum := 0.0
	for t in state.search_tasks:
		if typeof(t) == TYPE_DICTIONARY:
			sum += float(t.get("hoursDone", 0.0))
	for t in state.haul_tasks:
		if typeof(t) == TYPE_DICTIONARY:
			sum += float(t.get("hoursDone", 0.0))
	return sum


## 日钟是否停走：手动暂停 + 决策弹窗 `get_tree().paused`（各 modal 自管 pause）。
## 搜索面板仅 `search_panel_open`，不关表、不设 paused。
func sim_time_frozen() -> bool:
	if state == null:
		return true
	return time_paused or get_tree().paused


## IntentBus 唯一入口：match intent_name → 各 Service；失败 push_warning，成功 emit state_changed。
##
## Autoload 订阅 IntentBus 的唯一 match；成功 `state_changed.emit()`。
## @param intent_name IntentBus 意图名
## @param payload Intent 附带的 Dictionary
func _on_intent(intent_name: String, payload: Dictionary) -> void:
	if not _IntentRouter.dispatch(self, intent_name, payload):
		push_warning("GameSession: unhandled intent " + intent_name)


## SearchService.assign_search 机器码 → 本地化短句（push_warning）。
##
## @param code 机器错误码（本地化键前缀各异）
## @return 空串=成功；非空=机器错误码。
func _search_err_zh(code: String) -> String:
	return SearchService.localize_err(code)


## 读档：停靠且无户外任务时消费 `pending_threat`（对齐 `DriveService.set_intent(stop)`）。
func _sync_pending_threat_after_load(state: RunState) -> void:
	if state == null or state.failed != "":
		return
	if state.drive_intent != "stop":
		return
	if TrainService.has_outdoor_tasks(state):
		return
	if state.pending_threat.is_empty():
		return
	CombatL1.try_open_pending_threat(state)

## `END_DAY` 核心：驾驶累计 → 站/搜/搬日末 → 待战威胁 → `DaySettle.run` →
##
## 应用层 Autoload；串联 Intent 与各 Service。
## 无返回值。
func _advance_one_day() -> void:
	# 日切换前：把「本日驾驶小时」等写入 state，供紧接着的 DaySettle 步骤 0（F04）使用。
	DriveService.accrue_end_of_day(state)
	StationService.after_day_travel(state)
	SearchService.on_end_day(state)
	HaulService.on_end_day(state)
	_GameClock.reset_sim_day_fraction()
	TrainService.reconcile_outdoor_tasks(state)
	CombatL1.try_open_pending_threat(state)
	# 日结 02 §8（F04 / 粮水 / 生产 / 士气…）；仍在「旧 day_total」上结算。
	DaySettle.run(state)
	# 日历 +1 后，按新段同步天气并重算气候乘子（HUD / 油耗可见）。
	GameCalendar.advance_day(state)
	WeatherDraw.sync_weather_from_active_segment(state)
	ClimateService.refresh(state)
	state_changed.emit()

## `NEW_RUN`：RNG 种子、`balance.start` 资源、三节模板车、教程 RegionRun、
##
## 应用层 Autoload；串联 Intent 与各 Service。
## 无返回值。
func _new_run() -> void:
	# 开局：读 balance.start → 三节车 → 教程 RegionRun → 四人名册 → 清 UI 旗标。
	RngService.seed_from(int(Time.get_unix_time_from_system()) & 0x7FFFFFFF)
	state = RunState.new()
	_BalanceStart.apply_new_run(state)
	SegmentBuild.begin_tutorial_region_run(state)
	MemberRoster.seed_starting_crew(state)
	_PopulationConsumption.patch_members(state)
	CombatL1.seed_default_formation(state)  # combatRoster → fmt_default，供 L1 检定
	state.tutorial_done = false
	GameCalendar.sync_calendar_fields(state)
	search_telemetry.clear()
	state.search_tasks.clear()
	state.search_panel_open = false
	state.abandon_panel_open = false
	state.abandon_selected_car_id = ""
	state.region_pick_open = false
	state.region_pick_options.clear()
	state.tech_panel_open = false
	state.power_tech = 0
	state.armor_tech = 0
	state.radar_tech = 0
	state.living_tech = 0
	state.blueprints = {
		"power": false,
		"armor": false,
		"radar": false,
		"living": false,
	}
	state.morale_offset = 0.0
	state.pressure_history = ["", ""]
	state.pressure_display = ""
	state.haul_tasks.clear()
	state.combat_panel_open = false
	state.pending_combat.clear()
	state.combat_l1_after_fail = false
	state.event_modal_open = false
	state.incident_modal_open = false
	state.event_weight_history = []
	state.last_event_primary_tag = ""
	state.event_flags = {}
	state.last_recruit_success_day = -1
	state.morale_zero_streak = 0
	state.pending_threat.clear()
	state.breakdown_stop_hours_remaining = 0.0
	day_clock_fraction = 0.0
	time_speed = 1.0
	time_paused = false
	_PopulationConsumption.reset_day_counters()
	_GameClock.reset_sim_day_fraction()
	WeatherDraw.sync_weather_from_active_segment(state)
	state_changed.emit()


## 读档唯一附着 GameSession（日钟 HUD、遥测、事件同步）；`SaveService.load_into_game_session` 调用。
func apply_loaded_run(loaded: RunState) -> void:
	state = loaded
	day_clock_fraction = _GameClock.take_restored_hud_fraction()
	time_paused = false
	state.event_modal_open = false
	state.incident_modal_open = false
	TrainService.reconcile_outdoor_tasks(state)
	_sync_pending_threat_after_load(state)
	EventService.sync_after_load(state)
	IncidentService.sync_after_load(state)
	search_telemetry = SaveService.take_pending_search_telemetry()