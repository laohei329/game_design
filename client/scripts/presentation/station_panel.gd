extends PanelContainer

const MISS_ZH := {
	"no_pool": "无车厢池",
	"empty_roll": "空站",
	"no_offer": "未发现车厢",
}

@onready var _title: Label = $Margin/VBox/Title
@onready var _body: Label = $Margin/VBox/Body
@onready var _hint: Label = $Margin/VBox/Hint
@onready var _btn_accept: Button = $Margin/VBox/Row/Accept
@onready var _btn_defer: Button = $Margin/VBox/Row/Defer


func _ready() -> void:
	_btn_accept.pressed.connect(_on_accept)
	_btn_defer.pressed.connect(_on_defer)
	GameSession.state_changed.connect(_sync)
	visible = false
	_sync()


func _sync() -> void:
	var st := GameSession.state
	if st == null:
		_close()
		return
	var pending: Dictionary = st.pending_station
	if pending.is_empty():
		_close()
		return
	visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS

	if bool(pending.get("miss", false)):
		var reason := str(pending.get("missReason", ""))
		_title.text = "进站 · 无可挂车厢"
		_body.text = "原因：%s · 保底计数 %d" % [MISS_ZH.get(reason, reason), st.guarantee_fail_streak]
		_hint.text = ""
		_btn_accept.disabled = true
		_btn_accept.text = "接受"
		_btn_defer.text = "离开"
		return

	var offer: Dictionary = pending.get("offer", {})
	if offer.is_empty():
		_title.text = "进站"
		_body.text = "暂无要约"
		_hint.text = ""
		_btn_accept.disabled = true
		_btn_defer.text = "离开"
		return

	var tid := str(offer.get("templateId", ""))
	var cond := str(offer.get("condition", "damaged"))
	var cost := int(offer.get("repairCost", 0))
	var fuel_add := float(offer.get("fuelPerDay", 0.0))
	_title.text = "进站发现"
	_body.text = (
		"%s（%s）· 修复 %d 件 · 日耗油 +%.1f"
		% [StationService.TEMPLATE_ZH.get(tid, tid), StationService.CONDITION_ZH.get(cond, cond), cost, fuel_add]
	)
	var defer_txt := StationService.offer_defer_hint(st, offer)
	_hint.text = defer_txt
	if bool(offer.get("guaranteeForced", false)):
		_hint.text = ("保底要约 · " + _hint.text) if defer_txt != "" else "保底要约（可负担价）"
	if bool(offer.get("tutorial", false)):
		_hint.text = "教程首站 · 休息车厢挂钩"

	_btn_accept.text = "挂车（-%d 件）" % cost
	_btn_accept.disabled = st.parts < cost
	_btn_defer.text = "暂不挂"


func _on_accept() -> void:
	IntentBus.emit_intent("RESOLVE_OFFER", {"accept": true})


func _on_defer() -> void:
	IntentBus.emit_intent("RESOLVE_OFFER", {"accept": false})


func _close() -> void:
	if visible:
		get_tree().paused = false
	visible = false