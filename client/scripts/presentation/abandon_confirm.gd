extends PanelContainer
## 遗弃车厢（UI-5）：预览 TrainService 校验结果，确认发 ABANDON_CARRIAGE（至少保留 1 节动力）。

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


## 选中车厢后 TrainService.abandon_preview 显示成本；最后一节 power 按钮 disabled。
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

## 按编组填充可遗弃车厢列表；末节动力灰显。
func _rebuild_list(st: RunState) -> void:
	for c in _list.get_children():
		c.queue_free()
	for car in st.carriages:
		if typeof(car) != TYPE_DICTIONARY:
			continue
		var cid := str(car.get("id", ""))
		var tid := str(car.get("templateId", ""))
		var b := Button.new()
		var tpl := TrainService.template_label(tid)
		var head := LocaleApi.tr_key("abandon.protected_suffix") if TrainService.is_locomotive_protected(st, cid) else ""
		b.toggle_mode = true
		b.button_pressed = cid == st.abandon_selected_car_id
		b.text = LocaleApi.trf("abandon.row", [cid, tpl, head])
		b.disabled = TrainService.is_locomotive_protected(st, cid)
		b.pressed.connect(func() -> void: _select(cid))
		_list.add_child(b)

## 选中车厢 → `SELECT_ABANDON_CARRIAGE`。
func _select(car_id: String) -> void:
	IntentBus.emit_intent("SELECT_ABANDON_CARRIAGE", {"carId": car_id})

## 展示选中节模板、乘员与 `TrainService.can_abandon` 原因码。
func _refresh_detail(st: RunState) -> void:
	var cid := st.abandon_selected_car_id
	if cid == "":
		cid = TrainService.default_abandon_car_id(st)
		IntentBus.emit_intent("SELECT_ABANDON_CARRIAGE", {"carId": cid})
	var prev := TrainService.abandon_preview(st, cid)
	if prev.is_empty():
		_detail.text = LocaleApi.tr_key("abandon.title")
		_btn_confirm.disabled = true
		return
	var reason := str(prev.get("blockReason", ""))
	var tid := str(prev.get("templateId", ""))
	var tpl := TrainService.template_label(tid)
	var parts_cost := float(prev.get("partsCost", 0.0))
	var scrap_gain := int(prev.get("scrapGain", 0))
	var fuel_spent := float(prev.get("fuelSpent", 0.0))
	var day_frac := float(prev.get("dayFraction", -1.0))
	if day_frac < 0.0:
		day_frac = 0.0
	_detail.text = LocaleApi.trf(
		"abandon.detail",
		[cid, tpl, parts_cost, scrap_gain, fuel_spent, day_frac]
	)
	if reason != "":
		_detail.text += LocaleApi.trf("abandon.blocked_suffix", [TrainService.reason_text(reason)])
		_btn_confirm.disabled = true
	else:
		_btn_confirm.disabled = false
	if StationDeferService.tip_for_abandon(st):
		_hint.text = LocaleApi.tr_key("abandon.hint.t11")
	else:
		_hint.text = LocaleApi.tr_key("abandon.hint.default")

## 确认遗弃：`ABANDON_CARRIAGE` intent + 关闭面板。
func _on_confirm() -> void:
	var st := GameSession.state
	if st == null:
		return
	var cid := st.abandon_selected_car_id
	if cid == "":
		return
	IntentBus.emit_intent("ABANDON_CARRIAGE", {"carId": cid})
	IntentBus.emit_intent("CLOSE_ABANDON")

## 取消：不关局，仅 `_close`。
func _on_cancel() -> void:
	IntentBus.emit_intent("CLOSE_ABANDON")

## 隐藏面板，`abandon_panel_open=false`，通知 GameSession 刷新 HUD。
func _close() -> void:
	if visible:
		get_tree().paused = false
	visible = false