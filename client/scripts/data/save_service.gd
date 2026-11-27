extends Node
## 存档读写（Autoload SaveService）：save 12 子集落盘 `user://save_slot_N.json`。
##
## 序列化走 SaveSchema。客户端仅实现 **v11→v12** 迁移；`version.save` < 11 时 warning 后仍尝试补丁。

const SAVE_VERSION := 12

const _GameClock := preload("res://scripts/rhythm/game_clock.gd")
const _PopulationConsumption := preload("res://scripts/economy/population_consumption.gd")

var _pending_search_telemetry: Dictionary = {}

## SaveService 读档后补 UI/运行时缺省。
##
## Autoload SaveService；SAVE_GAME / LOAD_GAME 唯一落盘入口。
## @param save 存档根 Dictionary（save 12）
func apply_runtime_defaults(save: Dictionary) -> void:
	if not save.has("version"):
		save["version"] = {"save": SAVE_VERSION, "configVersion": ConfigDb.config_version}
	var train: Dictionary = save.get("train", {})
	if not train.has("abandonCount"):
		train["abandonCount"] = 0
	save["train"] = train
	if not save.has("telemetry"):
		save["telemetry"] = {"searchByPointDay": {}}

## 迁移链 + 缺键补丁（不写盘）。
##
## Autoload SaveService；SAVE_GAME / LOAD_GAME 唯一落盘入口。
## @param save 存档根 Dictionary（save 12）
## @return 结果字典；缺失语义键时可能为空 {}。
func patch_loaded_save(save: Dictionary) -> Dictionary:
	apply_runtime_defaults(save)
	var sv := int(save.get("version", {}).get("save", 0))
	if sv < 11:
		push_warning(
			"SaveService: save version %d < 11; applying v11→v12 patches only (no v2–v10 chain in client)"
			% sv
		)
	if sv < SAVE_VERSION:
		MigrationV11ToV12.apply(save)
	RuntimeSavePatch.ensure_abandon_fields(save)
	return save

## RunState → save dict（SaveSchema）。
##
## Autoload SaveService；SAVE_GAME / LOAD_GAME 唯一落盘入口。
## @param session_state 写档用快照（常等同 RunState 字段包）
## @return 结果字典；缺失语义键时可能为空 {}。
func snapshot_for_save(session_state: Dictionary) -> Dictionary:
	var save: Dictionary = session_state.duplicate(true)
	apply_runtime_defaults(save)
	save["version"] = {"save": SAVE_VERSION, "configVersion": ConfigDb.config_version}
	return save

## 槽位 JSON 绝对路径。
##
## Autoload SaveService；SAVE_GAME / LOAD_GAME 唯一落盘入口。
## @param slot 存档槽 0..N
## @return 空串=成功；非空=机器错误码。
func slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot


## Intent SAVE_GAME；含 `telemetry.searchByPointDay`（搜索 cap，见 GameSession）。
##
## Autoload SaveService；SAVE_GAME / LOAD_GAME 唯一落盘入口。
## @param state 当前局 `RunState`（就地修改字段）
## @param slot 存档槽 0..N
## @return 是否成功或条件成立。
func write_state(state: RunState, slot: int = 0) -> bool:
	var clock_rt: Dictionary = {
		"dayClockFraction": clampf(GameSession.day_clock_fraction, 0.0, 1.0),
		"simDayFractionToday": _GameClock.sim_day_fraction_today(),
		"outdoorEligibleFractionToday": _GameClock.outdoor_eligible_fraction_today(),
		"outdoorTickFractionToday": _GameClock.outdoor_tick_fraction_today(),
	}
	clock_rt.merge(_PopulationConsumption.export_day_counters())
	var save := SaveSchema.to_save_dict(state, clock_rt)
	apply_runtime_defaults(save)
	var tel: Dictionary = save.get("telemetry", {})
	if typeof(tel) != TYPE_DICTIONARY:
		tel = {}
	tel["searchByPointDay"] = GameSession.search_telemetry.duplicate(true)
	save["telemetry"] = tel
	var text := JSON.stringify(save, "\t")
	var path := slot_path(slot)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveService: cannot write " + path)
		return false
	f.store_string(text)
	return true


## Intent LOAD_GAME；失败返回 null，GameSession 保留旧 state。
##
## 仅反序列化 `RunState`；玩法读档用 `load_into_game_session`（接 `apply_loaded_run`）。
## @param slot 存档槽 0..N
## @return 重建后的 RunState。
func read_state(slot: int = 0) -> RunState:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		push_warning("SaveService: no save at " + path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveService: invalid json " + path)
		return null
	parsed = patch_loaded_save(parsed)
	_stash_search_telemetry(parsed)
	return SaveSchema.from_save_dict(parsed, true)


## 玩法读档：`read_state` + `GameSession.apply_loaded_run`（勿在 Intent 外只调 `read_state` 接 HUD）。
func load_into_game_session(slot: int = 0) -> bool:
	var loaded := read_state(slot)
	if loaded == null:
		return false
	GameSession.apply_loaded_run(loaded)
	return true


## 读档后由 GameSession 取走当日搜索 cap 分桶（只读一次）。
func take_pending_search_telemetry() -> Dictionary:
	var out := _pending_search_telemetry.duplicate(true)
	_pending_search_telemetry = {}
	return out


func _stash_search_telemetry(save: Dictionary) -> void:
	_pending_search_telemetry = {}
	var tel: Variant = save.get("telemetry", {})
	if typeof(tel) != TYPE_DICTIONARY:
		return
	var by_day: Variant = tel.get("searchByPointDay", {})
	if typeof(by_day) == TYPE_DICTIONARY:
		_pending_search_telemetry = by_day.duplicate(true)