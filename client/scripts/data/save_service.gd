extends Node
## Save 12 subset + runtime defaults (09 §3.1). Full disk I/O in S1b.

const SAVE_VERSION := 12


func apply_runtime_defaults(save: Dictionary) -> void:
	if not save.has("version"):
		save["version"] = {"save": SAVE_VERSION, "configVersion": ConfigDb.config_version}
	var train: Dictionary = save.get("train", {})
	if not train.has("abandonCount"):
		train["abandonCount"] = 0
	save["train"] = train
	if not save.has("telemetry"):
		save["telemetry"] = {"searchByPointDay": {}}


func patch_loaded_save(save: Dictionary) -> Dictionary:
	apply_runtime_defaults(save)
	var sv := int(save.get("version", {}).get("save", 0))
	if sv < SAVE_VERSION:
		push_warning("SaveService: migration chain not fully implemented; patched defaults only")
	RuntimeSavePatch.ensure_abandon_fields(save)
	return save


func snapshot_for_save(session_state: Dictionary) -> Dictionary:
	var save: Dictionary = session_state.duplicate(true)
	apply_runtime_defaults(save)
	save["version"] = {"save": SAVE_VERSION, "configVersion": ConfigDb.config_version}
	return save


func slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot


func write_state(state: RunState, slot: int = 0) -> bool:
	var save := SaveSchema.to_save_dict(state)
	var text := JSON.stringify(save, "\t")
	var path := slot_path(slot)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveService: cannot write " + path)
		return false
	f.store_string(text)
	return true


func read_state(slot: int = 0) -> RunState:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		push_warning("SaveService: no save at " + path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveService: invalid json " + path)
		return null
	return SaveSchema.from_save_dict(parsed)