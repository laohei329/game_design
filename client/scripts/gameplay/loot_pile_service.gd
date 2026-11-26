class_name LootPileService
extends RefCounted
## 02 §7 · 04 §5.4 点位临时堆（挂在 Segment.points[]）


static func find_point(state: RunState, point_id: String) -> Dictionary:
	if state.region_run == null:
		return {}
	for seg_var in state.region_run.segments:
		if not (seg_var is Segment):
			continue
		var seg := seg_var as Segment
		for i in seg.points.size():
			var pt: Dictionary = seg.points[i]
			if str(pt.get("id", "")) == point_id:
				return {"segment": seg, "pointIndex": i, "point": pt}
	return {}


static func pile_dict(pt: Dictionary) -> Dictionary:
	var pile: Variant = pt.get("lootPile", {})
	if typeof(pile) != TYPE_DICTIONARY:
		pt.lootPile = {}
		return pt.lootPile
	return pile


static func total_amount(pt: Dictionary) -> float:
	var pile := pile_dict(pt)
	var sum := 0.0
	for k in pile.keys():
		sum += maxf(0.0, float(pile[k]))
	return sum


static func add(state: RunState, point_id: String, inv_key: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var hit := find_point(state, point_id)
	if hit.is_empty():
		return 0.0
	var pt: Dictionary = hit.point
	var key := InventoryService.normalize_key(inv_key)
	var pile := pile_dict(pt)
	pile[key] = float(pile.get(key, 0.0)) + amount
	return amount


static func take(state: RunState, point_id: String, inv_key: String, amount: float) -> float:
	var hit := find_point(state, point_id)
	if hit.is_empty():
		return 0.0
	var pt: Dictionary = hit.point
	var key := InventoryService.normalize_key(inv_key)
	var pile := pile_dict(pt)
	var have := float(pile.get(key, 0.0))
	var moved := minf(have, amount)
	pile[key] = maxf(0.0, have - moved)
	if pile[key] <= 0.001:
		pile.erase(key)
	return moved


static func export_piles(state: RunState) -> Array:
	var out: Array = []
	if state.region_run == null:
		return out
	for seg_var in state.region_run.segments:
		if not (seg_var is Segment):
			continue
		var seg := seg_var as Segment
		for pt in seg.points:
			if typeof(pt) != TYPE_DICTIONARY:
				continue
			var pid := str(pt.get("id", ""))
			var pile := pile_dict(pt)
			for k in pile.keys():
				var amt := float(pile[k])
				if amt > 0.001:
					out.append({"pointId": pid, "inventoryKey": str(k), "amount": amt})
	return out


static func apply_world_list(state: RunState, piles: Array) -> void:
	if typeof(piles) != TYPE_ARRAY or piles.is_empty():
		return
	_clear_all_piles(state)
	for row in piles:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pid := str(row.get("pointId", ""))
		var key := str(row.get("inventoryKey", row.get("key", "food")))
		var amt := float(row.get("amount", 0.0))
		if pid == "" or amt <= 0.0:
			continue
		add(state, pid, key, amt)


static func _clear_all_piles(state: RunState) -> void:
	if state.region_run == null:
		return
	for seg_var in state.region_run.segments:
		if not (seg_var is Segment):
			continue
		var seg := seg_var as Segment
		for i in seg.points.size():
			var pt: Dictionary = seg.points[i]
			if typeof(pt) == TYPE_DICTIONARY:
				pt.lootPile = {}
				seg.points[i] = pt


static func summary_text(pt: Dictionary) -> String:
	var pile := pile_dict(pt)
	if pile.is_empty():
		return "临时堆空"
	var bits: PackedStringArray = []
	for k in pile.keys():
		bits.append("%s %.1f" % [k, float(pile[k])])
	return "待搬 " + ", ".join(bits)