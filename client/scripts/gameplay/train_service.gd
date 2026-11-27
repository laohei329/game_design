class_name TrainService
extends RefCounted
## 列车编组：挂车由 StationService 写入 `carriages[]`；本类负责 **遗弃** 与人口/床位派生。
##
## 遗弃前置（`can_abandon` 返回非空=阻断）：
##   - 须停靠；无进行中搜索/搬运；当日行驶额度还能扣 0.5 日；零件够；
##   - **禁止**扔掉最后一节 `power`；living 遗弃后床位须 ≥ onboard_count；
##   - 乘员在目标车上时自动迁到其它 living 或任意余车（`_relocate_members_off_car`）。
##
## 成功遗弃：扣零件/油、加废料、占用 0.5 行驶日、Telemetry `carriage_abandon`。

const ABANDON_DAY_FRACTION := 0.5

## 车厢模板展示名（`carriage.*`）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param template_id 车厢/威胁模板 id
## @return 空串=成功；非空=机器错误码。
static func template_label(template_id: String) -> String:
	return LocaleApi.tr_code("carriage", template_id, template_id)


## 挂车/遗弃废料折算用零件成本（carriages.repairParts）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param template_id 车厢/威胁模板 id
## @return 整数结果（计数/下标/容量）。
static func repair_cost(template_id: String) -> int:
	var root: Dictionary = ConfigDb.get_table("carriages")
	var rp: Variant = root.get("repairParts", {})
	if typeof(rp) == TYPE_DICTIONARY:
		var v: Variant = rp.get(template_id, rp.get("default", 5))
		return int(v)
	return 5


## 按 carriages[].id 查下标；-1 不存在。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param carriages（Array）
## @param car_id 车厢 `carriages[].id`
## @return 整数结果（计数/下标/容量）。
static func find_carriage_index(carriages: Array, car_id: String) -> int:
	for i in carriages.size():
		if str(carriages[i].get("id", "")) == car_id:
			return i
	return -1


## living.size×2 求和 + living_tech×2（生活科技床位）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 整数结果（计数/下标/容量）。
static func bed_count(state: RunState) -> int:
	var beds := 0
	for c in state.carriages:
		if str(c.get("templateId", "")) == "living":
			beds += int(c.get("size", 2)) * 2
	beds += state.living_tech * 2
	return beds


## 有 members[] 时数 hp>0；否则回退 onboard_pop（至少 1）。日结粮水用此值。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 整数结果（计数/下标/容量）。
static func onboard_count(state: RunState) -> int:
	if not state.members.is_empty():
		var n := 0
		for m in state.members:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			if float(m.get("hp", 100.0)) > 0.0:
				n += 1
		return maxi(1, n)
	return maxi(1, state.onboard_pop)


## 未完结搜索/搬运或队员 searching/hauling/in_combat；遗弃与开战前须为 false。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func has_outdoor_tasks(state: RunState) -> bool:
	for t in state.search_tasks:
		if typeof(t) == TYPE_DICTIONARY and not bool(t.get("complete", false)):
			return true
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var ts := str(m.get("taskState", "idle"))
		if ts in ["searching", "hauling", "in_combat", "returning"]:
			return true
	for h in state.haul_tasks:
		if typeof(h) == TYPE_DICTIONARY and not bool(h.get("complete", false)):
			return true
	return false


## 无进行中搜索/搬运单时，清掉队员残留的 searching/hauling（测试召回或异常清空任务后用）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
static func reconcile_outdoor_tasks(state: RunState) -> void:
	var active_search := false
	for t in state.search_tasks:
		if typeof(t) == TYPE_DICTIONARY and not bool(t.get("complete", false)):
			active_search = true
			break
	var active_haul := false
	for h in state.haul_tasks:
		if typeof(h) == TYPE_DICTIONARY and not bool(h.get("complete", false)):
			active_haul = true
			break
	if active_search or active_haul:
		return
	for i in state.members.size():
		var m: Variant = state.members[i]
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var ts := str(m.get("taskState", "idle"))
		if ts in ["searching", "hauling", "returning"]:
			m["taskState"] = "idle"
		elif ts == "in_combat" and not state.combat_panel_open:
			m["taskState"] = "idle"


## 空串=可遗弃；否则 `train.abandon.*` 错误码（UI 与 abandon_preview.blockReason）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param car_id 车厢 `carriages[].id`
## @return 空串=允许；非空=阻断原因码。
static func can_abandon(state: RunState, car_id: String) -> String:
	if state.drive_intent != "stop":
		return "must_stop"
	if has_outdoor_tasks(state):
		return "outdoor_tasks"
	if state.drive_hours_today + ABANDON_DAY_FRACTION > DriveService.hours_cap() + 0.001:
		return "drive_hours"
	var idx := find_carriage_index(state.carriages, car_id)
	if idx < 0:
		return "not_found"
	var car: Dictionary = state.carriages[idx]
	if violates_min_power(state, car_id):
		return "last_locomotive"
	var tid: String = str(car.get("templateId", ""))
	if _members_on_car(state, car_id) and _relocate_target(state, car_id) == "":
		return "no_other_car"
	var beds_after := bed_count(state)
	if str(car.get("templateId", "")) == "living":
		beds_after -= int(car.get("size", 2)) * 2
	if beds_after < onboard_count(state):
		return "beds"
	var cost: float = float(ConfigDb.require("balance.train.abandonPartsCost"))
	if state.parts < cost:
		return "parts"
	return ""


## can_abandon 错误码 → 本地化短句（`train.abandon.*`）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param code 机器错误码（本地化键前缀各异）
## @return 空串=成功；非空=机器错误码。
static func reason_text(code: String) -> String:
	return LocaleApi.tr_code("train.abandon", code, code)


## UI 展示：零件/油/废料与 blockReason（不修改 state）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param car_id 车厢 `carriages[].id`
## @return 结果字典；缺失语义键时可能为空 {}。
static func abandon_preview(state: RunState, car_id: String) -> Dictionary:
	var idx := find_carriage_index(state.carriages, car_id)
	if idx < 0:
		return {}
	var car: Dictionary = state.carriages[idx]
	var tid := str(car.get("templateId", ""))
	var parts_cost := float(ConfigDb.require("balance.train.abandonPartsCost"))
	var scrap_ratio := float(ConfigDb.require("balance.train.abandonScrapRatio"))
	var fuel_pct := float(ConfigDb.require("balance.train.abandonFuelCostPct"))
	var scrap_gain := int(float(repair_cost(tid)) * scrap_ratio)
	var fuel_spent := state.fuel_cap() * fuel_pct
	return {
		"carId": car_id,
		"templateId": tid,
		"partsCost": parts_cost,
		"scrapGain": scrap_gain,
		"fuelSpent": fuel_spent,
		"blockReason": can_abandon(state, car_id),
	}


## Intent `ABANDON_CARRIAGE` 唯一写入口；失败仅 warning，不改 state。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param car_id 车厢 `carriages[].id`
## @return 是否成功或条件成立。
static func abandon_carriage(state: RunState, car_id: String) -> bool:
	var reason := can_abandon(state, car_id)
	if reason != "":
		push_warning("TrainService.abandon blocked: " + reason)
		return false
	var idx := find_carriage_index(state.carriages, car_id)
	var car: Dictionary = state.carriages[idx]
	var tid: String = str(car.get("templateId", ""))
	var parts_cost: float = float(ConfigDb.require("balance.train.abandonPartsCost"))
	var scrap_ratio: float = float(ConfigDb.require("balance.train.abandonScrapRatio"))
	var fuel_pct: float = float(ConfigDb.require("balance.train.abandonFuelCostPct"))
	InventoryService.remove(state, "parts", parts_cost)
	state.scrap += float(int(float(repair_cost(tid)) * scrap_ratio))
	InventoryService.remove(state, "fuel", state.fuel_cap() * fuel_pct / 100.0)
	_relocate_members_off_car(state, car_id)
	state.carriages.remove_at(idx)
	state.abandon_count += 1
	state.drive_hours_today += ABANDON_DAY_FRACTION
	ClimateService.refresh(state)
	TelemetryService.record(
		"carriage_abandon",
		{
			"dayTotal": state.day_total,
			"carId": car_id,
			"templateId": tid,
			"carsAfter": state.car_count(),
			"fuelFill": snappedf(state.fuel_fill(), 0.01),
			"partsSpent": parts_cost,
			"scrapGranted": int(float(repair_cost(tid)) * scrap_ratio),
			"fuelSpent": state.fuel_cap() * fuel_pct,
			"driveIntent": state.drive_intent,
			"stationContext": true,
		}
	)
	return true


## 车上 power 模板节数，用于 violates_min_power。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 整数结果（计数/下标/容量）。
static func power_count(state: RunState) -> int:
	var n := 0
	for c in state.carriages:
		if str(c.get("templateId", "")) == "power":
			n += 1
	return n


## 本节前是否属于「最后一节动力」红线（仅当车上仅 1 节 power 且目标是该节）
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param car_id 车厢 `carriages[].id`
## @return 是否成功或条件成立。
static func violates_min_power(state: RunState, car_id: String) -> bool:
	var car := _carriage_dict(state, car_id)
	if car.is_empty():
		return false
	if str(car.get("templateId", "")) != "power":
		return false
	return power_count(state) <= 1


## UI 禁用「可遗弃」：等同 violates_min_power。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param car_id 车厢 `carriages[].id`
## @return 是否成功或条件成立。
static func is_locomotive_protected(state: RunState, car_id: String) -> bool:
	return violates_min_power(state, car_id)


## 打开遗弃面板时默认选中：首个非保护节，否则第一节。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 空串=成功；非空=机器错误码。
static func default_abandon_car_id(state: RunState) -> String:
	for car in state.carriages:
		if typeof(car) != TYPE_DICTIONARY:
			continue
		var cid := str(car.get("id", ""))
		if cid != "" and not violates_min_power(state, cid):
			return cid
	if not state.carriages.is_empty() and typeof(state.carriages[0]) == TYPE_DICTIONARY:
		return str(state.carriages[0].get("id", ""))
	return ""


## 按 id 取车厢字典。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param car_id 车厢 `carriages[].id`
## @return 结果字典；缺失语义键时可能为空 {}。
static func _carriage_dict(state: RunState, car_id: String) -> Dictionary:
	var idx := find_carriage_index(state.carriages, car_id)
	if idx < 0:
		return {}
	var row: Variant = state.carriages[idx]
	return row if typeof(row) == TYPE_DICTIONARY else {}

## 统计指定车厢 id 上分配的成员（bed/岗位绑定）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param car_id 车厢 `carriages[].id`
## @return 是否成功或条件成立。
static func _members_on_car(state: RunState, car_id: String) -> bool:
	if state.members.is_empty():
		return false
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("carId", "")) == car_id:
			return true
	return false

## 遗弃/挪人后：将成员迁到仍存在的目标车厢或回 idle。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param abandoning_car_id（String）
## @return 空串=成功；非空=机器错误码。
static func _relocate_target(state: RunState, abandoning_car_id: String) -> String:
	var living := ""
	var any_other := ""
	for c in state.carriages:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cid := str(c.get("id", ""))
		if cid == abandoning_car_id:
			continue
		any_other = cid if any_other == "" else any_other
		if str(c.get("templateId", "")) == "living":
			living = cid
	return living if living != "" else any_other


## 遗弃前把该节乘员 carId 改到 living 或任意余车。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param car_id 车厢 `carriages[].id`
static func _relocate_members_off_car(state: RunState, car_id: String) -> void:
	var dest := _relocate_target(state, car_id)
	if dest == "":
		return
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("carId", "")) == car_id:
			m["carId"] = dest