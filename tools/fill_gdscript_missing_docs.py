#!/usr/bin/env python3
"""Insert ## doc comments above public GDScript funcs that lack them."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "client" / "scripts"
FUNC_START = re.compile(r"^(\s*)(static\s+)?func\s+(\w+)\s*[\(:]")

DOCS: dict[str, str] = {
    "emit_intent": "派发玩法意图；唯一 UI→逻辑入口（§12.9）。",
    "all_event_ids": "索引表内全部 eventId（去重前合并各 bucket）。",
    "eligible_ids": "按当前季节/年份过滤可入池 eventId。",
    "get_card": "懒加载单张事件 JSON；缓存于 `_cards`。",
    "locale_text": "卡内多语块 → 当前语言（委托 LocaleApi）。",
    "primary_tag": "卡 `tags[0]`；缺省 `mood`，用于抽卡重复惩罚。",
    "on_segment_build": "段 built 后抽一次 event_id 并尝试开弹窗。",
    "draw_event_id": "加权抽卡；空池则随机一项。",
    "choose_option": "结算选项 immediate/延迟 op；写 segment 事件态。",
    "fire_delayed": "执行单条 delayedEvents 行（段解析后 apply_op）。",
    "apply_op": "单步事件 op；返回空=成功，否则机器码。",
    "expire_segment_influences": "段推进时递减 `expiresSegment` 气候影响。",
    "load_all": "按 manifest 加载 JSON 表；CSV 交 LocaleDb。",
    "get_table": "已加载根表；无则 `{}`。",
    "require": "点分路径取值；缺失 push_error。",
    "set_locale": "切换运行时语言并重建 TranslationServer。",
    "has_key": "合并表（含 Mod）是否含 ui 键。",
    "apply": "v11→v12 读档补丁。",
    "seed_from": "固定本局 PRNG 种子。",
    "randf": "均匀 [0,1) 浮点。",
    "randi_range": "闭区间整数。",
    "randi": "非负整数 % n。",
    "apply_runtime_defaults": "SaveService 读档后补 UI/运行时缺省。",
    "patch_loaded_save": "迁移链 + 缺键补丁（不写盘）。",
    "snapshot_for_save": "RunState → save dict（SaveSchema）。",
    "slot_path": "槽位 JSON 绝对路径。",
    "record": "追加一行 telemetry.jsonl。",
    "seed_starting_crew": "按 archetypes.startPartyTemplate 生成开局四人。",
    "to_dict": "导出存档/调试用 Dictionary。",
    "apply_event_tag_weight": "weight_mod：累加 tag 权重；raid 同步 raidWeightDelta。",
    "daily_speed_coef_from_hours": "F04：本日小时 → 速度/停靠油耗系数。",
    "try_open_pending_threat": "停靠且可战时消费 `pending_threat` 开遭遇。",
    "active_card": "当前段 event_id 对应卡 JSON。",
    "task_progress": "搬运任务进度 0~1。",
    "active_tasks_for_point": "某点未完成 haul 任务列表。",
    "life_mult": "生活科技库存倍率；S1a 固定 1.0。",
    "cargo_size_sum": "编组 cargo 节 size 合计。",
    "total_amount": "点位 lootPile 各键数量之和。",
    "enter_active_segment_if_needed": "段末/三选一后懒建下一段并 build。",
    "fuel_fill": "当前油量 / 油舱容量 0~1。",
    "offer_defer_reason": "进站要约 defer 原因码（hud_hints）。",
    "tip_for_abandon": "遗弃面板 fuel-fill 相关 tip 键。",
    "toggle": "切换 F3 调试 Overlay 显示。",
    "errors_config_paths": "冒烟：ConfigDb 必需路径与交叉校验。",
    "errors_start_crew": "冒烟：开局四人岗位/名册。",
    "errors_fuel_uses_config": "冒烟：F04 用表内 base 非硬编码。",
    "audit_after_triplet_end_day": "冒烟：连点三日结后资源/日历变化。",
    "errors_climate_region_mult": "冒烟：三选一后 region_fuel_mult。",
    "errors_guarantee_offer": "冒烟：guarantee 链路可出 offer。",
    "audit_tutorial_hang": "冒烟：教程挂车节数/parts。",
    "errors_min_power_rule": "冒烟：末节动力不可遗弃。",
    "errors_abandon_cargo": "冒烟：遗弃货舱扣件/节数。",
    "errors_search_telemetry": "冒烟：搜索 assign + telemetry。",
    "errors_combat_l1": "冒烟：L1 遭遇与检定链。",
    "errors_tech_power_lv1": "冒烟：动力 Lv1 扣件。",
    "errors_start_precision": "冒烟：开局 precision。",
    "errors_region_pick_tundra": "冒烟：三选一雪原 mult。",
    "season_index_for_day": "day_total → 季节序号 0..3。",
    "season_name_for_day": "day_total → spring|summer|autumn|winter。",
    "year_for_day": "day_total → 游戏年 1..。",
    "day_in_season_for_day": "day_total → 季内日 1..30。",
    "sync_calendar_fields": "写 RunState 四季/年/季日。",
    "advance_day": "日历 +1 并同步季节字段。",
    "sync_region_influence": "regionId → climate_influences 预设。",
    "build_weights": "本段天气加权表（季节×区域×节点）。",
    "draw_weather_id": "掷 segment.weather_id（built 时一次）。",
    "sync_weather_from_active_segment": "当前段 weatherId → RunState.weather_id。",
    "on_segment_build": "新段掷天气并写入 segment。",
    "_index": "events/_index.json 表根。",
    "_card_path": "event_id → res://data/events/... 路径。",
    "draw_rules": "event_draw_rules.json 根。",
    "scenario_event_rate": "balance×难度 eventDrawRate 全局乘子。",
    "try_day_end_recruit": "日结补抽；尊重 lastRecruitSuccessDay。",
    "try_recruit_one": "事件收留：有空床加一名 labor。",
    "queue_pending_threat": "无法立刻开战时写入 pending_threat。",
    "_threat_aliases": "combat.threatTemplateAliases 表。",
    "_inventory_cfg": "balance.inventory 根。",
    "_base_cap": "单资源基础上限（不含货舱）。",
    "_collective_morale": "成员 mood 均值 + morale_offset（04 §9.3）。",
    "_step_7c_day_end_recruit": "日结步骤 7c：收留补抽。",
    "errors_recruit_morale_save": "冒烟：收留门闩/事件率/moraleZeroStreak 存档。",
}


def has_doc_above(out: list[str]) -> bool:
    j = len(out) - 1
    while j >= 0 and out[j].strip() == "":
        j -= 1
    return j >= 0 and out[j].strip().startswith("##")


def doc_for(name: str) -> str | None:
    if name in DOCS:
        return "## " + DOCS[name]
    if name.startswith("errors_"):
        return f"## 冒烟断言 `{name}`；非空=失败原因列表。"
    # 无 DOCS 词条则跳过；多行说明手写或 enrich_core_service_docs.py
    return None


def process_file(path: Path) -> bool:
    lines = path.read_text(encoding="utf-8").splitlines()
    out: list[str] = []
    i = 0
    changed = False
    while i < len(lines):
        m = FUNC_START.match(lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        name = m.group(3)
        if name == "_ready":
            out.append(lines[i])
            i += 1
            continue
        if not has_doc_above(out):
            auto = doc_for(name)
            if auto:
                if out and out[-1].strip() != "":
                    out.append("")
                out.append(auto)
                changed = True
        out.append(lines[i])
        i += 1
    new_text = "\n".join(out)
    if path.read_text(encoding="utf-8").endswith("\n"):
        new_text += "\n"
    if changed:
        path.write_text(new_text, encoding="utf-8")
    return changed


def main() -> int:
    n = 0
    for p in sorted(ROOT.rglob("*.gd")):
        if process_file(p):
            n += 1
            print("updated", p.relative_to(ROOT))
    print("files_updated", n)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())