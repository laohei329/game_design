class_name SystemEffects
extends RefCounted
## 统一后果入口（incident / 延迟队列 / legacy 卡均委托 EventOps）。


## 顺序执行 effects[]；首错码返回（combat_opened 等视为成功）。
static func apply_effects(
	state: RunState,
	effects: Array,
	seg: Segment,
	source: String,
	source_action: String = ""
) -> String:
	for raw in effects:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var target_type := str(row.get("targetType", "segment"))
		var r := EventOps.apply_op(state, row, target_type, seg, source, source_action)
		if r == "" or r == "combat_opened" or r == "delayed_target_skip":
			continue
		return r
	return ""