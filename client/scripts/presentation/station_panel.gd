extends PanelContainer
## 进站要约（UI-3）：展示 StationService 生成的 offer，接受/搁置发 RESOLVE_OFFER。
## 打开时场景应 paused=true（见 run_main 子节点 process_mode）。

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


## `pending_station` 由 StationService 写入；miss/offer 两套文案；接受发 RESOLVE_OFFER accept=true。
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
		_title.text = LocaleApi.tr_key("station.title.miss")
		_body.text = LocaleApi.trf(
			"station.body.miss",
			[LocaleApi.tr_code("station.miss", reason, reason), st.guarantee_fail_streak]
		)
		_hint.text = ""
		_btn_accept.disabled = true
		_btn_accept.text = LocaleApi.tr_key("station.btn.accept")
		_btn_defer.text = LocaleApi.tr_key("station.btn.leave")
		return

	var offer: Dictionary = pending.get("offer", {})
	if offer.is_empty():
		_title.text = LocaleApi.tr_key("station.title.empty")
		_body.text = LocaleApi.tr_key("station.body.no_offer")
		_hint.text = ""
		_btn_accept.disabled = true
		_btn_defer.text = LocaleApi.tr_key("station.btn.leave")
		return

	var tid := str(offer.get("templateId", ""))
	var cond := str(offer.get("condition", "damaged"))
	var cost := int(offer.get("repairCost", 0))
	var fuel_add := float(offer.get("fuelPerDay", 0.0))
	_title.text = LocaleApi.tr_key("station.title.found")
	_body.text = LocaleApi.trf(
		"station.body.offer",
		[
			StationService.template_label(tid),
			StationService.condition_label(cond),
			cost,
			fuel_add,
		]
	)
	var defer_txt := StationService.offer_defer_hint(st, offer)
	_hint.text = defer_txt
	if bool(offer.get("guaranteeForced", false)):
		if defer_txt != "":
			_hint.text = LocaleApi.tr_key("station.hint.guarantee_prefix") + defer_txt
		else:
			_hint.text = LocaleApi.tr_key("station.hint.guarantee_only")
	if bool(offer.get("tutorial", false)):
		_hint.text = LocaleApi.tr_key("station.hint.tutorial")

	_btn_accept.text = LocaleApi.trf("station.btn.hook", [cost])
	_btn_accept.disabled = not bool(offer.get("affordable", false))
	_btn_defer.text = LocaleApi.tr_key("station.btn.defer")

## 接受进站要约 → `STATION_ACCEPT`（挂车/扣费逻辑在 StationService）。
func _on_accept() -> void:
	IntentBus.emit_intent("RESOLVE_OFFER", {"accept": true})

## 延迟要约 → `STATION_DEFER`（guarantee streak）。
func _on_defer() -> void:
	IntentBus.emit_intent("RESOLVE_OFFER", {"accept": false})

## 关闭进站 UI；要约状态仍由 RunState 持有。
func _close() -> void:
	visible = false
	if get_tree().paused:
		get_tree().paused = false