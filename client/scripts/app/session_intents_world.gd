class_name SessionIntentsWorld
extends RefCounted


## @return -1 未处理 · 0 已处理 · 1 已处理且需 `state_changed`
static func try_handle(session: Node, intent_name: String, payload: Dictionary) -> int:
	if session.state == null:
		return -1
	match intent_name:
		"PICK_REGION":
			var err: String = RegionService.pick_region(session.state, str(payload.get("regionId", "")))
			if err != "":
				push_warning("PICK_REGION: " + err)
			else:
				WeatherDraw.sync_weather_from_active_segment(session.state)
				ClimateService.refresh(session.state)
			return 1
		"CLOSE_REGION_PICK":
			session.state.region_pick_open = false
			return 1
		"OPEN_TECH":
			session.state.tech_panel_open = true
			return 1
		"CLOSE_TECH":
			session.state.tech_panel_open = false
			return 1
		"BUY_UPGRADE":
			var terr: String = TechService.buy_upgrade(session.state, str(payload.get("line", "")))
			if terr != "":
				push_warning("BUY_UPGRADE: " + LocaleApi.tr_code("tech.err", terr, terr))
			return 1
		"OPEN_COMBAT":
			var cerr: String = CombatL1.open_encounter(session.state, int(payload.get("enemyCount", 3)))
			if cerr != "":
				push_warning("OPEN_COMBAT: " + cerr)
			return 1
		"CLOSE_COMBAT":
			session.state.combat_panel_open = false
			session.state.pending_combat.clear()
			session.state.combat_l1_after_fail = false
			return 1
		"RESOLVE_COMBAT_L1_CHECK":
			var rep: Dictionary = CombatL1.resolve_l1_check(session.state)
			if not bool(rep.get("ok", false)):
				push_warning("L1: " + str(rep.get("error", "")))
			return 1
		"RESOLVE_NON_COMBAT":
			var nrep: Dictionary = CombatL1.resolve_non_combat(session.state, str(payload.get("path", "")))
			if not bool(nrep.get("ok", false)):
				push_warning("非战斗: " + str(nrep.get("error", "")))
			return 1
		"RESOLVE_COMBAT_L1_FAIL":
			var ferr: String = CombatL1.resolve_after_fail(session.state, str(payload.get("choice", "")))
			if ferr != "":
				push_warning("L1 fail: " + ferr)
			return 1
		"CHOOSE_EVENT_OPTION":
			var seg: Segment = (
				session.state.region_run.active_segment() if session.state.region_run else null
			)
			var eid := str(payload.get("eventId", seg.event_id if seg else ""))
			var oerr: String = EventOps.choose_option(session.state, eid, str(payload.get("optionId", "")))
			if oerr != "":
				push_warning("事件: " + oerr)
			return 1
		_:
			return -1