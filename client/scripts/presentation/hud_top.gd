extends MarginContainer

const SEASON_ZH := {
	"spring": "春",
	"summer": "夏",
	"autumn": "秋",
	"winter": "冬",
}

@onready var _calendar: Label = $VBox/RowCalendar/Calendar
@onready var _food: Label = $VBox/RowResources/Food
@onready var _water: Label = $VBox/RowResources/Water
@onready var _fuel: Label = $VBox/RowResources/Fuel
@onready var _parts: Label = $VBox/RowResources/Parts
@onready var _heating: CheckBox = $VBox/RowActions/Heating
@onready var _btn_end_day: Button = $VBox/RowActions/EndDay
@onready var _btn_fwd: Button = $VBox/RowActions/DriveForward
@onready var _btn_rev: Button = $VBox/RowActions/DriveReverse
@onready var _btn_stop: Button = $VBox/RowActions/DriveStop
@onready var _btn_station: Button = $VBox/RowActions/EnterStation
@onready var _btn_search: Button = $VBox/RowActions/OpenSearch
@onready var _btn_abandon: Button = $VBox/RowActions/OpenAbandon
@onready var _drive: Label = $VBox/RowDrive/DriveStatus


func _ready() -> void:
	_btn_end_day.pressed.connect(_on_end_day)
	_heating.toggled.connect(_on_heating)
	_btn_fwd.pressed.connect(func() -> IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "forward"}))
	_btn_rev.pressed.connect(func() -> IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "reverse"}))
	_btn_stop.pressed.connect(_on_drive_stop)
	_btn_station.pressed.connect(_on_enter_station)
	_btn_search.pressed.connect(_on_open_search)
	_btn_abandon.pressed.connect(_on_open_abandon)
	GameSession.state_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var st := GameSession.state
	if st == null:
		return
	var zh: String = SEASON_ZH.get(st.season, st.season)
	_calendar.text = "%s %d日 Y%d · dayTotal=%d" % [zh, st.day_in_season, st.year, st.day_total]
	_food.text = "粮 %.1f" % st.food
	_water.text = "水 %.1f" % st.water
	_fuel.text = "油 %.1f (%.0f%%)" % [st.fuel, st.fuel_fill() * 100.0]
	_parts.text = "件 %.1f" % st.parts
	_heating.set_block_signals(true)
	_heating.button_pressed = st.heating_enabled
	_heating.set_block_signals(false)
	var cap := DriveService.hours_cap()
	var seg := DriveService.active_segment(st)
	var prog := 0.0
	var seg_len := 0.0
	if seg:
		prog = seg.progress_km
		seg_len = seg.length_km
	var intent_zh: String = {"forward": "前进", "reverse": "返程", "stop": "停靠"}.get(st.drive_intent, st.drive_intent)
	var exhaust := " · 额度用尽" if DriveService.travel_budget_exhausted(st) else ""
	_drive.text = (
		"意图 %s · 前进 %.1f/%.1fh · 返程 %.1fh · %.0f/%.0f km%s"
		% [intent_zh, st.drive_hours_today, cap, st.reverse_hours_today, prog, seg_len, exhaust]
	)
	_btn_station.visible = StationService.can_manual_enter(st)
	_btn_search.visible = SearchService.can_open_search(st)
	_btn_abandon.visible = st.drive_intent == "stop"


func _on_end_day() -> void:
	IntentBus.emit_intent("END_DAY")


func _on_heating(enabled: bool) -> void:
	IntentBus.emit_intent("SET_HEATING", {"enabled": enabled})


func _on_drive_stop() -> void:
	IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "stop"})


func _on_enter_station() -> void:
	IntentBus.emit_intent("ENTER_STATION")


func _on_open_search() -> void:
	IntentBus.emit_intent("OPEN_SEARCH")


func _on_open_abandon() -> void:
	IntentBus.emit_intent("OPEN_ABANDON")