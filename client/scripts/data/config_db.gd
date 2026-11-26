extends Node
## Loads manifest + JSON/CSV tables from res://data (align sim/config_db.py).

var tables: Dictionary = {}
var load_errors: PackedStringArray = []
var config_version: int = 0

const MANIFEST := "res://data/manifest.json"


func _ready() -> void:
	load_all()


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
		var path := "res://data/" + rel
		if not FileAccess.file_exists(path):
			load_errors.append("missing table %s at %s" % [table_name, path])
			continue
		if rel.to_lower().ends_with(".csv"):
			if not _load_csv_table(table_name, path):
				continue
		else:
			var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(payload) != TYPE_DICTIONARY:
				load_errors.append("table %s root must be object" % table_name)
				continue
			tables[table_name] = payload
	return load_errors.is_empty()


func _load_csv_table(table_name: String, path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n", false)
	if lines.is_empty():
		load_errors.append("table %s: empty csv" % table_name)
		return false
	var header := _parse_csv_line(lines[0].strip_edges())
	if header.find("key") < 0:
		load_errors.append("table %s: CSV must have 'key' column" % table_name)
		return false
	var rows: Array = []
	for i in range(1, lines.size()):
		var line := lines[i].strip_edges()
		if line.is_empty():
			continue
		var cols := _parse_csv_line(line)
		var row := {}
		for j in header.size():
			if j < cols.size():
				row[header[j]] = cols[j]
		rows.append(row)
	tables[table_name] = {"_csv": true, "rows": rows, "path": path.get_file()}
	return true


func _parse_csv_line(line: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var i := 0
	var field := ""
	var in_quotes := false
	while i < line.length():
		var c: String = line[i]
		if in_quotes:
			if c == "\"":
				if i + 1 < line.length() and line[i + 1] == "\"":
					field += "\""
					i += 2
					continue
				in_quotes = false
			else:
				field += c
		else:
			if c == "\"":
				in_quotes = true
			elif c == ",":
				out.append(field)
				field = ""
			else:
				field += c
		i += 1
	out.append(field)
	return out


func get_table(table_name: String) -> Dictionary:
	var t: Variant = tables.get(table_name, {})
	return t if typeof(t) == TYPE_DICTIONARY else {}


func require(path: String) -> Variant:
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