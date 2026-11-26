class_name StationService
extends RefCounted
## 03 §5 · 06 §1.1 进站要约与 guaranteeFailStreak（S1a.2–3）


const TEMPLATE_ZH := {
	"power": "动力",
	"living": "休息",
	"cargo": "货舱",
	"greenhouse": "种植",
	"water": "净水",
	"workshop": "工坊",
	"medical": "医疗",
	"radar": "雷达",
	"armor": "装甲",
	"shell": "空壳",
}

const CONDITION_ZH := {
	"intact": "完好",
	"damaged": "受损",
	"wreck": "残骸",
}


static func stations_cfg() -> Dictionary:
	return ConfigDb.get_table("stations")


static func guarantee_after() -> int:
	return int(
		stations_cfg().get("guaranteeAfter", ConfigDb.require("balance.stations.guaranteeAfter"))
	)


static func carriage_template(template_id: String) -> Dictionary:
	var root: Dictionary = ConfigDb.get_table("carriages")
	var templates: Variant = root.get("templates", {})
	if typeof(templates) == TYPE_DICTIONARY:
		var row: Variant = templates.get(template_id, {})
		if typeof(row) == TYPE_DICTIONARY:
			return row
	return {}


static func fuel_per_day_add(template_id: String) -> float:
	return float(carriage_template(template_id).get("fuelPerDayAdd", 1.0))


static func at_station(seg: Segment, station: Dictionary) -> bool:
	var target := float(station.get("progressKm", station.get("progress_km", 0.0)))
	return seg.progress_km >= target - 0.05


static func find_station_at_progress(state: RunState) -> Dictionary:
	if state.region_run == null:
		return {}
	var seg_idx := state.region_run.segment_index
	var seg := state.region_run.active_segment()
	if seg == null:
		return {}
	for i in seg.stations.size():
		var st: Dictionary = seg.stations[i]
		if st.get("carriage_received", false):
			continue
		if at_station(seg, st):
			return {"segmentIndex": seg_idx, "stationIndex": i, "station": st, "segment": seg}
	return {}


static func can_manual_enter(state: RunState) -> bool:
	if state.drive_intent != "stop":
		return false
	return not find_station_at_progress(state).is_empty()


static func after_day_travel(state: RunState) -> void:
	if state.drive_intent != "stop":
		return
	var hit := find_station_at_progress(state)
	if hit.is_empty():
		return
	var st: Dictionary = hit.station
	if st.get("popup_dismissed", false):
		return
	if st.get("carriage_received", false):
		return
	if st.get("offer") == null and not st.get("visit_missed", false):
		generate_offer(state, hit.segment, st)
	state.pending_station = _pack_pending(hit)


static func manual_enter(state: RunState) -> void:
	var hit := find_station_at_progress(state)
	if hit.is_empty():
		push_warning("StationService: no station in range")
		return
	var st: Dictionary = hit.station
	if st.get("offer") == null and not st.get("visit_missed", false):
		generate_offer(state, hit.segment, st)
	state.pending_station = _pack_pending(hit)


static func generate_offer(state: RunState, _seg: Segment, station: Dictionary) -> Dictionary:
	if typeof(station.get("offer")) == TYPE_DICTIONARY and not station.offer.is_empty():
		return station.offer

	var skip_streak := bool(station.get("tutorialHook", false))

	if bool(station.get("forceLivingOffer", false)):
		var cost := int(station.get("livingRepairCost", stations_cfg().get("tutorialLivingRepairCost", 1)))
		station.offer = _make_offer("living", "damaged", cost, false, state.parts >= cost, true)
		return station.offer

	if station.get("nonePool", station.get("none_pool", false)) or station.get("hasPool", true) == false:
		_record_miss(state, station, skip_streak, "no_pool")
		return {}

	var cfg := stations_cfg()
	var force := state.guarantee_fail_streak >= guarantee_after()
	var found := force
	if not found:
		found = RngService.randf() < float(cfg.get("poolOfferChance", 0.9))
	if not found and RngService.randf() < float(cfg.get("emptyChance", 0.1)):
		_record_miss(state, station, skip_streak, "empty_roll")
		return {}
	if not found:
		_record_miss(state, station, skip_streak, "no_offer")
		return {}

	var size := str(station.get("size", "small"))
	var tid := _pick_from_pool(size, force)
	var condition := "damaged" if force else _pick_condition()
	var base_repair := TrainService.repair_cost(tid)
	var repair := base_repair
	if force:
		repair = mini(base_repair, maxi(1, int(state.parts)))
	if state.parts < repair and not force:
		_record_miss(state, station, skip_streak, "unaffordable")
		return {}
	station.offer = _make_offer(tid, condition, repair, force, state.parts >= repair, false)
	return station.offer


static func resolve_offer(state: RunState, accept: bool) -> String:
	var pending: Dictionary = state.pending_station
	if pending.is_empty():
		return "no_pending"
	var seg_idx := int(pending.get("segmentIndex", -1))
	var st_idx := int(pending.get("stationIndex", -1))
	if state.region_run == null or seg_idx < 0:
		return "no_run"
	if seg_idx >= state.region_run.segments.size():
		return "bad_segment"
	var seg_var: Variant = state.region_run.segments[seg_idx]
	if not (seg_var is Segment):
		return "bad_segment"
	var seg := seg_var as Segment
	if st_idx < 0 or st_idx >= seg.stations.size():
		return "bad_station"
	var station: Dictionary = seg.stations[st_idx]
	var offer: Variant = station.get("offer")
	var skip_streak := bool(station.get("tutorialHook", false))

	if accept:
		if typeof(offer) != TYPE_DICTIONARY or offer.is_empty():
			return "no_offer"
		var cost := int(offer.get("repairCost", 99))
		if state.parts < cost:
			return "parts"
		var tid := str(offer.get("templateId", ""))
		state.parts -= float(cost)
		var tmpl := carriage_template(tid)
		var car_id := "car_%s_%d" % [tid, state.carriages.size()]
		state.carriages.append(
			{
				"id": car_id,
				"templateId": tid,
				"size": int(tmpl.get("size", 2)),
			}
		)
		station.carriage_received = true
		station.offer = null
		station.popup_dismissed = true
		state.guarantee_fail_streak = 0
		if skip_streak:
			state.tutorial_done = true
		ClimateService.recompute(state)
		TelemetryService.record(
			"carriage_hung",
			{
				"dayTotal": state.day_total,
				"templateId": tid,
				"repairCost": cost,
				"fuelAdd": fuel_per_day_add(tid),
				"guaranteeForced": bool(offer.get("guaranteeForced", false)),
				"tutorial": skip_streak,
			}
		)
	else:
		if typeof(offer) != TYPE_DICTIONARY or offer.is_empty():
			station.popup_dismissed = true
			state.pending_station = {}
			return ""
		var guaranteed := bool(offer.get("guaranteeForced", false))
		if not skip_streak and not guaranteed:
			state.guarantee_fail_streak += 1
		station.popup_dismissed = true
		TelemetryService.record(
			"carriage_offer_defer",
			{
				"dayTotal": state.day_total,
				"templateId": str(offer.get("templateId", "")) if typeof(offer) == TYPE_DICTIONARY else "",
				"guaranteeStreak": state.guarantee_fail_streak,
			}
		)

	state.pending_station = {}
	return ""


static func offer_defer_hint(state: RunState, offer: Dictionary) -> String:
	if offer.is_empty():
		return ""
	var code := StationDeferService.offer_defer_reason(state, offer, state.prefer_expansion)
	if code == "":
		return ""
	var hints := ConfigDb.get_table("hud_hints")
	var codes: Variant = hints.get("offerDeferCodes", {})
	if typeof(codes) == TYPE_DICTIONARY:
		var row: Variant = codes.get(code, {})
		if typeof(row) == TYPE_DICTIONARY:
			var ui: String = str(row.get("ui", code))
			return ui
	return code


static func _pack_pending(hit: Dictionary) -> Dictionary:
	var st: Dictionary = hit.station
	var offer: Variant = st.get("offer")
	return {
		"segmentIndex": hit.segmentIndex,
		"stationIndex": hit.stationIndex,
		"stationId": str(st.get("id", "")),
		"size": str(st.get("size", "small")),
		"miss": bool(st.get("visit_missed", false)),
		"missReason": str(st.get("miss_reason", "")),
		"offer": offer.duplicate(true) if typeof(offer) == TYPE_DICTIONARY else {},
	}


static func _make_offer(
	tid: String,
	condition: String,
	repair: int,
	guarantee_forced: bool,
	affordable: bool,
	tutorial: bool
) -> Dictionary:
	return {
		"templateId": tid,
		"condition": condition,
		"repairCost": repair,
		"fuelPerDay": fuel_per_day_add(tid),
		"guaranteeForced": guarantee_forced,
		"affordable": affordable,
		"tutorial": tutorial,
	}


static func _record_miss(state: RunState, station: Dictionary, skip_streak: bool, reason: String) -> void:
	station.visit_missed = true
	station.miss_reason = reason
	station.offer = null
	if not skip_streak:
		state.guarantee_fail_streak += 1
	TelemetryService.record(
		"carriage_miss",
		{"dayTotal": state.day_total, "reason": reason, "streak": state.guarantee_fail_streak}
	)


static func _pick_from_pool(size: String, _force: bool) -> String:
	var pools: Variant = stations_cfg().get("pools", {})
	if typeof(pools) != TYPE_DICTIONARY:
		return "living"
	var pool: Variant = pools.get(size, pools.get("small", ["living"]))
	if typeof(pool) != TYPE_ARRAY or pool.is_empty():
		return "living"
	var idx := RngService.randi_range(0, pool.size() - 1)
	return str(pool[idx])


static func _pick_condition() -> String:
	var weights: Variant = stations_cfg().get("conditionWeights", {"intact": 0.15, "damaged": 0.6, "wreck": 0.25})
	if typeof(weights) != TYPE_DICTIONARY:
		return "damaged"
	var keys: Array = []
	var w: Array = []
	for k in weights.keys():
		keys.append(str(k))
		w.append(float(weights[k]))
	var total := 0.0
	for x in w:
		total += x
	if total <= 0.0:
		return "damaged"
	var r := RngService.randf() * total
	var acc := 0.0
	for i in keys.size():
		acc += float(w[i])
		if r <= acc:
			return keys[i]
	return keys[keys.size() - 1]