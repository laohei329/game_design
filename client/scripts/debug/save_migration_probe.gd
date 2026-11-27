class_name SaveMigrationProbe
extends RefCounted
## 存档迁移抽样：v10→12、`v6→12` 全链、v8 季节天气（需 ConfigDb 挂到场景树）。


static func run_all(db: Node) -> Dictionary:
	if db != null and db.get_parent() == null and Engine.get_main_loop() is SceneTree:
		(Engine.get_main_loop() as SceneTree).root.add_child(db)
	var lines: PackedStringArray = []
	var ok := true
	var v10 := _minimal_save_v10()
	var err := SaveMigrationSteps.apply_step("v10_to_v11", v10)
	if err != "":
		lines.append("FAIL v10_to_v11 %s" % err)
		ok = false
	else:
		if SaveMigrationUtil.save_version(v10) != 11:
			lines.append("FAIL v10 version got=%d" % SaveMigrationUtil.save_version(v10))
			ok = false
		else:
			lines.append("OK v10_to_v11")
	err = SaveMigrationSteps.apply_step("v11_to_v12", v10)
	if err != "":
		lines.append("FAIL v11_to_v12 %s" % err)
		ok = false
	elif SaveMigrationUtil.save_version(v10) != 12:
		lines.append("FAIL v12 version got=%d" % SaveMigrationUtil.save_version(v10))
		ok = false
	else:
		lines.append("OK v11_to_v12")
	var v6 := _minimal_save_v6()
	err = SaveMigrationChain.migrate_to(v6, 12)
	if err != "":
		lines.append("FAIL chain v6->12 %s" % err)
		ok = false
	elif SaveMigrationUtil.save_version(v6) != 12:
		lines.append("FAIL chain v6 final=%d" % SaveMigrationUtil.save_version(v6))
		ok = false
	else:
		lines.append("OK chain v6->12")
	var w6: Dictionary = v6.get("world", {})
	if typeof(w6) == TYPE_DICTIONARY and not str(w6.get("weatherId", "")).is_empty():
		lines.append("OK chain v6 weatherId=%s" % str(w6.get("weatherId")))
	var v8 := _minimal_save_v8_no_weather()
	SaveMigrationClimate.apply_v8_weather_and_climate(v8, db)
	err = SaveMigrationSteps.apply_step("v8_to_v9", v8)
	if err != "":
		lines.append("FAIL v8_to_v9 %s" % err)
		ok = false
	elif SaveMigrationUtil.save_version(v8) != 9:
		lines.append("FAIL v8_to_v9 version got=%d" % SaveMigrationUtil.save_version(v8))
		ok = false
	var w8: Dictionary = v8.get("world", {})
	var wid := str(w8.get("weatherId", ""))
	var infl: Variant = w8.get("climateInfluences", [])
	var infl_n: int = int(infl.size()) if typeof(infl) == TYPE_ARRAY else 0
	if wid.is_empty():
		lines.append("FAIL v8 weather draw empty")
		ok = false
	elif infl_n < 1 and wid != "clear":
		lines.append("WARN v8 influences empty wid=%s" % wid)
		lines.append("OK v8_to_v9 weather wid=%s influences=%d" % [wid, infl_n])
	elif infl_n < 1 and db != null and db.has_method("get_table"):
		lines.append("FAIL v8 climateInfluences empty with clear weather (config present)")
		ok = false
	else:
		lines.append("OK v8_to_v9 weather wid=%s influences=%d" % [wid, infl_n])
	if SaveMigrationUtil.save_version(v6) == 12 and not v6.get("train", {}).has("driveIntent"):
		lines.append("FAIL missing driveIntent after chain v6->12")
		ok = false
	return {"ok": ok, "lines": lines}


static func _minimal_save_v10() -> Dictionary:
	return {
		"version": {"save": 10, "configVersion": 30},
		"calendar": {"year": 1, "season": "spring", "dayInSeason": 1, "dayTotal": 5},
		"inventory": {"food": 10, "water": 10, "fuel": 50, "parts": 5},
		"train": {"carriages": [{"id": "c1", "templateId": "power", "size": 3}], "bodyHp": 100},
		"world": {"tutorialDone": true},
		"members": [
			{
				"id": "m1",
				"job": "guard",
				"combatRoster": true,
				"abilities": [{"id": "a1", "lv": 1}],
			}
		],
		"tasks": {"search": [], "haul": []},
		"runtime": {"driveHoursToday": 0},
	}


static func _minimal_save_v6() -> Dictionary:
	var s := _minimal_save_v10()
	s["version"] = {"save": 6, "configVersion": 30}
	var m: Dictionary = s["members"][0]
	m["skill"] = "repair"
	m["weaponKits"] = 2
	m.erase("specialties")
	return s


static func _minimal_save_v8_no_weather() -> Dictionary:
	return {
		"version": {"save": 8, "configVersion": 30},
		"calendar": {"year": 1, "season": "winter", "dayInSeason": 1, "dayTotal": 70},
		"inventory": {"food": 10, "water": 10, "fuel": 50},
		"train": {"carriages": [{"id": "c1", "templateId": "power", "size": 3}]},
		"world": {"tutorialDone": true},
		"members": [],
		"tasks": {"search": [], "haul": []},
		"runtime": {},
		"regionRun": {"regionId": "urban", "segmentCount": 2, "segmentIndex": 0, "segments": []},
	}