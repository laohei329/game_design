extends RefCounted
## Contract mirror (09 §2). Full chain implemented in SaveService by S1b.

class_name MigrationV11ToV12


static func apply(save: Dictionary) -> void:
	if not save.has("version"):
		save["version"] = {}
	save["version"]["save"] = 12
	if not save.get("train", {}).has("driveIntent"):
		save["train"]["driveIntent"] = "stop"