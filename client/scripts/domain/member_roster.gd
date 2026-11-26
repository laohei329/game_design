class_name MemberRoster
extends RefCounted
## 04 §4.3.1 开局四人编制（薄字段）


static func seed_starting_crew(state: RunState) -> void:
	state.members = [
		_make("mem_eng", "老周", "engineer", "car_pwr", true),
		_make("mem_grd", "阿韧", "guard", "car_liv", true),
		_make("mem_lab1", "小丁", "labor", "car_liv", false, ["scavenge"]),
		_make("mem_lab2", "阿兰", "labor", "car_cgo", false),
	]
	state.onboard_pop = state.members.size()


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
		"mood": 70.0,
		"taskState": "idle",
		"combatRoster": combat,
		"specialties": specialties.duplicate(),
	}