class_name RegionRun
extends RefCounted
## 06 §0 RegionRun · 一次行程内多段

var region_id: String = "urban"
var segment_count: int = 3
var segment_index: int = 0
var region_fuel_mult: float = 1.0
var point_type_weight_mods: Dictionary = {}
var segments: Array = []


func active_segment() -> Segment:
	if segments.is_empty():
		return null
	if segment_index < 0 or segment_index >= segments.size():
		return null
	var seg: Variant = segments[segment_index]
	return seg as Segment if seg is Segment else null


func to_dict() -> Dictionary:
	var seg_out: Array = []
	for s in segments:
		if s is Segment:
			seg_out.append((s as Segment).to_dict())
		elif typeof(s) == TYPE_DICTIONARY:
			seg_out.append(s)
	return {
		"regionId": region_id,
		"segmentCount": segment_count,
		"segmentIndex": segment_index,
		"regionFuelMult": region_fuel_mult,
		"pointTypeWeightMods": point_type_weight_mods.duplicate(true),
		"segments": seg_out,
	}