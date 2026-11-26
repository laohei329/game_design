class_name DaySettle
extends RefCounted
## 02 §8 onDayStart — order locked; steps 4–8 minimal until population/workshop land.


static func _clamp_resource(state: RunState, key: String, value: float, cap: float) -> float:
	return clampf(value, 0.0, cap)


static func _process_delayed_events(state: RunState, next_day: int) -> void:
	var keep: Array = []
	for ev in state.delayed_events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var fire := int(ev.get("fireOnDay", -1))
		if fire == next_day:
			# S2：结算选项；若改气候因子则 ClimateService.recompute
			continue
		keep.append(ev)
	state.delayed_events = keep


static func _greenhouse_car_count(state: RunState) -> int:
	var n := 0
	for c in state.carriages:
		var tid := str(c.get("templateId", ""))
		if tid == "greenhouse":
			n += 1
	return n


static func _water_car_count(state: RunState) -> int:
	var n := 0
	for c in state.carriages:
		var tid := str(c.get("templateId", ""))
		if tid == "water":
			n += 1
	return n


static func _step_4_greenhouse(state: RunState) -> void:
	var cars := _greenhouse_car_count(state)
	if cars <= 0:
		return
	var out_per := float(ConfigDb.require("balance.greenhouse.fullOutputPerDay"))
	var overlap := float(ConfigDb.require("balance.greenhouse.overlap"))
	var racks := cars # sim 薄模型：每节 1 架满效率
	var mult := pow(overlap, maxf(0, racks - 1))
	var out := out_per * racks * mult * state.greenhouse_climate
	state.food = _clamp_resource(state, "food", state.food + out, InventoryService.stock_cap(state, "food"))


static func _step_5_water(state: RunState) -> void:
	if state.fuel <= 0.0:
		return
	var cars := _water_car_count(state)
	if cars <= 0:
		return
	var basic := float(ConfigDb.require("balance.water.basicOutputPerDay"))
	var overlap := float(ConfigDb.require("balance.water.overlap"))
	var mult := pow(overlap, maxf(0, cars - 1))
	var out := basic * cars * mult
	state.water = _clamp_resource(state, "water", state.water + out, InventoryService.stock_cap(state, "water"))


static func _step_8b_breakdown(state: RunState) -> void:
	if state.body_hp >= 30.0:
		state.breakdown_counter = 0
		return
	if state.breakdown_counter >= 3:
		state.breakdown_counter = 0
		state.drive_hours_today = 0.0
		state.reverse_hours_today = 0.0
		# TODO: forced stop 2h (03 §6.3) when drive_service exists
	else:
		state.breakdown_counter += 1


static func run(state: RunState) -> void:
	var next_day := state.day_total + 1
	state.heating_applied_today = false

	# −1 delayed events (due on upcoming day index)
	_process_delayed_events(state, next_day)

	# 0 — F04 with yesterday hours; climate = **maintained** fuel_climate (02 §8 / 01 §4.3)
	var fuel_burn_pct := FuelF04.compute_day_burn_percent(state)
	state.drive_hours_today = 0.0
	state.reverse_hours_today = 0.0

	# 1 — climate for the day being entered
	ClimateService.recompute(state, next_day)

	# 2 — food / water (onboard × base × climate)
	var pop := maxi(1, TrainService.onboard_count(state))
	var food_use := float(pop) * 0.9 * state.food_climate
	var water_use := float(pop) * 0.8 * state.water_climate
	state.food = maxf(0.0, state.food - food_use)
	state.water = maxf(0.0, state.water - water_use)
	state.food_went_zero = state.food <= 0.0
	state.water_went_zero = state.water <= 0.0
	state.food_zero_streak = state.food_zero_streak + 1 if state.food_went_zero else 0
	state.water_zero_streak = state.water_zero_streak + 1 if state.water_went_zero else 0

	# 3 — apply step 0 fuel burn
	state.fuel = _clamp_resource(state, "fuel", state.fuel - fuel_burn_pct, state.fuel_cap())

	# 3b — greenhouse heating (01 §8.1.1)
	var green_cars := _greenhouse_car_count(state)
	if state.cold_index >= 1.0 and state.heating_enabled and green_cars > 0:
		var heat_cost := float(ConfigDb.require("balance.greenhouse.heatingFuelPerCarDay")) * green_cars
		if state.fuel >= heat_cost:
			state.fuel -= heat_cost
			state.heating_applied_today = true
			state.greenhouse_climate = float(ConfigDb.require("balance.greenhouse.heatingMult"))
		else:
			state.greenhouse_climate = float(ConfigDb.require("balance.greenhouse.noHeatWinterMult"))
	elif state.cold_index >= 1.0 and green_cars > 0:
		state.greenhouse_climate = float(ConfigDb.require("balance.greenhouse.noHeatWinterMult"))

	state.fuel = _clamp_resource(state, "fuel", state.fuel, state.fuel_cap())

	# 3c — fuel streak after all fuel deductions
	if state.fuel <= 0.0:
		state.fuel_zero_streak += 1
	else:
		state.fuel_zero_streak = 0

	# 4–5 production (after deductions; skipped if no cars)
	_step_4_greenhouse(state)
	_step_5_water(state)

	# 6 workshop — deferred (S1a population/jobs)

	# 7 zero consequences — fuel failure gate only (S0)
	if state.fuel_zero_streak >= 3:
		state.failed = "fuel"

	# 7b morale — deferred

	# 8 pressure refresh / recruit — deferred (S2 / members)

	_step_8b_breakdown(state)