extends PanelContainer
## 四线科技升级（停靠时 HUD 打开）：每行显示 Lv、下一级消耗、精度门槛。
## `BUY_UPGRADE` payload: { "line": "power"|"armor"|"radar"|"living" }；错误码 `tech.err.*`。


@onready var _title: Label = $Margin/VBox/Title
@onready var _rows: VBoxContainer = $Margin/VBox/Rows
@onready var _btn_close: Button = $Margin/VBox/BtnClose
func _ready() -> void:
	_btn_close.pressed.connect(_on_close)
	GameSession.state_changed.connect(_sync)
	visible = false
	_sync()

## 打开时从 state 同步四类科技等级与 parts 可读性。
func _sync() -> void:
	var st := GameSession.state
	if st == null or not st.tech_panel_open:
		_close()
		return
	visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_title.text = LocaleApi.trf("tech.title", [st.precision])
	_btn_close.text = LocaleApi.tr_key("ui.btn.close")
	_rebuild_rows(st)

## 按表生成升级行：下一级 cost、是否可点。
func _rebuild_rows(st: RunState) -> void:
	for c in _rows.get_children():
		c.queue_free()
	var lines: Variant = ConfigDb.get_table("upgrades").get("lines", [])
	if typeof(lines) != TYPE_ARRAY:
		return
	for raw in lines:
		var line := str(raw)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lv := TechService.tech_level(st, line)
		var target := lv + 1
		var cost := TechService.level_row(target)
		var need_p := TechService.precision_required(target)
		var lbl := Label.new()
		var cost_txt := ""
		if not cost.is_empty():
			cost_txt = LocaleApi.trf("tech.cost.parts", [target, int(cost.get("parts", 0))])
			var med := int(cost.get("medicine", 0))
			if med > 0:
				cost_txt += LocaleApi.trf("tech.cost.medicine", [med])
			var cat := int(cost.get("catalyst", 0))
			if cat > 0:
				cost_txt += LocaleApi.trf("tech.cost.catalyst", [cat])
			var fuel := float(cost.get("fuel", 0.0))
			if fuel > 0.0:
				cost_txt += LocaleApi.trf("tech.cost.fuel", [fuel])
		lbl.text = LocaleApi.trf(
			"tech.row",
			[TechService.line_label(line), lv, cost_txt, need_p]
		)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = LocaleApi.tr_key("tech.btn.upgrade")
		var captured := line
		btn.disabled = TechService.can_buy(st, line) != ""
		btn.pressed.connect(func() -> void: IntentBus.emit_intent("BUY_UPGRADE", {"line": captured}))
		row.add_child(btn)
		_rows.add_child(row)

## 关闭按钮。
func _on_close() -> void:
	IntentBus.emit_intent("CLOSE_TECH", {})

## `tech_panel_open=false`。
func _close() -> void:
	visible = false
	if get_tree().paused:
		get_tree().paused = false