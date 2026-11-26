class_name SaveSchema
extends RefCounted
## 09 §3 RunState ↔ save 12 子集（含 lootPile / members）


static func to_save_dict(state: RunState) -> Dictionary:
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
		"version": {"save": SaveService.SAVE_VERSION, "configVersion": ConfigDb.config_version},
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
		},
		"world": {
			"heatingEnabled": state.heating_enabled,
			"weatherId": state.weather_id,
			"regionFuelMult": state.region_fuel_mult,
			"regionTempMod": state.region_temp_mod,
			"guaranteeFailStreak": state.guarantee_fail_streak,
			"tutorialDone": state.tutorial_done,
			"lootPiles": LootPileService.export_piles(state),
			"climateInfluences": state.climate_influences.duplicate(true),
			"delayedEvents": state.delayed_events.duplicate(true),
		},
		"members": state.members.duplicate(true),
		"tasks": {
			"search": state.search_tasks.duplicate(true),
			"haul": state.haul_tasks.duplicate(true),
		},
		"regionRun": _region_run_to_dict(state.region_run),
		"runtime": {
			"driveHoursToday": state.drive_hours_today,
			"reverseHoursToday": state.reverse_hours_today,
			"foodZeroStreak": state.food_zero_streak,
			"waterZeroStreak": state.water_zero_streak,
			"fuelZeroStreak": state.fuel_zero_streak,
			"failed": state.failed,
		},
	}
	return save


static func from_save_dict(save: Dictionary) -> RunState:
	save = SaveService.patch_loaded_save(save.duplicate(true))
	var state := RunState.new()
	var cal: Dictionary = save.get("calendar", {})
	state.year = int(cal.get("year", 1))
	state.season = str(cal.get("season", "spring"))
	state.day_in_season = int(cal.get("dayInSeason", 1))
	state.day_total = int(cal.get("dayTotal", 1))

	var inv: Dictionary = save.get("inventory", {})
	state.parts = float(inv.get("parts", 6))
	state.scrap = float(inv.get("scrap", 0))
	state.fuel = float(inv.get("fuel", 88))
	state.food = float(inv.get("food", 20))
	state.water = float(inv.get("water", 24))
	state.medicine = float(inv.get("medicine", 4))
	state.seed = float(inv.get("seed", 1))
	state.chem = float(inv.get("chem", 0))
	state.cloth = float(inv.get("cloth", 0))

	var train: Dictionary = save.get("train", {})
	state.carriages = train.get("carriages", []).duplicate(true)
	state.body_hp = float(train.get("bodyHp", 100))
	state.abandon_count = int(train.get("abandonCount", 0))
	state.drive_intent = str(train.get("driveIntent", "stop"))
	state.breakdown_counter = int(train.get("breakdownCounter", 0))

	var world: Dictionary = save.get("world", {})
	state.heating_enabled = bool(world.get("heatingEnabled", false))
	state.weather_id = str(world.get("weatherId", "clear"))
	state.region_fuel_mult = float(world.get("regionFuelMult", 1.0))
	state.region_temp_mod = float(world.get("regionTempMod", 0.0))
	state.guarantee_fail_streak = int(world.get("guaranteeFailStreak", 0))
	state.tutorial_done = bool(world.get("tutorialDone", false))
	state.climate_influences = world.get("climateInfluences", [])
	state.delayed_events = world.get("delayedEvents", [])

	state.members = save.get("members", []).duplicate(true)
	var tasks: Dictionary = save.get("tasks", {})
	state.search_tasks = tasks.get("search", []).duplicate(true)
	state.haul_tasks = tasks.get("haul", []).duplicate(true)

	var rt: Dictionary = save.get("runtime", {})
	state.drive_hours_today = float(rt.get("driveHoursToday", 0))
	state.reverse_hours_today = float(rt.get("reverseHoursToday", 0))
	state.food_zero_streak = int(rt.get("foodZeroStreak", 0))
	state.water_zero_streak = int(rt.get("waterZeroStreak", 0))
	state.fuel_zero_streak = int(rt.get("fuelZeroStreak", 0))
	state.failed = str(rt.get("failed", ""))

	state.region_run = _region_run_from_dict(save.get("regionRun", {}))
	var piles: Variant = world.get("lootPiles", [])
	LootPileService.apply_world_list(state, piles if typeof(piles) == TYPE_ARRAY else [])
	_ensure_points_loot_on_segments(state)

	state.onboard_pop = TrainService.onboard_count(state)
	ClimateService.recompute(state)
	return state


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
	var s := Segment.new()
	s.segment_id = str(d.get("segmentId", ""))
	s.length_km = float(d.get("lengthKm", 50))
	s.progress_km = float(d.get("progressKm", 0))
	s.built = bool(d.get("built", false))
	s.stations = d.get("stations", []).duplicate(true)
	s.points = _normalize_points(d.get("points", []))
	s.weather_id = str(d.get("weatherId", "clear"))
	s.weather_draw_count = int(d.get("weatherDrawCount", 0))
	s.event_id = str(d.get("eventId", ""))
	s.segment_fuel_surcharge = float(d.get("segmentFuelSurcharge", 0))
	s.raid_weight_delta = float(d.get("raidWeightDelta", 0))
	s.pressure_class = str(d.get("pressureClass", ""))
	return s


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