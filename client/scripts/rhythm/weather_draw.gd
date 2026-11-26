class_name WeatherDraw
extends RefCounted
## 01 §3 · weatherId 仅在 onSegmentBuild 抽一次；权重读 weather.json + climateInfluences.weatherBias。


static func weight_column_for_day(day_total: int) -> int:
	var season := GameCalendar.season_name_for_day(day_total)
	var year := GameCalendar.year_for_day(day_total)
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


static func sync_region_influence(state: RunState, region_id: String, region_def: Dictionary) -> void:
	var kept: Array = []
	for inf in state.climate_influences:
		if typeof(inf) == TYPE_DICTIONARY and str(inf.get("source", "")) == "region":
			continue
		kept.append(inf)
	state.climate_influences = kept
	var key := str(region_def.get("climateInfluenceId", "region.%s" % region_id))
	var presets: Variant = ConfigDb.get_table("climate_influences").get("presets", {})
	if typeof(presets) != TYPE_DICTIONARY:
		state.region_temp_mod = float(region_def.get("tempMod", 0.0))
		return
	var preset: Variant = presets.get(key, {})
	if typeof(preset) != TYPE_DICTIONARY or preset.is_empty():
		state.region_temp_mod = float(region_def.get("tempMod", 0.0))
		return
	var inf: Dictionary = preset.duplicate(true)
	inf["id"] = key
	state.climate_influences.append(inf)
	# 温度走 ClimateInfluence.tempMod，避免与 region_temp_mod 叠两次
	state.region_temp_mod = 0.0


static func build_weights(state: RunState) -> Dictionary:
	var root: Dictionary = ConfigDb.get_table("weather")
	var weathers: Variant = root.get("weathers", {})
	if typeof(weathers) != TYPE_DICTIONARY:
		return {"clear": 1.0}
	var col := weight_column_for_day(state.day_total)
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
		for inf in state.climate_influences:
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


static func draw_weather_id(state: RunState) -> String:
	return _pick_weighted(build_weights(state))


static func on_segment_build(state: RunState, segment: Segment) -> void:
	if segment == null:
		return
	if segment.weather_draw_count > 0:
		push_warning("WeatherDraw: segment already drew weather")
		return
	var wid := draw_weather_id(state)
	segment.weather_id = wid
	segment.weather_draw_count = 1
	state.weather_id = wid
	ClimateService.recompute(state)


static func _pick_weighted(weights: Dictionary) -> String:
	var total := 0.0
	for w in weights.values():
		total += float(w)
	if total <= 0.0:
		return "clear"
	var r := RngService.randf() * total
	for wid in weights.keys():
		r -= float(weights[wid])
		if r <= 0.0:
			return str(wid)
	var keys := weights.keys()
	return str(keys[keys.size() - 1])