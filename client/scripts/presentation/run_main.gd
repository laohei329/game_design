extends Control
## 主玩法场景：无局时自动 NEW_RUN；F3 切换 DebugOverlay。
## 子场景 HudTop / 各 Modal 自行订阅 GameSession.state_changed。

@onready var _world: ColorRect = $WorldPlaceholder
@onready var _debug: CanvasLayer = $DebugOverlay
func _ready() -> void:
	if ConfigDb.tables.is_empty():
		var ok := ConfigDb.load_all()
		if not ok:
			push_error("ConfigDb failed: " + ", ".join(ConfigDb.load_errors))
			return
	if GameSession.state == null:
		IntentBus.emit_intent("NEW_RUN")

## 全局快捷键（如 F3 调试、Esc 关面板）；未消费则交 Godot 默认。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3 and _debug.has_method("toggle"):
			_debug.toggle()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_P or event.keycode == KEY_ESCAPE:
			IntentBus.emit_intent("TOGGLE_TIME_PAUSE")
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_1:
				IntentBus.emit_intent("SET_TIME_SPEED", {"speed": 1.0})
				get_viewport().set_input_as_handled()
			KEY_2:
				IntentBus.emit_intent("SET_TIME_SPEED", {"speed": 2.0})
				get_viewport().set_input_as_handled()
			KEY_3:
				IntentBus.emit_intent("SET_TIME_SPEED", {"speed": 4.0})
				get_viewport().set_input_as_handled()
