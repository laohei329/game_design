class_name SearchRules
extends RefCounted
## 10 §1 #7 · balance.search.*


static func cap() -> int:
	return int(ConfigDb.require("balance.search.maxAssignPerPointPerDay"))


static func hours_per_task() -> float:
	return float(ConfigDb.require("balance.search.hoursPerTask"))


static func hours_progress_per_day() -> float:
	return float(ConfigDb.require("balance.search.hoursProgressPerDay"))