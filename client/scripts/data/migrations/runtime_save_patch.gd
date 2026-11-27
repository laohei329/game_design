extends RefCounted
## 读档时原地补丁（未 bump version.save）：补 save 12 之后新增 train/world 缺键。
##
## 完整 v10→v12 链目标在 SaveService/S1b.5；此处仅保证旧 JSON 不因缺字段崩溃。

class_name RuntimeSavePatch


## 当前：abandonCount、precision、moraleOffset、pressureHistory 默认值。
static func ensure_abandon_fields(save: Dictionary) -> void:
	var train: Dictionary = save.get("train", {})
	if not train.has("abandonCount"):
		train["abandonCount"] = 0
	if not train.has("precision"):
		train["precision"] = SaveMigrationUtil.config_require_float("balance.start.precision", 40.0)
	save["train"] = train
	var world: Dictionary = save.get("world", {})
	if not world.has("moraleOffset"):
		world["moraleOffset"] = 0.0
	if not world.has("pressureHistory"):
		world["pressureHistory"] = ["", ""]
	save["world"] = world