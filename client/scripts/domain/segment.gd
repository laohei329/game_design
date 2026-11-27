class_name Segment
extends RefCounted
## 区段走廊：一次 RegionRun 内的行驶锚点（非独立关卡地图）。
##
## - `progress_km` / `length_km`：驾驶推进；段末触发 RegionService。
## - `stations[]`：车站字典（offer、tutorialHook、carriage_received 等，见 StationService）。
## - `points[]`：搜索点（type、remainingYield、lootPile）。
## - `built=false` 时由 RegionService.build_segment 掷点/天气/压力。

var segment_id: String = ""
var length_km: float = 50.0
var progress_km: float = 0.0
var built: bool = false
var stations: Array = []  ## 进站发现车厢
var points: Array = []  ## 侧线搜索点位
var weather_id: String = "clear"
var weather_draw_count: int = 0
var event_id: String = ""
var event_resolved: bool = false
var event_option_id: String = ""  ## 玩家已选 option.id；入盘防误重开
var segment_fuel_surcharge: float = 0.0
var raid_weight_delta: float = 0.0
## 本段按 `eventTag` 累加的事件抽卡权重（06 §2.3 / 09 `weight_mod`）。
var event_tag_weights: Dictionary = {}
var pressure_class: String = ""

## weight_mod：累加 tag 权重；raid 同步 raidWeightDelta。
func apply_event_tag_weight(tag: String, delta: float) -> void:
	var key := tag if not tag.is_empty() else "raid"
	event_tag_weights[key] = float(event_tag_weights.get(key, 0.0)) + delta
	if key == "raid":
		raid_weight_delta = float(event_tag_weights[key])

## 读档字典 → Segment（`points` 须已由 SaveSchema 规范化）。
static func from_dict(d: Dictionary, points: Array) -> Segment:
	var s := Segment.new()
	s.segment_id = str(d.get("segmentId", ""))
	s.length_km = float(d.get("lengthKm", 50))
	s.progress_km = float(d.get("progressKm", 0))
	s.built = bool(d.get("built", false))
	s.stations = d.get("stations", []).duplicate(true)
	s.points = points
	s.weather_id = str(d.get("weatherId", "clear"))
	s.weather_draw_count = int(d.get("weatherDrawCount", 0))
	s.event_id = str(d.get("eventId", ""))
	s.event_resolved = bool(d.get("eventResolved", false))
	s.event_option_id = str(d.get("eventOptionId", ""))
	if s.event_option_id != "":
		s.event_resolved = true
	s.segment_fuel_surcharge = float(d.get("segmentFuelSurcharge", 0))
	s.raid_weight_delta = float(d.get("raidWeightDelta", 0))
	var etw: Variant = d.get("eventTagWeights", {})
	s.event_tag_weights = etw.duplicate() if typeof(etw) == TYPE_DICTIONARY else {}
	if s.event_tag_weights.is_empty() and s.raid_weight_delta != 0.0:
		s.event_tag_weights["raid"] = s.raid_weight_delta
	elif s.event_tag_weights.has("raid"):
		s.raid_weight_delta = float(s.event_tag_weights["raid"])
	s.pressure_class = str(d.get("pressureClass", ""))
	return s


## 导出存档/调试用 Dictionary。
func to_dict() -> Dictionary:
	return {
		"segmentId": segment_id,
		"lengthKm": length_km,
		"progressKm": progress_km,
		"built": built,
		"stations": stations.duplicate(true),
		"points": points.duplicate(true),
		"weatherId": weather_id,
		"weatherDrawCount": weather_draw_count,
		"eventId": event_id,
		"eventResolved": event_resolved,
		"eventOptionId": event_option_id,
		"segmentFuelSurcharge": segment_fuel_surcharge,
		"raidWeightDelta": raid_weight_delta,
		"eventTagWeights": event_tag_weights.duplicate(),
		"pressureClass": pressure_class,
	}