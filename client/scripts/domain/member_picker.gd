class_name MemberPicker
extends RefCounted
## 04 §5.3 搜索点名：1–4 人，scavenge 专长置顶


const MAX_PARTY := 4

const JOB_ZH := {
	"engineer": "动力",
	"guard": "守卫",
	"labor": "杂工",
	"none": "闲置",
}


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


static func can_search(m: Dictionary) -> bool:
	if float(m.get("hp", 0.0)) <= 30.0:
		return false
	var ts := str(m.get("taskState", "idle"))
	if ts in ["searching", "hauling", "in_combat", "returning", "unavailable"]:
		return false
	return true


static func label_for(m: Dictionary) -> String:
	var name := str(m.get("name", m.get("id", "?")))
	var job := JOB_ZH.get(str(m.get("job", "")), str(m.get("job", "")))
	var mark := " ★搜刮" if _has_scavenge(m) else ""
	return "%s（%s）%s" % [name, job, mark]


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


static func _has_scavenge(m: Dictionary) -> bool:
	var specs: Variant = m.get("specialties", [])
	if typeof(specs) != TYPE_ARRAY:
		return false
	return "scavenge" in specs