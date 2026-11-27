class_name SegmentBuild
extends RefCounted
## 新局时构建教程 RegionRun 的薄入口（`NEW_RUN` 调用）。
##
## `NEW_RUN` 薄入口；onSegmentBuild 加厚在 RegionService.build_segment。
## @param state 当前局 `RunState`（就地修改字段）
static func begin_tutorial_region_run(state: RunState) -> void:
	RegionService.start_tutorial(state)