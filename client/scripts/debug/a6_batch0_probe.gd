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


## 与 LootPileService 换跨度归档 + orphan: 点位取货契约一致（H2R）。
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
	LootPileService.archive_piles_before_new_run(state)
	if state.orphan_loot_piles.size() != 1:
		return {"ok": false, "lines": ["FAIL H2 orphan count=%d" % state.orphan_loot_piles.size()]}
	var row: Dictionary = state.orphan_loot_piles[0]
	var pid := str(row.get("pointId", ""))
	if not LootPileService.is_orphan_point_id(pid):
		return {"ok": false, "lines": ["FAIL H2 expected orphan: prefix got=%s" % pid]}
	if float(row.get("amount", 0)) < 3.0:
		return {"ok": false, "lines": ["FAIL H2 orphan amount"]}
	if LootPileService.find_point(state, pid).is_empty():
		return {"ok": false, "lines": ["FAIL H2 find_point orphan"]}
	var taken := LootPileService.take(state, pid, "food", 1.5)
	if taken < 1.4:
		return {"ok": false, "lines": ["FAIL H2R orphan take got=%s" % taken]}
	if float(state.orphan_loot_piles[0].get("amount", 0)) > 2.1:
		return {"ok": false, "lines": ["FAIL H2R orphan row not reduced"]}
	return {"ok": true, "lines": ["OK H2 orphan archive + take via orphan:"]}