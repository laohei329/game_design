extends MarginContainer
## 顶栏 HUD：只读 GameSession.state，操作一律 IntentBus（与 GODOT_ARCH 表现层铁律一致）。

@onready var _calendar: Label = $VBox/RowCalendar/Calendar
@onready var _food: Label = $VBox/RowResources/Food
@onready var _water: Label = $VBox/RowResources/Water
@onready var _fuel: Label = $VBox/RowResources/Fuel
@onready var _parts: Label = $VBox/RowResources/Parts
@onready var _heating: CheckBox = $VBox/RowActions/Heating
@onready var _btn_pause: Button = $VBox/RowActions/TimePause
@onready var _btn_speed: Button = $VBox/RowActions/TimeSpeed
@onready var _btn_end_day: Button = $VBox/RowActions/EndDay
@onready var _btn_fwd: Button = $VBox/RowActions/DriveForward
@onready var _btn_rev: Button = $VBox/RowActions/DriveReverse
@onready var _btn_stop: Button = $VBox/RowActions/DriveStop
@onready var _btn_station: Button = $VBox/RowActions/EnterStation
@onready var _btn_search: Button = $VBox/RowActions/OpenSearch
@onready var _btn_abandon: Button = $VBox/RowActions/OpenAbandon
@onready var _btn_tech: Button = $VBox/RowActions/OpenTech
@onready var _btn_combat: Button = $VBox/RowActions/OpenCombat
@onready var _drive: Label = $VBox/RowDrive/DriveStatus
@onready var _crew: Label = $VBox/RowCrew/CrewVitals
func _ready() -> void:
	_btn_pause.pressed.connect(_on_time_pause)
	_btn_speed.pressed.connect(_on_time_speed_cycle)
	_btn_end_day.pressed.connect(_on_end_day)
	_heating.toggled.connect(_on_heating)
	_btn_fwd.pressed.connect(func() -> void: IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "forward"}))
	_btn_rev.pressed.connect(func() -> void: IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "reverse"}))
	_btn_stop.pressed.connect(_on_drive_stop)
	_btn_station.pressed.connect(_on_enter_station)
	_btn_search.pressed.connect(_on_open_search)
	_btn_abandon.pressed.connect(_on_open_abandon)
	_btn_tech.pressed.connect(_on_open_tech)
	_btn_combat.pressed.connect(_on_open_combat)
	GameSession.state_changed.connect(_refresh)
	_refresh()


## 顶栏按钮/供暖文案（`hud.btn.*` · `drive.*`）。
func _apply_action_labels() -> void:
	_btn_fwd.text = LocaleApi.tr_key("drive.forward")
	_btn_rev.text = LocaleApi.tr_key("drive.reverse")
	_btn_stop.text = LocaleApi.tr_key("drive.stop")
	_btn_pause.text = (
		LocaleApi.tr_key("hud.btn.time_resume")
		if GameSession.time_paused
		else LocaleApi.tr_key("hud.btn.time_pause")
	)
	_btn_speed.text = LocaleApi.trf(
		"hud.time.speed",
		[int(GameSession.time_speed)]
	)
	_btn_end_day.text = LocaleApi.tr_key("hud.btn.end_day")
	_heating.text = LocaleApi.tr_key("hud.btn.heating")
	_btn_station.text = LocaleApi.tr_key("hud.btn.enter_station")
	_btn_search.text = LocaleApi.tr_key("hud.btn.search")
	_btn_abandon.text = LocaleApi.tr_key("hud.btn.abandon")
	_btn_tech.text = LocaleApi.tr_key("hud.btn.tech")
	_btn_combat.text = LocaleApi.tr_key("hud.btn.combat_dev")


## 根据停靠/段内点位等条件显隐进站、搜索、遗弃、科技按钮（规则在对应 Service）。
func _refresh() -> void:
	var st := GameSession.state
	if st == null:
		return
	_apply_action_labels()
	var season_lbl := LocaleApi.tr_code("season", st.season, st.season)
	var day_pct := clampf(GameSession.day_clock_fraction * 100.0, 0.0, 99.9)
	_calendar.text = LocaleApi.trf(
		"hud.calendar",
		[season_lbl, st.day_in_season, st.year, st.day_total, day_pct]
	)
	_food.text = LocaleApi.trf("hud.food", [st.food])
	_water.text = LocaleApi.trf("hud.water", [st.water])
	_fuel.text = LocaleApi.trf("hud.fuel", [st.fuel, st.fuel_fill() * 100.0])
	_parts.text = LocaleApi.trf("hud.parts", [st.parts])
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
	var intent_lbl := LocaleApi.tr_code("drive", st.drive_intent, st.drive_intent)
	var exhaust := LocaleApi.tr_key("drive.exhaust_suffix") if DriveService.travel_budget_exhausted(st) else ""
	_drive.text = LocaleApi.trf(
		"hud.drive_status",
		[intent_lbl, st.drive_hours_today, cap, st.reverse_hours_today, prog, seg_len, exhaust]
	)
	if not st.members.is_empty():
		_crew.text = MemberPicker.roster_vitals_line(st)
		_crew.visible = true
	else:
		_crew.visible = false
	_btn_station.visible = StationService.can_manual_enter(st)
	_btn_search.visible = SearchService.can_open_search(st)
	_btn_abandon.visible = st.drive_intent == "stop"
	_btn_tech.visible = st.drive_intent == "stop"
	_btn_combat.visible = st.drive_intent == "stop"

## 手动暂停/继续（01 §2）。
func _on_time_pause() -> void:
	IntentBus.emit_intent("TOGGLE_TIME_PAUSE")


## 倍速 1→2→4 循环。
func _on_time_speed_cycle() -> void:
	var cur := GameSession.time_speed
	var next := 4.0 if cur >= 4.0 - 0.01 else (2.0 if cur >= 2.0 - 0.01 else 1.0)
	IntentBus.emit_intent("SET_TIME_SPEED", {"speed": next})


## 调试：仍保留 Intent，主界面按钮已隐藏。
func _on_end_day() -> void:
	IntentBus.emit_intent("END_DAY")

## HUD 供暖开关 → 对应 drive/heating intent（见 GameSession match）。
func _on_heating(enabled: bool) -> void:
	IntentBus.emit_intent("SET_HEATING", {"enabled": enabled})

## HUD 停靠 → `SET_DRIVE_INTENT` mode stop。
func _on_drive_stop() -> void:
	IntentBus.emit_intent("SET_DRIVE_INTENT", {"mode": "stop"})

## HUD 进站 → `ENTER_STATION`（需已停靠且在站点段）。
func _on_enter_station() -> void:
	IntentBus.emit_intent("ENTER_STATION")

## 打开搜索面板 intent；GameSession 置 `search_panel_open`。
func _on_open_search() -> void:
	IntentBus.emit_intent("OPEN_SEARCH")

## 打开遗弃确认面板。
func _on_open_abandon() -> void:
	IntentBus.emit_intent("OPEN_ABANDON")

## 打开科技面板。
func _on_open_tech() -> void:
	IntentBus.emit_intent("OPEN_TECH")


## 开发验收用：模拟 3 人 L1 遭遇（正式玩法应由事件/压力触发，非 HUD 常驻）。
func _on_open_combat() -> void:
	IntentBus.emit_intent("OPEN_COMBAT", {"enemyCount": 3})
