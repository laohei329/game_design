extends RefCounted
## save 12: train.abandonCount default 0 (09 §3.1). No version.save bump until save 13.

class_name RuntimeSavePatch


static func ensure_abandon_fields(save: Dictionary) -> void:
	var train: Dictionary = save.get("train", {})
	if not train.has("abandonCount"):
		train["abandonCount"] = 0
	save["train"] = train