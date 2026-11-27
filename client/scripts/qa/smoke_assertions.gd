class_name SmokeAssertions
extends RefCounted
## 无头冒烟断言库（headless_smoke.gd 调用，非玩家运行时）。
## 薄门面：按主题委托至 `SmokeAssertions*` 模块。

const _Core := preload("res://scripts/qa/smoke_assertions_core.gd")
const _World := preload("res://scripts/qa/smoke_assertions_world.gd")
const _Outdoor := preload("res://scripts/qa/smoke_assertions_outdoor.gd")
const _Events := preload("res://scripts/qa/smoke_assertions_events.gd")
const _Helpers := preload("res://scripts/qa/smoke_assertions_helpers.gd")

static func errors_main_scenes_load() -> PackedStringArray:
	return _Core.errors_main_scenes_load()

static func errors_config_paths() -> PackedStringArray:
	return _Core.errors_config_paths()

static func errors_start_crew(state: RunState) -> PackedStringArray:
	return _Core.errors_start_crew(state)

static func errors_fuel_uses_config(state: RunState) -> PackedStringArray:
	return _Core.errors_fuel_uses_config(state)

static func audit_after_triplet_end_day(d0: int, f0: float, w0: float, fuel0: float) -> PackedStringArray:
	return _Core.audit_after_triplet_end_day(d0, f0, w0, fuel0)

static func errors_climate_region_mult(state: RunState) -> PackedStringArray:
	return _World.errors_climate_region_mult(state)

static func errors_guarantee_offer(state: RunState) -> PackedStringArray:
	return _World.errors_guarantee_offer(state)

static func audit_tutorial_hang(state: RunState, cars_before: int, parts_before: float) -> PackedStringArray:
	return _World.audit_tutorial_hang(state, cars_before, parts_before)

static func errors_min_power_rule(state: RunState) -> PackedStringArray:
	return _World.errors_min_power_rule(state)

static func errors_abandon_cargo(state: RunState) -> PackedStringArray:
	return _World.errors_abandon_cargo(state)

static func first_member_id(state: RunState, prefer_job: String = "") -> String:
	return _Helpers.first_member_id(state, prefer_job)

static func errors_search_telemetry(state: RunState, telem: Dictionary) -> PackedStringArray:
	return _World.errors_search_telemetry(state, telem)

static func errors_outdoor_day_clock_p0_a(state: RunState, telem: Dictionary) -> PackedStringArray:
	return _Outdoor.errors_outdoor_day_clock_p0_a(state, telem)

static func errors_runtime_day_clock_save_roundtrip(state: RunState) -> PackedStringArray:
	return _Outdoor.errors_runtime_day_clock_save_roundtrip(state)

static func errors_combat_l1(state: RunState) -> PackedStringArray:
	return _World.errors_combat_l1(state)

static func errors_tech_power_lv1(state: RunState) -> PackedStringArray:
	return _World.errors_tech_power_lv1(state)

static func errors_start_precision(state: RunState) -> PackedStringArray:
	return _Core.errors_start_precision(state)

static func errors_member_mood_day_settle(state: RunState) -> PackedStringArray:
	return _Core.errors_member_mood_day_settle(state)

static func errors_region_pick_tundra(state: RunState) -> PackedStringArray:
	return _World.errors_region_pick_tundra(state)

static func errors_event_and_point_encounter(state: RunState) -> PackedStringArray:
	return _Events.errors_event_and_point_encounter(state)

static func errors_event_ops_full(state: RunState) -> PackedStringArray:
	return _Events.errors_event_ops_full(state)

static func errors_event_snapshot_and_load_pending(state: RunState) -> PackedStringArray:
	return _Events.errors_event_snapshot_and_load_pending(state)

static func errors_recruit_morale_save(state: RunState) -> PackedStringArray:
	return _Events.errors_recruit_morale_save(state)