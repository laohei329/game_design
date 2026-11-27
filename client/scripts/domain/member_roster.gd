class_name MemberRoster
extends RefCounted

const _PopulationRules := preload("res://scripts/domain/population_rules.gd")
## 开局名册薄实现：`NEW_RUN` 写入 `state.members[]`。
##
## 字段约定：`taskState` idle/searching/hauling；`carId` 床位所在节；
## `combatRoster` 战斗名册预留；日结人口数以 `TrainService.onboard_count` 为准。
## 开局四人权威：`archetypes.startPartyTemplate`（岗位/专长/combatRoster）。


## 当班：job 匹配、存活、未占用户外任务（对齐 sim `staff_on_duty` 子集）。
static func staff_on_duty(state: RunState, job: String) -> bool:
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("job", "")) != job:
			continue
		if float(m.get("hp", 0.0)) <= 0.0:
			continue
		var ts := str(m.get("taskState", "idle"))
		if ts in ["searching", "hauling", "in_combat", "returning", "unavailable"]:
			continue
		return true
	return false


## 日末按功能车填岗（sim `assign_jobs` 薄切片；不关guard/已固定岗）。
static func assign_daily_jobs(state: RunState) -> void:
	var need := _job_slots_needed(state)
	if need.is_empty():
		return
	var pool: Array = []
	var labor_keep := 0
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if float(m.get("hp", 0.0)) <= 0.0:
			continue
		var job := str(m.get("job", ""))
		if job == "labor":
			labor_keep += 1
		if job in ["none", "labor"]:
			pool.append(m)
	var labor_min := _PopulationRules.job_assign_labor_keep_min()
	for job_name in need.keys():
		var slots: int = int(need[job_name])
		for _i in slots:
			if pool.is_empty():
				return
			var best: Dictionary = {}
			var best_score := -1
			for cand in pool:
				var score := _job_pick_score(cand, str(job_name))
				if score > best_score:
					best_score = score
					best = cand
			if best.is_empty():
				break
			if str(best.get("job", "")) == "labor" and labor_keep <= labor_min:
				continue
			if str(best.get("job", "")) == "labor":
				labor_keep -= 1
			best["job"] = str(job_name)
			pool.erase(best)


static func _job_slots_needed(state: RunState) -> Dictionary:
	var need := {}
	var w_slots := _PopulationRules.job_slots_per_workshop()
	for c in state.carriages:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var tid := str(c.get("templateId", ""))
		if tid == "power":
			need["engineer"] = int(need.get("engineer", 0)) + 1
			continue
		var row := _carriage_template_row(tid)
		var fn := str(row.get("function", ""))
		match fn:
			"greenhouse":
				need["grower"] = int(need.get("grower", 0)) + 1
			"water":
				need["purifier"] = int(need.get("purifier", 0)) + 1
			"workshop":
				need["crafter"] = int(need.get("crafter", 0)) + w_slots
			"medical":
				need["pharmacist"] = int(need.get("pharmacist", 0)) + 1
			"radar":
				need["radar_op"] = int(need.get("radar_op", 0)) + 1
			_:
				pass
	return need


static func _carriage_template_row(template_id: String) -> Dictionary:
	var root: Dictionary = ConfigDb.get_table("carriages")
	var templates: Variant = root.get("templates", {})
	if typeof(templates) != TYPE_DICTIONARY:
		return {}
	var row: Variant = templates.get(template_id, {})
	return row if typeof(row) == TYPE_DICTIONARY else {}


static func _job_pick_score(member: Dictionary, job: String) -> int:
	var score := 0
	var ps: Variant = ConfigDb.require("balance.jobs.pickScore")
	if typeof(ps) != TYPE_DICTIONARY:
		return score
	var prior := int(ps.get("priorJobLabor", 1))
	var spec_m := int(ps.get("specialtyMatch", 10))
	var spec_r := int(ps.get("relatedSpecialty", 5))
	if str(member.get("job", "")) == "labor":
		score += prior
	var specs: Variant = member.get("specialties", [])
	if typeof(specs) == TYPE_ARRAY:
		for s in specs:
			if str(s) == job:
				score += spec_m
			elif job == "crafter" and str(s) == "repair":
				score += spec_r
			elif job == "pharmacist" and str(s) == "medicine":
				score += spec_r
	return score

## 按 archetypes.startPartyTemplate 生成开局四人。
##
## @param state 当前局 `RunState`（就地修改字段）
static func seed_starting_crew(state: RunState) -> void:
	var rows: Variant = ConfigDb.require("archetypes.startPartyTemplate.members")
	if typeof(rows) != TYPE_ARRAY or rows.is_empty():
		push_error("MemberRoster: archetypes.startPartyTemplate.members missing or empty")
		state.members = []
		return
	state.members = []
	var lang := str(ProjectSettings.get_setting("game/locale", "zh"))
	var name_i := 0
	for i in rows.size():
		if typeof(rows[i]) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = rows[i]
		var job := str(row.get("job", "none"))
		var combat := bool(row.get("combatRoster", false))
		var specs: Array = []
		var spec_v: Variant = row.get("specialties", [])
		if typeof(spec_v) == TYPE_ARRAY:
			for s in spec_v:
				specs.append(str(s))
		var car_id := _start_bed_car_id(state, i)
		var mid := "mem_start_%d" % i
		var display := _start_display_name(lang, name_i)
		name_i += 1
		state.members.append(_make(mid, display, job, car_id, combat, specs))


## 开局床位：优先 `living` 车厢 id，按 index 轮询 `state.carriages`。
static func _start_bed_car_id(state: RunState, index: int) -> String:
	var living: PackedStringArray = []
	var any: PackedStringArray = []
	for c in state.carriages:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cid := str(c.get("id", ""))
		if cid.is_empty():
			continue
		any.append(cid)
		if str(c.get("templateId", "")) == "living":
			living.append(cid)
	var pool := living if living.size() > 0 else any
	if pool.is_empty():
		return ""
	return pool[index % pool.size()]


## 玩家指派岗位；`jobIds` 权威见 `archetypes.json`。
static func set_member_job(state: RunState, member_id: String, job_id: String) -> String:
	if member_id.is_empty():
		return "no_member"
	var job := job_id.strip_edges().to_lower()
	if not _valid_job_id(job):
		return "invalid_job"
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("id", "")) != member_id:
			continue
		if str(m.get("taskState", "idle")) not in ["idle", "none"]:
			return "member_busy"
		m["job"] = job
		TelemetryService.record(
			"job_assign",
			{"dayTotal": state.day_total, "memberId": member_id, "job": job}
		)
		return ""
	return "not_found"


static func _valid_job_id(job: String) -> bool:
	var ids: Variant = ConfigDb.get_table("archetypes").get("jobIds", [])
	if typeof(ids) != TYPE_ARRAY:
		return false
	return job in ids


static func job_select_options() -> PackedStringArray:
	var ids: Variant = ConfigDb.get_table("archetypes").get("jobIds", [])
	var out := PackedStringArray()
	if typeof(ids) != TYPE_ARRAY:
		return out
	for raw in ids:
		out.append(str(raw))
	return out


## 开局名：读 `archetypes.namePools` 给定名表（按序，与语言列）。
##
## @param locale 语言 id（zh/en）
## @param index 段下标 region_run.segment_index 或名册序号
## @return 空串=成功；非空=机器错误码。
static func _start_display_name(locale: String, index: int) -> String:
	var pools: Variant = ConfigDb.get_table("archetypes").get("namePools", {})
	if typeof(pools) != TYPE_DICTIONARY:
		return "crew_%d" % (index + 1)
	var given: Variant = pools.get("given", {})
	if typeof(given) != TYPE_DICTIONARY:
		return "crew_%d" % (index + 1)
	var col: Variant = given.get(locale, given.get("en", []))
	if typeof(col) != TYPE_ARRAY or col.is_empty():
		return "crew_%d" % (index + 1)
	return str(col[index % col.size()])


## 日结补抽（06 §2.2）：当日尚未收留成功且有空床。
##
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func try_day_end_recruit(state: RunState) -> bool:
	if TrainService.onboard_count(state) >= TrainService.bed_count(state):
		return false
	if state.last_recruit_success_day == state.day_total:
		return false
	var rate := float(ConfigDb.require("balance.recruit.dayEndBaseRate"))
	if RngService.randf() >= rate:
		return false
	if not try_recruit_one(state):
		return false
	TelemetryService.record("day_end_recruit", {"dayTotal": state.day_total})
	return true


## 事件 `recruit_roll`：有空床则加一名杂工。
##
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func try_recruit_one(state: RunState) -> bool:
	if TrainService.onboard_count(state) >= TrainService.bed_count(state):
		return false
	var n := state.members.size()
	var mid := "mem_evt_%d" % n
	var bed := _start_bed_car_id(state, n)
	state.members.append(_make(mid, "路人 %d" % (n + 1), "none", bed, false, ["scavenge"]))
	assign_daily_jobs(state)
	state.last_recruit_success_day = state.day_total
	return true

## 由 archetype + 新 id 构造成员字典（hp/mood/岗位/taskState 默认值）。
##
## @param id（String）
## @param name（String）
## @param job（String）
## @param car_id 车厢 `carriages[].id`
## @param combat（bool）
## @param specialties（Array）
## @return 结果字典；缺失语义键时可能为空 {}。
static func _make(
	id: String,
	name: String,
	job: String,
	car_id: String,
	combat: bool,
	specialties: Array = []
) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"job": job,
		"carId": car_id,
		"hp": 100.0,
		"mood": _PopulationRules.mood_default(),
		"hunger": 0.0,
		"thirst": 0.0,
		"taskState": "idle",
		"combatRoster": combat,
		"specialties": specialties.duplicate(),
	}