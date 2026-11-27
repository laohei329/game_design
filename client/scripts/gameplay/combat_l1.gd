class_name CombatL1
extends RefCounted

const _PopulationRules := preload("res://scripts/domain/population_rules.gd")
## L1 小股战斗检定 + 非战斗路径（S1b 薄切片，L2/L3 未实现）。
##
## 状态（RunState）：
##   - `formations[]` / `active_formation_id`：上场编队（combatRoster 成员，最多 8 槽）
##   - `pending_combat`：当前遭遇 { layer, enemyCount, threat }；**不入盘**，读档后为空
##   - `combat_panel_open` / `combat_l1_after_fail`：UI 与 L1 失败后二选一（撤退 / 升级占位）
##
## 战力比 D = P / (P+E)：`power_p` 用守卫+装甲车+armor_tech；`power_e` = 敌人数 × l1Unit。
## 检定成功率 = base + scaleD×D（读 combat.json l1Success）。
##
## 非战斗四条：negotiate / bypass / horn（扣油%）/ evacuate（六元全 0 才可选）。
## 无编队：不可 L1 强攻，但可走非战斗（D 视为 0）。
##
## Intent：OPEN_COMBAT · RESOLVE_COMBAT_L1_CHECK · RESOLVE_NON_COMBAT · RESOLVE_COMBAT_L1_FAIL · CLOSE_COMBAT


## 非战路径按钮文案键前缀 `combat.tactic.*`（见 LocaleDb / ui.csv）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param path_id 非战路径 id
## @return 空串=成功；非空=机器错误码。
static func path_label(path_id: String) -> String:
	return LocaleApi.tr_code("combat.tactic", path_id, path_id)


## 战斗表根节点（data/combat.json），含 l1Success、nonCombat、guardBase 等。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @return 结果字典；缺失语义键时可能为空 {}。
static func combat_cfg() -> Dictionary:
	return ConfigDb.get_table("combat")


static func _c_f(path: String) -> float:
	return float(ConfigDb.require("combat." + path))


static func _c_i(path: String) -> int:
	return int(ConfigDb.require("combat." + path))


## NEW_RUN / 旧档缺 formations 时：把 combatRoster 成员填入单编队 fmt_default。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
static func seed_default_formation(state: RunState) -> void:
	var slots: Array = []
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if not bool(m.get("combatRoster", false)):
			continue
		var mid := str(m.get("id", ""))
		if mid.is_empty():
			continue
		slots.append({"memberId": mid, "slotId": "front_%d" % (slots.size() + 1)})
		if slots.size() >= _c_i("formationMaxSlots"):
			break
	state.formations = [
		{
			"id": "fmt_default",
			"name": "默认编队",
			"slots": slots,
			"reserve": [],
		},
	]
	state.active_formation_id = "fmt_default" if not slots.is_empty() else ""


## 当前 `active_formation_id` 对应的编队字典；无匹配返回 {}。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 结果字典；缺失语义键时可能为空 {}。
static func active_formation(state: RunState) -> Dictionary:
	for f in state.formations:
		if typeof(f) == TYPE_DICTIONARY and str(f.get("id", "")) == state.active_formation_id:
			return f
	return {}


## 上场槽位中的 memberId 列表（顺序即前排槽位），用于 P 值与 HP 结算。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 数组结果（列表/选项）。
static func field_member_ids(state: RunState) -> Array:
	var fmt := active_formation(state)
	var out: Array = []
	if fmt.is_empty():
		return out
	for row in fmt.get("slots", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var mid := str(row.get("memberId", ""))
		if mid != "":
			out.append(mid)
	return out


## 是否允许 L1 强攻检定（有编队且槽位非空）；无编队仍可走非战斗路径。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func has_combat_field(state: RunState) -> bool:
	if state.active_formation_id.is_empty():
		return false
	return not field_member_ids(state).is_empty()


## 开发/冒烟入口：停靠、无车外任务；敌人数钳在 layerRouting.stopMaxCountL1。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param enemy_count 遭遇敌人数（L1 层）
## @return 空串=成功；非空=机器错误码。
static func open_encounter(state: RunState, enemy_count: int) -> String:
	if state.drive_intent != "stop":
		return "must_stop"
	if TrainService.has_outdoor_tasks(state):
		return "outdoor_busy"
	var max_l1 := _c_i("layerRouting.stopMaxCountL1")
	enemy_count = clampi(enemy_count, 1, max_l1)
	state.pending_combat = {
		"layer": "L1",
		"enemyCount": enemy_count,
		"threat": "normal",
	}
	state.combat_l1_after_fail = false
	state.combat_panel_open = true
	state.pending_threat.clear()
	return ""


## 威胁表驱动遭遇；别名见 `combat.threatTemplateAliases`。
##
## 事件/点位/待战威胁共用；`must_stop` / `outdoor_busy` 时应走 `queue_pending_threat`。
## @param state 当前局 `RunState`（就地修改字段）
## @param template_id 车厢/威胁模板 id
## @param extra 遭遇元数据（source/eventId/pointId）
## @return 空串=成功；非空=机器错误码。
static func open_from_template(state: RunState, template_id: String, extra: Dictionary = {}) -> String:
	var tpl := _resolve_threat_template(template_id)
	if tpl.is_empty():
		return "unknown_threat"
	var layer := str(tpl["layerDefault"])
	var count_min := int(tpl["countMin"])
	var count_max := int(tpl["countMax"])
	var count := RngService.randi_range(count_min, count_max)
	var max_l1 := _c_i("layerRouting.stopMaxCountL1")
	count = clampi(count, 1, max_l1)
	if state.drive_intent != "stop":
		return "must_stop"
	if TrainService.has_outdoor_tasks(state):
		return "outdoor_busy"
	state.pending_combat = {
		"layer": "L1",
		"enemyCount": count,
		"threat": template_id,
		"threatTemplateId": str(tpl.get("id", template_id)),
		"source": str(extra.get("source", "")),
		"pointId": str(extra.get("pointId", "")),
		"eventId": str(extra.get("eventId", "")),
	}
	state.combat_l1_after_fail = false
	state.combat_panel_open = true
	state.pending_threat.clear()
	return ""


## 行驶中 / 车外任务无法立刻开战时排队；停靠且户外任务清空后 `try_open_pending_threat`。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param template_id 车厢/威胁模板 id
## @param extra 遭遇元数据（source/eventId/pointId）
static func queue_pending_threat(state: RunState, template_id: String, extra: Dictionary = {}) -> void:
	if template_id.is_empty():
		return
	state.pending_threat = {
		"threatTemplateId": template_id,
		"source": str(extra.get("source", "event")),
		"eventId": str(extra.get("eventId", "")),
		"pointId": str(extra.get("pointId", "")),
	}
	TelemetryService.record("pending_threat_queued", {"template": template_id})

## 停靠且可战时消费 `pending_threat` 开遭遇。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 空串=成功；非空=机器错误码。
static func try_open_pending_threat(state: RunState) -> String:
	if state.pending_threat.is_empty():
		return ""
	if state.combat_panel_open:
		return ""
	var tpl := str(state.pending_threat.get("threatTemplateId", ""))
	if tpl.is_empty():
		state.pending_threat.clear()
		return ""
	var extra := state.pending_threat.duplicate()
	extra.erase("threatTemplateId")
	var err := open_from_template(state, tpl, extra)
	if err == "":
		state.pending_threat.clear()
		return ""
	if err in ["must_stop", "outdoor_busy", "unknown_threat"]:
		return err
	state.pending_threat.clear()
	return err

## combat.threatTemplateAliases 表。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @return 结果字典；缺失语义键时可能为空 {}。
static func _threat_aliases() -> Dictionary:
	var raw: Variant = combat_cfg().get("threatTemplateAliases", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out := {}
	for k in raw.keys():
		out[str(k)] = str(raw[k])
	return out

## `threatTemplateId` 经 `combat.threatTemplateAliases` 别名表解析为真实模板 id。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param template_id 车厢/威胁模板 id
## @return 结果字典；缺失语义键时可能为空 {}。
static func _resolve_threat_template(template_id: String) -> Dictionary:
	var id := str(_threat_aliases().get(template_id, template_id))
	var root: Variant = ConfigDb.get_table("combat_targets").get("targets", [])
	if typeof(root) != TYPE_ARRAY:
		return {}
	for raw in root:
		if typeof(raw) == TYPE_DICTIONARY and str(raw.get("id", "")) == id:
			return raw
	return {}


## 强攻按钮门控：空串=可检定；否则 no_encounter / no_formation / must_stop。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 空串=允许；非空=阻断原因码。
static func can_l1_check(state: RunState) -> String:
	if state.pending_combat.is_empty():
		return "no_encounter"
	if not has_combat_field(state):
		return "no_formation"
	if state.drive_intent != "stop":
		return "must_stop"
	return ""


## 非战路径门控：negotiate/bypass 无额外消耗；horn 验油；evacuate 验六元全 0。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param path 非战斗路径 id（negotiate/bypass/horn/evacuate）
## @return 空串=允许；非空=阻断原因码。
static func can_non_combat_path(state: RunState, path: String) -> String:
	if state.pending_combat.is_empty():
		return "no_encounter"
	if state.drive_intent != "stop":
		return "must_stop"
	match path:
		"negotiate", "bypass":
			return ""
		"horn":
			var need := _c_f("nonCombat.hornFuelCostPct")
			var cost := state.fuel_cap() * need / 100.0
			if state.fuel < cost:
				return "fuel"
			return ""
		"evacuate":
			if not _core_six_all_zero(state):
				return "not_evacuable"
			return ""
		_:
			return "invalid_path"


## 友方战力 P：上场成员 guardBase（combat_drill 加成）+ 装甲车×12 + armor_tech×4。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 浮点结果（量/比率/工时）。
static func power_p(state: RunState) -> float:
	var cfg := combat_cfg()
	var guard_base := _c_f("guardBase")
	var drill_mult := _c_f("combatDrill.guardMult")
	var b := 0.0
	var ids := field_member_ids(state)
	for mid in ids:
		var g := guard_base
		var m := _member(state, mid)
		if m.is_empty():
			continue
		var specs: Variant = m.get("specialties", [])
		if typeof(specs) == TYPE_ARRAY and "combat_drill" in specs:
			g *= drill_mult
		b += g
	b += float(_armor_car_count(state)) * float(ConfigDb.require("combat.l1ArmorCarPower"))
	b += float(state.armor_tech) * float(ConfigDb.require("combat.l1ArmorTechPerLevel"))
	return maxf(b, 0.0)


## 敌方战力 E = enemy_count × combat.l1Unit（默认 8）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param enemy_count 遭遇敌人数（L1 层）
## @return 浮点结果（量/比率/工时）。
static func power_e(enemy_count: int) -> float:
	var unit := _c_f("l1Unit")
	return float(enemy_count) * unit


## 设计「D」：友方战力份额，用于成功率与非战路径概率。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param enemy_count 遭遇敌人数（L1 层）
## @return 浮点结果（量/比率/工时）。
static func ratio_d(state: RunState, enemy_count: int) -> float:
	var p := power_p(state)
	var e := power_e(enemy_count)
	if e <= 0.0:
		return 1.0
	return p / (p + e)


## clamp(base + scaleD×D, min, max)；参数来自 combat.l1Success。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param enemy_count 遭遇敌人数（L1 层）
## @return 浮点结果（量/比率/工时）。
static func l1_success_chance(state: RunState, enemy_count: int) -> float:
	var base := _c_f("l1Success.base")
	var scale := _c_f("l1Success.scaleD")
	var d := ratio_d(state, enemy_count)
	return clampf(
		base + scale * d,
		_c_f("l1Success.min"),
		_c_f("l1Success.max")
	)


## 非战路径成功率；无编队时 D=0；谈判有 guard 时 threatModNegotiateWithGuard。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param path 非战斗路径 id（negotiate/bypass/horn/evacuate）
## @return 浮点结果（量/比率/工时）。
static func non_combat_chance(state: RunState, path: String) -> float:
	var base := _c_f("nonCombat.pathChanceBase")
	var scale := _c_f("nonCombat.pathChanceScaleD")
	var d := ratio_d(state, int(state.pending_combat.get("enemyCount", 1)))
	if not has_combat_field(state):
		d = 0.0
	var threat := 0.0
	if path == "negotiate" and _has_guard_on_roster(state):
		threat = _c_f("nonCombat.threatModNegotiateWithGuard")
	return clampf(
		base + scale * d - threat,
		_c_f("nonCombat.pathChanceMin"),
		_c_f("nonCombat.pathChanceMax")
	)


## 单次 RNG；成功关面板；失败设 combat_l1_after_fail 并扣血（分支见 l1Fail）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 结果字典；缺失语义键时可能为空 {}。
static func resolve_l1_check(state: RunState) -> Dictionary:
	var err := can_l1_check(state)
	if err != "":
		return {"ok": false, "error": err}
	var n := int(state.pending_combat.get("enemyCount", 1))
	_set_field_in_combat(state, true)
	var chance := l1_success_chance(state, n)
	var roll := RngService.randf()
	var success := roll <= chance
	var out := {
		"ok": true,
		"success": success,
		"p": power_p(state),
		"e": power_e(n),
		"d": ratio_d(state, n),
		"chance": chance,
	}
	if success:
		_apply_l1_success(state)
		_close_combat(state)
		TelemetryService.record("combat_l1_success", {"dayTotal": state.day_total, "enemyCount": n})
	else:
		state.combat_l1_after_fail = true
		_apply_l1_fail(state)
		TelemetryService.record("combat_l1_fail", {"dayTotal": state.day_total, "enemyCount": n})
	_set_field_in_combat(state, false)
	return out


## 成功/失败都会关遭遇；谈判失败且有编队时 L2 仅 warning（未实现）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param path 非战斗路径 id（negotiate/bypass/horn/evacuate）
## @return 结果字典；缺失语义键时可能为空 {}。
static func resolve_non_combat(state: RunState, path: String) -> Dictionary:
	var err := can_non_combat_path(state, path)
	if err != "":
		return {"ok": false, "error": err}
	var chance := non_combat_chance(state, path)
	var roll := RngService.randf()
	var success := roll <= chance
	if success:
		_apply_non_combat_success(state, path)
		_close_combat(state)
		TelemetryService.record(
			"combat_non_combat",
			{"path": path, "success": true, "dayTotal": state.day_total}
		)
		return {"ok": true, "success": true, "path": path, "chance": chance}
	_apply_non_combat_fail(state, path)
	TelemetryService.record(
		"combat_non_combat",
		{"path": path, "success": false, "dayTotal": state.day_total}
	)
	if has_combat_field(state) and path == "negotiate":
		push_warning("CombatL1: 谈判失败（有编队）— L2 强攻未实现")
	_close_combat(state)
	return {"ok": true, "success": false, "path": path, "chance": chance}


## escalate 暂按撤退处理；两者都走 _apply_bypass_fail 全队扣 HP。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @param choice L1 失败后 UI 选择（retreat/escalate 占位）
## @return 空串=成功；非空=机器错误码。
static func resolve_after_fail(state: RunState, choice: String) -> String:
	if not state.combat_l1_after_fail:
		return "no_fail_pending"
	match choice:
		"retreat":
			_apply_bypass_fail(state)
			_close_combat(state)
			return ""
		"escalate":
			push_warning("CombatL1: L2 升级未实现，按撤退处理")
			_apply_bypass_fail(state)
			_close_combat(state)
			return ""
		_:
			return "invalid_choice"


## combat_panel 正文：敌人数、P/E/D、L1 成功率（ui.csv `combat.preview.*`）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @param state 当前局 `RunState`（就地修改字段）
## @return 空串=成功；非空=机器错误码。
static func preview_text(state: RunState) -> String:
	if state.pending_combat.is_empty():
		return ""
	var n := int(state.pending_combat.get("enemyCount", 0))
	var lines := LocaleApi.trf("combat.preview.line1", [n]) + "\n"
	lines += LocaleApi.trf(
		"combat.preview.stats",
		[
			LocaleApi.ui_num(power_p(state), 1),
			LocaleApi.ui_num(power_e(n), 1),
			LocaleApi.ui_num(ratio_d(state, n), 3),
		]
	) + "\n"
	lines += LocaleApi.trf(
		"combat.preview.chance",
		[LocaleApi.ui_num(l1_success_chance(state, n) * 100.0, 1)]
	)
	if not has_combat_field(state):
		lines += "\n" + LocaleApi.tr_key("combat.preview.no_formation")
	return lines


## 遭遇结束：关 UI 旗标并清空 pending（与 CLOSE_COMBAT Intent 效果一致）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
static func _close_combat(state: RunState) -> void:
	state.combat_panel_open = false
	state.pending_combat.clear()
	state.combat_l1_after_fail = false


## 上场成员 mood += moodCombatWinL1（默认 2，上限 100）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
static func _apply_l1_success(state: RunState) -> void:
	var bonus := _c_f("moodCombatWinL1")
	for mid in field_member_ids(state):
		var m := _member(state, mid)
		if not m.is_empty():
			m["mood"] = minf(
				100.0,
				float(m.get("mood", _PopulationRules.mood_default())) + bonus
			)


## l1Fail：50% 随机 1 人 -12 HP，否则全队上场 -allHpLoss（默认 8）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
static func _apply_l1_fail(state: RunState) -> void:
	if RngService.randf() < _c_f("l1Fail.injuryBranchChance"):
		var ids := field_member_ids(state)
		if not ids.is_empty():
			var pick := str(ids[RngService.randi() % ids.size()])
			var m := _member(state, pick)
			if not m.is_empty():
				var inj := _c_f("l1Fail.injuryHpLoss")
				m["hp"] = maxf(1.0, float(m.get("hp", 100.0)) - inj)
	else:
		var loss := _c_f("l1Fail.allHpLoss")
		for mid in field_member_ids(state):
			var m := _member(state, mid)
			if not m.is_empty():
				m["hp"] = maxf(1.0, float(m.get("hp", 100.0)) - loss)


## 成功后果：谈判+士气；bypass 段油耗附加；horn 扣油%；evacuate 耗尽日行驶额度。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param path 非战斗路径 id（negotiate/bypass/horn/evacuate）
static func _apply_non_combat_success(state: RunState, path: String) -> void:
	var mood_bonus := _c_f("nonCombat.negotiateMoodBonus")
	match path:
		"negotiate":
			for m in state.members:
				if typeof(m) == TYPE_DICTIONARY:
					m["mood"] = minf(
						100.0,
						float(m.get("mood", _PopulationRules.mood_default())) + mood_bonus
					)
		"bypass":
			var seg := state.region_run.active_segment() if state.region_run else null
			if seg is Segment:
				seg.segment_fuel_surcharge = _c_f("nonCombat.bypassFuelSurcharge")
		"horn":
			var pct := _c_f("nonCombat.hornFuelCostPct")
			InventoryService.remove(state, "fuel", state.fuel_cap() * pct / 100.0)
		"evacuate":
			state.drive_hours_today = DriveService.hours_cap()


## 失败统一走 bypassFailHpLoss；鸣笛失败额外标记 hornFail（预留）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param path 非战斗路径 id（negotiate/bypass/horn/evacuate）
static func _apply_non_combat_fail(state: RunState, path: String) -> void:
	if path == "horn":
		state.pending_combat["hornFail"] = true
	_apply_bypass_fail(state)


## 全队（含后备）HP -bypassFailHpLoss（默认 15），HP 下限 1。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
static func _apply_bypass_fail(state: RunState) -> void:
	var loss := _c_f("nonCombat.bypassFailHpLoss")
	for m in state.members:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		m["hp"] = maxf(1.0, float(m.get("hp", 100.0)) - loss)


## 检定进行中上场队员 taskState=in_combat，防止重复派出搜索等。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param on 布尔开关
static func _set_field_in_combat(state: RunState, on: bool) -> void:
	var ts := "in_combat" if on else "idle"
	for mid in field_member_ids(state):
		var m := _member(state, mid)
		if not m.is_empty():
			m["taskState"] = ts


## 按 id 查成员字典引用（可原地改 hp/mood/taskState）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @param member_id 成员 id
## @return 结果字典；缺失语义键时可能为空 {}。
static func _member(state: RunState, member_id: String) -> Dictionary:
	for m in state.members:
		if typeof(m) == TYPE_DICTIONARY and str(m.get("id", "")) == member_id:
			return m
	return {}


## 车上 templateId=armor 节数，每节为 P 贡献 12 点。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @return 整数结果（计数/下标/容量）。
static func _armor_car_count(state: RunState) -> int:
	var n := 0
	for c in state.carriages:
		if str(c.get("templateId", "")) == "armor":
			n += 1
	return n


## 名册是否存在 job=guard（影响谈判威胁修正，不要求上场）。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func _has_guard_on_roster(state: RunState) -> bool:
	for m in state.members:
		if typeof(m) == TYPE_DICTIONARY and str(m.get("job", "")) == "guard":
			return true
	return false


## 徒步撤离条件：粮水油件药催化剂（chem）库存均 ≤0。
##
## 模块内部实现；调用方限于本文件或同层 Service。
## @param state 当前局 `RunState`（就地修改字段）
## @return 是否成功或条件成立。
static func _core_six_all_zero(state: RunState) -> bool:
	return (
		state.food <= 0.0
		and state.water <= 0.0
		and state.fuel <= 0.0
		and state.parts <= 0.0
		and state.medicine <= 0.0
		and state.chem <= 0.0
	)