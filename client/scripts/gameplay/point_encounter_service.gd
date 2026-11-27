class_name PointEncounterService
extends RefCounted
## 点位首次当日搜索时按类型概率触发 L1 遭遇（05 薄切片）。
##
## SearchService.assign_search 成功后调用；同点同日只掷一次（store 按 day_total 分桶）。
## `force=true` 跳过 RNG（冒烟/调试）。
## @param state 当前局 `RunState`（就地修改字段）
## @param point_id 搜索点 id（段内 points[].id）
## @param store 搜索遥测分桶（GameSession.search_telemetry）
## @param force 跳过 RNG 或强制分支（调试）
## @return 空串=成功；非空=机器错误码。
static func try_on_search_assign(state: RunState, point_id: String, store: Dictionary, force: bool = false) -> String:
	if state.drive_intent != "stop":
		return ""
	var hit := SearchService.find_point(state, point_id)
	if hit.is_empty():
		return ""
	var pt: Dictionary = hit.point
	var ptype := str(pt.get("type", ""))
	var enc: Variant = ConfigDb.require("combat.searchEncounter")
	if typeof(enc) != TYPE_DICTIONARY:
		return ""
	var day := str(state.day_total)
	if not store.has(day):
		store[day] = {}
	var day_map: Dictionary = store[day]
	var enc_key := point_id + "_enc"
	if bool(day_map.get(enc_key, false)):
		return ""
	day_map[enc_key] = true
	var chance_path := (
		"combat.searchEncounter.chanceByPointType." + ptype
		if ConfigDb.has("combat.searchEncounter.chanceByPointType." + ptype)
		else "combat.searchEncounter.chanceByPointType.default"
	)
	var chance := float(ConfigDb.require(chance_path))
	if not force and RngService.randf() >= chance:
		return ""
	var tpl_path := (
		"combat.searchEncounter.templateByPointType." + ptype
		if ConfigDb.has("combat.searchEncounter.templateByPointType." + ptype)
		else "combat.searchEncounter.templateByPointType.default"
	)
	var tpl := str(ConfigDb.require(tpl_path))
	var err := CombatL1.open_from_template(state, tpl, {"source": "point", "pointId": point_id})
	if err != "":
		day_map.erase(enc_key)
	return err