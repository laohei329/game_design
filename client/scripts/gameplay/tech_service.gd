class_name TechService
extends RefCounted
## 四线科技 power/armor/radar/living：`BUY_UPGRADE` → 扣零件/精度门槛 → level+1。
##
## `living_bed_bonus` 已接 TrainService.bed_count；牵引等战斗向加成预留 S1b+。
## 配置：`upgrades.json` levels[] + precisionGate[]。


## 科技线展示名（`tech.line.*`）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param line 科技线 power|armor|radar|living
## @return 空串=成功；非空=机器错误码。
static func line_label(line: String) -> String:
	return LocaleApi.tr_code("tech.line", line, line)


## upgrades.levels：每级消耗行（parts/medicine/catalyst/fuel%/blueprint）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @return 数组结果（列表/选项）。
static func levels_table() -> Array:
	var root: Dictionary = ConfigDb.get_table("upgrades")
	var lv: Variant = root.get("levels", [])
	return lv if typeof(lv) == TYPE_ARRAY else []


## upgrades.precisionGate：升到第 N 级所需最低 workshop precision。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @return 数组结果（列表/选项）。
static func precision_gates() -> Array:
	var root: Dictionary = ConfigDb.get_table("upgrades")
	var g: Variant = root.get("precisionGate", [])
	return g if typeof(g) == TYPE_ARRAY else []


## 读 state 上 power_tech / armor_tech / radar_tech / living_tech。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param line 科技线 power|armor|radar|living
## @return 整数结果（计数/下标/容量）。
static func tech_level(state: RunState, line: String) -> int:
	match line:
		"power":
			return state.power_tech
		"armor":
			return state.armor_tech
		"radar":
			return state.radar_tech
		"living":
			return state.living_tech
		_:
			return 0


## 写回对应科技等级字段。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param line 科技线 power|armor|radar|living
## @param value 写入库存的绝对量
static func set_tech_level(state: RunState, line: String, value: int) -> void:
	match line:
		"power":
			state.power_tech = value
		"armor":
			state.armor_tech = value
		"radar":
			state.radar_tech = value
		"living":
			state.living_tech = value


## 即将购买的目标等级（当前+1）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param line 科技线 power|armor|radar|living
## @return 整数结果（计数/下标/容量）。
static func next_level(state: RunState, line: String) -> int:
	return tech_level(state, line) + 1


## levels[target_lv-1] 消耗行；越界 {}。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param target_lv 目标科技等级（1-based）
## @return 结果字典；缺失语义键时可能为空 {}。
static func level_row(target_lv: int) -> Dictionary:
	var rows := levels_table()
	if target_lv < 1 or target_lv > rows.size():
		return {}
	var row: Variant = rows[target_lv - 1]
	return row if typeof(row) == TYPE_DICTIONARY else {}


## 升到 target_lv 需要的 precision 下限。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param target_lv 目标科技等级（1-based）
## @return 浮点结果（量/比率/工时）。
static func precision_required(target_lv: int) -> float:
	var gates := precision_gates()
	if target_lv < 1 or target_lv > gates.size():
		return 0.0
	return float(gates[target_lv - 1])


## 返回空=可买；否则 `tech.err.*` 错误码（GameSession warning）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param line 科技线 power|armor|radar|living
## @return 空串=允许；非空=阻断原因码。
static func can_buy(state: RunState, line: String) -> String:
	var lines: Variant = ConfigDb.get_table("upgrades").get("lines", [])
	if typeof(lines) == TYPE_ARRAY and not (line in lines):
		return "invalid_line"
	var cur := tech_level(state, line)
	var max_lv := int(ConfigDb.get_table("upgrades").get("stageZeroSmokeMaxLv", 5))
	if cur >= max_lv:
		return "max_level"
	var target := cur + 1
	var row := level_row(target)
	if row.is_empty():
		return "no_row"
	if state.precision < precision_required(target):
		return "precision"
	if bool(row.get("blueprint", false)) and not bool(state.blueprints.get(line, false)):
		return "blueprint"
	var parts_need := float(row.get("parts", 0))
	if state.parts < parts_need:
		return "parts"
	var med_need := float(row.get("medicine", 0))
	if state.medicine < med_need:
		return "medicine"
	var cat_need := float(row.get("catalyst", 0))
	if state.chem < cat_need:
		return "catalyst"
	var fuel_pct := float(row.get("fuel", 0.0))
	if fuel_pct > 0.0:
		var fuel_need := state.fuel_cap() * fuel_pct / 100.0
		if state.fuel < fuel_need:
			return "fuel"
	if state.drive_intent != "stop":
		return "must_stop"
	return ""


## Intent BUY_UPGRADE；扣资源后 level+1 并 ClimateService.refresh（radar 影响能见度等）。
##
## Intent `BUY_UPGRADE` 写入口；成功可能触发 ClimateService.refresh。
## @param state 当前局 `RunState`（就地修改字段）
## @param line 科技线 power|armor|radar|living
## @return 空串=成功；非空=机器错误码。
static func buy_upgrade(state: RunState, line: String) -> String:
	var err := can_buy(state, line)
	if err != "":
		return err
	var target := next_level(state, line)
	var row := level_row(target)
	var parts_need := float(row.get("parts", 0))
	var med_need := float(row.get("medicine", 0))
	var cat_need := float(row.get("catalyst", 0))
	var fuel_pct := float(row.get("fuel", 0.0))
	InventoryService.remove(state, "parts", parts_need)
	InventoryService.remove(state, "medicine", med_need)
	InventoryService.remove(state, "chem", cat_need)
	if fuel_pct > 0.0:
		InventoryService.remove(state, "fuel", state.fuel_cap() * fuel_pct / 100.0)
	set_tech_level(state, line, target)
	ClimateService.refresh(state)
	return ""


## radar 科技累加能见度：visionBase + visionPerLevel × radar_tech。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 整数结果（计数/下标/容量）。
static func effective_vision(state: RunState) -> int:
	var base := int(ConfigDb.require("balance.radar.visionBase"))
	var per := int(ConfigDb.require("balance.radar.visionPerLevel"))
	return base + per * state.radar_tech


## 生活线每级 +2 床位（TrainService.bed_count 调用）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 整数结果（计数/下标/容量）。
static func living_bed_bonus(state: RunState) -> int:
	return state.living_tech * 2


const BLUEPRINT_LINES: PackedStringArray = ["power", "armor", "radar", "living"]


## 授予单线图纸；重复持有返回 false。
static func grant_blueprint(state: RunState, line: String) -> bool:
	var lid := str(line).to_lower()
	if lid not in BLUEPRINT_LINES:
		return false
	if bool(state.blueprints.get(lid, false)):
		return false
	state.blueprints[lid] = true
	TelemetryService.record("blueprint_grant", {"line": lid})
	return true


## 堆键 `blueprints` 入库：按件数授予尚未持有的线（顺序 power→living）。
static func add_blueprint_loot(state: RunState, amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var want := int(floorf(amount + 0.0001))
	var granted := 0.0
	for _i in want:
		var line := _next_blueprint_line(state)
		if line == "":
			break
		if grant_blueprint(state, line):
			granted += 1.0
	return granted


static func _next_blueprint_line(state: RunState) -> String:
	for line in BLUEPRINT_LINES:
		if not bool(state.blueprints.get(line, false)):
			return line
	return ""