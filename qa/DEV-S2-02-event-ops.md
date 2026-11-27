# DEV-S2-02 — 事件结算（薄切片证据）

- `EventOps`：对齐全卡 `op`（grant/remove_item、mood_delta、grant/clear_influence、loot_halve、weight_mod、spawn_threat、recruit_roll、flag_set）。
- 气候：`grant_influence` → `climate_influences` + `ClimateService.recompute`；`expiresSegment` 随段切换递减。
- 弹窗：`event_option_id` + `event_resolved`；仅新抽卡/读档续选打开，段内已选不重开。
- 冒烟：`errors_event_ops_full`、`errors_event_snapshot_and_load_pending`。
- 延迟：`capture=snapshot` 写入 `snapshot`（库存+堆）；触发时空堆跳过、不凭快照造堆；`sourceEventId@fireOnDay` 去重。
- 弹窗：读档 `sync_after_load` + `has_pending_segment_event`（未决且 tutorial_done）。