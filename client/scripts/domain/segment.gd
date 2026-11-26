class_name Segment
extends RefCounted
## 06 §0 · 单段走廊锚点（S0 内存子集）

var segment_id: String = ""
var length_km: float = 50.0
var progress_km: float = 0.0
var built: bool = false
var stations: Array = []
var points: Array = []
var weather_id: String = "clear"
var weather_draw_count: int = 0
var event_id: String = ""
var segment_fuel_surcharge: float = 0.0
var raid_weight_delta: float = 0.0
var pressure_class: String = ""

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
		"segmentFuelSurcharge": segment_fuel_surcharge,
		"raidWeightDelta": raid_weight_delta,
		"pressureClass": pressure_class,
	}