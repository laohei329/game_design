class_name RegionService
extends RefCounted
## 区域跨度 RegionRun：教程开局、段生成、段末 **三选一**、选区后重建行程。
##
## 生命周期：
##   1. `start_tutorial` / `begin_region_run`：写 regionFuelMult、掷 segmentCount(3–5)、建 segments。
##   2. 前进日结：`DriveService` 加满本日 km → 段末 `after_travel_day`。
##   3. 末段走完：`open_region_pick`（3 个 regionId + 线索）；`pick_region` 清旧要约并开始新跨度。
##
## 三选一线索：`regions.pickClues[]` 多语块（Mod 可覆写 regions.json）。


## regions.json 全部 regionId，排序后供三选一抽样。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @return 字符串数组。
static func all_region_ids() -> PackedStringArray:
	var root: Dictionary = ConfigDb.get_table("regions")
	var regions: Variant = root.get("regions", {})
	var out: PackedStringArray = []
	if typeof(regions) == TYPE_DICTIONARY:
		for k in regions.keys():
			out.append(str(k))
	out.sort()
	return out


## 单区配置行：regionFuelMult、pointTypeWeightMods、name.zh 等。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param region_id `regions.json` 的 regionId
## @return 结果字典；缺失语义键时可能为空 {}。
static func region_def(region_id: String) -> Dictionary:
	var root: Dictionary = ConfigDb.get_table("regions")
	var regions: Variant = root.get("regions", {})
	if typeof(regions) != TYPE_DICTIONARY:
		return {}
	var row: Variant = regions.get(region_id, {})
	return row if typeof(row) == TYPE_DICTIONARY else {}


## 三选一 UI 标题；读 regions.name 多语块 + LocaleApi.locale_id。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param region_id `regions.json` 的 regionId
## @return 空串=成功；非空=机器错误码。
static func region_display_name(region_id: String) -> String:
	var row := region_def(region_id)
	var names: Variant = row.get("name", {})
	return LocaleApi.from_locale_block(names, region_id)


## 三选一卡片线索行（本地化字符串数组）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param region_id `regions.json` 的 regionId
## @return 字符串数组。
static func region_pick_clues(region_id: String) -> PackedStringArray:
	var row := region_def(region_id)
	var raw: Variant = row.get("pickClues", [])
	var out: PackedStringArray = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for block in raw:
		var line := LocaleApi.from_locale_block(block, "")
		if line != "":
			out.append(line)
	return out


## NEW_RUN：tutorialRegion、单段、强制 tutorial 站与点位，segment_count 逻辑上为 3。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
static func start_tutorial(state: RunState) -> void:
	var stations_cfg: Dictionary = ConfigDb.get_table("stations")
	var region_id := str(
		stations_cfg.get("tutorialRegion", ConfigDb.require("balance.stations.tutorialRegion"))
	)
	_apply_region_factors(state, region_id)

	var run := RegionRun.new()
	run.region_id = region_id
	run.segment_count = 3
	run.segment_index = 0
	run.region_fuel_mult = _region_fuel_mult_for(region_id)
	run.point_type_weight_mods = _region_point_mods(region_id)
	var seg := _build_tutorial_segment_0(stations_cfg)
	seg.built = true
	run.segments = [seg]
	state.region_run = run
	WeatherDraw.on_segment_build(state, seg)


## 不重复随机 regionId，最多 count 项（默认三选一）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param count 抽样个数
## @return 数组结果（列表/选项）。
static func roll_pick_options(state: RunState, count: int = 3) -> Array:
	var pool := all_region_ids()
	if pool.is_empty():
		return []
	count = mini(count, pool.size())
	var picked: Array = []
	var tries := 0
	while picked.size() < count and tries < 32:
		tries += 1
		var id := str(pool[RngService.randi() % pool.size()])
		if id in picked:
			continue
		picked.append(id)
	return picked


## 段末触发：强停、填 region_pick_options、开面板。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
static func open_region_pick(state: RunState) -> void:
	state.drive_intent = "stop"
	state.region_pick_options = roll_pick_options(state, 3)
	state.region_pick_open = true


## 选区后清空 pending_station / streak，再 `begin_region_run`（新跨度清除上一跨度车站 offer）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param region_id `regions.json` 的 regionId
## @return 空串=成功；非空=机器错误码。
static func pick_region(state: RunState, region_id: String) -> String:
	if region_id.is_empty():
		return "missing_id"
	if not region_def(region_id):
		return "unknown_region"
	_close_region_pick(state)
	_clear_station_offers(state)
	begin_region_run(state, region_id)
	return ""


## 新跨度：区域因子 + 掷段数 + 仅构建第 0 段（其余懒加载）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param region_id `regions.json` 的 regionId
static func begin_region_run(state: RunState, region_id: String) -> void:
	_apply_region_factors(state, region_id)
	var seg_n := _roll_segment_count()
	var run := RegionRun.new()
	run.region_id = region_id
	run.segment_count = seg_n
	run.segment_index = 0
	run.region_fuel_mult = _region_fuel_mult_for(region_id)
	run.point_type_weight_mods = _region_point_mods(region_id)
	run.segments = []
	state.region_run = run
	_ensure_segment_built(state, 0)


## 段内进度到达 length_km：非末段则 index+1 并 build；末段则弹三选一（须 tutorial_done）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
static func after_travel_day(state: RunState) -> void:
	if state.region_pick_open:
		return
	if not state.tutorial_done:
		return
	if state.region_run == null or state.drive_intent != "forward":
		return
	var seg := state.region_run.active_segment()
	if seg == null:
		return
	if seg.progress_km < seg.length_km - 0.05:
		return
	_on_reach_segment_end(state)


## 返程跨段：过期段内影响、切换 segment_index 并懒建目标段（与前进段末对称）。
##
## 模块内部实现；`DriveService._apply_reverse_km` 在 index 变化时调用。
## @param state 当前局 `RunState`（就地修改字段）
## @param new_index 目标段下标
static func apply_reverse_segment_index(state: RunState, new_index: int) -> void:
	var rr: RegionRun = state.region_run
	if rr == null or new_index < 0 or new_index >= rr.segment_count:
		return
	if rr.segment_index == new_index:
		return
	EventOps.expire_segment_influences(state)
	rr.segment_index = new_index
	_ensure_segment_built(state, new_index)


## 段末分支：末段 open_region_pick，否则 segment_index++ 并重置 progress_km。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
static func _on_reach_segment_end(state: RunState) -> void:
	var rr: RegionRun = state.region_run
	if rr.segment_index >= rr.segment_count - 1:
		open_region_pick(state)
		return
	EventOps.expire_segment_influences(state)
	rr.segment_index += 1
	var seg := _ensure_segment_built(state, rr.segment_index)
	if seg:
		seg.progress_km = 0.0

## 段末/三选一后懒建下一段并 build。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
static func enter_active_segment_if_needed(state: RunState) -> void:
	if state.region_run == null:
		return
	_ensure_segment_built(state, state.region_run.segment_index)


## onSegmentBuild 薄实现：压力档、搜索点、段天气。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param segment 区段 `Segment`
static func build_segment(state: RunState, segment: Segment) -> void:
	if segment == null:
		return
	if segment.built:
		return
	segment.built = true
	segment.pressure_class = _roll_pressure_class()
	_push_pressure_history(state, segment.pressure_class)
	_roll_points_for_segment(state, segment)
	WeatherDraw.on_segment_build(state, segment)
	IncidentDirector.on_segment_build(state, segment)


## 步骤 8：只读刷新；不重抽事件（06 §8）
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
static func refresh_pressure_cache(state: RunState) -> void:
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg and not seg.pressure_class.is_empty():
		state.pressure_display = seg.pressure_class
	else:
		state.pressure_display = str(state.pressure_history.back()) if not state.pressure_history.is_empty() else ""


## 关闭三选一面板并清空 region_pick_options。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
static func _close_region_pick(state: RunState) -> void:
	state.region_pick_open = false
	state.region_pick_options.clear()


## 新跨度开始：清 pending_station、guarantee streak（06 §1 跨度清要约）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
static func _clear_station_offers(state: RunState) -> void:
	state.pending_station.clear()
	state.guarantee_fail_streak = 0


## `regions.json` 行 → 区域燃油倍率（`RegionRun` 权威）。
static func _region_fuel_mult_for(region_id: String) -> float:
	var row := region_def(region_id)
	var default_mult := float(ConfigDb.require("balance.regions.defaultFuelMult"))
	var fuel_mult := float(row.get("regionFuelMult", default_mult))
	if fuel_mult <= 0.0:
		fuel_mult = default_mult
	return fuel_mult


## 调试用：1.0 ↔ 1.3 切换当前跨度燃油倍率（仅 debug 构建）。
static func dev_toggle_region_fuel_mult(state: RunState) -> void:
	if not OS.is_debug_build():
		return
	if state.region_run == null:
		return
	var m := state.region_run.region_fuel_mult
	state.region_run.region_fuel_mult = 1.0 if m > 1.15 else 1.3
	state.region_fuel_mult = state.region_run.region_fuel_mult
	ClimateService.refresh(state)


## 写 climateInfluences（regions.json + 预设）；燃油倍率在创建 RegionRun 时写入。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param region_id `regions.json` 的 regionId
static func _apply_region_factors(state: RunState, region_id: String) -> void:
	var row := region_def(region_id)
	var fuel_mult := _region_fuel_mult_for(region_id)
	if state.region_run != null:
		state.region_run.region_fuel_mult = fuel_mult
	else:
		state.region_fuel_mult = fuel_mult
	WeatherDraw.sync_region_influence(state, region_id, row)


## 本区搜索点类型权重乘子 pointTypeWeightMods。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param region_id `regions.json` 的 regionId
## @return 结果字典；缺失语义键时可能为空 {}。
static func _region_point_mods(region_id: String) -> Dictionary:
	var row := region_def(region_id)
	var mods: Variant = row.get("pointTypeWeightMods", {})
	return mods.duplicate(true) if typeof(mods) == TYPE_DICTIONARY else {}


## 新跨度段数 ∈[3,5] 均匀随机。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @return 整数结果（计数/下标/容量）。
static func _roll_segment_count() -> int:
	var lo := int(ConfigDb.require("stations.regionRunSegmentCountMin"))
	var hi := int(ConfigDb.require("stations.regionRunSegmentCountMax"))
	return RngService.randi_range(lo, hi)


## 懒创建 segments[index]：缺则程序化骨架 + build_segment。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param index 段下标 region_run.segment_index 或名册序号
## @return 段实例；不存在时为 null。
static func _ensure_segment_built(state: RunState, index: int) -> Segment:
	var rr: RegionRun = state.region_run
	if rr == null:
		return null
	while rr.segments.size() <= index:
		var seg := _build_procedural_segment(state, rr.segments.size())
		rr.segments.append(seg)
	var raw: Variant = rr.segments[index]
	var seg := raw as Segment if raw is Segment else null
	if seg == null:
		return null
	if not seg.built:
		build_segment(state, seg)
	return seg


## 非教程段：随机长度 km、掷车站列表、points 留空待 build。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param index 段下标 region_run.segment_index 或名册序号
## @return 段实例；不存在时为 null。
static func _build_procedural_segment(state: RunState, index: int) -> Segment:
	var stations_cfg: Dictionary = ConfigDb.get_table("stations")
	var seg := Segment.new()
	seg.segment_id = "%s_seg_%d" % [state.region_run.region_id, index]
	var len_min := float(ConfigDb.require("stations.segmentLengthMin"))
	var len_max := float(ConfigDb.require("stations.segmentLengthMax"))
	seg.length_km = len_min + RngService.randf() * (len_max - len_min)
	seg.progress_km = 0.0
	seg.built = false
	seg.stations = _roll_stations_for_segment(seg.length_km, stations_cfg)
	seg.points = []
	return seg


## 按 stationCountWeights 掷站数，沿段长随机 progressKm 与规模。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param length_km 段长度（程序化生成用）
## @param stations_cfg（Dictionary）
## @return 数组结果（列表/选项）。
static func _roll_stations_for_segment(length_km: float, stations_cfg: Dictionary) -> Array:
	var weights: Dictionary = ConfigDb.require("stations.stationCountWeights")
	var station_n := int(_weighted_key(weights, "1"))
	var frac_min := float(ConfigDb.require("stations.stationProgressKmFractionMin"))
	var frac_span := float(ConfigDb.require("stations.stationProgressKmFractionSpan"))
	var out: Array = []
	for i in station_n:
		var km := length_km * (frac_min + frac_span * RngService.randf())
		var size_weights: Dictionary = ConfigDb.require("stations.sizeWeights")
		out.append(
			{
				"id": "st_%d_%d" % [Time.get_ticks_usec() % 100000, i],
				"progressKm": km,
				"size": _weighted_key(size_weights, "small"),
				"hasPool": true,
				"nonePool": RngService.randf() < float(ConfigDb.require("stations.nonePoolChance")),
				"visited": false,
			}
		)
	return out


## 掷 3–4 个搜索点：类型按 baseWeight×区域 mods 加权。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param seg 当前区段 `Segment`
static func _roll_points_for_segment(state: RunState, seg: Segment) -> void:
	var pt_lo := int(ConfigDb.require("stations.segmentPointsMin"))
	var pt_hi := int(ConfigDb.require("stations.segmentPointsMax"))
	var n_pts := RngService.randi_range(pt_lo, pt_hi)
	var mods: Dictionary = {}
	if state.region_run:
		mods = state.region_run.point_type_weight_mods
	var types_root: Dictionary = ConfigDb.get_table("point_types")
	var types: Variant = types_root.get("types", {})
	if typeof(types) != TYPE_DICTIONARY:
		return
	var weights := {}
	var total := 0.0
	for tid in types.keys():
		var row: Variant = types[tid]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if not bool(row.get("inPool", true)):
			continue
		var w := float(ConfigDb.require("point_types.types." + str(tid) + ".baseWeight")) * float(mods.get(tid, 1.0))
		if w > 0.0:
			weights[str(tid)] = w
			total += w
	if total <= 0.0:
		weights = {"supermarket": 1.0, "water_plant": 1.0}
	seg.points.clear()
	for i in n_pts:
		var picked := _pick_weighted_type(weights)
		seg.points.append(
			{
				"id": "pt_%s_%d_%d" % [picked, seg.points.size(), RngService.randi() % 1000],
				"type": picked,
				"remainingYield": SearchService.initial_remaining_yield(picked),
				"depleted": false,
				"lootPile": {},
			}
		)


## 从点位类型权重表抽一个 typeId。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param weights 加权抽键表
## @return 空串=成功；非空=机器错误码。
static func _pick_weighted_type(weights: Dictionary) -> String:
	var total := 0.0
	for w in weights.values():
		total += float(w)
	if total <= 0.0:
		return "supermarket"
	var r := RngService.randf() * total
	for tid in weights.keys():
		r -= float(weights[tid])
		if r <= 0.0:
			return str(tid)
	var keys := weights.keys()
	return str(keys[keys.size() - 1])


## 通用加权抽键（站数、规模等）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param weights 加权抽键表
## @param fallback（String）
## @return 空串=成功；非空=机器错误码。
static func _weighted_key(weights: Dictionary, fallback: String = "0") -> String:
	var total := 0.0
	for w in weights.values():
		total += float(w)
	if total <= 0.0:
		return fallback
	var r := RngService.randf() * total
	for k in weights.keys():
		r -= float(weights[k])
		if r <= 0.0:
			return str(k)
	var keys := weights.keys()
	return str(keys[keys.size() - 1])


## 段压力档 low/medium/high（影响压力史与展示）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @return 空串=成功；非空=机器错误码。
static func _roll_pressure_class() -> String:
	var roll := RngService.randf()
	var low_max := float(ConfigDb.require("event_draw_rules.pressureClassRoll.lowMax"))
	var med_max := float(ConfigDb.require("event_draw_rules.pressureClassRoll.mediumMax"))
	if roll < low_max:
		return "low"
	if roll < med_max:
		return "medium"
	return "high"


## 滑动窗口 pressure_history[0,1]，供 HUD/F3 与 refresh_pressure_cache。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param cls（String）
static func _push_pressure_history(state: RunState, cls: String) -> void:
	if cls.is_empty():
		return
	while state.pressure_history.size() < 2:
		state.pressure_history.append("")
	var hist := state.pressure_history.duplicate()
	if hist.size() >= 2:
		hist[0] = str(hist[1])
		hist[1] = cls
	else:
		hist.append(cls)
	state.pressure_history = hist


## 教程第 0 段：中点 tutorial 站 + tutorialForcePointTypes 固定点位。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param stations_cfg（Dictionary）
## @return 段实例；不存在时为 null。
static func _build_tutorial_segment_0(stations_cfg: Dictionary) -> Segment:
	var seg := Segment.new()
	seg.segment_id = "tutorial_seg_0"
	var len_min := float(ConfigDb.require("stations.segmentLengthMin"))
	var len_max := float(ConfigDb.require("stations.segmentLengthMax"))
	seg.length_km = (len_min + len_max) * 0.5
	seg.progress_km = 0.0

	var station_km := seg.length_km * 0.5
	seg.stations = [
		{
			"id": "st_tutorial_0",
			"progressKm": station_km,
			"size": "small",
			"hasPool": true,
			"nonePool": false,
			"visited": false,
			"tutorialHook": true,
			"forceLivingOffer": bool(stations_cfg.get("tutorialForceLivingOffer", true)),
			"livingRepairCost": int(ConfigDb.require("stations.tutorialLivingRepairCost")),
		},
	]

	seg.points = []
	var force: Variant = stations_cfg.get("tutorialForcePointTypes", ["supermarket", "water_plant"])
	if typeof(force) == TYPE_ARRAY:
		var idx := 0
		for pt in force:
			seg.points.append(
				{
					"id": "pt_%s_%d" % [str(pt), idx],
					"type": str(pt),
					"remainingYield": SearchService.initial_remaining_yield(str(pt)),
					"depleted": false,
					"lootPile": {},
				}
			)
			idx += 1
	return seg