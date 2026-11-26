class_name StationDeferService
extends RefCounted
## Reads hud_hints.json defer thresholds (08 §4 · S1a).

static func _hints() -> Dictionary:
	return ConfigDb.get_table("hud_hints")


static func fuel_fill(state: RunState) -> float:
	return state.fuel_fill()


static func offer_defer_reason(state: RunState, offer: Dictionary, prefer_expansion: bool) -> String:
	var hints := _hints()
	var fuel_cfg: Dictionary = hints.get("fuelFill", {})
	var car_cfg: Dictionary = hints.get("carCount", {})
	var throttle: float = float(fuel_cfg.get("expansionThrottle", 0.55))
	var high_burn: float = float(fuel_cfg.get("highBurnOfferBlock", 0.28))
	var length_banner: int = int(car_cfg.get("lengthBurdenBanner", 12))
	var ff := fuel_fill(state)
	var tid: String = str(offer.get("templateId", ""))
	var fuel_add: float = float(offer.get("fuelPerDay", offer.get("fuelAdd", 1.0)))
	if ff < throttle and tid == "armor":
		return "FUEL_TIGHT_ARMOR"
	if ff < high_burn and fuel_add >= 2.0:
		return "FUEL_TIGHT_HIGH_BURN"
	if prefer_expansion and ff < throttle and state.car_count() >= length_banner:
		var allow: Array = hints.get("whitelistWhenLongTrainTight", [])
		if tid not in allow:
			return "LENGTH_WHITELIST"
	return ""


static func tip_for_abandon(state: RunState) -> bool:
	var ab: Dictionary = _hints().get("abandonCarriage", {})
	var ff_max: float = float(ab.get("fuelFillSuggestMax", 0.35))
	var min_cars: int = int(ab.get("minCarsForTip", 12))
	return state.fuel_fill() <= ff_max and state.car_count() >= min_cars and state.drive_intent == "stop"