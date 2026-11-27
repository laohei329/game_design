extends Node
## 配置表加载（Autoload ConfigDb）：`res://data` ↔ 仓库 `data/`。
##
## 玩法数值只许 `require("表.键.…")` 读取；缺键 push_error，禁止玩法脚本写死乘子。

var tables: Dictionary = {}
var load_errors: PackedStringArray = []
var _config_version: int = 0

const MANIFEST := "res://data/manifest.json"


func _ready() -> void:
	if not load_all():
		push_error("ConfigDb autoload failed:\n" + "\n".join(load_errors))


## 按 manifest 加载 JSON 表；CSV 交 LocaleDb；legacyFiles 与 Python ConfigDb 对齐。
func load_all() -> bool:
	_config_version = 0
	tables.clear()
	load_errors.clear()
	if not FileAccess.file_exists(MANIFEST):
		load_errors.append("missing " + MANIFEST)
		return false
	var manifest_text := FileAccess.get_file_as_string(MANIFEST)
	var manifest: Variant = JSON.parse_string(manifest_text)
	if typeof(manifest) != TYPE_DICTIONARY:
		load_errors.append("manifest not object")
		return false
	_config_version = int(manifest.get("configVersion", 0))

	var files: Dictionary = manifest.get("files", {})
	for table_name in files.keys():
		var rel := str(files[table_name]).replace("\\", "/")
		if rel.ends_with(".csv"):
			var csv_path := "res://data/" + rel
			if not FileAccess.file_exists(csv_path):
				load_errors.append("missing locale csv %s at %s" % [table_name, csv_path])
				continue
			tables[table_name] = {"_localeCsv": rel}
			continue
		var path := "res://data/" + rel
		if not FileAccess.file_exists(path):
			load_errors.append("missing table %s at %s" % [table_name, path])
			continue
		var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(payload) != TYPE_DICTIONARY:
			load_errors.append("table %s root must be object" % table_name)
			continue
		tables[table_name] = payload

	var legacy: Variant = manifest.get("legacyFiles", {})
	if typeof(legacy) == TYPE_DICTIONARY:
		for table_name in legacy.keys():
			var rel := str(legacy[table_name]).replace("\\", "/")
			var path := "res://data/" + rel
			if not FileAccess.file_exists(path):
				load_errors.append("missing legacy table %s at %s" % [table_name, path])
				continue
			var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(payload) != TYPE_DICTIONARY:
				load_errors.append("legacy table %s root must be object" % table_name)
				continue
			tables[table_name] = payload

	if not load_errors.is_empty():
		tables.clear()
		_config_version = 0
		return false
	return true


func reload_all() -> bool:
	return load_all()


func has(path: String) -> bool:
	var parts := path.split(".")
	if parts.is_empty():
		return false
	var node: Variant = tables.get(parts[0], null)
	if node == null:
		return false
	for i in range(1, parts.size()):
		if typeof(node) != TYPE_DICTIONARY:
			return false
		if not node.has(parts[i]):
			return false
		node = node[parts[i]]
	return true


func config_version() -> int:
	return _config_version


func get_table(table_name: String) -> Dictionary:
	if not tables.has(table_name):
		push_error("ConfigDb.get_table unknown: " + table_name)
		return {}
	return tables[table_name]


func require(path: String) -> Variant:
	var parts := path.split(".")
	if parts.is_empty():
		push_error("ConfigDb.require empty path")
		return null
	var root_name := parts[0]
	var node: Variant = tables.get(root_name, null)
	if node == null:
		push_error("ConfigDb.require missing root: " + root_name)
		return null
	for i in range(1, parts.size()):
		if typeof(node) != TYPE_DICTIONARY:
			push_error("ConfigDb.require not a dict at: " + ".".join(parts.slice(0, i + 1)))
			return null
		var key := parts[i]
		if not node.has(key):
			push_error("ConfigDb.require missing: " + path)
			return null
		node = node[key]
	return node