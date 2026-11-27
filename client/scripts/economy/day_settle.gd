class_name DaySettle
extends RefCounted

const _PopulationRules := preload("res://scripts/domain/population_rules.gd")
const _MemberMorale := preload("res://scripts/economy/member_morale.gd")

const _PopulationConsumption := preload("res://scripts/economy/population_consumption.gd")
## 02 §8 onDayStart — order locked; steps 4–8 minimal until population/workshop land.

## 02 §8 前：处理 fireOnDay==next_day 的 delayed_events（S2 占位）。
##
## @param state 当前局 `RunState`（就地修改字段）
## @param next_day 即将进入的 day_total（延迟事件比对用）
static func _process_delayed_events(state: RunState, next_day: int) -> void:
	EventOps.process_due_delayed_events(state, next_day)


## 统计 templateId=greenhouse 节数（步骤 4/3b 供暖）。
##
## @param state 当前局 `RunState`（就地修改字段）
## @return 整数结果（计数/下标/容量）。
static func _greenhouse_car_count(state: RunState) -> int:
	var n := 0
	for c in state.carriages:
		var tid := str(c.get("templateId", ""))
		if tid == "greenhouse":
			n += 1
	return n


## 统计 templateId=water 净水节数（步骤 5）。
##
## @param state 当前局 `RunState`（就地修改字段）
## @return 整数结果（计数/下标/容量）。
static func _water_car_count(state: RunState) -> int:
	var n := 0
	for c in state.carriages:
		var tid := str(c.get("templateId", ""))
		if tid == "water":
			n += 1
	return n


## 步骤 4：种植产出 food，重叠架效率 overlap^ (n-1)× greenhouse_climate。
##
## 日结子步骤：仅 `DaySettle.run` 顺序调用；不直接响应 Intent。
## @param state 当前局 `RunState`（就地修改字段）
static func _step_4_greenhouse(state: RunState) -> void:
	var cars := _greenhouse_car_count(state)
	if cars <= 0:
		return
	var out_per := float(ConfigDb.require("balance.greenhouse.fullOutputPerDay"))
	var overlap := float(ConfigDb.require("balance.greenhouse.overlap"))
	var racks := cars # sim 薄模型：每节 1 架满效率
	var mult := pow(overlap, maxf(0, racks - 1))
	var out := out_per * racks * mult * state.greenhouse_climate
	InventoryService.add(state, "food", out)


## 步骤 5：净水产出 water（需 fuel>0；重叠衰减同温室）。
##
## 日结子步骤：仅 `DaySettle.run` 顺序调用；不直接响应 Intent。
## @param state 当前局 `RunState`（就地修改字段）
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
	InventoryService.add(state, "water", out)


## 统计 templateId=workshop 节数（步骤 6）。
##
## @param state 当前局 `RunState`（就地修改字段）
## @return 整数结果（计数/下标/容量）。
static func _workshop_car_count(state: RunState) -> int:
	var n := 0
	for c in state.carriages:
		if str(c.get("templateId", "")) == "workshop":
			n += 1
	return n


## 02 §8 步骤 6：有油则涨 precision 并按档产出零件；无油 precision 衰减（精炼分支占位）。
##
## 日结子步骤：仅 `DaySettle.run` 顺序调用；不直接响应 Intent。
## @param state 当前局 `RunState`（就地修改字段）
static func _step_6_workshop(state: RunState) -> void:
	var cars := _workshop_car_count(state)
	if cars <= 0:
		return
	var craft_bonus := float(ConfigDb.require("balance.workshop.precisionPerCraftDay"))
	var decay := float(ConfigDb.require("balance.workshop.precisionIdleDecay"))
	var refining := state.scrap > 0.0 and state.fuel > 0.0
	if refining:
		var scrap_batch := float(ConfigDb.require("balance.workshop.scrapPerRefineBatch"))
		var parts_batch := float(ConfigDb.require("balance.workshop.partsPerRefineBatch"))
		var batches := mini(cars, int(state.scrap / scrap_batch))
		if batches > 0:
			var spend := scrap_batch * float(batches)
			InventoryService.remove(state, "scrap", spend)
			InventoryService.add(state, "parts", parts_batch * float(batches))
	elif state.fuel > 0.0:
		state.precision += craft_bonus
		var parts_per := float(ConfigDb.require("balance.workshop.partsPerPrecision"))
		var out := (state.precision / parts_per) * float(cars)
		if out > 0.0:
			InventoryService.add(state, "parts", out)
	else:
		state.precision = maxf(0.0, state.precision + decay)


## F39 / 燃油三连零：扣全员 HP 或标 failed=fuel（薄实现）。
##
## 日结子步骤：仅 `DaySettle.run` 顺序调用；不直接响应 Intent。
## @param state 当前局 `RunState`（就地修改字段）
static func _step_7_zero_consequences(state: RunState) -> void:
	if state.fuel_zero_streak >= _PopulationRules.fuel_zero_streak_fail():
		state.failed = "fuel"
	var f39 := maxi(state.food_zero_streak, state.water_zero_streak) >= _PopulationRules.resource_zero_streak_f39()
	if not f39:
		return
	var hp_loss := _PopulationRules.f39_hp_loss()
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		m["hp"] = maxf(0.0, float(m.get("hp", 100.0)) - hp_loss)
	state.body_hp = maxf(0.0, state.body_hp - hp_loss)


## 士气偏移量 `morale_offset`：缺粮缺水惩罚，否则缓慢回归 0（未接完整士气 UI）。
##
## 日结子步骤：仅 `DaySettle.run` 顺序调用；不直接响应 Intent。
## @param state 当前局 `RunState`（就地修改字段）
static func _step_7b_morale(state: RunState) -> void:
	_MemberMorale.settle_daily_moods(state)
	var had_penalty := false
	if state.food_went_zero:
		state.morale_offset = maxf(
			_PopulationRules.morale_offset_min(),
			state.morale_offset - _PopulationRules.morale_food_zero_penalty()
		)
		had_penalty = true
	if state.water_went_zero:
		state.morale_offset = maxf(
			_PopulationRules.morale_offset_min(),
			state.morale_offset - _PopulationRules.morale_water_zero_penalty()
		)
		had_penalty = true
	if not had_penalty:
		if state.morale_offset < 0.0:
			state.morale_offset = minf(
				0.0, state.morale_offset + _PopulationRules.morale_offset_recover_per_day()
			)
		elif state.morale_offset > 0.0:
			state.morale_offset = maxf(
				0.0, state.morale_offset - _PopulationRules.morale_offset_decay_positive_per_day()
			)
	var collective := _collective_morale(state)
	if collective <= 0.0:
		state.morale_zero_streak += 1
	else:
		state.morale_zero_streak = 0
	if state.morale_zero_streak >= _PopulationRules.morale_zero_streak_fail() and state.failed.is_empty():
		state.failed = "morale"


## 04 §9.3：存活成员 mood 均值 + morale_offset。
##
## @param state 当前局 `RunState`（就地修改字段）
## @return 浮点结果（量/比率/工时）。
static func _collective_morale(state: RunState) -> float:
	var sum := 0.0
	var n := 0
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if float(m.get("hp", 0.0)) <= 0.0:
			continue
		sum += float(m.get("mood", _PopulationRules.mood_default()))
		n += 1
	if n == 0:
		return _PopulationRules.collective_morale_clamp(state.morale_offset)
	return _PopulationRules.collective_morale_clamp(sum / float(n) + state.morale_offset)


## 06 §2.2 日结补抽收留（消费 `lastRecruitSuccessDay`）。
##
## 日结子步骤：仅 `DaySettle.run` 顺序调用；不直接响应 Intent。
## @param state 当前局 `RunState`（就地修改字段）
static func _step_7c_day_end_recruit(state: RunState) -> void:
	if state.failed != "":
		return
	if IncidentDirector.use_legacy_event_cards():
		MemberRoster.try_day_end_recruit(state)
	else:
		IncidentDirector.on_day_end(state)


## 列车体 HP 低时累加 breakdown_counter；满 3 清零当日行驶小时（强制停薄模拟）。
##
## 日结子步骤：仅 `DaySettle.run` 顺序调用；不直接响应 Intent。
## @param state 当前局 `RunState`（就地修改字段）
static func _step_8b_breakdown(state: RunState) -> void:
	if state.body_hp >= _PopulationRules.body_hp_breakdown_threshold():
		state.breakdown_counter = 0
		return
	if state.breakdown_counter >= _PopulationRules.breakdown_counter_trigger():
		state.breakdown_counter = 0
		state.drive_hours_today = 0.0
		state.reverse_hours_today = 0.0
		state.breakdown_stop_hours_remaining = _PopulationRules.breakdown_stop_hours()
		DriveService.set_intent(state, "stop")
	else:
		state.breakdown_counter += 1


## 在 END_DAY 时调用：仍使用当前 day_total 结算「刚结束的那一天」。
##
## 权威日结入口：`GameSession._advance_one_day` 在 `GameCalendar.advance_day` **之前**调用。
## 仍使用结算时刻的 `day_total`（代表「刚结束的那一天」）；步骤顺序锁死 02 §8。
## @param state 当前局 `RunState`（就地修改字段）
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
	ClimateService.refresh(state, next_day)

	# 2 — food / water（日钟 tick 已扣大部分；此处补差 + streak）
	_PopulationConsumption.reconcile_day_end(state)

	# 3 — apply step 0 fuel burn
	InventoryService.remove(state, "fuel", fuel_burn_pct)
	# 3b — greenhouse heating (01 §8.1.1)
	var green_cars := _greenhouse_car_count(state)
	if state.cold_index >= 1.0 and state.heating_enabled and green_cars > 0:
		var heat_cost := float(ConfigDb.require("balance.greenhouse.heatingFuelPerCarDay")) * green_cars
		if state.fuel >= heat_cost:
			InventoryService.remove(state, "fuel", heat_cost)
			state.heating_applied_today = true
		else:
			state.heating_applied_today = false
	elif state.cold_index >= 1.0 and green_cars > 0:
		state.heating_applied_today = false

	ClimateService.refresh(state, next_day)

	InventoryService.clamp_resource(state, "fuel")

	# 3c — fuel streak after all fuel deductions
	if state.fuel <= 0.0:
		state.fuel_zero_streak += 1
	else:
		state.fuel_zero_streak = 0

	# 4–5 production (after deductions; skipped if no cars)
	_step_4_greenhouse(state)
	_step_5_water(state)

	_step_6_workshop(state)

	_step_7_zero_consequences(state)

	_step_7b_morale(state)
	_step_7c_day_end_recruit(state)
	MemberRoster.assign_daily_jobs(state)

	RegionService.refresh_pressure_cache(state)

	_step_8b_breakdown(state)