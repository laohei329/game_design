extends PanelContainer
## 区域三选一（S1b.2）：`region_pick_open` 时暂停游戏；选项来自 `state.region_pick_options`。
## 点「确认」→ PICK_REGION；不可关闭面板逃避选择（设计：必须三选一）。

@onready var _title: Label = $Margin/VBox/Title
@onready var _choices: HBoxContainer = $Margin/VBox/Choices
func _ready() -> void:
	GameSession.state_changed.connect(_sync)
	visible = false
	_sync()

## `region_pick_open` 时从 state 刷新标题与选项可见性。
func _sync() -> void:
	var st := GameSession.state
	if st == null or not st.region_pick_open:
		_close()
		return
	visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_title.text = LocaleApi.tr_key("region.pick.title")
	_rebuild_choices(st)

## 根据 `region_pick_options` 动态实例化三选一按钮与文案键。
func _rebuild_choices(st: RunState) -> void:
	for c in _choices.get_children():
		c.queue_free()
	for rid in st.region_pick_options:
		var region_id := str(rid)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 6)
		var name_lbl := Label.new()
		name_lbl.text = RegionService.region_display_name(region_id)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_lbl)
		for line in RegionService.region_pick_clues(region_id):
			var hint := Label.new()
			hint.text = line
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
			col.add_child(hint)
		var row := RegionService.region_def(region_id)
		var mult := float(row.get("regionFuelMult", 1.0))
		if mult > 1.01:
			var fuel_lbl := Label.new()
			fuel_lbl.text = LocaleApi.trf("region.pick.fuel_mult", [mult])
			fuel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(fuel_lbl)
		var btn := Button.new()
		btn.text = LocaleApi.tr_key("region.pick.confirm")
		var captured := region_id
		btn.pressed.connect(func() -> void: IntentBus.emit_intent("PICK_REGION", {"regionId": captured}))
		col.add_child(btn)
		_choices.add_child(col)

## 关闭三选一：`region_pick_open=false` 并清空 options。
func _close() -> void:
	visible = false
	if get_tree().paused:
		get_tree().paused = false