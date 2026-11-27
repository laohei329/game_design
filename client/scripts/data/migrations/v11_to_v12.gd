extends RefCounted
## 09 §2 v11→v12：编队、图纸、点位 yield、regionRun、战斗会话清理。

class_name MigrationV11ToV12

const _SearchService := preload("res://scripts/gameplay/search_service.gd")


static func apply(save: Dictionary) -> void:
	if typeof(save) != TYPE_DICTIONARY:
		return
	if not save.has("version"):
		save["version"] = {}
	save["version"]["save"] = 12
	_patch_train(save)
	_patch_members(save)
	_patch_region_run(save)
	save.erase("combatSession")


static func _patch_train(save: Dictionary) -> void:
	var train: Dictionary = save.get("train", {})
	if typeof(train) != TYPE_DICTIONARY:
		train = {}
		save["train"] = train
	if not train.has("driveIntent"):
		train["driveIntent"] = "stop"
	var bp: Variant = train.get("blueprints", {})
	if typeof(bp) != TYPE_DICTIONARY:
		bp = {}
	for key in ["power", "armor", "radar", "living"]:
		if not bp.has(key):
			bp[key] = false
	if bool(bp.get("life", false)) and not bool(bp.get("living", false)):
		bp["living"] = true
	bp.erase("life")
	train["blueprints"] = bp
	var forms: Variant = train.get("formations", [])
	if typeof(forms) != TYPE_ARRAY or forms.is_empty():
		_seed_formations_dict(save, train)
	train = save.get("train", train)
	save["train"] = train


static func _seed_formations_dict(save: Dictionary, train: Dictionary) -> void:
	var slots: Array = []
	var members: Variant = save.get("members", [])
	if typeof(members) == TYPE_ARRAY:
		for m in members:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			if not bool(m.get("combatRoster", false)):
				continue
			var mid := str(m.get("id", ""))
			if mid.is_empty():
				continue
			slots.append({"memberId": mid, "slotId": "front_%d" % (slots.size() + 1)})
			if slots.size() >= 8:
				break
	train["formations"] = [
		{
			"id": "fmt_default",
			"name": "默认编队",
			"slots": slots,
			"reserve": [],
		},
	]
	train["activeFormationId"] = "fmt_default" if not slots.is_empty() else ""


static func _patch_members(save: Dictionary) -> void:
	var members: Variant = save.get("members", [])
	if typeof(members) != TYPE_ARRAY:
		return
	for m in members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("taskState", "")) == "in_combat":
			m["taskState"] = "idle"


static func _patch_region_run(save: Dictionary) -> void:
	var rr: Variant = save.get("regionRun", {})
	if typeof(rr) != TYPE_DICTIONARY or rr.is_empty():
		return
	if not rr.has("regionFuelMult"):
		var rid := str(rr.get("regionId", "urban"))
		var row: Dictionary = RegionService.region_def(rid)
		rr["regionFuelMult"] = float(row.get("regionFuelMult", 1.0))
	if not rr.has("pointTypeWeightMods"):
		rr["pointTypeWeightMods"] = {}
	var segs: Variant = rr.get("segments", [])
	if typeof(segs) != TYPE_ARRAY:
		save["regionRun"] = rr
		return
	for sd in segs:
		if typeof(sd) != TYPE_DICTIONARY:
			continue
		if not sd.has("raidWeightDelta"):
			sd["raidWeightDelta"] = 0.0
		var points: Variant = sd.get("points", [])
		if typeof(points) != TYPE_ARRAY:
			continue
		for pt in points:
			if typeof(pt) != TYPE_DICTIONARY:
				continue
			if not pt.has("remainingYield"):
				pt["remainingYield"] = _SearchService.initial_remaining_yield(str(pt.get("type", "")))
			if not pt.has("depleted"):
				pt["depleted"] = false
			var pile: Variant = pt.get("lootPile", {})
			if typeof(pile) != TYPE_DICTIONARY:
				pt["lootPile"] = {}
	save["regionRun"] = rr