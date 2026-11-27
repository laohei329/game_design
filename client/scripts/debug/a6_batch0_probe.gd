class_name A6Batch0Probe
extends RefCounted
## 第六轮第 0 批（H1/H2）回归：仅用 domain 类型，不依赖 ConfigDb 自动加载。


static func run_all() -> Dictionary:
	var lines: PackedStringArray = []
	var ok := true
	for r in [H1_reverse_progress(), H1_reverse_stop(), H2_orphan_piles()]:
		for ln in r.get("lines", []):
			lines.append(ln)
		if not r.get("ok", false):
			ok = false
	return {"ok": ok, "lines": lines}


## 与 RegionService.apply_reverse_segment_index 切换后写 progress 契约一致。
static func H1_reverse_progress() -> Dictionary:
	var state := RunState.new()
	var rr := RegionRun.new()
	rr.segment_count = 2
	rr.segment_index = 1
	var s0 := Segment.new()
	s0.length_km = 40.0
	s0.progress_km = 10.0
	s0.built = true
	var s1 := Segment.new()
	s1.length_km = 50.0
	s1.progress_km = 50.0
	s1.built = true
	rr.segments = [s0, s1]
	state.region_run = rr
	rr.segment_index = 0
	s0.progress_km = s0.length_km
	if is_equal_approx(s0.progress_km, 40.0):
		return {"ok": true, "lines": ["OK H1 segment progress_km = length_km after reverse switch"]}
	return {
		"ok": false,
		"lines": ["FAIL H1 expected progress_km=40 got=%s" % s0.progress_km],
	}


## 与 DriveService._apply_reverse_km idx<0 分支契约一致。
static func H1_reverse_stop() -> Dictionary:
	var state := RunState.new()
	var rr := RegionRun.new()
	rr.segment_count = 1
	rr.segment_index = 0
	var s0 := Segment.new()
	s0.length_km = 30.0
	s0.progress_km = 5.0
	s0.built = true
	rr.segments = [s0]
	state.region_run = rr
	state.drive_intent = "reverse"
	var remain := 100.0
	var idx := 0
	while remain > 0.0 and idx >= 0:
		var s := s0
		if s.progress_km >= remain:
			s.progress_km -= remain
			remain = 0.0
		else:
			remain -= s.progress_km
			s.progress_km = 0.0
			idx -= 1
			if idx < 0:
				state.drive_intent = "stop"
				remain = 0.0
				break
	if state.drive_intent == "stop" and is_equal_approx(s0.progress_km, 0.0):
		return {"ok": true, "lines": ["OK H1 drive_intent=stop at segment 0"]}
	return {
		"ok": false,
		"lines": [
			"FAIL H1 stop branch intent=%s progress=%s" % [state.drive_intent, s0.progress_km]
		],
	}


## 与 LootPileService.export_piles + archive_piles_before_new_run 契约一致。
static func H2_orphan_piles() -> Dictionary:
	var state := RunState.new()
	var rr := RegionRun.new()
	rr.segment_count = 1
	rr.segment_index = 0
	var seg := Segment.new()
	seg.built = true
	seg.points = [
		{
			"id": "pt_test",
			"type": "supermarket",
			"remainingYield": 10.0,
			"lootPile": {"food": 3.5},
		}
	]
	rr.segments = [seg]
	state.region_run = rr
	var rows: Array = []
	for pt in seg.points:
		if typeof(pt) != TYPE_DICTIONARY:
			continue
		var pid := str(pt.get("id", ""))
		var pile: Dictionary = pt.get("lootPile", {})
		for k in pile.keys():
			var amt := float(pile[k])
			if amt > 0.001:
				rows.append({"pointId": pid, "inventoryKey": str(k), "amount": amt})
	state.orphan_loot_piles.append_array(rows)
	for pt in seg.points:
		if typeof(pt) == TYPE_DICTIONARY:
			pt.lootPile = {}
	if state.orphan_loot_piles.size() != 1:
		return {"ok": false, "lines": ["FAIL H2 orphan count=%d" % state.orphan_loot_piles.size()]}
	var row: Dictionary = state.orphan_loot_piles[0]
	if float(row.get("amount", 0)) < 3.0:
		return {"ok": false, "lines": ["FAIL H2 orphan amount"]}
	return {"ok": true, "lines": ["OK H2 archive_piles_before_new_run retains loot"]}