class_name InventoryService
extends RefCounted
## 02 §6 库存上限与入库（S1a 六元 + scrap；fuel 用 fuel_cap）


const BASE := {
	"food": 60.0,
	"water": 60.0,
	"parts": 20.0,
	"scrap": 30.0,
	"medicine": 15.0,
	"seed": 20.0,
	"chem": 15.0,
	"cloth": 20.0,
}


static func normalize_key(key: String) -> String:
	var k := str(key).to_lower()
	if k == "med":
		return "medicine"
	return k


static func life_mult(_state: RunState) -> float:
	# S1a：生活科技未接，固定 1.0
	return 1.0


static func cargo_size_sum(state: RunState) -> int:
	var total := 0
	for c in state.carriages:
		if str(c.get("templateId", "")) == "cargo":
			total += int(c.get("size", 0))
	return total


static func stock_cap(state: RunState, key: String) -> float:
	var k := normalize_key(key)
	if k == "fuel":
		return state.fuel_cap()
	var cargo := float(cargo_size_sum(state))
	var mult := life_mult(state)
	match k:
		"food", "water":
			return (BASE[k] + cargo * 10.0) * mult
		"parts", "medicine", "chem":
			return (BASE[k] + roundf(cargo * 10.0 / 3.0)) * mult
		"scrap":
			return (BASE["scrap"] + cargo * 8.0) * mult
		"seed", "cloth":
			return (BASE[k] + cargo * (4.0 if k == "seed" else 5.0)) * mult
		_:
			return 9999.0


static func get_amount(state: RunState, key: String) -> float:
	var k := normalize_key(key)
	match k:
		"food":
			return state.food
		"water":
			return state.water
		"fuel":
			return state.fuel
		"parts":
			return state.parts
		"scrap":
			return state.scrap
		"medicine":
			return state.medicine
		"seed":
			return state.seed
		"chem":
			return state.chem
		"cloth":
			return state.cloth
		_:
			return 0.0


static func add(state: RunState, key: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var k := normalize_key(key)
	var cap := stock_cap(state, k)
	var before := get_amount(state, k)
	var after := clampf(before + amount, 0.0, cap)
	var added := after - before
	_set_amount(state, k, after)
	return added


static func clamp_resource(state: RunState, key: String) -> void:
	var k := normalize_key(key)
	_set_amount(state, k, clampf(get_amount(state, k), 0.0, stock_cap(state, k)))


static func _set_amount(state: RunState, key: String, value: float) -> void:
	match key:
		"food":
			state.food = value
		"water":
			state.water = value
		"fuel":
			state.fuel = value
		"parts":
			state.parts = value
		"scrap":
			state.scrap = value
		"medicine":
			state.medicine = value
		"seed":
			state.seed = value
		"chem":
			state.chem = value
		"cloth":
			state.cloth = value