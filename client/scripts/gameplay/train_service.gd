class_name TrainService
extends RefCounted
## 03 §4.1 ABANDON_CARRIAGE

const REPAIR_LIVING_CARGO := 3
const REPAIR_OTHER := 5
const ABANDON_DAY_FRACTION := 0.5

const TEMPLATE_ZH := {
	"power": "动力",
	"living": "休息",
	"cargo": "货舱",
	"greenhouse": "种植",
	"water": "净水",
	"workshop": "工坊",
	"medical": "医疗",
	"radar": "雷达",
	"armor": "装甲",
	"shell": "空壳",
}

const REASON_ZH := {
	"must_stop": "须先停靠",
	"not_found": "车厢不存在",
	"last_locomotive": "最后一节动力不可遗弃",
	"parts": "零件不足",
	"outdoor_tasks": "车外搜索/搬运未完成",
	"drive_hours": "当日行驶额度不足 0.5 日",
	"beds": "遗弃后床位不足",
	"members_on_car": "乘员仍绑定该节，须先迁床",
}


static func repair_cost(template_id: String) -> int:
	return REPAIR_LIVING_CARGO if template_id in ["living", "cargo"] else REPAIR_OTHER


static func find_carriage_index(carriages: Array, car_id: String) -> int:
	for i in carriages.size():
		if str(carriages[i].get("id", "")) == car_id:
			return i
	return -1


static func bed_count(state: RunState) -> int:
	var beds := 0
	for c in state.carriages:
		if str(c.get("templateId", "")) == "living":
			beds += int(c.get("size", 2)) * 2
	return beds


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
	var tid: String = str(car.get("templateId", ""))
	var locos := 0
	for c in state.carriages:
		if str(c.get("templateId", "")) == "power":
			locos += 1
	if tid == "power" and locos <= 1:
		return "last_locomotive"
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("carId", "")) == car_id:
			return "members_on_car"
	var beds_after := bed_count(state)
	if str(car.get("templateId", "")) == "living":
		beds_after -= int(car.get("size", 2)) * 2
	if beds_after < onboard_count(state):
		return "beds"
	var cost: float = float(ConfigDb.require("balance.train.abandonPartsCost"))
	if state.parts < cost:
		return "parts"
	return ""


static func reason_text(code: String) -> String:
	return REASON_ZH.get(code, code)


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
	state.parts -= parts_cost
	state.scrap += float(int(float(repair_cost(tid)) * scrap_ratio))
	state.fuel = maxf(0.0, state.fuel - state.fuel_cap() * fuel_pct)
	_clear_members_from_car(state, car_id)
	state.carriages.remove_at(idx)
	state.abandon_count += 1
	state.drive_hours_today += ABANDON_DAY_FRACTION
	ClimateService.recompute(state)
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


static func _clear_members_from_car(state: RunState, car_id: String) -> void:
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("carId", "")) == car_id:
			m["carId"] = ""