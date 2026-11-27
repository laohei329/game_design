extends Node
## 开发遥测（Autoload TelemetryService）：追加 JSON Lines 到 user://telemetry.jsonl（09 §4.2）。
##
## 各 Service 在关键决策点 record(event, payload)；冒烟检查 search_assign / carriage_abandon 等。
## 不入正式发行包时可整 Autoload 剥离；与 SaveService 独立，不写存档。

const LOG_PATH := "user://telemetry.jsonl"

## 追加一行 telemetry.jsonl。
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