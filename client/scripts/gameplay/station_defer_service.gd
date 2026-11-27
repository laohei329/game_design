class_name StationDeferService
extends RefCounted
## 进站「搁置」灰字原因码：读 hud_hints.json 阈值，**不阻止**拒绝 offer。
##
## `offer_defer_reason` 返回码 → StationService.offer_defer_hint → UI 文案；
## `tip_for_abandon`：油位低且车长时提示可考虑遗弃（纯提示）。

static func _hints() -> Dictionary:
	return ConfigDb.get_table("hud_hints")

## 当前油量 / 油舱容量 0~1。
##
## HUD 搁置/遗弃提示专用；不改要约结算逻辑。
## @param state 当前局 `RunState`（就地修改字段）
## @return 浮点结果（量/比率/工时）。
static func fuel_fill(state: RunState) -> float:
	return state.fuel_fill()

## 进站要约 defer 原因码（hud_hints）。
##
## 只产原因码，不阻止拒绝要约；文案经 StationService.offer_defer_hint。
## @param state 当前局 `RunState`（就地修改字段）
## @param offer 车站要约快照（pending_station 形状）
## @param prefer_expansion 玩家扩张倾向（搁置提示分支）
## @return 空串=成功；非空=机器错误码。
static func offer_defer_reason(state: RunState, offer: Dictionary, prefer_expansion: bool) -> String:
	var hints := _hints()
	var fuel_cfg: Dictionary = hints.get("fuelFill", {})
	var car_cfg: Dictionary = hints.get("carCount", {})
	var throttle: float = float(ConfigDb.require("hud_hints.fuelFill.expansionThrottle"))
	var high_burn: float = float(ConfigDb.require("hud_hints.fuelFill.highBurnOfferBlock"))
	var high_burn_fuel_min: float = float(ConfigDb.require("hud_hints.fuelFill.highBurnFuelPerDayMin"))
	var length_banner: int = int(ConfigDb.require("hud_hints.carCount.lengthBurdenBanner"))
	var ff := fuel_fill(state)
	var tid: String = str(offer.get("templateId", ""))
	var fuel_add: float = float(offer.get("fuelPerDay", offer.get("fuelAdd", 1.0)))
	if ff < throttle and tid == "armor":
		return "FUEL_TIGHT_ARMOR"
	if ff < high_burn and fuel_add >= high_burn_fuel_min:
		return "FUEL_TIGHT_HIGH_BURN"
	if prefer_expansion and ff < throttle and state.car_count() >= length_banner:
		var allow: Array = hints.get("whitelistWhenLongTrainTight", [])
		if tid not in allow:
			return "LENGTH_WHITELIST"
	return ""

## 遗弃面板 fuel-fill 相关 tip 键。
##
## HUD 搁置/遗弃提示专用；不改要约结算逻辑。
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func tip_for_abandon(state: RunState) -> bool:
	var ab: Dictionary = _hints().get("abandonCarriage", {})
	var ff_max: float = float(ab.get("fuelFillSuggestMax", 0.35))
	var min_cars: int = int(ab.get("minCarsForTip", 12))
	return state.fuel_fill() <= ff_max and state.car_count() >= min_cars and state.drive_intent == "stop"