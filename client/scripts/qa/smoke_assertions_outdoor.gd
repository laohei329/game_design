class_name SmokeAssertionsOutdoor
extends RefCounted
## 冒烟：户外日钟与 runtime 存档 roundtrip。

const _GameClock := preload("res://scripts/rhythm/game_clock.gd")
const _PopulationConsumption := preload("res://scripts/economy/population_consumption.gd")
const _Helpers := preload("res://scripts/qa/smoke_assertions_helpers.gd")

static func errors_outdoor_day_clock_p0_a(state: RunState, telem: Dictionary) -> PackedStringArray:
	var errs: PackedStringArray = []
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null or seg.points.is_empty():
		errs.append("outdoor_clock: 无搜索点")
		return errs
	var point_id := str(seg.points[0].get("id", ""))
	var mid := _Helpers.first_member_id(state, "labor")
	if mid.is_empty():
		errs.append("outdoor_clock: 无 labor")
		return errs
	var per_day := SearchRules.hours_progress_per_day()
	_Helpers._clear_search_tasks(state)
	_GameClock.reset_sim_day_fraction()
	_Helpers._intent_drive("stop")
	var err := _Helpers._intent_assign_search(point_id, [mid], telem)
	if err != "":
		errs.append("outdoor_clock assign: " + err)
		return errs
	var task: Dictionary = state.search_tasks[state.search_tasks.size() - 1]
	_Helpers._intent_drive("forward")
	_GameClock.accrue_sim_day_fraction(1.0)
	SearchService.on_end_day(state)
	var done_fwd := float(task.get("hoursDone", 0.0))
	if done_fwd > per_day * 0.05:
		errs.append(
			"outdoor_clock: forward+sim=1d 应几乎无搜索进度 got hoursDone=%.3f" % done_fwd
		)
	_GameClock.reset_sim_day_fraction()
	task["hoursDone"] = 0.0
	_Helpers._intent_drive("forward")
	_GameClock.accrue_sim_day_fraction(0.7)
	SearchService.on_end_day(state)
	if float(task.get("hoursDone", 0.0)) > per_day * 0.05:
		errs.append(
			"outdoor_clock: 行0.7日无停靠不应日末补课 got %.3f" % float(task.get("hoursDone", 0.0))
		)
	SearchService.recall_search(state, {"pointId": point_id})
	_GameClock.reset_sim_day_fraction()
	err = _Helpers._intent_assign_search(point_id, [mid], telem)
	if err != "":
		errs.append("outdoor_clock assign2: " + err)
		return errs
	task = state.search_tasks[state.search_tasks.size() - 1]
	_Helpers._intent_drive("stop")
	SearchService.on_end_day(state)
	var done_headless := float(task.get("hoursDone", 0.0))
	if done_headless + 0.001 < per_day:
		errs.append(
			"outdoor_clock: 无日钟 END_DAY 应补满工日 got %.3f want %.3f" % [done_headless, per_day]
		)
	SearchService.recall_search(state, {"pointId": point_id})
	_GameClock.reset_sim_day_fraction()
	err = _Helpers._intent_assign_search(point_id, [mid], telem)
	if err != "":
		errs.append("outdoor_clock assign3: " + err)
		return errs
	task = state.search_tasks[state.search_tasks.size() - 1]
	_Helpers._intent_drive("stop")
	_GameClock.accrue_outdoor_eligible_fraction(0.5)
	SearchService.tick(state, 0.5)
	_GameClock.accrue_sim_day_fraction(0.5)
	_Helpers._intent_drive("forward")
	_GameClock.accrue_sim_day_fraction(0.5)
	SearchService.on_end_day(state)
	var want_half := per_day * 0.5
	var done_mix := float(task.get("hoursDone", 0.0))
	if absf(done_mix - want_half) > per_day * 0.08:
		errs.append(
			"outdoor_clock: 停0.5+行0.5 期望≈半工日 got %.3f want %.3f" % [done_mix, want_half]
		)
	SearchService.recall_search(state, {"pointId": point_id})
	_GameClock.reset_sim_day_fraction()
	var haul_h := float(ConfigDb.require("balance.haul.hoursPerTask"))
	state.haul_tasks.append(
		{
			"pointId": point_id,
			"inventoryKey": "food",
			"amountPending": 1.0,
			"memberId": mid,
			"hoursTotal": haul_h,
			"hoursDone": 0.0,
			"complete": false,
			"auto": false,
		}
	)
	_Helpers._intent_drive("forward")
	_GameClock.accrue_sim_day_fraction(1.0)
	HaulService.on_end_day(state)
	var haul_done := 0.0
	if not state.haul_tasks.is_empty() and typeof(state.haul_tasks[0]) == TYPE_DICTIONARY:
		haul_done = float(state.haul_tasks[0].get("hoursDone", 0.0))
	if haul_done > haul_h * 0.05:
		errs.append("outdoor_clock: haul 全日 forward 不应日末补课 got %.3f" % haul_done)
	state.haul_tasks.clear()
	_GameClock.reset_sim_day_fraction()
	return errs


## SaveService 写盘：`runtime` 日钟 + 饥渴当日计数往返（槽 93）。
static func errors_runtime_day_clock_save_roundtrip(state: RunState) -> PackedStringArray:
	const SLOT := 93
	var errs: PackedStringArray = []
	_Helpers._intent_drive("stop")
	state.food = maxf(state.food, 18.0)
	state.water = maxf(state.water, 18.0)
	for m in state.members:
		if typeof(m) == TYPE_DICTIONARY and float(m.get("hp", 0)) > 0:
			m["hunger"] = maxf(float(m.get("hunger", 0)), 25.0)
			m["thirst"] = maxf(float(m.get("thirst", 0)), 25.0)
	_GameClock.reset_sim_day_fraction()
	_PopulationConsumption.reset_day_counters()
	GameSession.day_clock_fraction = 0.42
	_GameClock.accrue_sim_day_fraction(0.42)
	_GameClock.accrue_outdoor_eligible_fraction(0.42)
	_PopulationConsumption.tick(state, 0.35)
	var food_ap := _PopulationConsumption.food_applied_today()
	if food_ap < 0.0001:
		errs.append("day_clock_save: 半日 tick 应扣少量粮")
		return errs
	if not SaveService.write_state(state, SLOT):
		errs.append("day_clock_save: write 失败")
		return errs
	_GameClock.reset_sim_day_fraction()
	_PopulationConsumption.reset_day_counters()
	GameSession.day_clock_fraction = 0.0
	if SaveService.read_state(SLOT) == null:
		errs.append("day_clock_save: read 失败")
		return errs
	var hud := _GameClock.take_restored_hud_fraction()
	if absf(hud - 0.42) > 0.03:
		errs.append("day_clock_save: dayClockFraction got %.3f want ~0.42" % hud)
	if absf(_GameClock.sim_day_fraction_today() - 0.42) > 0.03:
		errs.append(
			"day_clock_save: simDayFraction got %.3f want ~0.42" % _GameClock.sim_day_fraction_today()
		)
	if absf(_PopulationConsumption.food_applied_today() - food_ap) > 0.05:
		errs.append(
			"day_clock_save: foodAppliedToday got %.4f want %.4f"
			% [_PopulationConsumption.food_applied_today(), food_ap]
		)
	return errs


## 测试前复位：清空 `search_tasks`/`haul_tasks` 并将成员 `taskState` 置 idle。
