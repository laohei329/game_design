extends Node

signal intent_emitted(intent_name: String, payload: Dictionary)


func emit_intent(intent_name: String, payload: Dictionary = {}) -> void:
	intent_emitted.emit(intent_name, payload)