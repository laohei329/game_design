extends Node

var _rng := RandomNumberGenerator.new()


func seed_from(value: int) -> void:
	_rng.seed = value


func randf() -> float:
	return _rng.randf()


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)