class_name SegmentBuild
extends RefCounted
## 教程跨度 §0.1 · S0 只建第 0 段骨架；完整 onSegmentBuild 在 M2 加厚。


static func begin_tutorial_region_run(state: RunState) -> void:
	var stations_cfg: Dictionary = ConfigDb.get_table("stations")
	var region_id := str(stations_cfg.get("tutorialRegion", ConfigDb.require("balance.stations.tutorialRegion")))
	var regions_root: Dictionary = ConfigDb.get_table("regions")
	var regions: Variant = regions_root.get("regions", {})
	var region_def: Dictionary = {}
	if typeof(regions) == TYPE_DICTIONARY:
		var row: Variant = regions.get(region_id, {})
		if typeof(row) == TYPE_DICTIONARY:
			region_def = row

	var fuel_mult := float(region_def.get("regionFuelMult", 1.0))
	state.region_fuel_mult = fuel_mult
	WeatherDraw.sync_region_influence(state, region_id, region_def)

	var run := RegionRun.new()
	run.region_id = region_id
	run.segment_count = 3
	run.segment_index = 0
	run.region_fuel_mult = fuel_mult
	var mods: Variant = region_def.get("pointTypeWeightMods", {})
	run.point_type_weight_mods = mods if typeof(mods) == TYPE_DICTIONARY else {}
	var seg := _build_tutorial_segment_0(stations_cfg)
	run.segments = [seg]
	state.region_run = run
	WeatherDraw.on_segment_build(state, seg)


static func _build_tutorial_segment_0(stations_cfg: Dictionary) -> Segment:
	var seg := Segment.new()
	seg.segment_id = "tutorial_seg_0"
	var len_min := float(stations_cfg.get("segmentLengthMin", 40))
	var len_max := float(stations_cfg.get("segmentLengthMax", 60))
	seg.length_km = (len_min + len_max) * 0.5
	seg.progress_km = 0.0
	seg.built = true

	var station_km := seg.length_km * 0.5
	seg.stations = [
		{
			"id": "st_tutorial_0",
			"progressKm": station_km,
			"size": "small",
			"hasPool": true,
			"nonePool": false,
			"visited": false,
			"tutorialHook": true,
			"forceLivingOffer": bool(stations_cfg.get("tutorialForceLivingOffer", true)),
			"livingRepairCost": int(stations_cfg.get("tutorialLivingRepairCost", 1)),
		},
	]

	seg.points = []
	var force: Variant = stations_cfg.get("tutorialForcePointTypes", ["supermarket", "water_plant"])
	if typeof(force) == TYPE_ARRAY:
		var idx := 0
		for pt in force:
			seg.points.append(
				{
					"id": "pt_%s_%d" % [str(pt), idx],
					"type": str(pt),
					"remainingYield": SearchService.initial_remaining_yield(str(pt)),
					"depleted": false,
					"lootPile": {},
				}
			)
			idx += 1

	return seg