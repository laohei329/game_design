class_name StationService
extends RefCounted
## 进站发现车厢：生成要约（offer）、接受挂车、拒绝累计保底 streak（S1a.2–3）。
##
## 数据落在 `Segment.stations[]` 字典里，UI 读 `RunState.pending_station` 快照。
##
## 保底（guarantee）：
##   - `guarantee_fail_streak` 连续拒绝/落空时 +1（教程站 `tutorialHook` 不计入）。
##   - 达到 `stations.guaranteeAfter`（balance）后下次 `generate_offer` **必出**可负担要约（`guaranteeForced`）。
##
## 日结钩子：`after_day_travel` 在停靠且列车位于车站里程时预生成 offer（不必点「进站」）。
## 手动：`ENTER_STATION` → `manual_enter`；接受/拒绝 → `resolve_offer`。


## 车厢模板展示名（`carriage.*` in ui.csv）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param template_id 车厢/威胁模板 id
## @return 空串=成功；非空=机器错误码。
static func template_label(template_id: String) -> String:
	return LocaleApi.tr_code("carriage", template_id, template_id)


## 车况展示名（`station.condition.*`）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param condition_id 车况 intact/damaged/wreck
## @return 空串=成功；非空=机器错误码。
static func condition_label(condition_id: String) -> String:
	return LocaleApi.tr_code("station.condition", condition_id, condition_id)


## stations.json 根表（池子、权重、tutorial 键）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @return 结果字典；缺失语义键时可能为空 {}。
static func stations_cfg() -> Dictionary:
	return ConfigDb.get_table("stations")


## 连续拒绝/落空多少次后触发 guaranteeForced（balance.stations.guaranteeAfter）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @return 整数结果（计数/下标/容量）。
static func guarantee_after() -> int:
	return int(
		stations_cfg().get("guaranteeAfter", ConfigDb.require("balance.stations.guaranteeAfter"))
	)


## carriages.templates 单行；缺则 {}。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param template_id 车厢/威胁模板 id
## @return 结果字典；缺失语义键时可能为空 {}。
static func carriage_template(template_id: String) -> Dictionary:
	var root: Dictionary = ConfigDb.get_table("carriages")
	var templates: Variant = root.get("templates", {})
	if typeof(templates) == TYPE_DICTIONARY:
		var row: Variant = templates.get(template_id, {})
		if typeof(row) == TYPE_DICTIONARY:
			return row
	return {}


## 挂车后日耗贡献（写入 offer.fuelPerDay，供搁置提示）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param template_id 车厢/威胁模板 id
## @return 浮点结果（量/比率/工时）。
static func fuel_per_day_add(template_id: String) -> float:
	return float(carriage_template(template_id).get("fuelPerDayAdd", 1.0))


## 列车逻辑位置 `progress_km` 是否已到达该站（±0.05 km 容差）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param seg 当前区段 `Segment`
## @param station 段内车站字典 stations[] 元素
## @return 是否成功或条件成立。
static func at_station(seg: Segment, station: Dictionary) -> bool:
	var target := float(station.get("progressKm", station.get("progress_km", 0.0)))
	return seg.progress_km >= target - 0.05


## 当前活跃段内、列车已到达且未收车的第一个站；含 segmentIndex/stationIndex。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 结果字典；缺失语义键时可能为空 {}。
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


## HUD「进站」按钮：停靠且在站里程内。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func can_manual_enter(state: RunState) -> bool:
	if state.drive_intent != "stop":
		return false
	return not find_station_at_progress(state).is_empty()


## END_DAY 链中、日结前：若停靠在车站上且未关闭弹窗，生成 offer 并写入 pending。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
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


## Intent ENTER_STATION：同 after_day_travel 的 offer 生成逻辑，强制打开 pending。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
static func manual_enter(state: RunState) -> void:
	var hit := find_station_at_progress(state)
	if hit.is_empty():
		push_warning("StationService: no station in range")
		return
	var st: Dictionary = hit.station
	if st.get("offer") == null and not st.get("visit_missed", false):
		generate_offer(state, hit.segment, st)
	state.pending_station = _pack_pending(hit)


## 随机池 + emptyChance + 零件可负担性；`forceLivingOffer` 为教程强制休息车。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param _seg（Segment）
## @param station 段内车站字典 stations[] 元素
## @return 结果字典；缺失语义键时可能为空 {}。
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


## Intent RESOLVE_OFFER。accept：扣零件 append 车厢、清零 streak、tutorial_hook→tutorial_done。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param accept 是否接受车站要约
## @return 空串=成功；非空=机器错误码。
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
		InventoryService.remove(state, "parts", float(cost))
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
		ClimateService.refresh(state)
		MemberRoster.assign_daily_jobs(state)
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


## 搁置按钮旁灰字；经 hud_hints.offerDeferCodes 转中文 UI 文案。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param offer 车站要约快照（pending_station 形状）
## @return 空串=成功；非空=机器错误码。
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
			var ui_key := str(row.get("uiKey", ""))
			if ui_key != "":
				return LocaleApi.tr_key(ui_key, code)
			return str(row.get("ui", code))
	return code


## 进站面板只读快照（索引 + offer 副本），避免 UI 直接改 segment 内 station。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param hit find_point 返回 { segment, pointIndex, point }
## @return 结果字典；缺失语义键时可能为空 {}。
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


## 写入 station.offer 的标准形状，供 UI 与 resolve_offer 读取。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param tid（String）
## @param condition（String）
## @param repair（int）
## @param guarantee_forced（bool）
## @param affordable（bool）
## @param tutorial（bool）
## @return 结果字典；缺失语义键时可能为空 {}。
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


## visit_missed=true；非 tutorialHook 时 streak+1 并 telemetry carriage_miss。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param station 段内车站字典 stations[] 元素
## @param skip_streak（bool）
## @param reason（String）
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


## 按站规模 small/medium/large 从 stations.pools 抽 templateId。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param size 车站规模 small/medium/large
## @param _force（bool）
## @return 空串=成功；非空=机器错误码。
static func _pick_from_pool(size: String, _force: bool) -> String:
	var pools: Variant = stations_cfg().get("pools", {})
	if typeof(pools) != TYPE_DICTIONARY:
		return "living"
	var pool: Variant = pools.get(size, pools.get("small", ["living"]))
	if typeof(pool) != TYPE_ARRAY or pool.is_empty():
		return "living"
	var idx := RngService.randi_range(0, pool.size() - 1)
	return str(pool[idx])


## 非保底时加权抽车况 intact/damaged/wreck。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @return 空串=成功；非空=机器错误码。
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