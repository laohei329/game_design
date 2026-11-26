extends Node

signal state_changed

var state: RunState = null
var search_telemetry: Dictionary = {}


func _ready() -> void:
	IntentBus.intent_emitted.connect(_on_intent)


func _on_intent(intent_name: String, payload: Dictionary) -> void:
	match intent_name:
		"NEW_RUN":
			_new_run()
		"SET_DRIVE_INTENT":
			if state:
				DriveService.set_intent(state, str(payload.get("mode", "stop")))
				state_changed.emit()
		"ABANDON_CARRIAGE":
			if state:
				var car_id := str(payload.get("carId", ""))
				if TrainService.abandon_carriage(state, car_id):
					state.abandon_selected_car_id = ""
					state_changed.emit()
		"OPEN_ABANDON":
			if state:
				state.abandon_panel_open = true
				if state.abandon_selected_car_id == "" and not state.carriages.is_empty():
					state.abandon_selected_car_id = str(state.carriages[0].get("id", ""))
				state_changed.emit()
		"CLOSE_ABANDON":
			if state:
				state.abandon_panel_open = false
				state_changed.emit()
		"ASSIGN_SEARCH":
			if state:
				var err := SearchService.assign_search(
					state,
					str(payload.get("pointId", "")),
					payload.get("memberIds", []),
					search_telemetry
				)
				if err != "":
					push_warning("ASSIGN_SEARCH: " + _search_err_zh(err))
				else:
					state_changed.emit()
		"RECALL_SEARCH":
			if state:
				var err := SearchService.recall_search(state, payload)
				if err != "":
					push_warning("RECALL_SEARCH: " + err)
				state_changed.emit()
		"OPEN_SEARCH":
			if state:
				state.search_panel_open = true
				state_changed.emit()
		"CLOSE_SEARCH":
			if state:
				state.search_panel_open = false
				state_changed.emit()
		"ASSIGN_HAUL":
			if state:
				var err := HaulService.assign_haul(
					state,
					str(payload.get("pointId", "")),
					str(payload.get("memberId", ""))
				)
				if err != "":
					push_warning("ASSIGN_HAUL: " + err)
				state_changed.emit()
		"RECALL_HAUL":
			if state:
				var err := HaulService.recall_haul(state, payload)
				if err != "":
					push_warning("RECALL_HAUL: " + err)
				state_changed.emit()
		"ADVANCE_DAY", "END_DAY":
			if state:
				_advance_one_day()
		"SET_HEATING":
			if state:
				state.heating_enabled = bool(payload.get("enabled", false))
				ClimateService.recompute(state)
				state_changed.emit()
		"ENTER_STATION":
			if state:
				StationService.manual_enter(state)
				state_changed.emit()
		"SAVE_GAME":
			if state:
				if SaveService.write_state(state, int(payload.get("slot", 0))):
					state_changed.emit()
		"LOAD_GAME":
			var loaded := SaveService.read_state(int(payload.get("slot", 0)))
			if loaded:
				state = loaded
				search_telemetry.clear()
				state_changed.emit()
		"RESOLVE_OFFER":
			if state:
				var err := StationService.resolve_offer(state, bool(payload.get("accept", false)))
				if err != "":
					push_warning("RESOLVE_OFFER: " + err)
				state_changed.emit()
		_:
			push_warning("GameSession: unhandled intent " + intent_name)


func _search_err_zh(code: String) -> String:
	var m := {
		"pick_members": "请勾选 1–4 名搜刮队员",
		"too_many": "搜索最多 4 人",
		"member_busy": "队员不可派出",
		"cap_exceeded": "本日该点搜索次数已满",
	}
	return m.get(code, code)


func _advance_one_day() -> void:
	DriveService.accrue_end_of_day(state)
	StationService.after_day_travel(state)
	SearchService.on_end_day(state)
	HaulService.on_end_day(state)
	DaySettle.run(state)
	GameCalendar.advance_day(state)
	state_changed.emit()


func _new_run() -> void:
	RngService.seed_from(int(Time.get_unix_time_from_system()) & 0x7FFFFFFF)
	state = RunState.new()
	var start: Dictionary = ConfigDb.require("balance.start")
	if typeof(start) == TYPE_DICTIONARY:
		state.food = float(start.get("food", 20))
		state.water = float(start.get("water", 24))
		state.fuel = float(start.get("fuel", 88))
		state.parts = float(start.get("parts", 6))
		state.medicine = float(start.get("med", 4))
		state.seed = float(start.get("seed", 1))
	var regions: Dictionary = ConfigDb.require("balance.regions")
	if typeof(regions) == TYPE_DICTIONARY:
		state.region_fuel_mult = float(regions.get("defaultFuelMult", 1.0))
	state.carriages = [
		{"id": "car_pwr", "templateId": "power", "size": 3},
		{"id": "car_liv", "templateId": "living", "size": 2},
		{"id": "car_cgo", "templateId": "cargo", "size": 3},
	]
	SegmentBuild.begin_tutorial_region_run(state)
	MemberRoster.seed_starting_crew(state)
	state.tutorial_done = false
	GameCalendar.sync_calendar_fields(state)
	search_telemetry.clear()
	state.search_tasks.clear()
	state.search_panel_open = false
	state.abandon_panel_open = false
	state.abandon_selected_car_id = ""
	state.haul_tasks.clear()
	state_changed.emit()