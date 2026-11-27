class_name SmokeAssertionsCore
extends RefCounted
## 冒烟：场景/配置/开局与三选一日结差分。

const _Helpers := preload("res://scripts/qa/smoke_assertions_helpers.gd")
const _MemberMorale := preload("res://scripts/economy/member_morale.gd")

const M1_REQUIRE_PATHS: PackedStringArray = [
	"balance.start.food",
	"balance.start.water",
	"balance.start.fuel",
	"balance.start.parts",
	"balance.time.driveHoursPerDayCap",
	"balance.time.daysPerSeason",
	"balance.fuel.base",
	"balance.fuel.speedCoefDock",
	"balance.greenhouse.fullOutputPerDay",
	"balance.greenhouse.heatingFuelPerCarDay",
	"balance.greenhouse.heatingMult",
	"balance.greenhouse.noHeatWinterMult",
	"balance.water.basicOutputPerDay",
	"balance.stations.guaranteeAfter",
	"balance.stations.tutorialRegion",
	"balance.regions.defaultFuelMult",
	"balance.population.foodPerCapitaDay",
	"balance.population.waterPerCapitaDay",
	"balance.population.injuredHpThreshold",
	"balance.population.moodDefault",
	"balance.population.moodDailyBaseDelta",
	"balance.population.moraleFoodZeroPenalty",
	"balance.fuelTank.baseAmount",
	"balance.fuelTank.perCargoSize",
	"balance.search.maxAssignPerPointPerDay",
	"balance.search.hoursPerTask",
	"balance.haul.hoursPerTask",
	"balance.train.abandonPartsCost",
	"balance.train.abandonScrapRatio",
	"balance.start.precision",
	"balance.workshop.precisionStart",
	"balance.workshop.partsPerPrecision",
	"archetypes.startPartyTemplate",
	"combat.l1Unit",
	"balance.inventory.base.food",
	"balance.fuelTank.baseAmount",
	"balance.travel.corridorMult",
	"balance.travel.tacticalBaseKmh",
	"balance.travel.tacticalDivisor",
	"balance.eventDraw.scenarioEventRate",
	"difficulty.tiers.normal.multipliers.eventDrawRate",
	"balance.recruit.dayEndBaseRate",
]

static func errors_main_scenes_load() -> PackedStringArray:
	var errs: PackedStringArray = []
	for path in [
		"res://scenes/run_main.tscn",
		"res://scenes/boot.tscn",
		"res://scenes/ui/hud_top.tscn",
		"res://scenes/ui/region_pick.tscn",
		"res://scenes/ui/tech_panel.tscn",
		"res://scenes/ui/combat_panel.tscn",
		"res://scenes/ui/event_modal.tscn",
	]:
		if not ResourceLoader.exists(path):
			errs.append("missing scene " + path)
			continue
		var res: Resource = load(path)
		if res == null:
			errs.append("load failed " + path)
	return errs


static func errors_config_paths() -> PackedStringArray:
	var errs: PackedStringArray = []
	for path in M1_REQUIRE_PATHS:
		var v: Variant = ConfigDb.require(path)
		if v == null:
			errs.append("ConfigDb.require 缺失: " + path)
	var hints: Dictionary = ConfigDb.get_table("hud_hints")
	if hints.is_empty():
		errs.append("hud_hints 表空")
	var st_g: int = int(ConfigDb.get_table("stations").get("guaranteeAfter", -1))
	var bal_g: int = int(ConfigDb.require("balance.stations.guaranteeAfter"))
	if st_g >= 0 and st_g != bal_g:
		errs.append("guaranteeAfter 不一致 stations=%d balance=%d" % [st_g, bal_g])
	var tpl: Variant = ConfigDb.require("archetypes.startPartyTemplate")
	if typeof(tpl) != TYPE_DICTIONARY:
		errs.append("archetypes.startPartyTemplate 非对象")
	elif typeof(tpl.get("members", null)) != TYPE_ARRAY or tpl.get("members", []).size() != 4:
		errs.append("archetypes.startPartyTemplate.members 须为 4 人")
	return errs

## 冒烟：开局四人岗位/名册。
static func errors_start_crew(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	if state.members.size() != 4:
		errs.append("开局成员数应为 4 实际 %d" % state.members.size())
		return errs
	var jobs: Dictionary = {}
	var combat_n := 0
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var job := str(m.get("job", ""))
		jobs[job] = int(jobs.get(job, 0)) + 1
		if bool(m.get("combatRoster", false)):
			combat_n += 1
	if int(jobs.get("none", 0)) != 4:
		errs.append("开局四人应均为无岗 none jobs=%s" % str(jobs))
	if combat_n < 1:
		errs.append("开局 combatRoster 至少 1 人")
	return errs

## 冒烟：F04 用表内 base 非硬编码。
static func errors_fuel_uses_config(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	var base := float(ConfigDb.require("balance.fuel.base"))
	if base <= 0.0:
		errs.append("balance.fuel.base 无效")
		return errs
	var snap := _Helpers._snapshot_burn_inputs(state)
	snap.drive_hours_today = 0.0
	snap.reverse_hours_today = 0.0
	var dock_burn := FuelF04.compute_day_burn_percent(snap)
	if dock_burn <= 0.0:
		errs.append("F04 停靠日耗应为正")
	# 表格 +1 应抬高日耗（非硬编码常数）
	ConfigDb.tables["balance"]["fuel"]["base"] = base + 1.0
	var raised := FuelF04.compute_day_burn_percent(snap)
	ConfigDb.tables["balance"]["fuel"]["base"] = base
	if raised <= dock_burn:
		errs.append("改 balance.fuel.base 后 F04 未变化")
	return errs

## 冒烟：连点三日结后资源/日历变化。
static func audit_after_triplet_end_day(d0: int, f0: float, w0: float, fuel0: float) -> PackedStringArray:
	var errs: PackedStringArray = []
	if GameSession.state == null:
		errs.append("三轮 END_DAY 后 state 为空")
		return errs
	var st := GameSession.state
	if st.day_total != d0 + 3:
		errs.append("day_total 应为 %d 实际 %d" % [d0 + 3, st.day_total])
	if st.food >= f0 or st.water >= w0:
		errs.append("三轮后粮水应下降 food=%.2f water=%.2f" % [st.food, st.water])
	if st.fuel > fuel0 + 0.01:
		errs.append("三轮后油不应上升 fuel=%.2f" % [st.fuel])
	var rep := SoftLockProbe.audit(st)
	if not bool(rep.get("ok", false)):
		for line in rep.get("lines", []):
			errs.append("3日软锁: " + str(line))
	return errs


static func errors_member_mood_day_settle(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	if state.members.is_empty():
		errs.append("mood_daily 需要成员")
		return errs
	var m0: Dictionary = state.members[0]
	var before := float(m0.get("mood", 0.0))
	_MemberMorale.settle_daily_moods(state)
	var after := float(m0.get("mood", 0.0))
	if is_equal_approx(before, after):
		errs.append("mood_daily 应改变首成员 mood")
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mood := float(m.get("mood", -1.0))
		if mood < 0.0 or mood > 100.0:
			errs.append("mood_daily 越界 mood=%.2f" % mood)
	return errs


static func errors_start_precision(state: RunState) -> PackedStringArray:
	var errs: PackedStringArray = []
	var want := float(ConfigDb.require("balance.start.precision"))
	if not is_equal_approx(state.precision, want):
		errs.append("开局 precision 应为 %.0f, got=%.0f" % [want, state.precision])
	return errs

## 冒烟：三选一雪原 mult。
