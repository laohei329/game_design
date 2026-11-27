extends Node
## 配置表加载（Autoload ConfigDb）：`res://data` ↔ 仓库 `data/`。
##
## 玩法数值只许 `require("表.键.…")` 读取；缺键 push_error，禁止玩法脚本写死乘子。

var tables: Dictionary = {}
var load_errors: PackedStringArray = []
var config_version: int = 0

const MANIFEST := "res://data/manifest.json"
## _ready
##
## Autoload ConfigDb；玩法只读 require/get_table，禁止硬编码常数。
## 无返回值。
func _ready() -> void:
	load_all()

## 按 manifest 加载 JSON 表；CSV 交 LocaleDb。
##
## Autoload ConfigDb；玩法只读 require/get_table，禁止硬编码常数。
## @return 是否成功或条件成立。
func load_all() -> bool:
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
	config_version = int(manifest.get("configVersion", 0))
	var files: Dictionary = manifest.get("files", {})
	for table_name in files.keys():
		var rel := str(files[table_name]).replace("\\", "/")
		if rel.ends_with(".csv"):
			# 文案表由 Autoload LocaleDb 专载；此处占位避免误当 JSON 解析。
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
	return load_errors.is_empty()

## 已加载根表；无则 `{}`。
##
## Autoload ConfigDb；玩法只读 require/get_table，禁止硬编码常数。
## @param table_name Config manifest 表名
## @return 结果字典；缺失语义键时可能为空 {}。
func get_table(table_name: String) -> Dictionary:
	return tables.get(table_name, {})

## 点分路径取值；缺失 push_error。
##
## Autoload ConfigDb；玩法只读 require/get_table，禁止硬编码常数。
## @param path 点分配置路径
## @return `Variant`。
func require(path: String) -> Variant:
	# path like "balance.start" or "hud_hints.fuelFill"
	var parts := path.split(".")
	if parts.is_empty():
		return null
	var root_name := parts[0]
	var node: Variant = tables.get(root_name, null)
	if node == null:
		push_error("ConfigDb.require missing root: " + root_name)
		return null
	for i in range(1, parts.size()):
		if typeof(node) != TYPE_DICTIONARY:
			return null
		node = node.get(parts[i], null)
		if node == null:
			push_error("ConfigDb.require missing: " + path)
			return null
	return node
