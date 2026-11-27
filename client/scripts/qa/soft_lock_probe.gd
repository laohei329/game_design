class_name SoftLockProbe
extends RefCounted
## 软锁审计：DebugOverlay F3 与无头末尾调用 `audit(state)`。
##
## 检查：库存非负、failed 闸、末节动力不可遗弃、search cap 配置可读等；返回 { ok, lines }。


static func audit(state: RunState) -> Dictionary:
	if state == null:
		return {"ok": false, "lines": ["无 RunState"]}
	var lines: PackedStringArray = []
	var ok := true

	if state.food < 0.0 or state.water < 0.0 or state.fuel < 0.0 or state.parts < 0.0:
		ok = false
		lines.append("FAIL 负库存")
	else:
		lines.append("OK 库存非负")

	if state.failed != "":
		lines.append("FAIL 归零闸门 failed=%s" % state.failed)
		ok = false

	lines.append("guaranteeFailStreak=%d (拒×4 后期望≥4)" % state.guarantee_fail_streak)

	TrainService.reconcile_outdoor_tasks(state)
	HaulService.recall_haul(state, {"pointId": ""})
	TrainService.reconcile_outdoor_tasks(state)
	var last_loco := _sole_power_id(state)
	if last_loco != "":
		var r := TrainService.can_abandon(state, last_loco)
		if r == "last_locomotive":
			lines.append("OK 最少保留一节动力")
		else:
			ok = false
			lines.append("FAIL 末节动力应不可遗弃 got=%s" % r)
	else:
		lines.append("— 无单一动力检测")

	lines.append("Search cap 配置=%d" % SearchRules.cap())
	lines.append("车外任务=%d" % state.search_tasks.size())

	return {"ok": ok, "lines": lines}

## 若编组仅一节 `templateId==power`，返回其 `id`；否则空串（软锁规则输入）。
static func _sole_power_id(state: RunState) -> String:
	var found := ""
	var count := 0
	for c in state.carriages:
		if str(c.get("templateId", "")) == "power":
			count += 1
			found = str(c.get("id", ""))
	if count == 1:
		return found
	return ""