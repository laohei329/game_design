class_name LootPileService
extends RefCounted
## 每个搜索点位 `points[].lootPile` 上的待搬物资（Dict: inventoryKey → amount）。
##
## 与「列车库存」分离：离段/离跨度不删堆（设计 04 §5.4）；存档用 `world.lootPiles[]` 扁平列表
## export/apply，读档后 `_ensure_points_loot_on_segments` 会补空字典。


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
	var hit := find_point(state, point_id)
	if hit.is_empty():
		return 0.0
	var pt: Dictionary = hit.point
	var key := InventoryService.normalize_key(inv_key)
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
					out.append({"pointId": pid, "inventoryKey": str(k), "amount": amt})
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