class_name FuelF04
extends RefCounted
## 02 §4 F04 — daily fuel burn (% of cap); step 0 uses **current** fuel_climate (pre–step 1 recompute).


static func loco_count(state: RunState) -> int:
	var n := 0
	for c in state.carriages:
		if str(c.get("templateId", "")) == "power":
			n += 1
	return n


static func sum_car_fuel_add(state: RunState) -> float:
	var templates: Dictionary = ConfigDb.get_table("carriages").get("templates", {})
	var add := 0.0
	for c in state.carriages:
		var tid := str(c.get("templateId", ""))
		var tpl: Variant = templates.get(tid, {})
		if typeof(tpl) == TYPE_DICTIONARY:
			add += float(tpl.get("fuelPerDayAdd", 0.0))
	add += float(ConfigDb.require("balance.fuel.extraLocoAdd")) * maxf(0, loco_count(state) - 1)
	return add


static func traction(state: RunState) -> float:
	var per_loco := float(ConfigDb.require("balance.fuel.tractionPerLoco"))
	var per_tech := float(ConfigDb.require("balance.fuel.tractionPerPowerTech"))
	var floor_v := float(ConfigDb.require("balance.fuel.tractionFloor"))
	var n := loco_count(state)
	return maxf(floor_v, 1.0 - per_loco * minf(3, n) - per_tech * float(state.power_tech))


static func daily_rate_at_speed_coef(state: RunState, speed_coef: float, craft_day: bool = false) -> float:
	var base := float(ConfigDb.require("balance.fuel.base"))
	var add := sum_car_fuel_add(state)
	var craft := float(ConfigDb.require("balance.fuel.craftFuelPerDay")) if craft_day else 0.0
	var mult := minf(speed_coef * state.fuel_climate * state.region_fuel_mult, 3.0)
	return (base + add) * traction(state) * mult + craft


static func daily_speed_coef_from_hours(
	state: RunState,
	forward_h: float,
	reverse_h: float,
	dock_h: float,
) -> float:
	var cap := float(ConfigDb.require("balance.time.driveHoursPerDayCap"))
	var cruise := float(ConfigDb.require("balance.fuel.speedCoefCruise"))
	var slow := float(ConfigDb.require("balance.fuel.speedCoefSlow"))
	var dock := float(ConfigDb.require("balance.fuel.speedCoefDock"))
	var eff_fwd := minf(forward_h, cap)
	var total := maxf(24.0, eff_fwd + reverse_h + dock_h)
	if total <= 0.0:
		return dock
	return (eff_fwd * cruise + reverse_h * slow + dock_h * dock) / 24.0


static func compute_day_burn_percent(state: RunState, craft_day: bool = false) -> float:
	var cap := float(ConfigDb.require("balance.time.driveHoursPerDayCap"))
	var cruise := float(ConfigDb.require("balance.fuel.speedCoefCruise"))
	var slow := float(ConfigDb.require("balance.fuel.speedCoefSlow"))
	var dock := float(ConfigDb.require("balance.fuel.speedCoefDock"))
	var fwd := minf(state.drive_hours_today, cap)
	var rev := maxf(0.0, state.reverse_hours_today)
	var dock_h := maxf(0.0, 24.0 - fwd - rev)
	var burn := 0.0
	if fwd > 0.0:
		burn += daily_rate_at_speed_coef(state, cruise, craft_day) * (fwd / 24.0)
	if rev > 0.0:
		burn += daily_rate_at_speed_coef(state, slow, craft_day) * (rev / 24.0)
	if dock_h > 0.0:
		burn += daily_rate_at_speed_coef(state, dock, craft_day) * (dock_h / 24.0)
	# 昨日无行驶记录时默认全日停靠（教程开局）
	if fwd <= 0.0 and rev <= 0.0:
		burn = daily_rate_at_speed_coef(state, dock, craft_day)
	return burn