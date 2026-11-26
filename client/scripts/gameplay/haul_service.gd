class_name HaulService
extends RefCounted
## 04 §5.5 杂工搬运：临时堆 → 列车库存


static func hours_per_task(member: Dictionary) -> float:
	var base := float(ConfigDb.require("balance.haul.hoursPerTask"))
	for s in member.get("specialties", []):
		if str(s) == "haul":
			return base * 0.85
	return base


static func hours_progress_per_day() -> float:
	return float(ConfigDb.require("balance.haul.hoursProgressPerDay"))


static func on_search_loot(state: RunState, point_id: String, inv_key: String, amount: float) -> void:
	LootPileService.add(state, point_id, inv_key, amount)
	enqueue_for_loot(state, point_id, inv_key, amount)


static func enqueue_for_loot(state: RunState, point_id: String, inv_key: String, amount: float) -> String:
	for t in state.haul_tasks:
		if typeof(t) != TYPE_DICTIONARY or bool(t.get("complete", false)):
			continue
		if (
			str(t.get("pointId", "")) == point_id
			and str(t.get("inventoryKey", "")) == InventoryService.normalize_key(inv_key)
		):
			return ""
	var labor_id := _pick_labor(state)
	if labor_id == "":
		return "no_labor"
	var member := _member_by_id(state, labor_id)
	var hours := hours_per_task(member) if not member.is_empty() else float(ConfigDb.require("balance.haul.hoursPerTask"))
	_set_member_task(state, labor_id, "hauling")
	state.haul_tasks.append(
		{
			"pointId": point_id,
			"inventoryKey": InventoryService.normalize_key(inv_key),
			"amountPending": amount,
			"memberId": labor_id,
			"hoursTotal": hours,
			"hoursDone": 0.0,
			"complete": false,
			"auto": true,
		}
	)
	TelemetryService.record(
		"haul_assign",
		{"dayTotal": state.day_total, "pointId": point_id, "key": inv_key, "amount": amount, "memberId": labor_id}
	)
	return ""


static func assign_haul(state: RunState, point_id: String, member_id: String) -> String:
	var hit := LootPileService.find_point(state, point_id)
	if hit.is_empty():
		return "no_point"
	var pt: Dictionary = hit.point
	var pile := LootPileService.pile_dict(pt)
	if pile.is_empty():
		return "empty_pile"
	var labor_id := member_id
	if labor_id == "":
		labor_id = _pick_labor(state)
	if labor_id == "":
		return "no_labor"
	var member := _member_by_id(state, labor_id)
	if str(member.get("job", "")) != "labor":
		return "not_labor"
	if not _member_available(member):
		return "member_busy"
	var key := _largest_pile_key(pile)
	var amount := float(pile.get(key, 0.0))
	if amount <= 0.0:
		return "empty_pile"
	return enqueue_for_loot(state, point_id, key, amount)


static func recall_haul(state: RunState, payload: Dictionary) -> String:
	var point_filter := str(payload.get("pointId", ""))
	var kept: Array = []
	var recalled := 0
	for t in state.haul_tasks:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if bool(t.get("complete", false)):
			kept.append(t)
			continue
		if point_filter != "" and str(t.get("pointId", "")) != point_filter:
			kept.append(t)
			continue
		_release_member(state, str(t.get("memberId", "")))
		recalled += 1
	state.haul_tasks = kept
	if recalled > 0:
		TelemetryService.record("haul_recall", {"dayTotal": state.day_total, "pointId": point_filter, "count": recalled})
	return "" if recalled > 0 else "nothing_to_recall"


static func on_end_day(state: RunState) -> void:
	var step := hours_progress_per_day()
	for t in state.haul_tasks:
		if typeof(t) != TYPE_DICTIONARY or bool(t.get("complete", false)):
			continue
		t.hoursDone = float(t.get("hoursDone", 0.0)) + step
		if float(t.hoursDone) >= float(t.get("hoursTotal", 0.4)) - 0.001:
			_complete_task(state, t)
			_release_member(state, str(t.get("memberId", "")))
			t.complete = true
	_try_enqueue_waiting(state)


static func task_progress(t: Dictionary) -> float:
	var total := maxf(0.001, float(t.get("hoursTotal", 0.4)))
	return clampf(float(t.get("hoursDone", 0.0)) / total, 0.0, 1.0)


static func active_tasks_for_point(state: RunState, point_id: String) -> Array:
	var out: Array = []
	for t in state.haul_tasks:
		if typeof(t) != TYPE_DICTIONARY or bool(t.get("complete", false)):
			continue
		if str(t.get("pointId", "")) == point_id:
			out.append(t)
	return out


static func _complete_task(state: RunState, task: Dictionary) -> void:
	var point_id := str(task.get("pointId", ""))
	var key := str(task.get("inventoryKey", "food"))
	var pending := float(task.get("amountPending", 0.0))
	var from_pile := LootPileService.take(state, point_id, key, pending)
	var added := InventoryService.add(state, key, from_pile)
	TelemetryService.record(
		"haul_complete",
		{
			"dayTotal": state.day_total,
			"pointId": point_id,
			"inventoryKey": key,
			"fromPile": from_pile,
			"added": added,
			"overflowLeftOnPile": pending - from_pile + (from_pile - added),
		}
	)
	var overflow := maxf(0.0, from_pile - added)
	if overflow > 0.001:
		LootPileService.add(state, point_id, key, overflow)


static func _try_enqueue_waiting(state: RunState) -> void:
	if state.region_run == null:
		return
	for seg_var in state.region_run.segments:
		if not (seg_var is Segment):
			continue
		var seg := seg_var as Segment
		for pt in seg.points:
			if typeof(pt) != TYPE_DICTIONARY:
				continue
			var pid := str(pt.get("id", ""))
			var pile := LootPileService.pile_dict(pt)
			for k in pile.keys():
				var amt := float(pile[k])
				if amt > 0.001:
					enqueue_for_loot(state, pid, str(k), amt)


static func _largest_pile_key(pile: Dictionary) -> String:
	var best := ""
	var best_v := 0.0
	for k in pile.keys():
		var v := float(pile[k])
		if v > best_v:
			best_v = v
			best = str(k)
	return best


static func _pick_labor(state: RunState) -> String:
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("job", "")) != "labor":
			continue
		if _member_available(m):
			return str(m.get("id", ""))
	return ""


static func _member_by_id(state: RunState, member_id: String) -> Dictionary:
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("id", "")) == member_id:
			return m
	return {}


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


static func _release_member(state: RunState, member_id: String) -> void:
	if member_id == "":
		return
	_set_member_task(state, member_id, "idle")