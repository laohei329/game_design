extends PanelContainer
## L1 遭遇 UI（S1b.4）：暂停；展示 CombatL1.preview_text。
##
## 两阶段 UI：
##   1. 正常：L1 检定 + 四条非战斗路径（按钮 disabled 绑 can_* 错误码）
##   2. combat_l1_after_fail：隐藏上行，显示撤退/升级（escalate 占位）
## CLOSE_COMBAT 可由 Debug/HUD 发；胜利/非战成功由 Service 自动关面板。


@onready var _title: Label = $Margin/VBox/Title
@onready var _body: Label = $Margin/VBox/Body
@onready var _hint: Label = $Margin/VBox/Hint
@onready var _row_fight: HBoxContainer = $Margin/VBox/RowFight
@onready var _row_paths: HBoxContainer = $Margin/VBox/RowPaths
@onready var _row_fail: HBoxContainer = $Margin/VBox/RowFail
@onready var _btn_l1: Button = $Margin/VBox/RowFight/L1Check
@onready var _btn_neg: Button = $Margin/VBox/RowPaths/Negotiate
@onready var _btn_bypass: Button = $Margin/VBox/RowPaths/Bypass
@onready var _btn_horn: Button = $Margin/VBox/RowPaths/Horn
@onready var _btn_evac: Button = $Margin/VBox/RowPaths/Evacuate
@onready var _btn_retreat: Button = $Margin/VBox/RowFail/Retreat
@onready var _btn_escalate: Button = $Margin/VBox/RowFail/Escalate
@onready var _btn_close: Button = $Margin/VBox/BtnClose
func _ready() -> void:
	_btn_l1.pressed.connect(func() -> void: IntentBus.emit_intent("RESOLVE_COMBAT_L1_CHECK"))
	_btn_neg.pressed.connect(func() -> void: IntentBus.emit_intent("RESOLVE_NON_COMBAT", {"path": "negotiate"}))
	_btn_bypass.pressed.connect(func() -> void: IntentBus.emit_intent("RESOLVE_NON_COMBAT", {"path": "bypass"}))
	_btn_horn.pressed.connect(func() -> void: IntentBus.emit_intent("RESOLVE_NON_COMBAT", {"path": "horn"}))
	_btn_evac.pressed.connect(func() -> void: IntentBus.emit_intent("RESOLVE_NON_COMBAT", {"path": "evacuate"}))
	_btn_retreat.pressed.connect(func() -> void: IntentBus.emit_intent("RESOLVE_COMBAT_L1_FAIL", {"choice": "retreat"}))
	_btn_escalate.pressed.connect(func() -> void: IntentBus.emit_intent("RESOLVE_COMBAT_L1_FAIL", {"choice": "escalate"}))
	_btn_close.pressed.connect(func() -> void: IntentBus.emit_intent("CLOSE_COMBAT"))
	GameSession.state_changed.connect(_sync)
	visible = false
	_sync()


## l1_err 非空时禁用强攻并显示 combat.err.* 主因。
func _sync() -> void:
	var st := GameSession.state
	if st == null or not st.combat_panel_open:
		_close()
		return
	visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	var n := int(st.pending_combat.get("enemyCount", 0))
	_title.text = LocaleApi.trf("combat.title.l1", [n])
	_body.text = CombatL1.preview_text(st)
	_row_fail.visible = st.combat_l1_after_fail
	_row_fight.visible = not st.combat_l1_after_fail
	_row_paths.visible = not st.combat_l1_after_fail

	_btn_l1.text = LocaleApi.tr_key("combat.btn.l1_check")
	_btn_neg.text = CombatL1.path_label("negotiate")
	_btn_bypass.text = CombatL1.path_label("bypass")
	_btn_horn.text = CombatL1.path_label("horn")
	_btn_evac.text = CombatL1.path_label("evacuate")
	_btn_retreat.text = LocaleApi.tr_key("combat.btn.retreat")
	_btn_escalate.text = LocaleApi.tr_key("combat.btn.escalate")
	_btn_close.text = LocaleApi.tr_key("combat.btn.close")

	var l1_err := CombatL1.can_l1_check(st)
	_btn_l1.disabled = l1_err != ""
	if l1_err != "":
		_hint.text = LocaleApi.tr_code("combat.err", l1_err, l1_err)
	else:
		_hint.text = LocaleApi.tr_key("combat.hint.non_combat_ok")

	_btn_neg.disabled = CombatL1.can_non_combat_path(st, "negotiate") != ""
	_btn_bypass.disabled = CombatL1.can_non_combat_path(st, "bypass") != ""
	_btn_horn.disabled = CombatL1.can_non_combat_path(st, "horn") != ""
	_btn_evac.disabled = CombatL1.can_non_combat_path(st, "evacuate") != ""

## 关闭战斗 UI：`combat_panel_open=false`，发 `CLOSE_COMBAT` 或仅刷新 state。
func _close() -> void:
	visible = false
	if get_tree().paused:
		get_tree().paused = false