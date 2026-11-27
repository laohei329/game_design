extends SceneTree
## Headless：打印 A6Batch0Probe JSON 一行后以退出码结束。

const _Batch0Probe = preload("res://scripts/debug/a6_batch0_probe.gd")


func _init() -> void:
	var r: Dictionary = _Batch0Probe.run_all()
	print(JSON.stringify(r))
	var code := 0 if r.get("ok", false) else 1
	quit(code)