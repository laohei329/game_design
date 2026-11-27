class_name HaulService
extends RefCounted

const _PopulationRules := preload("res://scripts/domain/population_rules.gd")
## 杂工（job=labor）把 `point.lootPile` 物资搬入列车库存（InventoryService.add）。
##
## 搜索完成时 `on_search_loot` / `enqueue_for_loot` 可 **自动** 创建 haul 任务（auto=true）。
## 玩家也可 `assign_haul` 手动指定杂工与点位最大堆。
## 超库存部分：完成任务时退回同点 lootPile（02 §7 临时堆语义）。

const _GameClock := preload("res://scripts/rhythm/game_clock.gd")


static func hours_per_task(member: Dictionary) -> float:
	var base := float(ConfigDb.require("balance.haul.hoursPerTask"))
	var spec_mult := float(ConfigDb.require("balance.haul.haulSpecialtyMult"))
	for s in member.get("specialties", []):
		if str(s) == "haul":
			return base * spec_mult
	return base


## 每日搬运工时总额（×日钟 day_delta 分摊到 `tick`）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @return 浮点结果（量/比率/工时）。
static func hours_progress_per_day() -> float:
	return float(ConfigDb.require("balance.haul.hoursProgressPerDay"))


## 搜索产出的标准出口：先堆后搬，避免瞬间绕过 cap。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @param inv_key inventory 键（food/water/…）
## @param amount 数量（float，可为小数）
static func on_search_loot(state: RunState, point_id: String, inv_key: String, amount: float) -> void:
	LootPileService.add(state, point_id, inv_key, amount)
	enqueue_for_loot(state, point_id, inv_key, amount)


## 创建搬运单；同点同键已有进行中则跳过；无 labor 返回 no_labor。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @param inv_key inventory 键（food/water/…）
## @param amount 数量（float，可为小数）
## @return 空串=成功；非空=机器错误码。
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


## Intent ASSIGN_HAUL；member 空则自动 _pick_labor；搬最大堆单品类。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @param member_id 成员 id
## @return 空串=成功；非空=机器错误码。
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


## Intent RECALL_HAUL；filter 点位或全体进行中搬运。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param payload Intent 附带的 Dictionary
## @return 空串=成功；非空=机器错误码。
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


## 日钟：停靠时推进搬运工时（语义同 SearchService.tick）。
static func tick(state: RunState, day_delta: float) -> bool:
	if not _GameClock.begin_outdoor_work_tick(state, day_delta):
		return false
	return _advance_hours(state, hours_progress_per_day() * day_delta)


## 日界补差 + 扫堆自动 enqueue。
static func on_end_day(state: RunState) -> void:
	var step := _GameClock.outdoor_end_day_hours(hours_progress_per_day())
	if step > 0.0001:
		_advance_hours(state, step)
	_try_enqueue_waiting(state)


static func _advance_hours(state: RunState, step: float) -> bool:
	if step <= 0.0:
		return false
	var moved := false
	for t in state.haul_tasks:
		if typeof(t) != TYPE_DICTIONARY or bool(t.get("complete", false)):
			continue
		t.hoursDone = float(t.get("hoursDone", 0.0)) + step
		moved = true
		if float(t.hoursDone) >= float(t.get("hoursTotal", hours_per_task({}))) - 0.001:
			_complete_task(state, t)
			_release_member(state, str(t.get("memberId", "")))
			t.complete = true
	return moved

## 搬运任务进度 0~1。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param t 任务字典（搜索/搬运）
## @return 浮点结果（量/比率/工时）。
static func task_progress(t: Dictionary) -> float:
	var total := maxf(0.001, float(t.get("hoursTotal", hours_per_task({}))))
	return clampf(float(t.get("hoursDone", 0.0)) / total, 0.0, 1.0)

## 某点未完成 haul 任务列表。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @return 数组结果（列表/选项）。
static func active_tasks_for_point(state: RunState, point_id: String) -> Array:
	var out: Array = []
	for t in state.haul_tasks:
		if typeof(t) != TYPE_DICTIONARY or bool(t.get("complete", false)):
			continue
		if str(t.get("pointId", "")) == point_id:
			out.append(t)
	return out


## 从堆取量 → add 到库存；`added < from_pile` 时差额写回堆（满仓溢出）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param task search_tasks / haul_tasks 中单条字典
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


## 日结末：扫描全场 lootPile，为有货无任务者自动 enqueue。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
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


## 手动搬运会取堆中数量最大的 inventoryKey。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param pile（Dictionary）
## @return 空串=成功；非空=机器错误码。
static func _largest_pile_key(pile: Dictionary) -> String:
	var best := ""
	var best_v := 0.0
	for k in pile.keys():
		var v := float(pile[k])
		if v > best_v:
			best_v = v
			best = str(k)
	return best


## 第一个 job=labor 且空闲的 memberId。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @return 空串=成功；非空=机器错误码。
static func _pick_labor(state: RunState) -> String:
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("job", "")) != "labor":
			continue
		if _member_available(m):
			return str(m.get("id", ""))
	return ""


## 按 id 查 members[] 字典。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param member_id 成员 id
## @return 结果字典；缺失语义键时可能为空 {}。
static func _member_by_id(state: RunState, member_id: String) -> Dictionary:
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("id", "")) == member_id:
			return m
	return {}


## hp>30 且 taskState idle/none。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param m（Dictionary）
## @return 是否成功或条件成立。
static func _member_available(m: Dictionary) -> bool:
	if float(m.get("hp", 0.0)) <= _PopulationRules.injured_hp_threshold():
		return false
	var ts := str(m.get("taskState", "idle"))
	return ts in ["idle", "none"]


## 写入 members[].taskState（hauling 等）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param member_id 成员 id
## @param task_state（String）
static func _set_member_task(state: RunState, member_id: String, task_state: String) -> void:
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("id", "")) == member_id:
			m["taskState"] = task_state
			return


## 搬运结束或召回：member taskState→idle。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param member_id 成员 id
static func _release_member(state: RunState, member_id: String) -> void:
	if member_id == "":
		return
	_set_member_task(state, member_id, "idle")