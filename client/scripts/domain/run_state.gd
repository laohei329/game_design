class_name RunState
extends RefCounted
## Minimal S1a state (GODOT_ARCH §3); expand toward 09 §3.

var year: int = 1
var season: String = "spring"
var day_in_season: int = 1
var day_total: int = 1

var parts: float = 6.0
var scrap: float = 0.0
var fuel: float = 88.0
var food: float = 20.0
var water: float = 24.0
var medicine: float = 4.0
var seed: float = 1.0
var chem: float = 0.0
var cloth: float = 0.0
var drive_intent: String = "stop"  # forward | reverse | stop（03 §6.2）
var heating_enabled: bool = false
var body_hp: float = 100.0
var carriages: Array = []
var abandon_count: int = 0
var power_tech: int = 0
var prefer_expansion: bool = true

var drive_hours_today: float = 0.0
var reverse_hours_today: float = 0.0
var onboard_pop: int = 4
var members: Array = []
var haul_tasks: Array = []  # 杂工搬运单（S1a 薄）

var food_went_zero: bool = false
var water_went_zero: bool = false
var food_zero_streak: int = 0
var water_zero_streak: int = 0
var fuel_zero_streak: int = 0
var breakdown_counter: int = 0

var weather_id: String = "clear"
var region_fuel_mult: float = 1.0
var region_temp_mod: float = 0.0
var climate_influences: Array = []
var delayed_events: Array = []

var effective_temp: float = 0.0
var cold_index: float = 0.0
var heat_index: float = 0.0
var food_climate: float = 1.0
var water_climate: float = 1.0
var fuel_climate: float = 1.0
var greenhouse_climate: float = 1.0
var speed_climate: float = 1.0
var heating_applied_today: bool = false

var failed: String = ""

var region_run: RegionRun = null
var guarantee_fail_streak: int = 0
var tutorial_done: bool = false
var pending_station: Dictionary = {}  # UI-3 进站面板上下文（非存档主干 S1b 前）
var search_tasks: Array = []
var search_panel_open: bool = false
var abandon_panel_open: bool = false
var abandon_selected_car_id: String = ""

func fuel_cap() -> float:
	var cap := 60.0
	for c in carriages:
		if c.get("templateId", "") == "cargo":
			cap += float(c.get("size", 1)) * 10.0
	return cap

func fuel_fill() -> float:
	var cap := fuel_cap()
	if cap <= 0.0:
		return 0.0
	return fuel / cap

func car_count() -> int:
	return carriages.size()

func to_dict() -> Dictionary:
	return SaveSchema.to_save_dict(self)