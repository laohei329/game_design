extends CanvasLayer
## F3 调试层：气候倍率、区段/天气、存读档与 dev regionFuelMult（仅开发验收，非玩家向 UI）。

@onready var _panel: PanelContainer = $Panel
@onready var _body: Label = $Panel/Margin/VBox/Body
@onready var _btn_save: Button = $Panel/Margin/VBox/DevRow/DevSave
@onready var _btn_load: Button = $Panel/Margin/VBox/DevRow/DevLoad
@onready var _btn_mult: Button = $Panel/Margin/VBox/DevRegionMult
func _ready() -> void:
	visible = false
	_btn_save.pressed.connect(func() -> void: IntentBus.emit_intent("SAVE_GAME", {"slot": 0}))
	_btn_load.pressed.connect(func() -> void: IntentBus.emit_intent("LOAD_GAME", {"slot": 0}))
	_btn_mult.pressed.connect(_on_dev_region_mult)
	GameSession.state_changed.connect(_refresh)
	_refresh()

## 切换 F3 调试 Overlay 显示。
func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()

## F3 Overlay：从 `GameSession.state` 拉取日历/段/资源一行行文本。
func _refresh() -> void:
	var st := GameSession.state
	if st == null:
		_body.text = LocaleApi.tr_key("debug.no_state")
		return
	_body.text = (
		"configVersion=%d\n"
		% ConfigDb.config_version()
		+ "season=%s eff_temp=%.2f cold=%.2f\n"
		% [st.season, st.effective_temp, st.cold_index]
		+ "foodClimate=%.2f waterClimate=%.2f fuelClimate=%.2f\n"
		% [st.food_climate, st.water_climate, st.fuel_climate]
		+ "greenhouseClimate=%.2f speedClimate=%.2f\n"
		% [st.greenhouse_climate, st.speed_climate]
		+ "regionFuelMult=%.2f regionTempMod=%.2f weatherId=%s\n"
		% [st.region_fuel_mult_active(), st.region_temp_mod, st.weather_id]
		+ _region_run_lines(st)
		+ "food=%.1f cap=%.0f water=%.1f cap=%.0f\n"
		% [st.food, InventoryService.stock_cap(st, "food"), st.water, InventoryService.stock_cap(st, "water")]
		+ "lootPiles=%d searchTasks=%d haulTasks=%d\n"
		% [LootPileService.export_piles(st).size(), st.search_tasks.size(), st.haul_tasks.size()]
		+ "beds=%d onboard=%d scrap=%.1f\n"
		% [TrainService.bed_count(st), TrainService.onboard_count(st), st.scrap]
		+ _soft_lock_block(st)
		+ "tech pwr=%d arm=%d rad=%d liv=%d vision=%d\n"
		% [st.power_tech, st.armor_tech, st.radar_tech, st.living_tech, TechService.effective_vision(st)]
		+ "guaranteeFailStreak=%d cars=%d precision=%.0f moraleOff=%.0f\n"
		% [st.guarantee_fail_streak, st.car_count(), st.precision, st.morale_offset]
		+ "pressure=%s hist=%s\n"
		% [st.pressure_display, str(st.pressure_history)]
		+ "foodZeroStreak=%d waterZeroStreak=%d fuelZeroStreak=%d"
		% [st.food_zero_streak, st.water_zero_streak, st.fuel_zero_streak]
	)


## 内嵌 §12.7 探针结果，供编辑器 F3 肉眼签 S1a.7。
func _soft_lock_block(st: RunState) -> String:
	var rep: Dictionary = SoftLockProbe.audit(st)
	var lines: Variant = rep.get("lines", [])
	if typeof(lines) != TYPE_ARRAY:
		return ""
	var out := "§12.7:\n"
	for line in lines:
		out += str(line) + "\n"
	if bool(rep.get("ok", false)):
		out += "probe=PASS\n"
	else:
		out += "probe=CHECK\n"
	return out

## 格式化 `region_run` 段 id、weather、event 态为多行调试字串。
func _region_run_lines(st: RunState) -> String:
	if st.region_run == null:
		return "\nregionRun=(none)"
	var rr: RegionRun = st.region_run
	var seg := rr.active_segment()
	var extra := ""
	if seg:
		extra = " len=%.0f prog=%.1f wx=%s pts=%d st=%d" % [
			seg.length_km,
			seg.progress_km,
			seg.weather_id,
			seg.points.size(),
			seg.stations.size(),
		]
	return "\nregionRun=%s seg %d/%d%s" % [rr.region_id, rr.segment_index + 1, rr.segment_count, extra]


## S0.5 验收：1.0 ↔ 1.3 切换 regionFuelMult，验证 fuelClimate 非硬编码。
func _on_dev_region_mult() -> void:
	IntentBus.emit_intent("DEV_TOGGLE_REGION_FUEL", {})