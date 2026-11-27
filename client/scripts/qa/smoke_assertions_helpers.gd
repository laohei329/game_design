class_name SmokeAssertionsHelpers
extends RefCounted
## 冒烟共用：Intent 驱动与搜索复位辅助。

static func _intent_drive(mode: String) -> void:
	IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": mode})


## 指派搜索经 GameSession；`telem` 非空时临时写入 `GameSession.search_telemetry`。
static func _intent_assign_search(point_id: String, member_ids: Array, telem: Dictionary) -> String:
	if not telem.is_empty():
		GameSession.search_telemetry = telem.duplicate(true)
	IntentBus.emit_intent("ASSIGN_SEARCH", {"pointId": point_id, "memberIds": member_ids})
	var st := GameSession.state
	if st == null:
		return "no_state"
	for t in st.search_tasks:
		if typeof(t) == TYPE_DICTIONARY and str(t.get("pointId", "")) == point_id:
			if not bool(t.get("complete", false)):
				return ""
	return "assign_failed"


static func first_member_id(state: RunState, prefer_job: String = "") -> String:
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if prefer_job != "" and str(m.get("job", "")) != prefer_job:
			continue
		var mid := str(m.get("id", ""))
		if mid != "":
			return mid
	if prefer_job != "":
		return first_member_id(state, "")
	return ""

## 冒烟：搜索 assign + telemetry。
static func _clear_search_tasks(state: RunState) -> void:
	for m in state.members:
		if typeof(m) == TYPE_DICTIONARY:
			m["taskState"] = "idle"
			m["hp"] = maxf(float(m.get("hp", 100.0)), 100.0)
	state.search_tasks.clear()

## 截取日结前粮/水/油快照，供 `audit_after_triplet_end_day` 差分断言。
static func _snapshot_burn_inputs(state: RunState) -> RunState:
	var s := RunState.new()
	s.carriages = state.carriages.duplicate(true)
	s.fuel = state.fuel
	s.power_tech = state.power_tech
	s.drive_hours_today = state.drive_hours_today
	s.reverse_hours_today = state.reverse_hours_today
	s.fuel_climate = state.fuel_climate
	s.region_fuel_mult = state.region_fuel_mult
	return s

## 冒烟：L1 遭遇与检定链。
static func _telemetry_has(event_name: String) -> bool:
	var path := "user://telemetry.jsonl"
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	return text.find("\"event\":\"%s\"" % event_name) >= 0 or text.find('"event": "%s"' % event_name) >= 0
