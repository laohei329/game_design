class_name SearchService
extends RefCounted
## 点位搜索任务：点名 → 多日工时 → 产出进 **临时堆**（再由 HaulService 搬上车）。
##
## 同点同日上限：`SearchRules.cap()`，计数存在 GameSession.search_telemetry（非存档）。
## 任务存在 `state.search_tasks[]`；日钟 `tick`（仅停靠）推进工时，`on_end_day` 补差（无头冒烟仍全时推进）。
##
## 完成时：按 `point_types.median` × 队效 × 随机 jitter 扣 `remainingYield`，
## 调 `HaulService.on_search_loot` 写入 `point.lootPile` 并自动排队搬运。

const _GameClock := preload("res://scripts/rhythm/game_clock.gd")
const _PopulationRules := preload("res://scripts/domain/population_rules.gd")


## 点位类型展示名（`search.point.*`；未知 type 回退 id）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param type_id 搜索点类型 id
## @return 空串=成功；非空=机器错误码。
static func point_label(type_id: String) -> String:
	return LocaleApi.tr_code("search.point", type_id, type_id)


## `assign_search` 等返回的机器码 → 本地化短句（Intent / UI warning）。
static func localize_err(code: String) -> String:
	if code.is_empty():
		return ""
	return LocaleApi.tr_code("search.err", code, code)


## search_telemetry 分桶键（按 day_total 字符串）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @return 空串=成功；非空=机器错误码。
static func _day_key(state: RunState) -> String:
	return str(state.day_total)


## 停靠且当前段有点位。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func can_open_search(state: RunState) -> bool:
	if state.drive_intent != "stop":
		return false
	if state.region_run == null:
		return false
	var seg := state.region_run.active_segment()
	return seg != null and not seg.points.is_empty()


## 委托 LootPileService；{ segment, pointIndex, point } 或 {}。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @return 结果字典；缺失语义键时可能为空 {}。
static func find_point(state: RunState, point_id: String) -> Dictionary:
	return LootPileService.find_point(state, point_id)


## 返回空串=成功；否则为机器码（GameSession 转中文）。store 由 GameSession 传入以跨 Intent 持久 cap。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @param member_ids 参与搜索的成员 id 列表
## @param store 搜索遥测分桶（GameSession.search_telemetry）
## @return 空串=成功；非空=机器错误码。
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
	var enc_err: String = PointEncounterService.try_on_search_assign(state, point_id, store)
	if enc_err != "" and enc_err != "must_stop" and enc_err != "outdoor_busy":
		push_warning("point_encounter: " + enc_err)
	return ""


## Intent RECALL_SEARCH；pointId 空=召回全部进行中任务；释放队员 taskState。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param payload Intent 附带的 Dictionary
## @return 空串=成功；非空=机器错误码。
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


## 日钟：停靠时每任务 +`hours_progress_per_day`×day_delta；返回是否有工时推进或任务完成。
##
## @param state 当前局 `RunState`
## @param day_delta 本帧流逝的游戏日比例 0~1
static func tick(state: RunState, day_delta: float) -> bool:
	if not _GameClock.begin_outdoor_work_tick(state, day_delta):
		return false
	return _advance_hours(state, SearchRules.hours_progress_per_day() * day_delta)


## 日界补未走过日钟份额（P0-A，见 `GameClock.outdoor_end_day_reconcile_fraction`）。
static func on_end_day(state: RunState) -> void:
	var step := _GameClock.outdoor_end_day_hours(SearchRules.hours_progress_per_day())
	if step > 0.0001:
		_advance_hours(state, step)


static func _advance_hours(state: RunState, step: float) -> bool:
	if step <= 0.0:
		return false
	var moved := false
	for t in state.search_tasks:
		if typeof(t) != TYPE_DICTIONARY or bool(t.get("complete", false)):
			continue
		t.hoursDone = float(t.get("hoursDone", 0.0)) + step
		moved = true
		if float(t.hoursDone) >= float(t.get("hoursTotal", 1.0)) - 0.001:
			_complete_task(state, t)
			_release_task_members(state, t)
			t.complete = true
	return moved


## UI 进度条：hoursDone / hoursTotal，0~1。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param t 任务字典（搜索/搬运）
## @return 浮点结果（量/比率/工时）。
static func task_progress(t: Dictionary) -> float:
	if t.is_empty():
		return 0.0
	var total := maxf(0.001, float(t.get("hoursTotal", 1.0)))
	return clampf(float(t.get("hoursDone", 0.0)) / total, 0.0, 1.0)


## 某点未完成搜索任务列表（可多任务并发薄支持）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @return 数组结果（列表/选项）。
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


## 从点位池扣 yield → 不到列车库存，先进 lootPile（设计：搜索与搬运分步）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param task search_tasks / haul_tasks 中单条字典
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


## point_types.types 单行：median、inventoryPrimary 等。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param type_id 搜索点类型 id
## @return 结果字典；缺失语义键时可能为空 {}。
static func _point_type_row(type_id: String) -> Dictionary:
	var root: Dictionary = ConfigDb.get_table("point_types")
	var types: Variant = root.get("types", {})
	if typeof(types) == TYPE_DICTIONARY:
		var row: Variant = types.get(type_id, {})
		if typeof(row) == TYPE_DICTIONARY:
			return row
	return {}


## 新建点位：median × poolMultiplier（默认 2.5）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param type_id 搜索点类型 id
## @return 浮点结果（量/比率/工时）。
static func initial_remaining_yield(type_id: String) -> float:
	var row := _point_type_row(type_id)
	var median := float(row.get("median", 1.0))
	var root: Dictionary = ConfigDb.get_table("point_types")
	var mult := float(root.get("poolMultiplier", 2.5))
	return median * mult


## 无 members 点名时回退：按名册顺序取可用队员至多 max_n。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param max_n（int）
## @return 数组结果（列表/选项）。
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


## 改 members[].taskState（searching / idle 等）。
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


## 任务完成或召回：memberIds 全部 idle。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param task search_tasks / haul_tasks 中单条字典
static func _release_task_members(state: RunState, task: Dictionary) -> void:
	var ids: Variant = task.get("memberIds", [])
	if typeof(ids) != TYPE_ARRAY:
		return
	for mid in ids:
		_set_member_task(state, str(mid), "idle")