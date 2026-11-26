class_name ClimateService
extends RefCounted
## 01 §8 — effective temp → cold/heat → consumption multipliers.

const SEASON_BASE_TEMP := {
	"spring": 0.0,
	"summer": 1.0,
	"autumn": 0.0,
	"winter": -1.0,
}


static func _weather_row(weather_id: String) -> Dictionary:
	var root: Dictionary = ConfigDb.get_table("weather")
	var weathers: Variant = root.get("weathers", {})
	if typeof(weathers) != TYPE_DICTIONARY:
		return {}
	var row: Variant = weathers.get(weather_id, weathers.get("clear", {}))
	return row if typeof(row) == TYPE_DICTIONARY else {}


static func _sum_influence_temp(state: RunState) -> float:
	var s := 0.0
	for inf in state.climate_influences:
		if typeof(inf) == TYPE_DICTIONARY:
			if inf.has("tempMod"):
				s += float(inf.get("tempMod", 0.0))
			else:
				s += float(inf.get("tempDelta", 0.0))
	return s


static func recompute(state: RunState, calendar_day: int = -1) -> void:
	var day := calendar_day if calendar_day > 0 else state.day_total
	var season := GameCalendar.season_name_for_day(day)
	var base_temp: float = float(SEASON_BASE_TEMP.get(season, 0.0))
	var w := _weather_row(state.weather_id)
	var temp_mod := float(w.get("tempMod", 0.0))
	var water_mod := float(w.get("waterMod", 1.0))
	var speed_c := float(w.get("speedClimate", 1.0))
	var eff := clampf(base_temp + temp_mod + state.region_temp_mod + _sum_influence_temp(state), -2.0, 2.0)
	state.effective_temp = eff
	state.cold_index = maxf(0.0, -eff)
	state.heat_index = maxf(0.0, eff)

	var cold_tbl: Dictionary = ConfigDb.require("balance.climateColdFoodFuel")
	var food_c := 1.0
	var fuel_c := 1.0
	if state.cold_index >= 2.0:
		var c2: Dictionary = cold_tbl.get("cold2", {})
		food_c = float(c2.get("food", 1.4))
		fuel_c = float(c2.get("fuel", 1.56))
	elif state.cold_index >= 1.0:
		var c1: Dictionary = cold_tbl.get("cold1", {})
		food_c = float(c1.get("food", 1.25))
		fuel_c = float(c1.get("fuel", 1.43))
	elif state.cold_index >= 0.5:
		var c05: Dictionary = cold_tbl.get("cold0_5", {})
		food_c = float(c05.get("food", 1.1))
		fuel_c = float(c05.get("fuel", 1.15))

	var water_temp := 1.0
	if state.heat_index >= 1.0:
		water_temp = 1.5
	elif state.heat_index >= 0.5:
		water_temp = 1.2

	state.food_climate = food_c
	state.fuel_climate = fuel_c
	state.water_climate = water_temp * water_mod
	state.speed_climate = speed_c

	var heat_mult := float(ConfigDb.require("balance.greenhouse.heatingMult"))
	var no_heat := float(ConfigDb.require("balance.greenhouse.noHeatWinterMult"))
	if state.cold_index >= 1.0:
		state.greenhouse_climate = heat_mult if state.heating_applied_today else no_heat
	else:
		state.greenhouse_climate = 1.0