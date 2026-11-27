class_name SaveSchema
extends RefCounted

const _BalanceStart := preload("res://scripts/data/balance_start.gd")
const _GameClock := preload("res://scripts/rhythm/game_clock.gd")
const _PopulationConsumption := preload("res://scripts/economy/population_consumption.gd")
## RunState ↔ JSON 存档（version.save **12** 客户端子集）。
##
## 顶层块（与 09 §3 对齐，S1a 尚未全字段）：
##   - `version` · `calendar` · `inventory` · `train` · `world` · `members`（含 hunger/thirst 0–100）· `tasks` · `regionRun` · `runtime`
##   - `world.lootPiles` 扁平行列表，非嵌在 segment 内（见 LootPileService.export_piles）
##   - `runtime`：当日小时、zero streak、failed、**日钟**（`dayClockFraction` 与 GameClock 三份额、`foodAppliedToday`）——读档继续同一游戏日
##   - **不入盘**：`pending_station`、`pending_combat`、各 `*_panel_open`（纯 UI / 遭遇态）
##   - **入盘**：`train.formations` · `activeFormationId` · `blueprints`；`telemetry.searchByPointDay`（cap）
##
## 读档：`from_save_dict` → patch → 重建 RegionRun/Segment → apply loot → `ClimateService.refresh`。


static func to_save_dict(state: RunState, runtime_extra: Dictionary = {}) -> Dictionary:
	var inv := {
		"parts": state.parts,
		"scrap": state.scrap,
		"fuel": state.fuel,
		"food": state.food,
		"water": state.water,
		"medicine": state.medicine,
		"seed": state.seed,
		"chem": state.chem,
		"cloth": state.cloth,
	}
	var save := {
		"version": {"save": SaveService.SAVE_VERSION, "configVersion": ConfigDb.config_version()},
		"calendar": {
			"year": state.year,
			"season": state.season,
			"dayInSeason": state.day_in_season,
			"dayTotal": state.day_total,
		},
		"inventory": inv,
		"train": {
			"carriages": state.carriages.duplicate(true),
			"bodyHp": state.body_hp,
			"abandonCount": state.abandon_count,
			"driveIntent": state.drive_intent,
			"breakdownCounter": state.breakdown_counter,
			"precision": state.precision,
			"powerTech": state.power_tech,
			"armorTech": state.armor_tech,
			"radarTech": state.radar_tech,
			"livingTech": state.living_tech,
			"blueprints": state.blueprints.duplicate(true),
			"formations": state.formations.duplicate(true),
			"activeFormationId": state.active_formation_id,
		},
		"world": {
			"heatingEnabled": state.heating_enabled,
			"weatherId": state.weather_id,
			"regionFuelMult": state.region_fuel_mult_active(),
			"regionTempMod": state.region_temp_mod,
			"guaranteeFailStreak": state.guarantee_fail_streak,
			"tutorialDone": state.tutorial_done,
			"lootPiles": LootPileService.export_piles(state),
			"climateInfluences": state.climate_influences.duplicate(true),
			"delayedEvents": state.delayed_events.duplicate(true),
			"eventWeightHistory": state.event_weight_history.duplicate(),
			"lastEventPrimaryTag": state.last_event_primary_tag,
			"eventFlags": state.event_flags.duplicate(true),
			"pendingThreat": state.pending_threat.duplicate(true),
			"lastRecruitSuccessDay": state.last_recruit_success_day,
			"moraleOffset": state.morale_offset,
			"pressureHistory": state.pressure_history.duplicate(true),
			"pressureDisplay": state.pressure_display,
		},
		"members": state.members.duplicate(true),
		"tasks": {
			"search": state.search_tasks.duplicate(true),
			"haul": state.haul_tasks.duplicate(true),
		},
		"regionRun": _region_run_to_dict(state.region_run),
		"runtime": _merge_runtime_clock(
			{
				"driveHoursToday": state.drive_hours_today,
				"reverseHoursToday": state.reverse_hours_today,
				"foodZeroStreak": state.food_zero_streak,
				"waterZeroStreak": state.water_zero_streak,
				"fuelZeroStreak": state.fuel_zero_streak,
				"moraleZeroStreak": state.morale_zero_streak,
				"failed": state.failed,
				"breakdownStopHoursRemaining": state.breakdown_stop_hours_remaining,
			},
			runtime_extra
		),
	}
	return save


static func _merge_runtime_clock(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	if typeof(extra) != TYPE_DICTIONARY:
		return out
	for k in extra.keys():
		out[k] = extra[k]
	return out


## 反序列化；缺字段用文档默认或 ConfigDb（precisionStart）。
##
## 读盘重建 RunState；日钟字段须经 `SaveService.write_state` 写入完整 `runtime`。
## 直接 `to_save_dict(state)` 无 `runtime_extra` 时，读档日钟归零。
## 人口由 `members[]` 派生，不再单独字段。
## 磁盘读档经 `SaveService.read_state`（已 patch 一次）；`LootPileService.apply_world_list` + `ClimateService.refresh` 在此内完成。
## @param save 存档根 Dictionary（save 12）
## @param already_patched `read_state` 已 patch 时传 true，避免双次迁移。
## @return 重建后的 RunState。
static func from_save_dict(save: Dictionary, already_patched: bool = false) -> RunState:
	if already_patched:
		save = save.duplicate(true)
	else:
		save = SaveService.patch_loaded_save(save.duplicate(true))
	var state := RunState.new()
	var cal: Dictionary = save.get("calendar", {})
	state.year = int(cal.get("year", 1))
	state.season = str(cal.get("season", "spring"))
	state.day_in_season = int(cal.get("dayInSeason", 1))
	state.day_total = int(cal.get("dayTotal", 1))

	var inv: Dictionary = save.get("inventory", {})
	state.parts = float(inv.get("parts", _BalanceStart.inventory_default("parts")))
	state.scrap = float(inv.get("scrap", _BalanceStart.inventory_default("scrap")))
	state.fuel = float(inv.get("fuel", _BalanceStart.inventory_default("fuel")))
	state.food = float(inv.get("food", _BalanceStart.inventory_default("food")))
	state.water = float(inv.get("water", _BalanceStart.inventory_default("water")))
	state.medicine = float(inv.get("medicine", _BalanceStart.inventory_default("medicine")))
	state.seed = float(inv.get("seed", _BalanceStart.inventory_default("seed")))
	state.chem = float(inv.get("chem", _BalanceStart.inventory_default("chem")))
	state.cloth = float(inv.get("cloth", _BalanceStart.inventory_default("cloth")))

	var train: Dictionary = save.get("train", {})
	state.carriages = train.get("carriages", []).duplicate(true)
	state.body_hp = float(train.get("bodyHp", 100))
	state.abandon_count = int(train.get("abandonCount", 0))
	state.drive_intent = str(train.get("driveIntent", "stop"))
	state.breakdown_counter = int(train.get("breakdownCounter", 0))
	state.precision = float(train.get("precision", _BalanceStart.starting_precision()))
	state.power_tech = int(train.get("powerTech", 0))
	state.armor_tech = int(train.get("armorTech", 0))
	state.radar_tech = int(train.get("radarTech", 0))
	state.living_tech = int(train.get("livingTech", 0))
	state.blueprints = _blueprints_from_train(train)
	state.formations = train.get("formations", []).duplicate(true)
	state.active_formation_id = str(train.get("activeFormationId", ""))

	var world: Dictionary = save.get("world", {})
	state.heating_enabled = bool(world.get("heatingEnabled", false))
	state.weather_id = str(world.get("weatherId", "clear"))
	state.region_fuel_mult = float(world.get("regionFuelMult", 1.0))
	state.region_temp_mod = float(world.get("regionTempMod", 0.0))
	state.guarantee_fail_streak = int(world.get("guaranteeFailStreak", 0))
	state.tutorial_done = bool(world.get("tutorialDone", false))
	state.climate_influences = world.get("climateInfluences", [])
	state.delayed_events = world.get("delayedEvents", [])
	state.event_weight_history = world.get("eventWeightHistory", []).duplicate()
	state.last_event_primary_tag = str(world.get("lastEventPrimaryTag", ""))
	var flags: Variant = world.get("eventFlags", {})
	state.event_flags = flags.duplicate(true) if typeof(flags) == TYPE_DICTIONARY else {}
	state.last_recruit_success_day = int(world.get("lastRecruitSuccessDay", -1))
	var pt: Variant = world.get("pendingThreat", {})
	state.pending_threat = pt.duplicate(true) if typeof(pt) == TYPE_DICTIONARY else {}
	state.morale_offset = float(world.get("moraleOffset", 0.0))
	var ph: Variant = world.get("pressureHistory", ["", ""])
	state.pressure_history = ph.duplicate() if typeof(ph) == TYPE_ARRAY else ["", ""]
	state.pressure_display = str(world.get("pressureDisplay", ""))

	state.members = save.get("members", []).duplicate(true)
	_PopulationConsumption.patch_members(state)
	_ensure_default_formation_after_members(state)
	var tasks: Dictionary = save.get("tasks", {})
	state.search_tasks = tasks.get("search", []).duplicate(true)
	state.haul_tasks = tasks.get("haul", []).duplicate(true)

	var rt: Dictionary = save.get("runtime", {})
	_GameClock.restore_from_runtime(rt)
	_PopulationConsumption.restore_day_counters(rt)
	state.drive_hours_today = float(rt.get("driveHoursToday", 0))
	state.reverse_hours_today = float(rt.get("reverseHoursToday", 0))
	state.food_zero_streak = int(rt.get("foodZeroStreak", 0))
	state.water_zero_streak = int(rt.get("waterZeroStreak", 0))
	state.fuel_zero_streak = int(rt.get("fuelZeroStreak", 0))
	state.morale_zero_streak = int(rt.get("moraleZeroStreak", 0))
	state.failed = str(rt.get("failed", ""))
	state.breakdown_stop_hours_remaining = float(rt.get("breakdownStopHoursRemaining", 0))

	state.region_run = _region_run_from_dict(save.get("regionRun", {}))
	var piles: Variant = world.get("lootPiles", [])
	LootPileService.apply_world_list(state, piles if typeof(piles) == TYPE_ARRAY else [])
	_ensure_points_loot_on_segments(state)
	_sync_region_fuel_mult_from_run(state)

	ClimateService.refresh(state)
	return state


## `regionRun.regionFuelMult` 为当前跨度权威值，回写 `state`/`world` 镜像。
static func _sync_region_fuel_mult_from_run(state: RunState) -> void:
	if state.region_run == null:
		return
	state.region_fuel_mult = state.region_run.region_fuel_mult


static func _blueprints_from_train(train: Dictionary) -> Dictionary:
	var out := {
		"power": false,
		"armor": false,
		"radar": false,
		"living": false,
	}
	var bp: Variant = train.get("blueprints", {})
	if typeof(bp) != TYPE_DICTIONARY:
		return out
	for k in out.keys():
		out[k] = bool(bp.get(k, false))
	if bool(bp.get("life", false)) and not bool(out["living"]):
		out["living"] = true
	return out


## 读档后：`formations[]` 仍空则按 combatRoster 补默认编队（须在 members 赋值之后）。
static func _ensure_default_formation_after_members(state: RunState) -> void:
	if not state.formations.is_empty():
		return
	if state.members.is_empty():
		return
	CombatL1.seed_default_formation(state)


static func _region_run_to_dict(rr: RegionRun) -> Dictionary:
	if rr == null:
		return {}
	return rr.to_dict()

static func _region_run_from_dict(d: Variant) -> RegionRun:
	if typeof(d) != TYPE_DICTIONARY or d.is_empty():
		return null
	var rr := RegionRun.new()
	rr.region_id = str(d.get("regionId", "urban"))
	rr.segment_count = int(d.get("segmentCount", 3))
	rr.segment_index = int(d.get("segmentIndex", 0))
	rr.region_fuel_mult = float(d.get("regionFuelMult", 1.0))
	var mods: Variant = d.get("pointTypeWeightMods", {})
	rr.point_type_weight_mods = mods if typeof(mods) == TYPE_DICTIONARY else {}
	rr.segments = []
	for sd in d.get("segments", []):
		if typeof(sd) == TYPE_DICTIONARY:
			rr.segments.append(_segment_from_dict(sd))
	return rr

static func _segment_from_dict(d: Dictionary) -> Segment:
	return Segment.from_dict(d, _normalize_points(d.get("points", [])))


static func _normalize_points(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for pt in raw:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = pt.duplicate(true)
		var pile: Variant = row.get("lootPile", {})
		row.lootPile = pile if typeof(pile) == TYPE_DICTIONARY else {}
		if not row.has("remainingYield"):
			row.remainingYield = SearchService.initial_remaining_yield(str(row.get("type", "")))
		if not row.has("depleted"):
			row.depleted = false
		out.append(row)
	return out

static func _ensure_points_loot_on_segments(state: RunState) -> void:
	if state.region_run == null:
		return
	for seg_var in state.region_run.segments:
		if not (seg_var is Segment):
			continue
		var seg := seg_var as Segment
		for i in seg.points.size():
			var pt: Dictionary = seg.points[i]
			if typeof(pt) != TYPE_DICTIONARY:
				continue
			if typeof(pt.get("lootPile", null)) != TYPE_DICTIONARY:
				pt.lootPile = {}
			seg.points[i] = pt