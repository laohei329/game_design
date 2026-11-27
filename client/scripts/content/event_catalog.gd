class_name EventCatalog
extends RefCounted
## 懒加载 `data/events/*.json`；索引来自 ConfigDb `events_index`。


static var _cards: Dictionary = {}

## events/_index.json 表根。
##
## 事件卡只读缓存；写 state 走 EventOps / EventDraw。
## @return 结果字典；缺失语义键时可能为空 {}。
static func _index() -> Dictionary:
	return ConfigDb.get_table("events_index")

## event_id → res://data/events/... 路径。
##
## 事件卡只读缓存；写 state 走 EventOps / EventDraw。
## @param event_id 事件卡 id
## @return 空串=成功；非空=机器错误码。
static func _card_path(event_id: String) -> String:
	if event_id.begins_with("gen_"):
		return "res://data/events/general/%s.json" % event_id
	if event_id.begins_with("yr_"):
		return "res://data/events/year/%s.json" % event_id
	var prefix := event_id.split("_", false, 1)[0]
	var season_map := {"spr": "spring", "sum": "summer", "aut": "autumn", "win": "winter"}
	var season: String = str(season_map.get(prefix, ""))
	if season != "":
		return "res://data/events/season/%s/%s.json" % [season, event_id]
	return ""

## 索引表内全部 eventId（去重前合并各 bucket）。
##
## 事件卡只读缓存；写 state 走 EventOps / EventDraw。
## @return 数组结果（列表/选项）。
static func all_event_ids() -> Array:
	var idx := _index()
	var buckets: Variant = idx.get("buckets", {})
	if typeof(buckets) != TYPE_DICTIONARY:
		return []
	var ids: Array = []
	var general: Variant = buckets.get("general", {})
	if typeof(general) == TYPE_DICTIONARY:
		for eid in general.get("eventIds", []):
			ids.append(str(eid))
	var season: Variant = buckets.get("season", {})
	if typeof(season) == TYPE_DICTIONARY:
		var by: Variant = season.get("bySeason", {})
		if typeof(by) == TYPE_DICTIONARY:
			for row in by.values():
				if typeof(row) == TYPE_DICTIONARY:
					for eid in row.get("eventIds", []):
						ids.append(str(eid))
	var year: Variant = buckets.get("year", {})
	if typeof(year) == TYPE_DICTIONARY:
		for eid in year.get("eventIds", []):
			ids.append(str(eid))
	return ids

## 按当前季节/年份过滤可入池 eventId。
##
## 事件卡只读缓存；写 state 走 EventOps / EventDraw。
## @param season spring|summer|autumn|winter
## @param year 游戏内年份
## @return 数组结果（列表/选项）。
static func eligible_ids(season: String, year: int) -> Array:
	if not _legacy_cards_enabled():
		return []
	var out: Array = []
	for eid in all_event_ids():
		var card := get_card(str(eid))
		if card.is_empty():
			continue
		var bucket := str(card.get("bucket", "general"))
		if bucket == "season" and str(card.get("season", "")) != season:
			continue
		if bucket == "year" and year < int(card.get("minYear", 2)):
			continue
		out.append(str(eid))
	return out

## 懒加载单张事件 JSON；缓存于 `_cards`。
##
## 事件卡只读缓存；写 state 走 EventOps / EventDraw。
## @param event_id 事件卡 id
## @return 结果字典；缺失语义键时可能为空 {}。
static func get_card(event_id: String) -> Dictionary:
	if event_id.is_empty():
		return {}
	if not _legacy_cards_enabled():
		return {}
	if _cards.has(event_id):
		return _cards[event_id]
	var path := _card_path(event_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("EventCatalog missing card: " + event_id)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("EventCatalog bad json: " + path)
		return {}
	_cards[event_id] = parsed
	return parsed

## 卡内多语块 → 当前语言（委托 LocaleDb）。
##
## 事件卡只读缓存；写 state 走 EventOps / EventDraw。
## @param block 多语 block 或 Variant 文案块
## @param fallback 缺翻译时的回退串
## @return 空串=成功；非空=机器错误码。
static func locale_text(block: Variant, fallback: String = "") -> String:
	return LocaleApi.from_locale_block(block, fallback)

## 卡 `tags[0]`；缺省 `mood`，用于抽卡重复惩罚。
##
## 事件卡只读缓存；写 state 走 EventOps / EventDraw。
## @param card 事件卡 JSON（EventCatalog）
## @return 空串=成功；非空=机器错误码。
static func primary_tag(card: Dictionary) -> String:
	var tags: Variant = card.get("tags", [])
	if typeof(tags) == TYPE_ARRAY and not tags.is_empty():
		return str(tags[0])
	return "mood"


static func _legacy_cards_enabled() -> bool:
	if IncidentDirector.use_legacy_event_cards():
		return true
	return bool(ConfigDb.require("balance.featureFlags.loadLegacyEventCatalog"))