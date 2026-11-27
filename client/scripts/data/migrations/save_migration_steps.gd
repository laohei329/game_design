class_name SaveMigrationSteps
extends RefCounted
## 09 §2 存档迁移逐步实现（v2→…→v12）。


const _V11 := preload("res://scripts/data/migrations/v11_to_v12.gd")

const JOB_CLOSED: Array[String] = [
	"none",
	"labor",
	"guard",
	"engineer",
	"crafter",
	"grower",
	"purifier",
	"radar_op",
	"pharmacist",
]


static func apply_step(step_id: String, save: Dictionary) -> String:
	match step_id:
		"v2_to_v3":
			_apply_v2_to_v3(save)
		"v3_to_v4":
			_apply_v3_to_v4(save)
		"v4_to_v5":
			_apply_v4_to_v5(save)
		"v5_to_v6":
			_apply_v5_to_v6(save)
		"v6_to_v7":
			_apply_v6_to_v7(save)
		"v7_to_v8":
			_apply_v7_to_v8(save)
		"v8_to_v9":
			_apply_v8_to_v9(save)
		"v9_to_v10":
			_apply_v9_to_v10(save)
		"v10_to_v11":
			_apply_v10_to_v11(save)
		"v11_to_v12":
			_V11.apply(save)
		_:
			return "unknown_migration_%s" % step_id
	return ""


static func _apply_v2_to_v3(save: Dictionary) -> void:
	SaveMigrationUtil.ensure_dict(save, "version")
	SaveMigrationUtil.ensure_dict(save, "calendar")
	SaveMigrationUtil.ensure_dict(save, "inventory")
	SaveMigrationUtil.ensure_dict(save, "train")
	SaveMigrationUtil.ensure_dict(save, "world")
	SaveMigrationUtil.ensure_array(save, "members")
	SaveMigrationUtil.ensure_dict(save, "tasks")
	SaveMigrationUtil.ensure_dict(save, "runtime")
	SaveMigrationUtil.set_save_version(save, 3)


static func _apply_v3_to_v4(save: Dictionary) -> void:
	var tasks := SaveMigrationUtil.ensure_dict(save, "tasks")
	if not tasks.has("search"):
		tasks["search"] = []
	if not tasks.has("haul"):
		tasks["haul"] = []
	SaveMigrationUtil.set_save_version(save, 4)


static func _apply_v4_to_v5(save: Dictionary) -> void:
	var train := SaveMigrationUtil.ensure_dict(save, "train")
	var cars := SaveMigrationUtil.ensure_array(train, "carriages")
	for i in cars.size():
		if typeof(cars[i]) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = cars[i]
		if not c.has("templateId") and c.has("type"):
			c["templateId"] = str(c["type"])
		c.erase("type")
		if not c.has("function"):
			c["function"] = null
		cars[i] = c
	train.erase("research")
	for m in SaveMigrationUtil.ensure_array(save, "members"):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if m.has("weaponKits"):
			var n := int(m.get("weaponKits", 0))
			var gear: Dictionary = m.get("gear", {}) if typeof(m.get("gear", {})) == TYPE_DICTIONARY else {}
			gear["ranged"] = int(gear.get("ranged", 0)) + n
			gear["melee"] = int(gear.get("melee", 0)) + int(n / 2)
			gear["defense"] = int(gear.get("defense", 0)) + int(n / 3)
			m["gear"] = gear
			m.erase("weaponKits")
	if SaveMigrationUtil.has_workshop_carriage(save) and not train.has("precision"):
		train["precision"] = SaveMigrationUtil.config_require_float("balance.start.precision", 40.0)
	SaveMigrationUtil.set_save_version(save, 5)


static func _apply_v5_to_v6(save: Dictionary) -> void:
	var inv := SaveMigrationUtil.ensure_dict(save, "inventory")
	if not inv.has("potion"):
		inv["potion"] = 0.0
	if not inv.has("chem"):
		inv["chem"] = 0.0
	for m in SaveMigrationUtil.ensure_array(save, "members"):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var ab_list: Array = m.get("abilities", [])
		if typeof(ab_list) != TYPE_ARRAY:
			continue
		for j in ab_list.size():
			if typeof(ab_list[j]) != TYPE_DICTIONARY:
				continue
			var ab: Dictionary = ab_list[j]
			if ab.has("cost") and not ab.has("costCatalyst"):
				ab["costCatalyst"] = ab["cost"]
				ab.erase("cost")
			if ab.has("crystal") and not ab.has("costCatalyst"):
				ab["costCatalyst"] = ab["crystal"]
				ab.erase("crystal")
			ab_list[j] = ab
		m["abilities"] = ab_list
	SaveMigrationUtil.set_save_version(save, 6)


static func _apply_v6_to_v7(save: Dictionary) -> void:
	for m in SaveMigrationUtil.ensure_array(save, "members"):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if m.has("skill") and not m.has("specialties"):
			var sk := str(m.get("skill", ""))
			m["specialties"] = [] if sk.is_empty() else [sk]
			m.erase("skill")
		var job := str(m.get("job", "none"))
		if job == "medic":
			job = "pharmacist"
		elif job not in JOB_CLOSED:
			job = "none"
		m["job"] = job
		if str(m.get("job", "")) == "guard":
			m["combatRoster"] = true
	SaveMigrationUtil.set_save_version(save, 7)


static func _apply_v7_to_v8(save: Dictionary) -> void:
	for m in SaveMigrationUtil.ensure_array(save, "members"):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("job", "")) == "medic":
			m["job"] = "pharmacist"
		m.erase("medicalSlotLock")
	SaveMigrationUtil.set_save_version(save, 8)


static func _apply_v8_to_v9(save: Dictionary) -> void:
	var rt := SaveMigrationUtil.ensure_dict(save, "runtime")
	if not rt.has("reverseHoursToday"):
		rt["reverseHoursToday"] = 0.0
	for sk in ["foodZeroStreak", "waterZeroStreak", "fuelZeroStreak", "moraleZeroStreak"]:
		if not rt.has(sk):
			rt[sk] = 0
	var world := SaveMigrationUtil.ensure_dict(save, "world")
	if not world.has("lastRecruitSuccessDay"):
		world["lastRecruitSuccessDay"] = -1
	SaveMigrationClimate.apply_v8_weather_and_climate(save)
	if not save.has("regionRun") or typeof(save.get("regionRun")) != TYPE_DICTIONARY:
		save["regionRun"] = {
			"regionId": "urban",
			"segmentCount": 3,
			"segmentIndex": 0,
			"segments": [],
		}
	var train := SaveMigrationUtil.ensure_dict(save, "train")
	if not train.has("formations"):
		train["formations"] = []
	if not train.has("activeFormationId"):
		train["activeFormationId"] = ""
	var cars := SaveMigrationUtil.ensure_array(train, "carriages")
	for i in cars.size():
		if typeof(cars[i]) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = cars[i]
		if str(c.get("templateId", "")) == "power" and not c.has("unattendedFault"):
			c["unattendedFault"] = []
		cars[i] = c
	for m in SaveMigrationUtil.ensure_array(save, "members"):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var ab_list: Array = m.get("abilities", [])
		if typeof(ab_list) != TYPE_ARRAY:
			continue
		for j in ab_list.size():
			if typeof(ab_list[j]) != TYPE_DICTIONARY:
				continue
			var ab: Dictionary = ab_list[j]
			if not ab.has("proficiency"):
				ab["proficiency"] = 0
			ab_list[j] = ab
		m["abilities"] = ab_list
	SaveMigrationUtil.set_save_version(save, 9)


static func _apply_v9_to_v10(save: Dictionary) -> void:
	var world := SaveMigrationUtil.ensure_dict(save, "world")
	if not world.has("heatingEnabled"):
		world["heatingEnabled"] = false
	SaveMigrationUtil.set_save_version(save, 10)


static func _apply_v10_to_v11(save: Dictionary) -> void:
	var world := SaveMigrationUtil.ensure_dict(save, "world")
	if not world.has("pressureHistory"):
		world["pressureHistory"] = [null, null]
	var train := SaveMigrationUtil.ensure_dict(save, "train")
	if not train.has("breakdownCounter"):
		train["breakdownCounter"] = 0
	for m in SaveMigrationUtil.ensure_array(save, "members"):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var ab_list: Array = m.get("abilities", [])
		if typeof(ab_list) != TYPE_ARRAY:
			continue
		for j in ab_list.size():
			if typeof(ab_list[j]) != TYPE_DICTIONARY:
				continue
			var ab: Dictionary = ab_list[j]
			if not ab.has("cooldownUntilDay"):
				ab["cooldownUntilDay"] = 0
			ab_list[j] = ab
		m["abilities"] = ab_list
	SaveMigrationUtil.set_save_version(save, 11)