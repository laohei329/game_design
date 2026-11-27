class_name RegionRun
extends RefCounted
## 区域跨度：玩家三选一某 region 后，连续跑 `segment_count` 个 Segment 的容器。
##
## `segment_index` 指向当前活跃段；跨段时 index++ 或末段结束弹三选一。
## `point_type_weight_mods` 影响本跨度内搜索点类型权重（regions.json）。

var region_id: String = "urban"
var segment_count: int = 3
var segment_index: int = 0
var region_fuel_mult: float = 1.0
var point_type_weight_mods: Dictionary = {}
var segments: Array = []


## segments[segment_index] 若为 Segment 实例则返回，否则 null。
func active_segment() -> Segment:
	if segments.is_empty():
		return null
	if segment_index < 0 or segment_index >= segments.size():
		return null
	var seg: Variant = segments[segment_index]
	return seg as Segment if seg is Segment else null

## 导出存档/调试用 Dictionary。
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