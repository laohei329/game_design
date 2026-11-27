class_name BalanceStart
extends RefCounted
## `balance.start` 单点：NEW_RUN 写入与存档 inventory 缺字段回填（E-4/E-5）。


static func _start_cfg_key(inventory_key: String) -> String:
	return "med" if inventory_key == "medicine" else inventory_key


## 旧档缺 `inventory.*` 时的回填值；仅 scalar 六元 + seed（scrap/chem/cloth 开局为 0）。
static func inventory_default(inventory_key: String) -> float:
	var k := inventory_key.to_lower()
	if k in ["food", "water", "fuel", "parts", "medicine", "seed"]:
		return float(ConfigDb.require("balance.start." + _start_cfg_key(k)))
	if k in ["scrap", "chem", "cloth"]:
		return 0.0
	push_error("BalanceStart.inventory_default unknown key: " + k)
	return 0.0


static func starting_precision() -> float:
	return float(ConfigDb.require("balance.start.precision"))


static func starting_carriages() -> Array:
	var cars: Variant = ConfigDb.require("balance.start.carriages")
	if typeof(cars) != TYPE_ARRAY or cars.is_empty():
		push_error("BalanceStart: balance.start.carriages missing or empty")
		return []
	return (cars as Array).duplicate(true)


static func default_region_fuel_mult() -> float:
	return float(ConfigDb.require("balance.regions.defaultFuelMult"))


## `NEW_RUN` 资源、精度、开局编组；不写 members/region（由 GameSession 后续步骤接）。
static func apply_new_run(state: RunState) -> void:
	state.food = inventory_default("food")
	state.water = inventory_default("water")
	state.fuel = inventory_default("fuel")
	state.parts = inventory_default("parts")
	state.medicine = inventory_default("medicine")
	state.seed = inventory_default("seed")
	state.scrap = inventory_default("scrap")
	state.chem = inventory_default("chem")
	state.cloth = inventory_default("cloth")
	state.precision = starting_precision()
	state.region_fuel_mult = default_region_fuel_mult()
	state.carriages = starting_carriages()