class_name IncidentService
extends RefCounted
## 段 incident 弹窗策略（自发路径；与 EventService 互斥，legacy 时本路径不打开）。


static func try_open_pending(state: RunState) -> void:
	if IncidentDirector.use_legacy_event_cards():
		state.incident_modal_open = false
		return
	_open_if_pending(state)


static func sync_after_load(state: RunState) -> void:
	state.incident_modal_open = false
	if IncidentDirector.use_legacy_event_cards():
		return
	if not has_pending_modal(state):
		return
	_open_if_pending(state)


static func has_pending_modal(state: RunState) -> bool:
	if state == null or not state.tutorial_done or state.failed != "":
		return false
	if state.region_run == null:
		return false
	return not IncidentDirector.active_pending_modal(state).is_empty()


static func active_pending(state: RunState) -> Dictionary:
	return IncidentDirector.active_pending_modal(state)


static func type_def(type_id: String) -> Dictionary:
	var root: Variant = ConfigDb.get_table("incidents").get("types", {})
	if typeof(root) != TYPE_DICTIONARY:
		return {}
	var row: Variant = root.get(type_id, null)
	return row if typeof(row) == TYPE_DICTIONARY else {}


static func title_for(type_id: String) -> String:
	var def := type_def(type_id)
	var key := str(def.get("titleKey", "incident.%s.title" % type_id))
	return LocaleApi.tr_key(key)


static func body_for(type_id: String) -> String:
	var def := type_def(type_id)
	var key := str(def.get("bodyKey", "incident.%s.body" % type_id))
	return LocaleApi.tr_key(key)


static func _open_if_pending(state: RunState) -> void:
	if not has_pending_modal(state):
		return
	if state.region_pick_open or state.combat_panel_open or state.event_modal_open:
		return
	state.incident_modal_open = true