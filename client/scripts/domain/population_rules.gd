class_name PopulationRules
extends RefCounted
## `balance.population` / `fuelTank` 薄封装（轻伤、士气、油舱、日岗参数）。


static func injured_hp_threshold() -> float:
	return float(ConfigDb.require("balance.population.injuredHpThreshold"))


static func mood_min() -> float:
	return float(ConfigDb.require("balance.population.moodMin"))


static func mood_max() -> float:
	return float(ConfigDb.require("balance.population.moodMax"))


static func mood_default() -> float:
	return float(ConfigDb.require("balance.population.moodDefault"))


static func clamp_mood(value: float) -> float:
	return clampf(value, mood_min(), mood_max())


static func morale_offset_min() -> float:
	return float(ConfigDb.require("balance.population.moraleOffsetMin"))


static func morale_offset_max() -> float:
	return float(ConfigDb.require("balance.population.moraleOffsetMax"))


static func morale_party_delta_min() -> float:
	return float(ConfigDb.require("balance.population.moralePartyDeltaMin"))


static func morale_party_delta_max() -> float:
	return float(ConfigDb.require("balance.population.moralePartyDeltaMax"))


static func morale_food_zero_penalty() -> float:
	return float(ConfigDb.require("balance.population.moraleFoodZeroPenalty"))


static func morale_water_zero_penalty() -> float:
	return float(ConfigDb.require("balance.population.moraleWaterZeroPenalty"))


static func morale_offset_recover_per_day() -> float:
	return float(ConfigDb.require("balance.population.moraleOffsetRecoverPerDay"))


static func morale_offset_decay_positive_per_day() -> float:
	return float(ConfigDb.require("balance.population.moraleOffsetDecayPositivePerDay"))


static func morale_zero_streak_fail() -> int:
	return int(ConfigDb.require("balance.population.moraleZeroStreakFail"))


static func fuel_zero_streak_fail() -> int:
	return int(ConfigDb.require("balance.population.fuelZeroStreakFail"))


static func resource_zero_streak_f39() -> int:
	return int(ConfigDb.require("balance.population.resourceZeroStreakF39"))


static func breakdown_counter_trigger() -> int:
	return int(ConfigDb.require("balance.population.breakdownCounterTrigger"))


static func breakdown_stop_hours() -> float:
	return float(ConfigDb.require("balance.population.breakdownStopHours"))


static func f39_hp_loss() -> float:
	return float(ConfigDb.require("balance.population.f39HpLoss"))


static func body_hp_breakdown_threshold() -> float:
	return float(ConfigDb.require("balance.population.bodyHpBreakdownThreshold"))


static func fuel_tank_base() -> float:
	return float(ConfigDb.require("balance.fuelTank.baseAmount"))


static func fuel_tank_per_cargo() -> float:
	return float(ConfigDb.require("balance.fuelTank.perCargoSize"))


static func job_assign_labor_keep_min() -> int:
	return int(ConfigDb.require("balance.population.jobAssignLaborKeepMin"))


static func job_slots_per_workshop() -> int:
	return int(ConfigDb.require("balance.population.jobSlotsPerWorkshop"))


static func mood_daily_base_delta() -> float:
	return float(ConfigDb.require("balance.population.moodDailyBaseDelta"))


static func mood_daily_no_job_penalty() -> float:
	return float(ConfigDb.require("balance.population.moodDailyNoJobPenalty"))


static func mood_daily_bedded_bonus() -> float:
	return float(ConfigDb.require("balance.population.moodDailyBeddedBonus"))


static func mood_daily_unbedded_penalty() -> float:
	return float(ConfigDb.require("balance.population.moodDailyUnbeddedPenalty"))


static func mood_daily_ration_bonus() -> float:
	return float(ConfigDb.require("balance.population.moodDailyRationBonus"))


static func mood_daily_living_tech_per_level() -> float:
	return float(ConfigDb.require("balance.population.moodDailyLivingTechPerLevel"))


static func collective_morale_clamp(value: float) -> float:
	return clampf(value, mood_min(), mood_max())