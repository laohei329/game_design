class_name SearchService
extends RefCounted
## 02 §7 · 04 §5 搜索任务、上限与入库（S1a 薄模型）


const POINT_ZH := {
	"supermarket": "废弃超市",
	"water_plant": "水厂",
	"farm": "农田",
	"gas_station": "加油站",
	"factory": "机械厂",
	"scrapyard": "残骸堆",
}


static func _day_key(state: RunState) -> String:
	return str(state.day_total)


static func can_open_search(state: RunState) -> bool:
	if state.drive_intent != "stop":
		return false
	if state.region_run == null:
		return false
	var seg := state.region_run.active_segment()
	return seg != null and not seg.points.is_empty()


static func find_point(state: RunState, point_id: String) -> Dictionary:
	return LootPileService.find_point(state, point_id)


static func assign_search(state: RunState, point_id: String, member_ids: Array, store: Dictionary) -> String:
	var hit := find_point(state, point_id)
	if hit.is_empty():
		return "no_point"
	var pt: Dictionary = hit.point
	if bool(pt.get("depleted", false)):
		return "depleted"
	if float(pt.get("remainingYield", 0.0)) <= 0.0:
		return "depleted"
	var day := _day_key(state)
	if not store.has(day):
		store[day] = {}
	var day_map: Dictionary = store[day]
	var n: int = int(day_map.get(point_id, 0))
	if n >= SearchRules.cap():
		return "cap_exceeded"
	var ids: Array = []
	for raw in member_ids:
		ids.append(str(raw))
	if not state.members.is_empty():
		var pick_err := MemberPicker.validate_selection(state, ids)
		if pick_err != "":
			return pick_err
	elif ids.is_empty():
		ids = _auto_pick_searchers(state, mini(2, maxi(1, state.onboard_pop)))
	var members := ids.size()
	if members <= 0:
		return "no_members"
	for mid in ids:
		_set_member_task(state, mid, "searching")
	day_map[point_id] = n + 1
	store[day] = day_map
	var hours := SearchRules.hours_per_task()
	state.search_tasks.append(
		{
			"pointId": point_id,
			"assignedDay": state.day_total,
			"memberCount": members,
			"memberIds": ids.duplicate(),
			"hoursTotal": hours,
			"hoursDone": 0.0,
			"complete": false,
		}
	)
	TelemetryService.record(
		"search_assign",
		{
			"dayTotal": state.day_total,
			"pointId": point_id,
			"memberCount": members,
			"searchesOnPointToday": day_map[point_id],
			"cap": SearchRules.cap(),
		}
	)
	return ""


static func recall_search(state: RunState, payload: Dictionary) -> String:
	var point_filter := str(payload.get("pointId", ""))
	var kept: Array = []
	var recalled := 0
	for t in state.search_tasks:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if bool(t.get("complete", false)):
			kept.append(t)
			continue
		if point_filter != "" and str(t.get("pointId", "")) != point_filter:
			kept.append(t)
			continue
		_release_task_members(state, t)
		recalled += 1
	state.search_tasks = kept
	if recalled > 0:
		TelemetryService.record(
			"search_recall",
			{"dayTotal": state.day_total, "pointId": point_filter, "count": recalled}
		)
	return "" if recalled > 0 else "nothing_to_recall"


static func on_end_day(state: RunState) -> void:
	var step := SearchRules.hours_progress_per_day()
	for t in state.search_tasks:
		if typeof(t) != TYPE_DICTIONARY or bool(t.get("complete", false)):
			continue
		t.hoursDone = float(t.get("hoursDone", 0.0)) + step
		if float(t.hoursDone) >= float(t.get("hoursTotal", 1.0)) - 0.001:
			_complete_task(state, t)
			_release_task_members(state, t)
			t.complete = true


static func task_progress(t: Dictionary) -> float:
	if t.is_empty():
		return 0.0
	var total := maxf(0.001, float(t.get("hoursTotal", 1.0)))
	return clampf(float(t.get("hoursDone", 0.0)) / total, 0.0, 1.0)


static func active_tasks_for_point(state: RunState, point_id: String) -> Array:
	var out: Array = []
	for t in state.search_tasks:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if bool(t.get("complete", false)):
			continue
		if str(t.get("pointId", "")) == point_id:
			out.append(t)
	return out


static func _complete_task(state: RunState, task: Dictionary) -> void:
	var point_id := str(task.get("pointId", ""))
	var hit := find_point(state, point_id)
	if hit.is_empty():
		return
	var pt: Dictionary = hit.point
	var type_id := str(pt.get("type", ""))
	var type_row := _point_type_row(type_id)
	var median := float(type_row.get("median", 1.0))
	var remaining := float(pt.get("remainingYield", 0.0))
	var members := int(task.get("memberCount", 1))
	var team_eff := 0.9 + 0.02 * float(members)
	var jitter := 0.55 + RngService.randf() * 0.5
	var take := minf(remaining, median * jitter * team_eff)
	pt.remainingYield = maxf(0.0, remaining - take)
	if pt.remainingYield <= 0.001:
		pt.depleted = true
		pt.remainingYield = 0.0
	var inv_key := str(type_row.get("inventoryPrimary", type_row.get("simYield", "food")))
	HaulService.on_search_loot(state, point_id, inv_key, take)
	TelemetryService.record(
		"search_complete",
		{
			"dayTotal": state.day_total,
			"pointId": point_id,
			"type": type_id,
			"inventoryKey": inv_key,
			"requested": take,
			"toLootPile": take,
			"remainingYield": pt.remainingYield,
		}
	)


static func _point_type_row(type_id: String) -> Dictionary:
	var root: Dictionary = ConfigDb.get_table("point_types")
	var types: Variant = root.get("types", {})
	if typeof(types) == TYPE_DICTIONARY:
		var row: Variant = types.get(type_id, {})
		if typeof(row) == TYPE_DICTIONARY:
			return row
	return {}


static func initial_remaining_yield(type_id: String) -> float:
	var row := _point_type_row(type_id)
	var median := float(row.get("median", 1.0))
	var root: Dictionary = ConfigDb.get_table("point_types")
	var mult := float(root.get("poolMultiplier", 2.5))
	return median * mult


static func _auto_pick_searchers(state: RunState, max_n: int) -> Array:
	var out: Array = []
	if state.members.is_empty():
		return out
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if not _member_available(m):
			continue
		out.append(str(m.get("id", "")))
		if out.size() >= max_n:
			break
	return out


static func _member_available(m: Dictionary) -> bool:
	if float(m.get("hp", 0.0)) <= 30.0:
		return false
	var ts := str(m.get("taskState", "idle"))
	return ts in ["idle", "none"]


static func _set_member_task(state: RunState, member_id: String, task_state: String) -> void:
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("id", "")) == member_id:
			m["taskState"] = task_state
			return


static func _release_task_members(state: RunState, task: Dictionary) -> void:
	var ids: Variant = task.get("memberIds", [])
	if typeof(ids) != TYPE_ARRAY:
		return
	for mid in ids:
		_set_member_task(state, str(mid), "idle")