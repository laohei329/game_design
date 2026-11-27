class_name PopulationConsumption
extends RefCounted
## 全放逐之城式：每位乘员独立 `hunger`/`thirst`，日钟内饿/渴上升，到阈值从全车粮水取食。
##
## 同日总消耗仍对齐 `foodPerCapitaDay`×人数×气候（02 §8）；日结 `reconcile_day_end` 只补差与 streak。

const _GameClock := preload("res://scripts/rhythm/game_clock.gd")


static func _pop_float(key: String) -> float:
	return float(ConfigDb.require("balance.population." + key))


static var _food_applied_today: float = 0.0
static var _water_applied_today: float = 0.0


static func _add_food_applied(amt: float) -> void:
	_food_applied_today += maxf(0.0, amt)


static func _add_water_applied(amt: float) -> void:
	_water_applied_today += maxf(0.0, amt)


static func reset_day_counters() -> void:
	_food_applied_today = 0.0
	_water_applied_today = 0.0


static func export_day_counters() -> Dictionary:
	return {
		"foodAppliedToday": _food_applied_today,
		"waterAppliedToday": _water_applied_today,
	}


static func food_applied_today() -> float:
	return _food_applied_today


static func water_applied_today() -> float:
	return _water_applied_today


static func restore_day_counters(rt: Dictionary) -> void:
	if typeof(rt) != TYPE_DICTIONARY or not rt.has("foodAppliedToday"):
		reset_day_counters()
		return
	_food_applied_today = maxf(0.0, float(rt.get("foodAppliedToday", 0)))
	_water_applied_today = maxf(0.0, float(rt.get("waterAppliedToday", 0)))


static func patch_members(state: RunState) -> void:
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if not m.has("hunger"):
			m["hunger"] = 0.0
		if not m.has("thirst"):
			m["thirst"] = 0.0


## 存活且 hp>0 的成员字典列表（引用）。
static func _living_members(state: RunState) -> Array:
	var out: Array = []
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if float(m.get("hp", 0.0)) <= 0.0:
			continue
		out.append(m)
	return out


## 本日全车理论粮需求（对表 sim）。
static func daily_food_need(state: RunState) -> float:
	var pop := maxi(1, _living_members(state).size())
	var food_per := _pop_float("foodPerCapitaDay")
	return float(pop) * food_per * state.food_climate


static func daily_water_need(state: RunState) -> float:
	var pop := maxi(1, _living_members(state).size())
	var water_per := _pop_float("waterPerCapitaDay")
	return float(pop) * water_per * state.water_climate


static func tick(state: RunState, day_delta: float) -> void:
	if day_delta <= 0.0 or state.failed != "":
		return
	patch_members(state)
	var hunger_rise := _pop_float("hungerRisePerDay")
	var thirst_rise := _pop_float("thirstRisePerDay")
	var eat_thr := _pop_float("eatUrgeThreshold")
	var drink_thr := _pop_float("drinkUrgeThreshold")
	var sat_h := _pop_float("satisfactionHungerPerFullDayRation")
	var sat_w := _pop_float("satisfactionThirstPerFullDayRation")
	var starve_thr := _pop_float("starvingHungerThreshold")
	var hp_loss := _pop_float("hpLossPerDayAtStarving")
	var food_per := _pop_float("foodPerCapitaDay") * state.food_climate
	var water_per := _pop_float("waterPerCapitaDay") * state.water_climate
	var partial_pen := _pop_float("tickPartialShortfallPenalty")
	var thirst_hp_frac := _pop_float("thirstStarvingHpLossFraction")
	var metabolism: float = _GameClock.metabolism_mult(state)
	var bite_f: float = food_per * day_delta * metabolism
	var bite_w: float = water_per * day_delta * metabolism

	for m in _living_members(state):
		var hunger := float(m.get("hunger", 0.0))
		var thirst := float(m.get("thirst", 0.0))
		hunger = clampf(hunger + hunger_rise * day_delta * metabolism, 0.0, 100.0)
		thirst = clampf(thirst + thirst_rise * day_delta * metabolism, 0.0, 100.0)

		if hunger >= eat_thr or bite_f > 0.0001:
			var want := bite_f
			var got := InventoryService.remove(state, "food", want)
			_add_food_applied(got)
			if want > 0.0001:
				var fed := clampf(got / want, 0.0, 1.0)
				hunger = maxf(0.0, hunger - fed * sat_h * day_delta * 24.0)
			if got + 0.0001 < want:
				hunger = minf(100.0, hunger + (want - got) / maxf(food_per, 0.01) * partial_pen)

		if thirst >= drink_thr or bite_w > 0.0001:
			var want_w := bite_w
			var got_w := InventoryService.remove(state, "water", want_w)
			_add_water_applied(got_w)
			if want_w > 0.0001:
				var fed_w := clampf(got_w / want_w, 0.0, 1.0)
				thirst = maxf(0.0, thirst - fed_w * sat_w * day_delta * 24.0)
			if got_w + 0.0001 < want_w:
				thirst = minf(100.0, thirst + (want_w - got_w) / maxf(water_per, 0.01) * partial_pen)

		if hunger >= starve_thr:
			var hp := float(m.get("hp", 100.0))
			m["hp"] = maxf(0.0, hp - hp_loss * day_delta * metabolism)
		if thirst >= starve_thr:
			var hp2 := float(m.get("hp", 100.0))
			m["hp"] = maxf(0.0, hp2 - hp_loss * thirst_hp_frac * day_delta * metabolism)

		m["hunger"] = hunger
		m["thirst"] = thirst

	state.food_went_zero = state.food <= 0.0
	state.water_went_zero = state.water <= 0.0


## 日结补 tick 差额（冒烟/跳帧全日）；并更新 streak。
static func reconcile_day_end(state: RunState) -> void:
	var alive := _living_members(state)
	if alive.is_empty():
		reset_day_counters()
		return
	var target_f := daily_food_need(state)
	var target_w := daily_water_need(state)
	var rem_f := maxf(0.0, target_f - _food_applied_today)
	var rem_w := maxf(0.0, target_w - _water_applied_today)
	var hun_fed := _pop_float("reconcileHungerFedDelta")
	var hun_short := _pop_float("reconcileHungerShortfallDelta")
	var thr_fed := _pop_float("reconcileThirstFedDelta")
	var thr_short := _pop_float("reconcileThirstShortfallDelta")

	if rem_f > 0.0:
		var per := rem_f / float(alive.size())
		for m in alive:
			var got := InventoryService.remove(state, "food", per)
			_add_food_applied(got)
			var hunger := float(m.get("hunger", 0.0))
			if got + 0.0001 >= per:
				hunger = maxf(0.0, hunger - hun_fed)
			else:
				hunger = minf(100.0, hunger + hun_short)
			m["hunger"] = hunger

	if rem_w > 0.0:
		var per_w := rem_w / float(alive.size())
		for m in alive:
			var got_w := InventoryService.remove(state, "water", per_w)
			_add_water_applied(got_w)
			var thirst := float(m.get("thirst", 0.0))
			if got_w + 0.0001 >= per_w:
				thirst = maxf(0.0, thirst - thr_fed)
			else:
				thirst = minf(100.0, thirst + thr_short)
			m["thirst"] = thirst

	state.food_went_zero = state.food <= 0.0
	state.water_went_zero = state.water <= 0.0
	state.food_zero_streak = state.food_zero_streak + 1 if state.food_went_zero else 0
	state.water_zero_streak = state.water_zero_streak + 1 if state.water_went_zero else 0
	reset_day_counters()