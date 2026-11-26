extends CanvasLayer

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


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _refresh() -> void:
	var st := GameSession.state
	if st == null:
		_body.text = "no RunState"
		return
	_body.text = (
		"configVersion=%d\n"
		% ConfigDb.config_version
		+ "season=%s eff_temp=%.2f cold=%.2f\n"
		% [st.season, st.effective_temp, st.cold_index]
		+ "foodClimate=%.2f waterClimate=%.2f fuelClimate=%.2f\n"
		% [st.food_climate, st.water_climate, st.fuel_climate]
		+ "greenhouseClimate=%.2f speedClimate=%.2f\n"
		% [st.greenhouse_climate, st.speed_climate]
		+ "regionFuelMult=%.2f regionTempMod=%.2f weatherId=%s\n"
		% [st.region_fuel_mult, st.region_temp_mod, st.weather_id]
		+ _region_run_lines(st)
		+ "food=%.1f cap=%.0f water=%.1f cap=%.0f\n"
		% [st.food, InventoryService.stock_cap(st, "food"), st.water, InventoryService.stock_cap(st, "water")]
		+ "lootPiles=%d searchTasks=%d haulTasks=%d\n"
		% [LootPileService.export_piles(st).size(), st.search_tasks.size(), st.haul_tasks.size()]
		+ "beds=%d onboard=%d scrap=%.1f\n"
		% [TrainService.bed_count(st), TrainService.onboard_count(st), st.scrap]
		+ _soft_lock_block(st)
		+ "guaranteeFailStreak=%d cars=%d\n"
		% [st.guarantee_fail_streak, st.car_count()]
		+ "foodZeroStreak=%d waterZeroStreak=%d fuelZeroStreak=%d"
		% [st.food_zero_streak, st.water_zero_streak, st.fuel_zero_streak]
	)


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


func _on_dev_region_mult() -> void:
	var st := GameSession.state
	if st == null:
		return
	if is_equal_approx(st.region_fuel_mult, 1.3):
		st.region_fuel_mult = 1.0
	else:
		st.region_fuel_mult = 1.3
	ClimateService.recompute(st)
	GameSession.state_changed.emit()