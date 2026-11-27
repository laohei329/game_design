class_name SessionIntentsLifecycle
extends RefCounted

const _GameClock := preload("res://scripts/rhythm/game_clock.gd")


## @return -1 未处理 · 0 已处理 · 1 已处理且需 `state_changed`
static func try_handle(session: Node, intent_name: String, payload: Dictionary) -> int:
	match intent_name:
		"NEW_RUN":
			session._new_run()
			return 0
		"ADVANCE_DAY", "END_DAY":
			if session.state:
				session._force_end_game_day()
			return 0
		"SET_TIME_SPEED":
			var s := float(payload.get("speed", session.time_speed))
			if _GameClock.speed_choices().has(s):
				session.time_speed = s
				session.time_paused = false
				return 1
			return 0
		"TOGGLE_TIME_PAUSE":
			session.time_paused = not session.time_paused
			return 1
		"SET_HEATING":
			if session.state:
				session.state.heating_enabled = bool(payload.get("enabled", false))
				ClimateService.refresh(session.state)
				return 1
			return 0
		"SAVE_GAME":
			if session.state and SaveService.write_state(session.state, int(payload.get("slot", 0))):
				return 1
			return 0
		"LOAD_GAME":
			if SaveService.load_into_game_session(int(payload.get("slot", 0))):
				return 1
			return 0
		"DEV_TOGGLE_REGION_FUEL":
			if session.state:
				RegionService.dev_toggle_region_fuel_mult(session.state)
				return 1
			return 0
		_:
			return -1