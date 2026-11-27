extends PanelContainer
## 段 incident 弹窗：文案来自 `incidents.json` + `ui.csv` `incident.*` 键。


@onready var _title: Label = $Margin/VBox/Title
@onready var _body: Label = $Margin/VBox/Body
@onready var _choices: VBoxContainer = $Margin/VBox/Choices


func _ready() -> void:
	GameSession.state_changed.connect(_sync)
	visible = false
	_sync()


func _sync() -> void:
	var st := GameSession.state
	if st == null or not st.incident_modal_open or st.combat_panel_open or st.event_modal_open:
		_close()
		return
	var pending := IncidentService.active_pending(st)
	if pending.is_empty():
		_close()
		return
	visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	var type_id := str(pending.get("typeId", ""))
	var chrome := LocaleApi.tr_key("incident.modal.chrome")
	var title := IncidentService.title_for(type_id)
	_title.text = LocaleApi.trf("incident.modal.title", [chrome, title])
	_body.text = IncidentService.body_for(type_id)
	_rebuild_choices(st, pending, type_id)


func _rebuild_choices(st: RunState, pending: Dictionary, type_id: String) -> void:
	for c in _choices.get_children():
		c.queue_free()
	var def := IncidentService.type_def(type_id)
	for raw in def.get("actions", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var aid := str(raw.get("id", ""))
		if aid.is_empty():
			continue
		var btn := Button.new()
		var lk := str(raw.get("labelKey", "incident.%s.action.%s" % [type_id, aid]))
		btn.text = LocaleApi.tr_key(lk)
		var uid := str(pending.get("uid", ""))
		btn.pressed.connect(
			func() -> void:
				IntentBus.emit_intent("RESOLVE_INCIDENT", {"incidentUid": uid, "actionId": aid})
		)
		_choices.add_child(btn)


func _close() -> void:
	visible = false
	if get_tree().paused and not _another_modal_needs_pause():
		get_tree().paused = false


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