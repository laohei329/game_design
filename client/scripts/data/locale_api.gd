class_name LocaleApi
extends RefCounted
## 本地化静态 API：供 `class_name` / `static func` 安全调用（勿在 static 里绑 Autoload 实例方法）。
##
## Autoload LocaleDb 负责热重载与 TranslationServer；本类持合并 CSV 表。


const MANIFEST_PATH := "res://data/manifest.json"
const MOD_LOCALE_GLOB := "user://mods/locale"
const LANG_COLUMNS := ["en", "zh", "de", "ru", "es"]

static var locale_id: String = "zh"
static var debug_show_keys: bool = false
static var _entries: Dictionary = {}
static var load_errors: PackedStringArray = []


## 清空并加载 manifest + mod CSV。
static func load_all() -> bool:
	_entries.clear()
	load_errors.clear()
	_load_manifest_tables()
	_load_mod_overlays()
	return load_errors.is_empty()


static func entries() -> Dictionary:
	return _entries


## 取 ui 键文案（勿命名 tr，避免与 Object.tr 冲突）。
static func tr_key(key: String, fallback: String = "") -> String:
	if debug_show_keys:
		return "[%s]" % key
	var via := TranslationServer.translate(key)
	if via != key:
		return via
	var row: Variant = _entries.get(key, null)
	if typeof(row) == TYPE_DICTIONARY:
		var s := str(row.get(locale_id, "")).strip_edges()
		if s.is_empty():
			s = str(row.get("en", "")).strip_edges()
		if not s.is_empty():
			return s
	return fallback if fallback != "" else key


static func tr_code(prefix: String, code: String, fallback: String = "") -> String:
	if code.is_empty():
		return fallback
	return tr_key("%s.%s" % [prefix, code], fallback if fallback != "" else code)


## 玩家可见数值（HUD/面板）；禁止 `str(float)` 直出长尾小数。
static func ui_num(value: float, decimals: int = 1) -> String:
	var places := clampi(decimals, 0, 4)
	var step: float = pow(10.0, float(places))
	var rounded: float = round(value * step) / step
	if places == 0:
		return str(int(rounded))
	return ("%0." + str(places) + "f") % rounded


static func trf(key: String, args: Array, fallback: String = "") -> String:
	var s := tr_key(key, fallback)
	for i in args.size():
		s = s.replace("{%d}" % i, _trf_arg_string(args[i]))
	return s


static func _trf_arg_string(arg: Variant) -> String:
	match typeof(arg):
		TYPE_FLOAT:
			return ui_num(arg, 1)
		TYPE_INT:
			return str(arg)
		TYPE_STRING:
			return arg
		_:
			return str(arg)


static func from_locale_block(block: Variant, fallback: String = "") -> String:
	if typeof(block) != TYPE_DICTIONARY:
		return fallback
	var s := str(block.get(locale_id, "")).strip_edges()
	if s.is_empty():
		s = str(block.get("en", "")).strip_edges()
	if s.is_empty():
		s = str(block.get("zh", "")).strip_edges()
	return s if s != "" else fallback


static func has_key(key: String) -> bool:
	return _entries.has(key)


static func _load_manifest_tables() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		load_errors.append("missing manifest")
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(manifest) != TYPE_DICTIONARY:
		load_errors.append("manifest not object")
		return
	var files: Variant = manifest.get("files", {})
	if typeof(files) != TYPE_DICTIONARY:
		return
	for table_name in files.keys():
		if not str(table_name).begins_with("localization_"):
			continue
		var rel := str(files[table_name]).replace("\\", "/")
		if not rel.ends_with(".csv"):
			continue
		var path := "res://data/" + rel
		if not FileAccess.file_exists(path):
			load_errors.append("missing locale csv: " + path)
			continue
		_merge_csv_file(path)


static func _load_mod_overlays() -> void:
	var dir := DirAccess.open(MOD_LOCALE_GLOB)
	if dir == null:
		return
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir() and fn.ends_with(".csv"):
			_merge_csv_file(MOD_LOCALE_GLOB + "/" + fn)
		fn = dir.get_next()
	dir.list_dir_end()


static func _merge_csv_file(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var line_no := 0
	for raw_line in text.split("\n"):
		line_no += 1
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line_no == 1 and line.begins_with("key,"):
			continue
		var cols := _split_csv_line(line)
		if cols.size() < 2:
			load_errors.append("%s:%d bad row" % [path, line_no])
			continue
		var key := cols[0].strip_edges()
		if key.is_empty():
			continue
		var row := {}
		for i in LANG_COLUMNS.size():
			var col := i + 1
			if col < cols.size():
				row[LANG_COLUMNS[i]] = cols[col].strip_edges()
		_entries[key] = row


static func _split_csv_line(line: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var cur := ""
	var i := 0
	while i < line.length():
		var ch: String = line[i]
		if ch == "\"":
			i += 1
			while i < line.length():
				if line[i] == "\"":
					if i + 1 < line.length() and line[i + 1] == "\"":
						cur += "\""
						i += 2
					else:
						i += 1
						break
				else:
					cur += line[i]
					i += 1
			continue
		if ch == ",":
			out.append(cur)
			cur = ""
			i += 1
			continue
		cur += ch
		i += 1
	out.append(cur)
	return out