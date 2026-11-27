class_name SessionIntentRouter
extends RefCounted
## Intent 表驱动：`Lifecycle` → `Train` → `World` 顺序尝试；未知 Intent 返回 false。

const _Lifecycle := preload("res://scripts/app/session_intents_lifecycle.gd")
const _Train := preload("res://scripts/app/session_intents_train.gd")
const _World := preload("res://scripts/app/session_intents_world.gd")


## @return 是否已识别并处理（含 `NEW_RUN` 等自备 `state_changed` 的路径）
static func dispatch(session: Node, intent_name: String, payload: Dictionary) -> bool:
	for mod in [_Lifecycle, _Train, _World]:
		var code: int = int(mod.call("try_handle", session, intent_name, payload))
		if code >= 0:
			if code == 1:
				session.state_changed.emit()
			return true
	return false