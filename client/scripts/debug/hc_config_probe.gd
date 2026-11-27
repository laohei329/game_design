class_name HcConfigProbe
extends RefCounted
## 配置无头探针：legacyFiles · events_index · locale 注册 · get_table/require 行为。


const _LocaleDb := preload("res://scripts/data/locale_db.gd")


static func _count_indexed_event_ids(db: Node) -> int:
	var idx: Dictionary = db.get_table("events_index")
	var buckets: Variant = idx.get("buckets", {})
	if typeof(buckets) != TYPE_DICTIONARY:
		return 0
	var count := 0
	var general: Variant = buckets.get("general", {})
	if typeof(general) == TYPE_DICTIONARY:
		var ids: Variant = general.get("eventIds", [])
		if typeof(ids) == TYPE_ARRAY:
			count += ids.size()
	var season: Variant = buckets.get("season", {})
	if typeof(season) == TYPE_DICTIONARY:
		var by: Variant = season.get("bySeason", {})
		if typeof(by) == TYPE_DICTIONARY:
			for row in by.values():
				if typeof(row) == TYPE_DICTIONARY:
					var sids: Variant = row.get("eventIds", [])
					if typeof(sids) == TYPE_ARRAY:
						count += sids.size()
	var year: Variant = buckets.get("year", {})
	if typeof(year) == TYPE_DICTIONARY:
		var yids: Variant = year.get("eventIds", [])
		if typeof(yids) == TYPE_ARRAY:
			count += yids.size()
	return count


static func _expected_translation_count() -> int:
	return _LocaleDb.editor_translation_paths().size()


static func _registered_translation_count() -> int:
	var paths: Variant = ProjectSettings.get_setting("internationalization/locale/translations", [])
	if typeof(paths) != TYPE_PACKED_STRING_ARRAY and typeof(paths) != TYPE_ARRAY:
		return 0
	return paths.size()


static func run_all(db: Node) -> Dictionary:
	var lines: PackedStringArray = []
	var ok := true
	if not db.has_method("require") or not db.has_method("get_table"):
		return {"ok": false, "lines": ["FAIL HcConfigProbe invalid db"]}
	if not db.tables.has("events_index"):
		lines.append("FAIL legacyFiles events_index not loaded")
		ok = false
	else:
		lines.append("OK legacyFiles events_index loaded")
	var target := int(db.require("events_index.targetTotal"))
	var n := _count_indexed_event_ids(db)
	if n < target:
		lines.append("FAIL events_index listed ids=%d target=%d" % [n, target])
		ok = false
	else:
		lines.append("OK events_index listed ids=%d" % n)
	if int(db.require("upgrades.stageZeroSmokeMaxLv")) != 3:
		lines.append("FAIL stageZeroSmokeMaxLv")
		ok = false
	else:
		lines.append("OK upgrades.stageZeroSmokeMaxLv=3")
	if db.require("balance.fuel.climateRegionMultCap") == null:
		lines.append("FAIL balance.fuel.climateRegionMultCap")
		ok = false
	else:
		lines.append("OK balance.fuel.climateRegionMultCap")
	var unknown: Dictionary = db.get_table("__no_such_probe_table__")
	if unknown.size() != 0:
		lines.append("FAIL get_table unknown should return {}")
		ok = false
	else:
		lines.append("OK get_table unknown returns empty")
	if db.require("__no_such.probe.path") != null:
		lines.append("FAIL require missing path should return null")
		ok = false
	else:
		lines.append("OK require missing path returns null")
	var want_loc := _expected_translation_count()
	var got_loc := _registered_translation_count()
	if got_loc < want_loc:
		lines.append("FAIL locale translations registered %d want>=%d" % [got_loc, want_loc])
		ok = false
	else:
		lines.append("OK locale translations registered=%d" % got_loc)
	if db.load_errors.size() > 0:
		lines.append("FAIL load_errors present after load_all")
		ok = false
	else:
		lines.append("OK ConfigDb load_errors empty")
	return {"ok": ok, "lines": lines}