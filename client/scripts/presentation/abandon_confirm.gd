extends PanelContainer

@onready var _list: VBoxContainer = $Margin/VBox/CarList
@onready var _detail: Label = $Margin/VBox/Detail
@onready var _hint: Label = $Margin/VBox/Hint
@onready var _btn_confirm: Button = $Margin/VBox/Row/Confirm
@onready var _btn_cancel: Button = $Margin/VBox/Row/Cancel


func _ready() -> void:
	_btn_confirm.pressed.connect(_on_confirm)
	_btn_cancel.pressed.connect(_on_cancel)
	GameSession.state_changed.connect(_sync)
	visible = false
	_sync()


func _sync() -> void:
	var st := GameSession.state
	if st == null or not st.abandon_panel_open:
		_close()
		return
	visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rebuild_list(st)
	_refresh_detail(st)


func _rebuild_list(st: RunState) -> void:
	for c in _list.get_children():
		c.queue_free()
	for car in st.carriages:
		if typeof(car) != TYPE_DICTIONARY:
			continue
		var cid := str(car.get("id", ""))
		var tid := str(car.get("templateId", ""))
		var b := Button.new()
		var zh: String = TrainService.TEMPLATE_ZH.get(tid, tid)
		b.toggle_mode = true
		b.button_pressed = cid == st.abandon_selected_car_id
		b.text = "%s · %s" % [cid, zh]
		b.pressed.connect(func() -> void: _select(cid))
		_list.add_child(b)


func _select(car_id: String) -> void:
	var st := GameSession.state
	if st == null:
		return
	st.abandon_selected_car_id = car_id
	GameSession.state_changed.emit()


func _refresh_detail(st: RunState) -> void:
	var cid := st.abandon_selected_car_id
	if cid == "" and not st.carriages.is_empty():
		var car0: Dictionary = st.carriages[0]
		cid = str(car0.get("id", ""))
		st.abandon_selected_car_id = cid
	var prev := TrainService.abandon_preview(st, cid)
	if prev.is_empty():
		_detail.text = "选择要遗弃的车厢"
		_btn_confirm.disabled = true
		return
	var reason := str(prev.get("blockReason", ""))
	var tid := str(prev.get("templateId", ""))
	var zh: String = TrainService.TEMPLATE_ZH.get(tid, tid)
	_detail.text = (
		"%s（%s）\n"
		+ "消耗 零件 %.0f · 返废料 %d · 扣油 %.1f\n"
		+ "占用行驶额度 %.1f 日"
		% [
			cid,
			zh,
			float(prev.partsCost),
			int(prev.scrapGain),
			float(prev.fuelSpent),
			TrainService.ABANDON_DAY_FRACTION,
		]
	)
	if reason != "":
		_detail.text += "\n不可遗弃：%s" % TrainService.reason_text(reason)
		_btn_confirm.disabled = true
	else:
		_btn_confirm.disabled = false
	if StationDeferService.tip_for_abandon(st):
		_hint.text = "提示：油紧时可考虑甩节减负（T11）"
	else:
		_hint.text = "须停靠；完成后扣当日 0.5 行驶额度"


func _on_confirm() -> void:
	var st := GameSession.state
	if st == null:
		return
	var cid := st.abandon_selected_car_id
	if cid == "":
		return
	IntentBus.emit_intent("ABANDON_CARRIAGE", {"carId": cid})
	IntentBus.emit_intent("CLOSE_ABANDON")


func _on_cancel() -> void:
	IntentBus.emit_intent("CLOSE_ABANDON")


func _close() -> void:
	if visible:
		get_tree().paused = false
	visible = false