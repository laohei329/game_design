class_name RunState
extends RefCounted

const _PopulationRules := preload("res://scripts/domain/population_rules.gd")
## 单局内存状态（RefCounted，非 Node）。存档形状见 SaveSchema ↔ 09 §3 save 12。
##
## 字段分三类：① 可存档主干（日历/库存/列车/区段/成员）② 气候派生（日结重算）③ UI 旗标（S1b 前多不入盘）。

# --- 日历 ---
var year: int = 1
var season: String = "spring"
var day_in_season: int = 1
var day_total: int = 1

# --- 六元库存（fuel 上限见 fuel_cap）---
var parts: float = 6.0
var scrap: float = 0.0
var fuel: float = 88.0
var food: float = 20.0
var water: float = 24.0
var medicine: float = 4.0
var seed: float = 1.0
var chem: float = 0.0
var cloth: float = 0.0

# --- 列车与驾驶（03 §6）---
var drive_intent: String = "stop"  # forward | reverse | stop
var heating_enabled: bool = false
var body_hp: float = 100.0
var carriages: Array = []
var abandon_count: int = 0
var power_tech: int = 0
var armor_tech: int = 0
var radar_tech: int = 0
var living_tech: int = 0
## 图纸持有（09 train.blueprints；与 upgrades 行 blueprint 门槛对齐）。
var blueprints: Dictionary = {
	"power": false,
	"armor": false,
	"radar": false,
	"living": false,
}
var precision: float = 40.0
var morale_offset: float = 0.0
var pressure_history: Array = ["", ""]
var pressure_display: String = ""
var prefer_expansion: bool = true

# --- 当日行驶累计（日结 F04 后清零）---
var drive_hours_today: float = 0.0
var reverse_hours_today: float = 0.0
var onboard_pop: int = 4
var members: Array = []
var haul_tasks: Array = []  # 杂工搬运单（S1a 薄）

# --- 饥渴/燃油 streak（日结维护，影响士气与失败）---
var food_went_zero: bool = false
var water_went_zero: bool = false
var food_zero_streak: int = 0
var water_zero_streak: int = 0
var fuel_zero_streak: int = 0
var morale_zero_streak: int = 0
var breakdown_counter: int = 0
## 抛锚强制停靠剩余游戏小时（03 §6.3；日结 8b 置 2，随 `day_delta` 递减）。
var breakdown_stop_hours_remaining: float = 0.0

# --- 气候输入与派生（ClimateService.refresh 唯一写入乘子）---
var weather_id: String = "clear"
var region_fuel_mult: float = 1.0
var region_temp_mod: float = 0.0
var climate_influences: Array = []
var delayed_events: Array = []
var event_modal_open: bool = false
var event_weight_history: Array = []
var last_event_primary_tag: String = ""
var event_flags: Dictionary = {}
## 当日已成功收留日（06 §2.2）；`-1` 表示本局尚未收留。
var last_recruit_success_day: int = -1

var effective_temp: float = 0.0
var cold_index: float = 0.0
var heat_index: float = 0.0
var food_climate: float = 1.0
var water_climate: float = 1.0
var fuel_climate: float = 1.0
var greenhouse_climate: float = 1.0
var speed_climate: float = 1.0
var heating_applied_today: bool = false

var failed: String = ""

# --- 区段行程与玩法上下文 ---
var region_run: RegionRun = null
var guarantee_fail_streak: int = 0
var tutorial_done: bool = false
var pending_station: Dictionary = {}  # 进站面板用：当前要约/车站，薄字段
var search_tasks: Array = []

# --- 面板开关（多数仅运行时，存档子集见 SaveSchema）---
var search_panel_open: bool = false
var abandon_panel_open: bool = false
var abandon_selected_car_id: String = ""
var region_pick_open: bool = false
var region_pick_options: Array = []
var tech_panel_open: bool = false

# --- 战斗 L1（05 §6；编队入 train.formations，遭遇态多仅内存）---
var formations: Array = []  ## [{ id, name, slots:[{memberId,slotId}], reserve:[] }]
var active_formation_id: String = ""
var combat_panel_open: bool = false
var pending_combat: Dictionary = {}  ## 遭遇上下文；关面板或读档后清空
var pending_threat: Dictionary = {}  ## 延迟开战威胁模板；入 `world.pendingThreat`
var combat_l1_after_fail: bool = false  ## L1 检定失败后 UI 切「撤退/升级」行

## S1a：`balance.fuelTank`；完整百分比口径见 02 §6。
##
## RunState 实例方法；不触发日结或 Intent。
## @return 浮点结果（量/比率/工时）。
func fuel_cap() -> float:
	var cap: float = _PopulationRules.fuel_tank_base()
	var per_cargo: float = _PopulationRules.fuel_tank_per_cargo()
	for c in carriages:
		if str(c.get("templateId", "")) == "cargo":
			cap += float(c.get("size", 1)) * per_cargo
	return cap

## 当前油量占油舱比例 0~1（HUD、搁置提示）。
##
## RunState 实例方法；不触发日结或 Intent。
## @return 浮点结果（量/比率/工时）。
func fuel_fill() -> float:
	var cap := fuel_cap()
	if cap <= 0.0:
		return 0.0
	return fuel / cap

## 编组节数（遗弃 tip、车站长度提示）。
##
## RunState 实例方法；不触发日结或 Intent。
## @return 整数结果（计数/下标/容量）。
func car_count() -> int:
	return carriages.size()

## 调试/遗留：等价 SaveSchema.to_save_dict。
##
## RunState 实例方法；不触发日结或 Intent。
## @return 结果字典；缺失语义键时可能为空 {}。
func to_dict() -> Dictionary:
	return SaveSchema.to_save_dict(self)