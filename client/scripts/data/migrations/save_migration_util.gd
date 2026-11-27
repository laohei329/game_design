class_name SaveMigrationUtil
extends RefCounted
## 迁移链共用：安全取块、写 version.save。


static func ensure_dict(parent: Dictionary, key: String) -> Dictionary:
	var raw: Variant = parent.get(key, {})
	if typeof(raw) != TYPE_DICTIONARY:
		raw = {}
		parent[key] = raw
	return raw


static func ensure_array(parent: Dictionary, key: String) -> Array:
	var raw: Variant = parent.get(key, [])
	if typeof(raw) != TYPE_ARRAY:
		raw = []
		parent[key] = raw
	return raw


static func set_save_version(save: Dictionary, ver: int) -> void:
	var ver_block := ensure_dict(save, "version")
	ver_block["save"] = ver


static func save_version(save: Dictionary) -> int:
	var ver: Variant = save.get("version", {})
	if typeof(ver) != TYPE_DICTIONARY:
		return 0
	return int(ver.get("save", 0))


static func config_db_node() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return null
	return (tree as SceneTree).root.get_node_or_null("ConfigDb")


static func config_db_ready() -> bool:
	var db := config_db_node()
	if db == null:
		return false
	var tables: Variant = db.get("tables")
	return typeof(tables) == TYPE_DICTIONARY and tables.size() > 0


static func config_get_table(table_name: String) -> Dictionary:
	var db := config_db_node()
	if db == null or not db.has_method("get_table"):
		return {}
	var row: Variant = db.call("get_table", table_name)
	return row if typeof(row) == TYPE_DICTIONARY else {}


static func config_require(path: String, fallback: Variant = null) -> Variant:
	var db := config_db_node()
	if db == null or not db.has_method("require"):
		return fallback
	if not config_db_ready():
		return fallback
	var v: Variant = db.call("require", path)
	return fallback if v == null else v


static func config_require_float(path: String, fallback: float) -> float:
	return float(config_require(path, fallback))


static func has_workshop_carriage(save: Dictionary) -> bool:
	var train: Dictionary = save.get("train", {})
	if typeof(train) != TYPE_DICTIONARY:
		return false
	for c in train.get("carriages", []):
		if typeof(c) == TYPE_DICTIONARY and str(c.get("templateId", "")) == "workshop":
			return true
	return false