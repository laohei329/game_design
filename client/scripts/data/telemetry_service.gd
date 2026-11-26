extends Node
## Dev telemetry (09 §4.2). Appends JSON lines to user://telemetry.jsonl.

const LOG_PATH := "user://telemetry.jsonl"


func record(event_name: String, payload: Dictionary = {}) -> void:
	var row: Dictionary = {"event": event_name, "ts_ms": Time.get_unix_time_from_system() * 1000}
	for k in payload.keys():
		row[k] = payload[k]
	var line := JSON.stringify(row) + "\n"
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	else:
		f.seek_end()
	if f:
		f.store_string(line)
		f.close()