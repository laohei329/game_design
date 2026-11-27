class_name LootPileService
extends RefCounted
## 每个搜索点位 `points[].lootPile` 上的待搬物资（Dict: inventoryKey → amount）。
##
## 与「列车库存」分离：离段/离跨度不删堆（设计 04 §5.4）；存档用 `world.lootPiles[]` 扁平列表
## export/apply，读档后 `_ensure_points_loot_on_segments` 会补空字典。
## 离跨度未匹配点位的物资在 `orphan_loot_piles`，`pointId` 前缀 `orphan:`，杂工可照常搬运。

const ORPHAN_POINT_PREFIX := "orphan:"


static func _norm_inv_key(key: String) -> String:
	var k := str(key).to_lower()
	if k == "med":
		return "medicine"
	return k


static func is_orphan_point_id(point_id: String) -> bool:
	return str(point_id).begins_with(ORPHAN_POINT_PREFIX)


static func to_orphan_point_id(original_id: String) -> String:
	var oid := str(original_id)
	if is_orphan_point_id(oid):
		return oid
	return ORPHAN_POINT_PREFIX + oid


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
	if is_orphan_point_id(point_id):
		var pile := _orphan_pile_aggregate(state, point_id)
		if pile.is_empty():
			return {}
		return {"point": {"id": point_id, "lootPile": pile}, "orphan": true}
	return {}


static func _orphan_pile_aggregate(state: RunState, point_id: String) -> Dictionary:
	var pile: Dictionary = {}
	for row in state.orphan_loot_piles:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("pointId", "")) != point_id:
			continue
		var key := _norm_inv_key(str(row.get("inventoryKey", row.get("key", "food"))))
		pile[key] = float(pile.get(key, 0.0)) + float(row.get("amount", 0.0))
	return pile


## 确保 pt.lootPile 为字典并返回引用（可原地 +=）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param pt 点位字典 points[] 元素
## @return 结果字典；缺失语义键时可能为空 {}。
static func pile_dict(pt: Dictionary) -> Dictionary:
	var pile: Variant = pt.get("lootPile", {})
	if typeof(pile) != TYPE_DICTIONARY:
		pt.lootPile = {}
		return pt.lootPile
	return pile

## 点位 lootPile 各键数量之和。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param pt 点位字典 points[] 元素
## @return 浮点结果（量/比率/工时）。
static func total_amount(pt: Dictionary) -> float:
	var pile := pile_dict(pt)
	var sum := 0.0
	for k in pile.keys():
		sum += maxf(0.0, float(pile[k]))
	return sum


## 堆内累加；键经 normalize_key；返回实增量。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @param inv_key inventory 键（food/water/…）
## @param amount 数量（float，可为小数）
## @return 浮点结果（量/比率/工时）。
static func add(state: RunState, point_id: String, inv_key: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	if is_orphan_point_id(point_id):
		var key := _norm_inv_key(inv_key)
		for row in state.orphan_loot_piles:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			if str(row.get("pointId", "")) == point_id and _norm_inv_key(
					str(row.get("inventoryKey", row.get("key", "food")))
				) == key:
				row["amount"] = float(row.get("amount", 0.0)) + amount
				return amount
		state.orphan_loot_piles.append(
			{"pointId": point_id, "inventoryKey": key, "amount": amount}
		)
		return amount
	var hit := find_point(state, point_id)
	if hit.is_empty():
		return 0.0
	var pt: Dictionary = hit.point
	var key := _norm_inv_key(inv_key)
	var pile := pile_dict(pt)
	pile[key] = float(pile.get(key, 0.0)) + amount
	return amount


## 从堆扣减，返回实际取出量；0 量键 erase。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @param inv_key inventory 键（food/water/…）
## @param amount 数量（float，可为小数）
## @return 浮点结果（量/比率/工时）。
static func take(state: RunState, point_id: String, inv_key: String, amount: float) -> float:
	if is_orphan_point_id(point_id):
		return _take_orphan_row(state, point_id, inv_key, amount)
	var hit := find_point(state, point_id)
	if hit.is_empty():
		return 0.0
	var pt: Dictionary = hit.point
	var key := _norm_inv_key(inv_key)
	var pile := pile_dict(pt)
	var have := float(pile.get(key, 0.0))
	var moved := minf(have, amount)
	pile[key] = maxf(0.0, have - moved)
	if pile[key] <= 0.001:
		pile.erase(key)
	return moved


static func _take_orphan_row(state: RunState, point_id: String, inv_key: String, amount: float) -> float:
	var key := _norm_inv_key(inv_key)
	var moved := 0.0
	var kept: Array = []
	for row in state.orphan_loot_piles:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("pointId", "")) != point_id:
			kept.append(row)
			continue
		var rk := _norm_inv_key(str(row.get("inventoryKey", row.get("key", "food"))))
		if rk != key:
			kept.append(row)
			continue
		var have := float(row.get("amount", 0.0))
		var take_amt := minf(have, amount - moved)
		if take_amt <= 0.001:
			kept.append(row)
			continue
		moved += take_amt
		var left := have - take_amt
		if left > 0.001:
			row = row.duplicate(true)
			row["amount"] = left
			kept.append(row)
	state.orphan_loot_piles = kept
	return moved


## 存档：`[{pointId, inventoryKey, amount}, …]` 展开所有段内非空堆。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 数组结果（列表/选项）。
## 换跨度前：把当前段内堆并入 `orphan_loot_piles`（不丢货）。
static func archive_piles_before_new_run(state: RunState) -> void:
	var rows := export_piles(state)
	if rows.is_empty():
		return
	state.orphan_loot_piles.append_array(rows)
	_clear_all_piles(state)


## 新跨度段建成后：把 orphan 里能 `find_point` 的行灌回点位堆。
static func apply_orphan_piles(state: RunState) -> void:
	if state.orphan_loot_piles.is_empty():
		return
	var kept: Array = []
	for row in state.orphan_loot_piles:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pid := str(row.get("pointId", ""))
		var key := str(row.get("inventoryKey", row.get("key", "food")))
		var amt := float(row.get("amount", 0.0))
		if pid == "" or amt <= 0.001:
			continue
		if not is_orphan_point_id(pid) and find_point(state, pid).is_empty():
			pid = to_orphan_point_id(pid)
			row = row.duplicate(true)
			row["pointId"] = pid
		if find_point(state, pid).is_empty():
			kept.append(row)
		else:
			add(state, pid, key, amt)
	state.orphan_loot_piles = kept


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
					out.append({
						"pointId": to_orphan_point_id(pid),
						"inventoryKey": str(k),
						"amount": amt,
					})
	return out


## 读档：先清空段内堆再按列表 add（避免重复叠加）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param piles `world.lootPiles` 扁平行列表
static func apply_world_list(state: RunState, piles: Array) -> void:
	if typeof(piles) != TYPE_ARRAY:
		return
	_clear_all_piles(state)
	if piles.is_empty():
		return
	for row in piles:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var pid := str(row.get("pointId", ""))
		var key := str(row.get("inventoryKey", row.get("key", "food")))
		var amt := float(row.get("amount", 0.0))
		if pid == "" or amt <= 0.0:
			continue
		add(state, pid, key, amt)

## 清空 world 列表导入前：段内全部点 `lootPile` 置空（空数组=清场语义）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
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


## 搜索 UI 一行「待搬 food 3.0, …」。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param pt 点位字典 points[] 元素
## @return 空串=成功；非空=机器错误码。
static func summary_text(pt: Dictionary) -> String:
	var pile := pile_dict(pt)
	if pile.is_empty():
		return LocaleApi.tr_key("loot.pile.empty")
	var bits: PackedStringArray = []
	for k in pile.keys():
		bits.append("%s %.1f" % [k, float(pile[k])])
	return LocaleApi.tr_key("loot.pile.prefix") + ", ".join(bits)