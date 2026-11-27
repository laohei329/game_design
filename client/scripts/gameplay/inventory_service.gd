class_name InventoryService
extends RefCounted
## 列车库存上限与 `add`/`remove`（搬运、日结、饥渴、扣油等统一入口）。
##
## 上限键：`balance.inventory.*`（02 §6 S1a 线性货舱增量）。
## `fuel` 上限用 `RunState.fuel_cap()`（`balance.fuelTank`）。
## `add` 返回**实际入库量**（可能因 cap 小于请求量）；HaulService 据此处理溢出回堆。


static func _inventory_cfg() -> Dictionary:
	var root: Variant = ConfigDb.require("balance.inventory")
	return root if typeof(root) == TYPE_DICTIONARY else {}

## 单资源基础上限（不含货舱）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param key 库存或配置键（常经 normalize_key）
## @return 浮点结果（量/比率/工时）。
static func _base_cap(key: String) -> float:
	var inv := _inventory_cfg()
	var base: Variant = inv.get("base", {})
	if typeof(base) == TYPE_DICTIONARY:
		return float(base.get(key, 0.0))
	return 0.0


## med → medicine；堆/表键统一小写。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param key 库存或配置键（常经 normalize_key）
## @return 空串=成功；非空=机器错误码。
static func normalize_key(key: String) -> String:
	var k := str(key).to_lower()
	if k == "med":
		return "medicine"
	return k


## 六元 scalar 库存键（不含 `blueprints`，图纸走 TechService）。
static func is_scalar_inventory_key(key: String) -> bool:
	var k := normalize_key(key)
	return k in ["food", "water", "fuel", "parts", "scrap", "medicine", "seed", "chem", "cloth"]

## 生活科技库存倍率；S1a 固定 1.0。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param _state（RunState）
## @return 浮点结果（量/比率/工时）。
static func life_mult(_state: RunState) -> float:
	# S1a：生活科技未接，固定 1.0
	return 1.0

## 编组 cargo 节 size 合计。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 整数结果（计数/下标/容量）。
static func cargo_size_sum(state: RunState) -> int:
	var total := 0
	for c in state.carriages:
		if str(c.get("templateId", "")) == "cargo":
			total += int(c.get("size", 0))
	return total


## `balance.inventory.base` + `cargoPerSize`；`fuel` 走 `RunState.fuel_cap()`。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param key 库存或配置键（常经 normalize_key）
## @return 浮点结果（量/比率/工时）。
static func stock_cap(state: RunState, key: String) -> float:
	var k := normalize_key(key)
	if k == "fuel":
		return state.fuel_cap()
	var cargo := float(cargo_size_sum(state))
	var mult := life_mult(state)
	var inv := _inventory_cfg()
	var cps: Variant = inv.get("cargoPerSize", {})
	var cargo_per: Dictionary = cps if typeof(cps) == TYPE_DICTIONARY else {}
	var cap := 0.0
	match k:
		"food", "water":
			cap = _base_cap(k) + cargo * float(cargo_per.get("foodWater", 10.0))
		"parts", "medicine", "chem":
			var tenth := float(cargo_per.get("partsMedicineChemTenth", 10.0))
			cap = _base_cap(k) + roundf(cargo * tenth / 3.0)
		"scrap":
			cap = _base_cap("scrap") + cargo * float(cargo_per.get("scrap", 8.0))
		"seed":
			cap = _base_cap("seed") + cargo * float(cargo_per.get("seed", 4.0))
		"cloth":
			cap = _base_cap("cloth") + cargo * float(cargo_per.get("cloth", 5.0))
		_:
			cap = float(inv.get("unknownResourceCap", 9999.0))
	return cap * mult


## 读 RunState 上对应字段。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param key 库存或配置键（常经 normalize_key）
## @return 浮点结果（量/比率/工时）。
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


## 入库并钳 cap；返回**实际增加量**（Haul 溢出处理依赖此值）。
##
## 搬运完成、生产、事件 grant_item 等统一入库；可能因 cap 截断。
## @return 实际入库量（HaulService 用返回值把溢出写回 lootPile）。
## @param state 当前局 `RunState`（就地修改字段）
## @param key 库存或配置键（常经 normalize_key）
## @param amount 数量（float，可为小数）
static func add(state: RunState, key: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var k := normalize_key(key)
	if k == "blueprints":
		return TechService.add_blueprint_loot(state, amount)
	if not is_scalar_inventory_key(k):
		return 0.0
	var cap := stock_cap(state, k)
	var before := get_amount(state, k)
	var after := clampf(before + amount, 0.0, cap)
	var added := after - before
	_set_amount(state, k, after)
	return added


## 扣减库存；返回实际扣除量（不足则扣至 0）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param key 库存或配置键（常经 normalize_key）
## @param amount 数量（float，可为小数）
## @return 浮点结果（量/比率/工时）。
static func remove(state: RunState, key: String, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var k := normalize_key(key)
	var before := get_amount(state, k)
	var after := maxf(0.0, before - amount)
	var removed := before - after
	_set_amount(state, k, after)
	return removed


## 把当前量钳在 [0, cap]（日结或作弊恢复用）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param key 库存或配置键（常经 normalize_key）
static func clamp_resource(state: RunState, key: String) -> void:
	var k := normalize_key(key)
	_set_amount(state, k, clampf(get_amount(state, k), 0.0, stock_cap(state, k)))

## 写单资源库存并夹紧 [0, cap]；内部 add/remove 共用。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param key 库存或配置键（常经 normalize_key）
## @param value 写入库存的绝对量
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