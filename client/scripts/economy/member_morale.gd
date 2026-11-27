class_name MemberMorale
extends RefCounted
## 日结逐人 mood（对齐 sim `morale_settle` 成员环；offset/streak 仍由 `DaySettle._step_7b_morale`）。

const _PopulationRules := preload("res://scripts/domain/population_rules.gd")


## 床位按名册顺序前 `bed_count` 名存活者；岗/粮水/生活科技加成进表。
static func settle_daily_moods(state: RunState) -> void:
	var alive: Array = []
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if float(m.get("hp", 0.0)) <= 0.0:
			continue
		alive.append(m)
	var beds := TrainService.bed_count(state)
	var bedded: Dictionary = {}
	for i in mini(beds, alive.size()):
		var row: Dictionary = alive[i]
		var mid := str(row.get("id", ""))
		if mid != "":
			bedded[mid] = true
	var has_rations := state.food > 0.0 and state.water > 0.0
	var living_bonus := float(state.living_tech) * _PopulationRules.mood_daily_living_tech_per_level()
	for m in alive:
		var delta := _PopulationRules.mood_daily_base_delta()
		if str(m.get("job", "")) == "none":
			delta += _PopulationRules.mood_daily_no_job_penalty()
		var mid := str(m.get("id", ""))
		if bedded.has(mid):
			delta += _PopulationRules.mood_daily_bedded_bonus()
		else:
			delta += _PopulationRules.mood_daily_unbedded_penalty()
		if has_rations:
			delta += _PopulationRules.mood_daily_ration_bonus()
		delta += living_bonus
		var prev := float(m.get("mood", _PopulationRules.mood_default()))
		m["mood"] = _PopulationRules.clamp_mood(prev + delta)