extends PanelContainer
## 搜索与搬运（UI-4）：点位列表 + 点名 → ASSIGN_SEARCH / ASSIGN_HAUL / RECALL_*。
## 开面板**不** `get_tree().paused`：日钟继续，进度条 `_process` 高频刷新（静态度仍靠 `state_changed`）。

@onready var _list: VBoxContainer = $Margin/VBox/PointList
@onready var _caps: Label = $Margin/VBox/Caps
@onready var _crew_jobs: VBoxContainer = $Margin/VBox/CrewJobs
@onready var _btn_close: Button = $Margin/VBox/Close

## pointId -> Array[String] member ids（最多 4）
var _member_pick: Dictionary = {}
## pointId -> { search_bar, haul_bar, pile, title, row_btns... }
var _row_widgets: Dictionary = {}
var _last_task_signature: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_btn_close.pressed.connect(_on_close)
	GameSession.state_changed.connect(_sync)
	visible = false
	_sync()


func _process(_delta: float) -> void:
	var st := GameSession.state
	if not visible or st == null or not st.search_panel_open:
		return
	_refresh_caps(st)
	_update_progress_widgets(st)


## 列出当前段 `points[]`；结构变化时重建行，否则只刷进度。
func _sync() -> void:
	var st := GameSession.state
	if st == null or not st.search_panel_open:
		_close()
		return
	visible = true
	_btn_close.text = LocaleApi.tr_key("ui.btn.close")
	_rebuild_crew_jobs(st)
	var sig := _task_signature(st)
	if sig != _last_task_signature or _list.get_child_count() == 0:
		_last_task_signature = sig
		_rebuild_points(st)
	else:
		_refresh_caps(st)
		_update_pile_and_titles(st)
		_update_progress_widgets(st)
		_refresh_row_buttons(st)


func _task_signature(st: RunState) -> String:
	var parts: PackedStringArray = []
	for t in st.search_tasks:
		if typeof(t) == TYPE_DICTIONARY:
			parts.append(
				"s:%s:%s"
				% [str(t.get("pointId", "")), "1" if bool(t.get("complete", false)) else "0"]
			)
	for t in st.haul_tasks:
		if typeof(t) == TYPE_DICTIONARY:
			parts.append(
				"h:%s:%s"
				% [str(t.get("pointId", "")), "1" if bool(t.get("complete", false)) else "0"]
			)
	var seg := st.region_run.active_segment() if st.region_run else null
	var n_pts := seg.points.size() if seg else 0
	return "%d|%s" % [n_pts, ",".join(parts)]


func _rebuild_crew_jobs(st: RunState) -> void:
	for c in _crew_jobs.get_children():
		c.queue_free()
	var heading := Label.new()
	heading.text = LocaleApi.tr_key("search.crew.jobs")
	_crew_jobs.add_child(heading)
	var jobs := MemberRoster.job_select_options()
	for m in st.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var mid := str(m.get("id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_lbl := Label.new()
		name_lbl.text = str(m.get("name", mid))
		name_lbl.custom_minimum_size = Vector2(72, 0)
		row.add_child(name_lbl)
		var opt := OptionButton.new()
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cur := str(m.get("job", "none"))
		var select_i := 0
		for i in jobs.size():
			var jid := str(jobs[i])
			opt.add_item(LocaleApi.tr_code("job", jid, jid), i)
			opt.set_item_metadata(i, jid)
			if jid == cur:
				select_i = i
		opt.select(select_i)
		var busy := str(m.get("taskState", "idle")) not in ["idle", "none"]
		opt.disabled = busy
		opt.item_selected.connect(
			func(idx: int) -> void: _on_job_picked(mid, opt.get_item_metadata(idx))
		)
		row.add_child(opt)
		_crew_jobs.add_child(row)


func _on_job_picked(member_id: String, job_id: Variant) -> void:
	if typeof(job_id) != TYPE_STRING:
		return
	IntentBus.emit_intent("SET_MEMBER_JOB", {"memberId": member_id, "job": job_id})


func _refresh_caps(st: RunState) -> void:
	_caps.text = LocaleApi.trf(
		"search.caps",
		[
			st.food,
			InventoryService.stock_cap(st, "food"),
			st.water,
			InventoryService.stock_cap(st, "water"),
			SearchRules.cap(),
		]
	)


## 当前段搜索点列表：cap/任务状态/堆预览。
func _rebuild_points(st: RunState) -> void:
	for c in _list.get_children():
		c.queue_free()
	_row_widgets.clear()
	var seg := st.region_run.active_segment() if st.region_run else null
	if seg == null:
		return
	_refresh_caps(st)
	for pt in seg.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		var row := _make_row(st, pt)
		_list.add_child(row)


## 工厂：单搜索点一行 UI（指派/召回/haul 按钮绑定 pointId）。
func _make_row(st: RunState, pt: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var pid := str(pt.get("id", ""))
	var type_id := str(pt.get("type", ""))
	var type_lbl := SearchService.point_label(type_id)
	var depleted := bool(pt.get("depleted", false))
	var remain := float(pt.get("remainingYield", 0.0))
	var title := Label.new()
	var suf := LocaleApi.tr_key("search.point.depleted") if depleted else ""
	title.text = LocaleApi.trf("search.point.title", [type_lbl, remain, suf])
	box.add_child(title)

	var pile := Label.new()
	pile.text = LootPileService.summary_text(pt)
	box.add_child(pile)

	if not _member_pick.has(pid):
		_member_pick[pid] = []
	box.add_child(_make_member_picker(st, pid))

	var search_bar := ProgressBar.new()
	search_bar.custom_minimum_size = Vector2(180, 18)
	search_bar.show_percentage = true
	box.add_child(search_bar)

	var haul_bar := ProgressBar.new()
	haul_bar.custom_minimum_size = Vector2(180, 18)
	haul_bar.show_percentage = true
	box.add_child(haul_bar)

	var row_btns := HBoxContainer.new()
	row_btns.add_theme_constant_override("separation", 8)
	var btn_go := Button.new()
	btn_go.text = LocaleApi.tr_key("search.btn.search")
	btn_go.disabled = depleted or remain <= 0.0
	btn_go.pressed.connect(func() -> void: _assign(pid))
	row_btns.add_child(btn_go)
	var btn_recall := Button.new()
	btn_recall.text = LocaleApi.tr_key("search.btn.recall")
	btn_recall.pressed.connect(func() -> void: _recall(pid))
	row_btns.add_child(btn_recall)
	var btn_haul := Button.new()
	btn_haul.text = LocaleApi.tr_key("search.btn.haul")
	btn_haul.pressed.connect(func() -> void: _haul(pid))
	row_btns.add_child(btn_haul)
	var btn_haul_recall := Button.new()
	btn_haul_recall.text = LocaleApi.tr_key("search.btn.haul_recall")
	btn_haul_recall.pressed.connect(func() -> void: _recall_haul(pid))
	row_btns.add_child(btn_haul_recall)
	box.add_child(row_btns)

	_row_widgets[pid] = {
		"title": title,
		"pile": pile,
		"search_bar": search_bar,
		"haul_bar": haul_bar,
		"btn_go": btn_go,
		"btn_recall": btn_recall,
		"btn_haul": btn_haul,
		"btn_haul_recall": btn_haul_recall,
	}
	_update_point_widgets(st, pid, pt)
	return box


func _update_progress_widgets(st: RunState) -> void:
	var seg := st.region_run.active_segment() if st.region_run else null
	if seg == null:
		return
	for pt in seg.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		var pid := str(pt.get("id", ""))
		if _row_widgets.has(pid):
			_update_point_widgets(st, pid, pt)


func _update_pile_and_titles(st: RunState) -> void:
	var seg := st.region_run.active_segment() if st.region_run else null
	if seg == null:
		return
	for pt in seg.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		var pid := str(pt.get("id", ""))
		if not _row_widgets.has(pid):
			continue
		var w: Dictionary = _row_widgets[pid]
		var type_lbl := SearchService.point_label(str(pt.get("type", "")))
		var depleted := bool(pt.get("depleted", false))
		var remain := float(pt.get("remainingYield", 0.0))
		var suf := LocaleApi.tr_key("search.point.depleted") if depleted else ""
		w.title.text = LocaleApi.trf("search.point.title", [type_lbl, remain, suf])
		w.pile.text = LootPileService.summary_text(pt)


func _refresh_row_buttons(st: RunState) -> void:
	var seg := st.region_run.active_segment() if st.region_run else null
	if seg == null:
		return
	for pt in seg.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		var pid := str(pt.get("id", ""))
		if not _row_widgets.has(pid):
			continue
		var depleted := bool(pt.get("depleted", false))
		var remain := float(pt.get("remainingYield", 0.0))
		var tasks := SearchService.active_tasks_for_point(st, pid)
		var hauls := HaulService.active_tasks_for_point(st, pid)
		var w: Dictionary = _row_widgets[pid]
		w.btn_go.disabled = depleted or remain <= 0.0
		w.btn_recall.disabled = tasks.is_empty()
		w.btn_haul.disabled = LootPileService.total_amount(pt) <= 0.0
		w.btn_haul_recall.disabled = hauls.is_empty()


func _update_point_widgets(st: RunState, pid: String, pt: Dictionary) -> void:
	if not _row_widgets.has(pid):
		return
	var w: Dictionary = _row_widgets[pid]
	var tasks := SearchService.active_tasks_for_point(st, pid)
	if tasks.is_empty():
		w.search_bar.value = 0.0
		w.search_bar.tooltip_text = LocaleApi.tr_key("search.task.none")
	else:
		var best := 0.0
		for t in tasks:
			best = maxf(best, SearchService.task_progress(t))
		w.search_bar.value = best * 100.0
		w.search_bar.tooltip_text = LocaleApi.tr_key("search.task.progress")
	var hauls := HaulService.active_tasks_for_point(st, pid)
	if hauls.is_empty():
		w.haul_bar.value = 0.0
		w.haul_bar.tooltip_text = LocaleApi.tr_key("search.haul.none")
	else:
		var best_h := 0.0
		var keys: PackedStringArray = []
		for h in hauls:
			best_h = maxf(best_h, HaulService.task_progress(h))
			keys.append(str(h.get("inventoryKey", "")))
		w.haul_bar.value = best_h * 100.0
		w.haul_bar.tooltip_text = LocaleApi.tr_key("search.haul.prefix") + ", ".join(keys)


## 多选 labor 列表，同步 `picked` 与 SearchRules。
func _make_member_picker(st: RunState, point_id: String) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	var cap := Label.new()
	cap.text = LocaleApi.tr_key("search.picker.caption")
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
		lone.text = LocaleApi.tr_key("search.picker.auto")
		row.add_child(lone)
	wrap.add_child(row)
	return wrap


## 切换某成员是否加入本次搜索队。
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


## 本地校验后 `ASSIGN_SEARCH` intent。
func _assign(point_id: String) -> void:
	var ids: Array = _member_pick.get(point_id, []).duplicate()
	IntentBus.emit_intent("ASSIGN_SEARCH", {"pointId": point_id, "memberIds": ids})


## `RECALL_SEARCH` 取消该点任务。
func _recall(point_id: String) -> void:
	IntentBus.emit_intent("RECALL_SEARCH", {"pointId": point_id})


## 发起搬运：`HAUL_FROM_PILE`（杂工任务）。
func _haul(point_id: String) -> void:
	IntentBus.emit_intent("ASSIGN_HAUL", {"pointId": point_id, "memberId": ""})


## 取消搬运任务。
func _recall_haul(point_id: String) -> void:
	IntentBus.emit_intent("RECALL_HAUL", {"pointId": point_id})


## 关闭按钮 → `_close`。
func _on_close() -> void:
	IntentBus.emit_intent("CLOSE_SEARCH")


## `search_panel_open=false`。
func _close() -> void:
	visible = false
	_row_widgets.clear()
	_last_task_signature = ""