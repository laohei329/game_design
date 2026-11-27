extends Node
## S1b.5 · 写档后新进程读档（模拟杀进程）

const SLOT := 92
const MARKER_PARTS := 12.345
const MARKER_DAY := 7
func _ready() -> void:
	call_deferred("_run")

## 冒烟子场景入口：下一帧后加载 ConfigDb，再按命令行分支执行写档或验档。
##
## 用户参数 `--verify` → `_verify`；否则 `_write`。ConfigDb 失败时 exit 1。
func _run() -> void:
	await get_tree().process_frame
	if ConfigDb.tables.is_empty() and not ConfigDb.load_all():
		_quit(1, "ConfigDb failed")
		return
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--verify"):
		_verify()
	else:
		_write()

## 写档探针（run_all_smoke 子进程「write」阶段）。
##
## 派发 `NEW_RUN`，连续 `END_DAY` 直至 `MARKER_DAY`，写入畸形但可识别的
## `parts`/`precision` 到槽位 `SLOT`，成功 exit 0 并打印摘要；任一步失败 exit 1。
func _write() -> void:
	IntentBus.emit_intent("NEW_RUN")
	await get_tree().process_frame
	var st := GameSession.state
	if st == null:
		_quit(1, "NEW_RUN failed")
		return
	for _i in MARKER_DAY - 1:
		IntentBus.emit_intent("END_DAY")
		await get_tree().process_frame
	st = GameSession.state
	st.parts = MARKER_PARTS
	st.precision = float(ConfigDb.require("balance.start.precision"))
	if not SaveService.write_state(st, SLOT):
		_quit(1, "write_state failed")
	_quit(0, "wrote slot %d day=%d parts=%.3f precision=%.0f" % [SLOT, st.day_total, st.parts, st.precision])

## 读档探针（新进程、`--verify`）：不经过 GameSession 玩法，仅 `SaveService.read_state`。
##
## 断言 `day_total`、`parts`、`precision` 与 `MARKER_*` 一致，且 `region_run` 非空；
## 用于验证杀进程后 JSON 仍完整可读。
func _verify() -> void:
	var loaded := SaveService.read_state(SLOT)
	if loaded == null:
		_quit(1, "read_state null")
		return
	var want_p := float(ConfigDb.require("balance.start.precision"))
	if loaded.day_total != MARKER_DAY:
		_quit(1, "day_total want=%d got=%d" % [MARKER_DAY, loaded.day_total])
		return
	if not is_equal_approx(loaded.parts, MARKER_PARTS):
		_quit(1, "parts want=%.3f got=%.3f" % [MARKER_PARTS, loaded.parts])
		return
	if not is_equal_approx(loaded.precision, want_p):
		_quit(1, "precision want=%.0f got=%.0f" % [want_p, loaded.precision])
		return
	if loaded.region_run == null or loaded.region_run.region_id.is_empty():
		_quit(1, "region_run missing")
		return
	_quit(0, "verify ok slot %d" % SLOT)

## 统一收尾：`[save_kill]` 前缀日志 + `get_tree().quit(code)`。
##
## @param code 进程退出码（CI 据此判 PASS/FAIL）。
## @param msg 单行人类可读原因或成功摘要。
func _quit(code: int, msg: String) -> void:
	print("[save_kill] ", msg)
	get_tree().quit(code)