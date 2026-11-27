class_name EventService
extends RefCounted
## 段事件弹窗策略（06 / 09）：
## - 新段抽卡后 `try_open_new_segment_event`
## - 读档 `sync_after_load`：仅当本段 **未选**（`!event_resolved` 且无 `event_option_id`）时恢复
## - 已选段内永不因 state_changed 重开；`event_modal_open` 不入盘


static func try_open_new_segment_event(state: RunState) -> void:
	_open_if_pending(state)


## 读档 / LOAD_GAME 后调用：清 UI 旗标再按 pending 规则恢复。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
static func sync_after_load(state: RunState) -> void:
	state.event_modal_open = false
	if not has_pending_segment_event(state):
		return
	_open_if_pending(state)


## 是否应在弹窗中强制玩家选择（只读，不修改 state）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func has_pending_segment_event(state: RunState) -> bool:
	if state == null or not state.tutorial_done or state.failed != "":
		return false
	if state.region_run == null:
		return false
	var seg := state.region_run.active_segment()
	if seg == null:
		return false
	if seg.event_id.is_empty() or seg.event_resolved or seg.event_option_id != "":
		return false
	return not EventCatalog.get_card(seg.event_id).is_empty()

## 段 built 且有待开事件 id 时打开 EventModal（与 EventDraw 协同）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
static func _open_if_pending(state: RunState) -> void:
	if not has_pending_segment_event(state):
		return
	if state.region_pick_open or state.combat_panel_open:
		return
	state.event_modal_open = true

## 当前段 event_id 对应卡 JSON。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 结果字典；缺失语义键时可能为空 {}。
static func active_card(state: RunState) -> Dictionary:
	var seg := state.region_run.active_segment() if state.region_run else null
	if seg == null:
		return {}
	return EventCatalog.get_card(seg.event_id)