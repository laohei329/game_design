class_name SaveMigrationChain
extends RefCounted
## 按 data/migrations/manifest.json 逐级迁移至目标 version.save。

const MANIFEST_PATH := "res://data/migrations/manifest.json"

static var _chain: Array = []
static var _chain_loaded: bool = false


static func _load_chain() -> void:
	if _chain_loaded:
		return
	_chain_loaded = true
	_chain = []
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_error("SaveMigrationChain: missing " + MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveMigrationChain: bad manifest")
		return
	var raw: Variant = parsed.get("chain", [])
	if typeof(raw) != TYPE_ARRAY:
		return
	for row in raw:
		if typeof(row) == TYPE_DICTIONARY:
			_chain.append(row)


static func migrate_to(save: Dictionary, target_version: int) -> String:
	_load_chain()
	if _chain.is_empty():
		return "migration_manifest_empty"
	SaveMigrationUtil.ensure_dict(save, "version")
	var sv := SaveMigrationUtil.save_version(save)
	if sv <= 0:
		return "missing_save_version"
	if sv < 2:
		return "unsupported_save_version_%d" % sv
	if sv > target_version:
		return "unsupported_save_version_%d" % sv
	while sv < target_version:
		var step: Dictionary = {}
		for row in _chain:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			if int(row.get("from", -1)) == sv:
				step = row
				break
		if step.is_empty():
			return "missing_migration_from_%d" % sv
		var step_id := str(step.get("id", ""))
		var to_ver := int(step.get("to", sv + 1))
		var err := SaveMigrationSteps.apply_step(step_id, save)
		if err != "":
			return err
		if SaveMigrationUtil.save_version(save) != to_ver:
			SaveMigrationUtil.set_save_version(save, to_ver)
		sv = SaveMigrationUtil.save_version(save)
	return ""