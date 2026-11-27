class_name SaveMigrationClimate
extends RefCounted
## v8→v9：缺 `weatherId` / `climateInfluences` 时按季节权重表抽一次天气（09 §2，对齐 `WeatherDraw`）。


const SEASONS: Array[String] = ["spring", "summer", "autumn", "winter"]


static func apply_v8_weather_and_climate(save: Dictionary, config_db: Node = null) -> void:
	if typeof(save) != TYPE_DICTIONARY:
		return
	var world := SaveMigrationUtil.ensure_dict(save, "world")
	var weather_key_present := world.has("weatherId")
	var weather_id := str(world.get("weatherId", "")) if weather_key_present else ""
	var need_weather := not weather_key_present or weather_id.is_empty()
	var influences_raw: Variant = world.get("climateInfluences", null)
	var need_influences := not world.has("climateInfluences") or typeof(influences_raw) != TYPE_ARRAY
	if not need_weather and not need_influences:
		return
	var db: Node = config_db if config_db != null else SaveMigrationUtil.config_db_node()
	if db == null or not _config_usable(db):
		if need_weather:
			world["weatherId"] = "clear"
		if need_influences:
			world["climateInfluences"] = []
		return
	var cal: Dictionary = save.get("calendar", {})
	if typeof(cal) != TYPE_DICTIONARY:
		cal = {}
	var day_total := maxi(1, int(cal.get("dayTotal", 1)))
	var influences: Array = []
	if typeof(influences_raw) == TYPE_ARRAY and not need_influences:
		influences = influences_raw.duplicate(true)
	elif need_influences:
		influences = _sync_region_influence(save, db, [])
		world["climateInfluences"] = influences.duplicate(true)
	if need_weather:
		var wid := _draw_weather_id(save, db, day_total, influences)
		world["weatherId"] = wid
		_patch_region_run_segment_weather(save, wid)


static func _config_usable(db: Node) -> bool:
	var tables: Variant = db.get("tables")
	return typeof(tables) == TYPE_DICTIONARY and tables.size() > 0


static func _season_index(db: Node, day_total: int) -> int:
	var days_per := int(_require_int(db, "balance.time.daysPerSeason", 30))
	var seasons_per := int(_require_int(db, "balance.time.seasonsPerYear", 4))
	var zero := maxi(0, day_total - 1)
	return (zero / days_per) % seasons_per


static func _year_for_day(db: Node, day_total: int) -> int:
	var days_per := int(_require_int(db, "balance.time.daysPerSeason", 30))
	var seasons_per := int(_require_int(db, "balance.time.seasonsPerYear", 4))
	var zero := maxi(0, day_total - 1)
	return zero / (days_per * seasons_per) + 1


static func _weight_column(db: Node, day_total: int) -> int:
	var season := SEASONS[_season_index(db, day_total)]
	var year := _year_for_day(db, day_total)
	match season:
		"spring":
			return 0
		"summer":
			return 1
		"autumn":
			return 2
		"winter":
			return 3 if year <= 2 else 4
		_:
			return 0


static func _require_int(db: Node, path: String, fallback: int) -> int:
	if not db.has_method("require"):
		return fallback
	var v: Variant = db.call("require", path)
	return int(v) if v != null else fallback


static func _sync_region_influence(save: Dictionary, db: Node, existing: Array) -> Array:
	var kept: Array = []
	for inf in existing:
		if typeof(inf) == TYPE_DICTIONARY and str(inf.get("source", "")) != "region":
			kept.append(inf)
	var region_id := _region_id_from_save(save)
	var regions: Dictionary = db.call("get_table", "regions") if db.has_method("get_table") else {}
	var row: Variant = {}
	if typeof(regions) == TYPE_DICTIONARY:
		var bucket: Variant = regions.get("regions", {})
		if typeof(bucket) == TYPE_DICTIONARY:
			row = bucket.get(region_id, {})
	if typeof(row) != TYPE_DICTIONARY or row.is_empty():
		return kept
	var key := str(row.get("climateInfluenceId", "region.%s" % region_id))
	var ci: Dictionary = db.call("get_table", "climate_influences") if db.has_method("get_table") else {}
	var presets: Variant = ci.get("presets", {})
	if typeof(presets) != TYPE_DICTIONARY:
		return kept
	var preset: Variant = presets.get(key, {})
	if typeof(preset) != TYPE_DICTIONARY or preset.is_empty():
		return kept
	var inf: Dictionary = preset.duplicate(true)
	inf["id"] = key
	if not inf.has("source"):
		inf["source"] = "region"
	kept.append(inf)
	return kept


static func _region_id_from_save(save: Dictionary) -> String:
	var rr: Variant = save.get("regionRun", {})
	if typeof(rr) == TYPE_DICTIONARY and rr.has("regionId"):
		return str(rr.get("regionId", "urban"))
	var world: Variant = save.get("world", {})
	if typeof(world) == TYPE_DICTIONARY:
		var wrr: Variant = world.get("regionRun", {})
		if typeof(wrr) == TYPE_DICTIONARY and wrr.has("regionId"):
			return str(wrr.get("regionId", "urban"))
	return "urban"


static func _build_weights(db: Node, day_total: int, influences: Array) -> Dictionary:
	var root: Dictionary = db.call("get_table", "weather") if db.has_method("get_table") else {}
	var weathers: Variant = root.get("weathers", {})
	if typeof(weathers) != TYPE_DICTIONARY:
		return {"clear": 1.0}
	var col := _weight_column(db, day_total)
	var weights := {}
	var total := 0.0
	for wid in weathers.keys():
		var row: Variant = weathers[wid]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var warr: Variant = row.get("weightBySeason", [])
		var base_w := 0.0
		if typeof(warr) == TYPE_ARRAY and col < warr.size():
			base_w = float(warr[col])
		var mult := 1.0
		for inf in influences:
			if typeof(inf) != TYPE_DICTIONARY:
				continue
			var bias: Variant = inf.get("weatherBias", {})
			if typeof(bias) == TYPE_DICTIONARY and bias.has(wid):
				mult *= float(bias[wid])
		var w := base_w * mult
		if w > 0.0:
			weights[str(wid)] = w
			total += w
	if total <= 0.0:
		return {"clear": 1.0}
	return weights


static func _draw_weather_id(save: Dictionary, db: Node, day_total: int, influences: Array) -> String:
	var weights := _build_weights(db, day_total, influences)
	var total := 0.0
	for w in weights.values():
		total += float(w)
	if total <= 0.0:
		return "clear"
	var r := _rand01(save) * total
	for wid in weights.keys():
		r -= float(weights[wid])
		if r <= 0.0:
			return str(wid)
	var keys := weights.keys()
	return str(keys[keys.size() - 1])


static func _patch_region_run_segment_weather(save: Dictionary, weather_id: String) -> void:
	var rr: Variant = save.get("regionRun", null)
	if typeof(rr) != TYPE_DICTIONARY:
		return
	var segs: Array = rr.get("segments", [])
	if typeof(segs) != TYPE_ARRAY or segs.is_empty():
		return
	var idx := int(rr.get("segmentIndex", 0))
	if idx < 0 or idx >= segs.size():
		idx = 0
	var seg: Variant = segs[idx]
	if typeof(seg) != TYPE_DICTIONARY:
		return
	if not seg.has("weatherId") or str(seg.get("weatherId", "")).is_empty():
		seg["weatherId"] = weather_id
		if not seg.has("weatherDrawCount"):
			seg["weatherDrawCount"] = 1
		segs[idx] = seg
		rr["segments"] = segs
		save["regionRun"] = rr


static func _rand01(save: Dictionary) -> float:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		var rng: Node = (tree as SceneTree).root.get_node_or_null("RngService")
		if rng != null and rng.has_method("randf"):
			return float(rng.call("randf"))
	var cal: Variant = save.get("calendar", {})
	var day := int(cal.get("dayTotal", 1)) if typeof(cal) == TYPE_DICTIONARY else 1
	var g := RandomNumberGenerator.new()
	g.seed = hash("save_v8_weather_%d" % day)
	return g.randf()