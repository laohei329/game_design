class_name MemberPicker
extends RefCounted

const _PopulationRules := preload("res://scripts/domain/population_rules.gd")
## 搜索 UI 点名规则：1–4 人，`scavenge` 专长优先排序。
##
## `validate_selection` 错误码 → `search.err.*`（GameSession warning）；
## 与 SearchService 队内人数/队效（0.9+0.02n）配合，但队效仍写在 SearchService 内。


const MAX_PARTY := 4

## UI 队员列表排序：scavenge 专长在前，再按 name。
static func sorted_for_search(state: RunState) -> Array:
	var rows: Array = []
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		rows.append(m)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := _has_scavenge(a)
		var sb := _has_scavenge(b)
		if sa != sb:
			return sa
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return rows


## 与 SearchService._member_available 口径一致。
static func can_search(m: Dictionary) -> bool:
	if float(m.get("hp", 0.0)) <= _PopulationRules.injured_hp_threshold():
		return false
	var ts := str(m.get("taskState", "idle"))
	if ts in ["searching", "hauling", "in_combat", "returning", "unavailable"]:
		return false
	return true


## 复选框展示「姓名（岗位）★搜刮」。
static func label_for(m: Dictionary) -> String:
	var name := str(m.get("name", m.get("id", "?")))
	var job := LocaleApi.tr_code("job", str(m.get("job", "")), str(m.get("job", "")))
	var mark := LocaleApi.tr_key("spec.scavenge.badge") if _has_scavenge(m) else ""
	var hun_warn := float(ConfigDb.require("balance.population.satisfactionHungerPerFullDayRation"))
	var thr_warn := float(ConfigDb.require("balance.population.satisfactionThirstPerFullDayRation"))
	if float(m.get("hunger", 0.0)) >= hun_warn or float(m.get("thirst", 0.0)) >= thr_warn:
		mark = (mark + " ") if mark != "" else ""
		mark += "☆"
	var hun := int(round(float(m.get("hunger", 0.0))))
	var thr := int(round(float(m.get("thirst", 0.0))))
	mark += LocaleApi.trf("member.vitals_paren", [hun, thr])
	return LocaleApi.trf("member.label", [name, job, mark])


## HUD 一行：存活乘员「名 饿/渴」。
static func roster_vitals_line(state: RunState) -> String:
	var bits: PackedStringArray = []
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if float(m.get("hp", 0.0)) <= 0.0:
			continue
		var name := str(m.get("name", m.get("id", "?")))
		var hun := int(round(float(m.get("hunger", 0.0))))
		var thr := int(round(float(m.get("thirst", 0.0))))
		bits.append(LocaleApi.trf("member.vitals_roster", [name, hun, thr]))
	if bits.is_empty():
		return LocaleApi.tr_key("hud.crew.empty")
	return LocaleApi.trf("hud.crew.line", [" · ".join(bits)])


## 点名提交前校验；空 pick_members / too_many / member_busy / not_found。
static func validate_selection(state: RunState, member_ids: Array) -> String:
	if member_ids.is_empty():
		return "pick_members"
	if member_ids.size() > MAX_PARTY:
		return "too_many"
	for raw in member_ids:
		var mid := str(raw)
		var found := false
		for m in state.members:
			if typeof(m) != TYPE_DICTIONARY:
				continue
			if str(m.get("id", "")) != mid:
				continue
			found = true
			if not can_search(m):
				return "member_busy"
			break
		if not found:
			return "not_found"
	return ""

## 成员是否具备搜索岗位或 scavenge 相关标记（Search 面板选人过滤）。
static func _has_scavenge(m: Dictionary) -> bool:
	var specs: Variant = m.get("specialties", [])
	if typeof(specs) != TYPE_ARRAY:
		return false
	return "scavenge" in specs
