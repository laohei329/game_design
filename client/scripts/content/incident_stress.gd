class_name IncidentStress
extends RefCounted
## 局内应力快照（incident 触发谓词输入）。


static func build_snapshot(state: RunState, segment: Segment = null) -> Dictionary:
	var rules := ConfigDb.get_table("event_draw_rules")
	var onboard := TrainService.onboard_count(state)
	var fpc := float(ConfigDb.require("event_draw_rules.foodNeedPerCapita"))
	var wpc := float(ConfigDb.require("event_draw_rules.waterNeedPerCapita"))
	var seg_ref: Segment = segment
	if seg_ref == null and state.region_run:
		seg_ref = state.region_run.active_segment()
	var unclaimed := false
	if seg_ref != null:
		unclaimed = _has_unclaimed_loot(seg_ref)
	var fuel_cap := maxf(state.fuel_cap(), 1.0)
	var fuel_fill := state.fuel / fuel_cap if fuel_cap > 0.0 else 1.0
	return {
		"food": state.food,
		"water": state.water,
		"food_need": float(onboard) * fpc,
		"water_need": float(onboard) * wpc,
		"onboard": onboard,
		"beds": TrainService.bed_count(state),
		"fuel": state.fuel,
		"fuel_cap": fuel_cap,
		"fuel_fill": fuel_fill,
		"day_total": state.day_total,
		"last_recruit_success_day": state.last_recruit_success_day,
		"unclaimed_loot": unclaimed,
		"guard_on_duty": MemberRoster.staff_on_duty(state, "guard"),
		"forced_low_content": _forced_low_content(state),
		"scenario_event_rate": EventDraw.scenario_event_rate(),
	}


static func predicate_met(pred_id: String, snap: Dictionary) -> bool:
	var root: Dictionary = ConfigDb.get_table("stress")
	var preds: Variant = root.get("predicates", {})
	if typeof(preds) != TYPE_DICTIONARY:
		return false
	var row: Variant = preds.get(pred_id, null)
	if typeof(row) != TYPE_DICTIONARY:
		return false
	var signal_name := str(row.get("signal", ""))
	var cmp := str(row.get("compare", ""))
	match signal_name:
		"food":
			var need := float(snap.get("food_need", 0.0))
			if cmp == "lt":
				return float(snap.get("food", 0.0)) < need
		"water":
			var need_w := float(snap.get("water_need", 0.0))
			if cmp == "lt":
				return float(snap.get("water", 0.0)) < need_w
		"onboard":
			var beds := int(snap.get("beds", 0))
			var ob := int(snap.get("onboard", 0))
			if str(row.get("extra", "")) == "onboard_lt_beds":
				if float(snap.get("food", 0.0)) >= float(snap.get("food_need", 0.0)):
					return false
				return ob < beds
			var min_b := int(row.get("minBeds", 0))
			if cmp == "gte" and min_b > 0:
				return ob >= beds and beds >= min_b
			if cmp == "lt":
				return ob < beds
		"unclaimed_loot":
			return bool(snap.get("unclaimed_loot", false)) == bool(row.get("value", true))
		"guard_on_duty":
			return bool(snap.get("guard_on_duty", false)) == bool(row.get("value", true))
		"forced_low_content":
			return bool(snap.get("forced_low_content", false)) == bool(row.get("value", true))
		"fuel_fill":
			var thr := float(row.get("value", 0.35))
			if cmp == "lt":
				return float(snap.get("fuel_fill", 1.0)) < thr
		"day_end_recruit":
			var ob := int(snap.get("onboard", 0))
			var beds := int(snap.get("beds", 0))
			if ob >= beds:
				return false
			return int(snap.get("last_recruit_success_day", -1)) != int(snap.get("day_total", 0))
	return false


static func _forced_low_content(state: RunState) -> bool:
	var ph := state.pressure_history
	if ph.size() < 2:
		return false
	return str(ph[0]) == "high" and str(ph[1]) == "high"


static func _has_unclaimed_loot(segment: Segment) -> bool:
	for pt in segment.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		if LootPileService.total_amount(pt) > 0.001:
			return true
	return false