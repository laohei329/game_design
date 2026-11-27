extends Node
## 可选启动场景：校验 ConfigDb 后跳转 run_main（正式 main_scene 多为 run_main 直开）。

@onready var _status: Label = $CanvasLayer/Status
func _ready() -> void:
	var ok := ConfigDb.load_all()
	if not ok:
		_status.text = "ConfigDb FAIL:\n" + "\n".join(ConfigDb.load_errors)
		return
	_status.text = "ConfigDb OK configVersion=%d\n→ run_main…" % ConfigDb.config_version
	get_tree().change_scene_to_file("res://scenes/run_main.tscn")