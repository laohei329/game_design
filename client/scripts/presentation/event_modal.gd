extends PanelContainer
## 段事件弹窗（S2）：壳标题 `event.modal.*` + 卡内 title/body/options（EventCatalog）。


@onready var _title: Label = $Margin/VBox/Title
@onready var _body: Label = $Margin/VBox/Body
@onready var _choices: VBoxContainer = $Margin/VBox/Choices
func _ready() -> void:
	GameSession.state_changed.connect(_sync)
	visible = false
	_sync()


## `event_modal_open` 时暂停；标题 = 区段事件 + 卡标题。
func _sync() -> void:
	var st := GameSession.state
	if st == null or not st.event_modal_open or st.combat_panel_open:
		_close()
		return
	var card := EventService.active_card(st)
	if card.is_empty():
		_close()
		return
	visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	var card_title := LocaleApi.from_locale_block(card.get("title", {}), str(card.get("id", "")))
	var chrome := LocaleApi.tr_key("event.modal.chrome")
	_title.text = LocaleApi.trf("event.modal.title", [chrome, card_title])
	_body.text = LocaleApi.from_locale_block(card.get("body", {}))
	_rebuild_choices(st, card)


## 选项按钮文案来自卡内 label 多语块。
func _rebuild_choices(st: RunState, card: Dictionary) -> void:
	for c in _choices.get_children():
		c.queue_free()
	var seg := st.region_run.active_segment() if st.region_run else null
	var eid := seg.event_id if seg else ""
	for raw in card.get("options", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var oid := str(raw.get("id", ""))
		if oid.is_empty():
			continue
		var btn := Button.new()
		btn.text = LocaleApi.from_locale_block(raw.get("label", {}), oid)
		btn.pressed.connect(
			func() -> void: IntentBus.emit_intent(
				"CHOOSE_EVENT_OPTION",
				{"eventId": eid, "optionId": oid}
			)
		)
		_choices.add_child(btn)

## 关闭事件弹窗：`event_modal_open=false`；若未结算保留 segment 事件态。
func _close() -> void:
	visible = false
	if get_tree().paused and not _another_modal_needs_pause():
		get_tree().paused = false


## 其它模态仍需要暂停时不恢复 time_scale。
func _another_modal_needs_pause() -> bool:
	var st := GameSession.state
	if st == null:
		return false
	return (
		st.region_pick_open
		or st.combat_panel_open
		or st.event_modal_open
		or st.incident_modal_open
		or st.abandon_panel_open
	)