class_name IncidentDirector
extends RefCounted
## 应力 → incident 类型；替代段级 EventDraw（featureFlags 关闭 legacy 时）。


static func use_legacy_event_cards() -> bool:
	return bool(ConfigDb.require("balance.featureFlags.useLegacyEventCards"))


static func use_incident_director() -> bool:
	return bool(ConfigDb.require("balance.featureFlags.useIncidentDirector"))


## region_service.build_segment 分流入口。
static func on_segment_build(state: RunState, segment: Segment) -> void:
	if use_legacy_event_cards() or not use_incident_director():
		EventDraw.on_segment_build(state, segment)
		return
	if not state.tutorial_done or segment == null:
		return
	_run_hook(state, segment, "onSegmentBuild")


## DaySettle 日结补抽收留（06 §2.2）；legacy 时仍走 MemberRoster.try_day_end_recruit。
static func on_day_end(state: RunState) -> void:
	if use_legacy_event_cards() or not use_incident_director():
		return
	if not state.tutorial_done or state.failed != "":
		return
	var seg := state.region_run.active_segment() if state.region_run else null
	_run_hook(state, seg, "onDayEnd")


static func resolve_action(
	state: RunState,
	incident_uid: String,
	action_id: String
) -> String:
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null:
		return "no_segment"
	var row: Dictionary = {}
	for raw in seg.pending_incidents:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if str(raw.get("uid", "")) == incident_uid:
			row = raw
			break
	if row.is_empty() or bool(row.get("resolved", false)):
		return "already_resolved"
	var type_id := str(row.get("typeId", ""))
	var type_def := _type_def(type_id)
	if type_def.is_empty():
		return "unknown_incident"
	var action: Dictionary = {}
	for raw_a in type_def.get("actions", []):
		if typeof(raw_a) == TYPE_DICTIONARY and str(raw_a.get("id", "")) == action_id:
			action = raw_a
			break
	if action.is_empty():
		return "unknown_action"
	var effects: Array = action.get("effects", [])
	var err := SystemEffects.apply_effects(state, effects, seg, "incident." + type_id, action_id)
	if err != "":
		return err
	row["resolved"] = true
	row["chosenActionId"] = action_id
	state.incident_modal_open = _has_unresolved_modal(seg)
	return ""


static func active_pending_modal(state: RunState) -> Dictionary:
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null:
		return {}
	for raw in seg.pending_incidents:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if bool(raw.get("resolved", false)):
			continue
		var tid := str(raw.get("typeId", ""))
		var def := _type_def(tid)
		if str(def.get("presentation", "")) != "modal":
			continue
		return raw
	return {}


static func _run_hook(state: RunState, segment: Segment, hook: String) -> void:
	var snap := IncidentStress.build_snapshot(state, segment)
	var eligible := _eligible_types(snap, hook)
	if eligible.is_empty():
		return
	var modals: Array = []
	for row in eligible:
		var pres := str(row.get("presentation", "silent"))
		if pres == "silent":
			if _silent_should_fire(row):
				_fire_silent(state, segment, row, state.day_total)
		elif pres == "modal":
			modals.append(row)
	if modals.is_empty():
		return
	var picked: Dictionary = _pick_weighted(modals, snap)
	if picked.is_empty():
		return
	var type_id := str(picked.get("_typeId", ""))
	var entry := _make_pending_entry(type_id, picked, state.day_total)
	if segment != null:
		segment.pending_incidents.append(entry)
		IncidentService.try_open_pending(state)


static func _silent_should_fire(row: Dictionary) -> bool:
	var chance := float(row.get("weightBase", 1.0))
	if chance >= 1.0:
		return true
	return RngService.randf() < chance


static func _fire_silent(state: RunState, segment: Segment, row: Dictionary, day: int) -> void:
	var type_id := str(row.get("_typeId", ""))
	var effects: Array = row.get("effects", [])
	var seg := segment
	if seg == null and state.region_run:
		seg = state.region_run.active_segment()
	var entry := _make_pending_entry(type_id, row, day)
	if seg != null:
		var src := "incident." + type_id
		var err := SystemEffects.apply_effects(state, effects, seg, src, "auto")
		if err != "":
			push_warning("IncidentDirector silent %s: %s" % [type_id, err])
		entry["resolved"] = true
		seg.pending_incidents.append(entry)
	elif not effects.is_empty():
		push_warning("IncidentDirector silent %s: no segment" % type_id)


static func _has_unresolved_modal(seg: Segment) -> bool:
	for raw in seg.pending_incidents:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if bool(raw.get("resolved", false)):
			continue
		var def := _type_def(str(raw.get("typeId", "")))
		if str(def.get("presentation", "")) == "modal":
			return true
	return false


static func _types_root() -> Dictionary:
	var raw: Variant = ConfigDb.get_table("incidents").get("types", {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


static func _type_def(type_id: String) -> Dictionary:
	var row: Variant = _types_root().get(type_id, null)
	return row if typeof(row) == TYPE_DICTIONARY else {}


static func _eligible_types(snap: Dictionary, hook: String) -> Array:
	var out: Array = []
	for tid in _types_root().keys():
		var row: Dictionary = _types_root()[tid]
		if str(row.get("hook", "")) != hook:
			continue
		if not _triggers_pass(row, snap):
			continue
		var copy := row.duplicate(true)
		copy["_typeId"] = str(tid)
		out.append(copy)
	return out


static func _triggers_pass(row: Dictionary, snap: Dictionary) -> bool:
	var any_list: Variant = row.get("triggersAny", [])
	if typeof(any_list) == TYPE_ARRAY and any_list.size() > 0:
		for pid in any_list:
			if IncidentStress.predicate_met(str(pid), snap):
				return true
		return false
	var all_list: Variant = row.get("triggersAll", [])
	if typeof(all_list) == TYPE_ARRAY and all_list.size() > 0:
		for pid2 in all_list:
			if not IncidentStress.predicate_met(str(pid2), snap):
				return false
		return true
	return true


static func _pick_weighted(pool: Array, snap: Dictionary) -> Dictionary:
	if pool.is_empty():
		return {}
	var weights := {}
	var total := 0.0
	var rate := float(snap.get("scenario_event_rate", 1.0))
	for row in pool:
		var w := float(row.get("weightBase", 1.0)) * rate
		if w > 0.0:
			var tid := str(row.get("_typeId", ""))
			weights[tid] = w
			total += w
	if total <= 0.0:
		return {}
	var pick := RngService.randf() * total
	var acc := 0.0
	for tid in weights.keys():
		acc += float(weights[tid])
		if pick <= acc:
			for row in pool:
				if str(row.get("_typeId", "")) == tid:
					return row
			break
	return pool[0] if pool.size() > 0 else {}


static func _make_pending_entry(type_id: String, type_def: Dictionary, day: int) -> Dictionary:
	return {
		"uid": "inc_%d_%d" % [day, RngService.randi() % 100000],
		"typeId": type_id,
		"createdDayTotal": day,
		"resolved": false,
		"chosenActionId": "",
		"tags": type_def.get("tags", []),
	}