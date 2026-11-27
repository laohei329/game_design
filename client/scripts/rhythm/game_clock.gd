class_name GameClock
extends RefCounted
## 日历钟（01 §2）：**一切随时间变的系统的共同基底**（`day_delta` = 流逝的游戏日份额 0~1）。
##
## `GameSession._process` 将真实 `delta` 换为 `day_delta`，再分发给驾驶 / 饥渴 / 搜索 / 搬运等 tick。

## 1 游戏日对应的真实秒数（`balance.time.secondsPerDay`，默认 180）。
static func seconds_per_day() -> float:
	var t: Variant = ConfigDb.require("balance.time")
	if typeof(t) != TYPE_DICTIONARY:
		return 180.0
	return maxf(1.0, float(t.get("secondsPerDay", 180.0)))


## 真实秒 × 倍速 → 游戏日份额。
static func day_delta_from_real_seconds(real_seconds: float, speed_mult: float = 1.0) -> float:
	if real_seconds <= 0.0 or speed_mult <= 0.0:
		return 0.0
	return real_seconds * speed_mult / seconds_per_day()


## 饥渴上升 / 咬粮咬水 tick 倍率：`stop` 车上活动多，`forward` 行进略缓。
static func metabolism_mult(state: RunState) -> float:
	var t: Dictionary = ConfigDb.require("balance.time") if typeof(ConfigDb.require("balance.time")) == TYPE_DICTIONARY else {}
	var table: Variant = t.get("metabolismMultByIntent", {})
	if typeof(table) != TYPE_DICTIONARY:
		table = {"stop": 1.35, "forward": 0.55, "reverse": 0.75}
	var intent := str(state.drive_intent)
	var v: Variant = table.get(intent, 1.0)
	return maxf(0.05, float(v))


## 车外搜索/搬运工时是否随日钟推进（默认仅 `stop`）。
static func outdoor_work_active(state: RunState) -> bool:
	var t: Dictionary = ConfigDb.require("balance.time") if typeof(ConfigDb.require("balance.time")) == TYPE_DICTIONARY else {}
	var need := str(t.get("outdoorWorkRequiresIntent", "stop"))
	return str(state.drive_intent) == need


## 本游戏日日历份额 / 可户外份额 / 已由户外 tick 消费份额（日界归零）。
static var _sim_day_fraction_today: float = 0.0
static var _outdoor_eligible_fraction_today: float = 0.0
static var _outdoor_tick_fraction_today: float = 0.0


static func accrue_sim_day_fraction(day_delta: float) -> void:
	if day_delta > 0.0:
		_sim_day_fraction_today += day_delta


static func accrue_outdoor_eligible_fraction(day_delta: float) -> void:
	if day_delta > 0.0:
		_outdoor_eligible_fraction_today += day_delta


static func accrue_outdoor_tick_fraction(day_delta: float) -> void:
	if day_delta > 0.0:
		_outdoor_tick_fraction_today += day_delta


static func sim_day_fraction_today() -> float:
	return _sim_day_fraction_today


static func outdoor_eligible_fraction_today() -> float:
	return _outdoor_eligible_fraction_today


static func outdoor_tick_fraction_today() -> float:
	return _outdoor_tick_fraction_today


## 户外任务 tick 公共前缀：已记 `outdoor_tick` 返回 true。
static func begin_outdoor_work_tick(state: RunState, day_delta: float) -> bool:
	if day_delta <= 0.0 or state.failed != "":
		return false
	if not outdoor_work_active(state):
		return false
	accrue_outdoor_tick_fraction(day_delta)
	return true


## 日末补课折算游戏小时（`hoursPerDay` × rem 份额）。
static func outdoor_end_day_hours(hours_per_calendar_day: float) -> float:
	var rem := outdoor_end_day_reconcile_fraction()
	if rem <= 0.0001:
		return 0.0
	return hours_per_calendar_day * rem


## 户外日末补课：无日钟（sim≈0）→1 日；否则 max(0, 停靠份额−已 tick 份额)，与 forward 全日无关。
static func outdoor_end_day_reconcile_fraction() -> float:
	if _sim_day_fraction_today < 0.001:
		return 1.0
	return maxf(0.0, _outdoor_eligible_fraction_today - _outdoor_tick_fraction_today)


static func reset_sim_day_fraction() -> void:
	_sim_day_fraction_today = 0.0
	_outdoor_eligible_fraction_today = 0.0
	_outdoor_tick_fraction_today = 0.0


static var _pending_hud_fraction: float = -1.0


## 读档：`runtime` 日钟字段 → 静态份额；HUD 分数由 `take_restored_hud_fraction` 交给 GameSession。
static func restore_from_runtime(rt: Dictionary) -> void:
	if typeof(rt) != TYPE_DICTIONARY:
		reset_sim_day_fraction()
		_pending_hud_fraction = 0.0
		return
	if rt.has("dayClockFraction") or rt.has("simDayFractionToday"):
		_sim_day_fraction_today = clampf(float(rt.get("simDayFractionToday", 0)), 0.0, 1.0)
		_outdoor_eligible_fraction_today = clampf(
			float(rt.get("outdoorEligibleFractionToday", 0)), 0.0, 1.0
		)
		_outdoor_tick_fraction_today = clampf(float(rt.get("outdoorTickFractionToday", 0)), 0.0, 1.0)
		_pending_hud_fraction = clampf(
			float(rt.get("dayClockFraction", _sim_day_fraction_today)), 0.0, 1.0
		)
	else:
		reset_sim_day_fraction()
		_pending_hud_fraction = 0.0


## 读档后 GameSession 设置 `day_clock_fraction`（只读一次）。
static func take_restored_hud_fraction() -> float:
	var v := _pending_hud_fraction
	_pending_hud_fraction = -1.0
	if v < 0.0:
		return 0.0
	return v


## 合法倍速档（0=冻结 UI 用手动暂停）。
static func speed_choices() -> Array:
	return [1.0, 2.0, 4.0]