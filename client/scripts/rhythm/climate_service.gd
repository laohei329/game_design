class_name ClimateService
extends RefCounted
## 气候乘子唯一写入口：effective_temp → cold/heat index → food/water/fuel/greenhouse/speed 倍率。
##
## 输入：当前 day_total（或传入 calendar_day）、weather_id、region 影响、climate_influences[]。
## 调用点：日结步骤 1、SET_HEATING、PICK_REGION、挂车后 StationService、NEW_RUN 末 sync。

static func _season_base_temp(season: String) -> float:
	return float(ConfigDb.require("balance.time.seasonBaseTemp." + season))

## 从 `weather` 表取当前 `weather_id` 行；缺则退回温和默认。
##
## 节拍层 Service：日结、换区、段建造时调用；HUD 只读派生乘子。
## @param weather_id weather 表 id
## @return 结果字典；缺失语义键时可能为空 {}。
static func _weather_row(weather_id: String) -> Dictionary:
	var path := "weather.weathers." + weather_id
	if not ConfigDb.has(path):
		path = "weather.weathers.clear"
	var row: Variant = ConfigDb.require(path)
	return row if typeof(row) == TYPE_DICTIONARY else {}

## 累加 `climate_influences` 中温度分量，供 HUD/油耗展示。
##
## 节拍层 Service：日结、换区、段建造时调用；HUD 只读派生乘子。
## @param state 当前局 `RunState`（就地修改字段）
## @return 浮点结果（量/比率/工时）。
static func _sum_influence_temp(state: RunState) -> float:
	var s := 0.0
	for inf in state.climate_influences:
		if typeof(inf) == TYPE_DICTIONARY:
			if inf.has("tempMod"):
				s += float(inf.get("tempMod", 0.0))
			else:
				s += float(inf.get("tempDelta", 0.0))
	return clampf(s, -1.5, 1.5)


static func _product_influence_mult(state: RunState, field: String) -> float:
	var p := 1.0
	for inf in state.climate_influences:
		if typeof(inf) == TYPE_DICTIONARY and inf.has(field):
			p *= float(inf.get(field, 1.0))
	return p


## 气候重算**唯一公开触发**（各系统勿直接写 `*_climate`）。
static func refresh(state: RunState, calendar_day: int = -1) -> void:
	recompute(state, calendar_day)


## 根据季节、天气、区温、气候影响，写回 state.*_climate 与 cold/heat 指数。
##
## 实现体：仅由 `refresh()` 调用；`calendar_day=-1` 时用 `state.day_total`。
## @param state 当前局 `RunState`（就地修改字段）
## @param calendar_day 用于气候公历日；`-1` 表示 state.day_total
static func recompute(state: RunState, calendar_day: int = -1) -> void:
	var day := calendar_day if calendar_day > 0 else state.day_total
	var season := GameCalendar.season_name_for_day(day)
	var base_temp: float = _season_base_temp(season)
	var w := _weather_row(state.weather_id)
	var temp_mod := float(w["tempMod"]) if w.has("tempMod") else 0.0
	var water_mod := float(w["waterMod"]) if w.has("waterMod") else 1.0
	var speed_c := float(w["speedClimate"]) if w.has("speedClimate") else 1.0
	var eff := clampf(base_temp + temp_mod + state.region_temp_mod + _sum_influence_temp(state), -2.0, 2.0)
	state.effective_temp = eff
	state.cold_index = maxf(0.0, -eff)
	state.heat_index = maxf(0.0, eff)

	var food_c := 1.0
	var fuel_c := 1.0
	if state.cold_index >= 2.0:
		food_c = float(ConfigDb.require("balance.climateColdFoodFuel.cold2.food"))
		fuel_c = float(ConfigDb.require("balance.climateColdFoodFuel.cold2.fuel"))
	elif state.cold_index >= 1.0:
		food_c = float(ConfigDb.require("balance.climateColdFoodFuel.cold1.food"))
		fuel_c = float(ConfigDb.require("balance.climateColdFoodFuel.cold1.fuel"))
	elif state.cold_index >= 0.5:
		food_c = float(ConfigDb.require("balance.climateColdFoodFuel.cold0_5.food"))
		fuel_c = float(ConfigDb.require("balance.climateColdFoodFuel.cold0_5.fuel"))

	var water_temp := 1.0
	if state.heat_index >= 1.0:
		water_temp = float(ConfigDb.require("balance.climateHeatWater.heat1"))
	elif state.heat_index >= 0.5:
		water_temp = float(ConfigDb.require("balance.climateHeatWater.heat0_5"))

	var inf_water := _product_influence_mult(state, "waterMod")
	var inf_speed := _product_influence_mult(state, "speedMult")

	state.food_climate = food_c
	state.fuel_climate = fuel_c
	state.water_climate = water_temp * water_mod * inf_water
	state.speed_climate = speed_c * inf_speed

	var heat_mult := float(ConfigDb.require("balance.greenhouse.heatingMult"))
	var no_heat := float(ConfigDb.require("balance.greenhouse.noHeatWinterMult"))
	if state.cold_index >= 1.0:
		state.greenhouse_climate = heat_mult if state.heating_applied_today else no_heat
	else:
		state.greenhouse_climate = 1.0