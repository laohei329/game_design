extends PanelContainer

@onready var _list: VBoxContainer = $Margin/VBox/PointList
@onready var _caps: Label = $Margin/VBox/Caps
@onready var _btn_close: Button = $Margin/VBox/Close

## pointId -> Array[String] member ids（最多 4）
var _member_pick: Dictionary = {}


func _ready() -> void:
	_btn_close.pressed.connect(_on_close)
	GameSession.state_changed.connect(_sync)
	visible = false
	_sync()


func _sync() -> void:
	var st := GameSession.state
	if st == null or not st.search_panel_open:
		_close()
		return
	visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rebuild_points(st)


func _rebuild_points(st: RunState) -> void:
	for c in _list.get_children():
		c.queue_free()
	var seg := st.region_run.active_segment() if st.region_run else null
	if seg == null:
		return
	_caps.text = (
		"粮 %.0f/%.0f · 水 %.0f/%.0f · 搜索上限 %d/点/日 · 点名 1–4 人"
		% [
			st.food,
			InventoryService.stock_cap(st, "food"),
			st.water,
			InventoryService.stock_cap(st, "water"),
			SearchRules.cap(),
		]
	)
	for pt in seg.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		var row := _make_row(st, pt)
		_list.add_child(row)


func _make_row(st: RunState, pt: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var pid := str(pt.get("id", ""))
	var type_id := str(pt.get("type", ""))
	var zh: String = SearchService.POINT_ZH.get(type_id, type_id)
	var depleted := bool(pt.get("depleted", false))
	var remain := float(pt.get("remainingYield", 0.0))
	var title := Label.new()
	title.text = "%s · 余量 %.1f%s" % [zh, remain, "（已尽）" if depleted else ""]
	box.add_child(title)

	var pile := Label.new()
	pile.text = LootPileService.summary_text(pt)
	box.add_child(pile)

	if not _member_pick.has(pid):
		_member_pick[pid] = []
	box.add_child(_make_member_picker(st, pid))

	var tasks := SearchService.active_tasks_for_point(st, pid)
	var prog := Label.new()
	if tasks.is_empty():
		prog.text = "无进行中任务"
	else:
		var bits: PackedStringArray = []
		for t in tasks:
			bits.append("%.0f%%" % (SearchService.task_progress(t) * 100.0))
		prog.text = "进度 " + ", ".join(bits)
	box.add_child(prog)

	var hauls := HaulService.active_tasks_for_point(st, pid)
	var haul_lbl := Label.new()
	if hauls.is_empty():
		haul_lbl.text = "搬运 无"
	else:
		var hb: PackedStringArray = []
		for h in hauls:
			hb.append(
				"%s %.0f%%"
				% [str(h.get("inventoryKey", "")), HaulService.task_progress(h) * 100.0]
			)
		haul_lbl.text = "搬运 " + ", ".join(hb)
	box.add_child(haul_lbl)

	var row_btns := HBoxContainer.new()
	row_btns.add_theme_constant_override("separation", 8)
	var btn_go := Button.new()
	btn_go.text = "开始搜索"
	btn_go.disabled = depleted or remain <= 0.0
	btn_go.pressed.connect(func() -> void: _assign(pid))
	row_btns.add_child(btn_go)
	var btn_recall := Button.new()
	btn_recall.text = "召回"
	btn_recall.disabled = tasks.is_empty()
	btn_recall.pressed.connect(func() -> void: _recall(pid))
	row_btns.add_child(btn_recall)
	var btn_haul := Button.new()
	btn_haul.text = "派杂工搬"
	btn_haul.disabled = LootPileService.total_amount(pt) <= 0.0
	btn_haul.pressed.connect(func() -> void: _haul(pid))
	row_btns.add_child(btn_haul)
	var btn_haul_recall := Button.new()
	btn_haul_recall.text = "停搬"
	btn_haul_recall.disabled = hauls.is_empty()
	btn_haul_recall.pressed.connect(func() -> void: _recall_haul(pid))
	row_btns.add_child(btn_haul_recall)
	box.add_child(row_btns)
	return box


func _make_member_picker(st: RunState, point_id: String) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	var cap := Label.new()
	cap.text = "点名："
	wrap.add_child(cap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var picked: Array = _member_pick.get(point_id, [])
	for m in MemberPicker.sorted_for_search(st):
		var mid := str(m.get("id", ""))
		var cb := CheckBox.new()
		cb.text = MemberPicker.label_for(m)
		cb.disabled = not MemberPicker.can_search(m)
		cb.button_pressed = mid in picked
		cb.toggled.connect(func(pressed: bool) -> void: _toggle_member(point_id, mid, pressed, cb))
		row.add_child(cb)
	if st.members.is_empty():
		var lone := Label.new()
		lone.text = "（无成员表，自动派人）"
		row.add_child(lone)
	wrap.add_child(row)
	return wrap


func _toggle_member(point_id: String, member_id: String, pressed: bool, cb: CheckBox) -> void:
	var picked: Array = _member_pick.get(point_id, []).duplicate()
	if pressed:
		if member_id not in picked:
			if picked.size() >= MemberPicker.MAX_PARTY:
				if cb:
					cb.set_pressed_no_signal(false)
				return
			picked.append(member_id)
	else:
		picked.erase(member_id)
	_member_pick[point_id] = picked


func _assign(point_id: String) -> void:
	var ids: Array = _member_pick.get(point_id, []).duplicate()
	IntentBus.emit_intent("ASSIGN_SEARCH", {"pointId": point_id, "memberIds": ids})


func _recall(point_id: String) -> void:
	IntentBus.emit_intent("RECALL_SEARCH", {"pointId": point_id})


func _haul(point_id: String) -> void:
	IntentBus.emit_intent("ASSIGN_HAUL", {"pointId": point_id, "memberId": ""})


func _recall_haul(point_id: String) -> void:
	IntentBus.emit_intent("RECALL_HAUL", {"pointId": point_id})


func _on_close() -> void:
	IntentBus.emit_intent("CLOSE_SEARCH")


func _close() -> void:
	if visible:
		get_tree().paused = false
	visible = false