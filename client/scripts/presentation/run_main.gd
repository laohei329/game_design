extends Control

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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3 and _debug.has_method("toggle"):
			_debug.toggle()
			get_viewport().set_input_as_handled()