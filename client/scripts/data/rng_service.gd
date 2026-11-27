extends Node
## 局内随机源（Autoload RngService）。`NEW_RUN` 用 Unix 时间播种，保证可复现抽查需固定 seed_from。
## 玩法层禁止 `RandomNumberGenerator` 自建，统一走本服务以便日后对接存档 seed。

var _rng := RandomNumberGenerator.new()

## 固定本局 PRNG 种子。
func seed_from(value: int) -> void:
	_rng.seed = value

## 均匀 [0,1) 浮点。
func randf() -> float:
	return _rng.randf()

## 闭区间整数。
func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

## 非负整数 % n。
func randi() -> int:
	return _rng.randi()