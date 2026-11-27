class_name SessionIntentsTrain
extends RefCounted


## @return -1 未处理 · 0 已处理 · 1 已处理且需 `state_changed`
static func try_handle(session: Node, intent_name: String, payload: Dictionary) -> int:
	if session.state == null:
		match intent_name:
			"SET_DRIVE_INTENT", "OPEN_SEARCH", "CLOSE_SEARCH":
				return 0
		return -1
	match intent_name:
		"SET_DRIVE_INTENT":
			DriveService.set_intent(session.state, str(payload.get("mode", "stop")))
			return 1
		"ABANDON_CARRIAGE":
			var car_id := str(payload.get("carId", ""))
			if TrainService.abandon_carriage(session.state, car_id):
				session.state.abandon_selected_car_id = ""
				return 1
			return 0
		"OPEN_ABANDON":
			session.state.abandon_panel_open = true
			if session.state.abandon_selected_car_id == "":
				session.state.abandon_selected_car_id = TrainService.default_abandon_car_id(session.state)
			return 1
		"CLOSE_ABANDON":
			session.state.abandon_panel_open = false
			return 1
		"ASSIGN_SEARCH":
			var err := SearchService.assign_search(
				session.state,
				str(payload.get("pointId", "")),
				payload.get("memberIds", []),
				session.search_telemetry
			)
			if err != "":
				push_warning("ASSIGN_SEARCH: " + SearchService.localize_err(err))
				return 0
			return 1
		"RECALL_SEARCH":
			var serr := SearchService.recall_search(session.state, payload)
			if serr != "":
				push_warning("RECALL_SEARCH: " + serr)
			return 1
		"OPEN_SEARCH":
			session.state.search_panel_open = true
			return 1
		"CLOSE_SEARCH":
			session.state.search_panel_open = false
			return 1
		"SET_MEMBER_JOB":
			var jerr := MemberRoster.set_member_job(
				session.state,
				str(payload.get("memberId", "")),
				str(payload.get("job", ""))
			)
			if jerr != "":
				push_warning("SET_MEMBER_JOB: " + jerr)
				return 0
			return 1
		"ASSIGN_HAUL":
			var herr := HaulService.assign_haul(
				session.state,
				str(payload.get("pointId", "")),
				str(payload.get("memberId", ""))
			)
			if herr != "":
				push_warning("ASSIGN_HAUL: " + herr)
			return 1
		"RECALL_HAUL":
			var rerr := HaulService.recall_haul(session.state, payload)
			if rerr != "":
				push_warning("RECALL_HAUL: " + rerr)
			return 1
		"ENTER_STATION":
			StationService.manual_enter(session.state)
			return 1
		"RESOLVE_OFFER":
			var oerr := StationService.resolve_offer(session.state, bool(payload.get("accept", false)))
			if oerr != "":
				push_warning("RESOLVE_OFFER: " + oerr)
			return 1
		_:
			return -1