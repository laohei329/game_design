#!/usr/bin/env python3
"""Enrich core Service ## docs: summary + blank ## + body + @param/@return (JavaDoc style)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

_TOOLS = Path(__file__).resolve().parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from core_service_paths import CORE_SERVICE_PATHS as CORE  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent / "client" / "scripts"

FUNC_START = re.compile(r"^(\s*)(static\s+)?func\s+(\w+)\s*[\(:]")
PARAM_SPLIT = re.compile(r",\s*(?=[\w]+:)")

# file → func → extra ## lines (inserted after summary blank line, before @param)
EXTRA: dict[str, dict[str, list[str]]] = {
    "economy/day_settle.gd": {
        "run": [
            "## 权威日结入口：`GameSession._advance_one_day` 在 `GameCalendar.advance_day` **之前**调用。",
            "## 仍使用结算时刻的 `day_total`（代表「刚结束的那一天」）；步骤顺序锁死 02 §8。",
        ],
    },
    "gameplay/inventory_service.gd": {
        "add": [
            "## 搬运完成、生产、事件 grant_item 等统一入库；可能因 cap 截断。",
            "## @return 实际入库量（HaulService 用返回值把溢出写回 lootPile）。",
        ],
    },
    "gameplay/combat_l1.gd": {
        "open_from_template": [
            "## 事件/点位/待战威胁共用；`must_stop` / `outdoor_busy` 时应走 `queue_pending_threat`。",
        ],
    },
    "data/save_schema.gd": {
        "to_save_dict": ["## 写盘前快照；不含 panel 旗标与 pending_combat（09 §3）。"],
        "from_save_dict": [
            "## 读盘重建 RunState；`onboard_pop` 由 TrainService 重算。",
            "## 调用方须再 `patch_loaded_save`、`LootPileService.apply_world_list`、`ClimateService.recompute`。",
        ],
    },
    "app/game_session.gd": {
        "_on_intent": [
            "## Autoload 订阅 IntentBus 的唯一 match；成功 `state_changed.emit()`。",
        ],
    },
    "gameplay/point_encounter_service.gd": {
        "try_on_search_assign": [
            "## SearchService.assign_search 成功后调用；同点同日只掷一次（store 按 day_total 分桶）。",
            "## `force=true` 跳过 RNG（冒烟/调试）。",
        ],
    },
    "rhythm/climate_service.gd": {
        "recompute": [
            "## 唯一写入 `RunState.*_climate` 与 cold/heat 指数的入口；日结步骤 1 必调。",
            "## `calendar_day=-1` 时用 `state.day_total`（供暖/挂车后亦应调用）。",
        ],
    },
    "rhythm/weather_draw.gd": {
        "on_segment_build": [
            "## RegionService.build_segment 末尾调用；段内天气不再重掷。",
        ],
    },
    "gameplay/station_defer_service.gd": {
        "offer_defer_reason": [
            "## 只产原因码，不阻止拒绝要约；文案经 StationService.offer_defer_hint。",
        ],
    },
    "gameplay/tech_service.gd": {
        "buy_upgrade": [
            "## Intent `BUY_UPGRADE` 写入口；成功可能触发 ClimateService.recompute。",
        ],
    },
    "data/save_service.gd": {
        "read_state": [
            "## 读档后 GameSession 应 `patch_loaded_save`、重建堆与气候。",
        ],
    },
}

PARAM_HINT: dict[str, str] = {
    "state": "当前局 `RunState`（就地修改字段）",
    "seg": "当前区段 `Segment`",
    "segment": "区段 `Segment`",
    "region_id": "`regions.json` 的 regionId",
    "point_id": "搜索点 id（段内 points[].id）",
    "car_id": "车厢 `carriages[].id`",
    "member_id": "成员 `members[].id`",
    "template_id": "车厢/威胁模板 id",
    "key": "库存或配置键（常经 normalize_key）",
    "inv_key": "inventory 键（food/water/…）",
    "store": "搜索遥测分桶（GameSession.search_telemetry）",
    "payload": "Intent 附带的 Dictionary",
    "offer": "车站要约快照（pending_station 形状）",
    "task": "search_tasks / haul_tasks 中单条字典",
    "card": "事件卡 JSON（EventCatalog）",
    "ctx": "EventDraw 抽卡上下文",
    "save": "存档根 Dictionary（save 12）",
    "piles": "`world.lootPiles` 扁平行列表",
    "enemy_count": "遭遇敌人数（L1 层）",
    "path": "非战斗路径 id（negotiate/bypass/horn/evacuate）",
    "choice": "L1 失败后 UI 选择（retreat/escalate 占位）",
    "mode": "驾驶意图 forward/reverse/stop（含同义词）",
    "accept": "是否接受车站要约",
    "code": "机器错误码（本地化键前缀各异）",
    "amount": "数量（float，可为小数）",
    "ratio": "比例 0~1",
    "delay_days": "延迟触发距今游戏日数",
    "next_day": "即将进入的 day_total（延迟事件比对用）",
    "hit": "find_point 返回 { segment, pointIndex, point }",
    "pt": "点位字典 points[] 元素",
    "station": "段内车站字典 stations[] 元素",
    "extra": "遭遇元数据（source/eventId/pointId）",
    "entry": "delayed_events 单行",
    "op_row": "事件 op 行（含 op/args/target）",
    "member_ids": "参与搜索的成员 id 列表",
    "member": "成员字典引用",
    "t": "任务字典（搜索/搬运）",
    "force": "跳过 RNG 或强制分支（调试）",
    "craft_day": "是否工艺日附加油耗分支",
    "speed_coef": "F04 速度系数（forward 额度折算）",
    "value": "写入库存的绝对量",
    "cap": "上限（日结 clamp 用）",
    "calendar_day": "用于气候公历日；`-1` 表示 state.day_total",
    "weather_id": "weather 表 id",
    "region_def": "regions.json 单行",
    "prefer_expansion": "玩家扩张倾向（搁置提示分支）",
    "line": "科技线 power|armor|radar|living",
    "target_lv": "目标科技等级（1-based）",
    "session_state": "写档用快照（常等同 RunState 字段包）",
    "slot": "存档槽 0..N",
    "table_name": "Config manifest 表名",
    "path": "点分配置路径",
    "block": "多语 block 或 Variant 文案块",
    "fallback": "缺翻译时的回退串",
    "season": "spring|summer|autumn|winter",
    "year": "游戏内年份",
    "day_total": "从 1 起的总局内日序",
    "intent_name": "IntentBus 意图名",
    "index": "段下标 region_run.segment_index 或名册序号",
    "count": "抽样个数",
    "length_km": "段长度（程序化生成用）",
    "weights": "加权抽键表",
    "size": "车站规模 small/medium/large",
    "condition_id": "车况 intact/damaged/wreck",
    "type_id": "搜索点类型 id",
    "path_id": "非战路径 id",
    "option_id": "事件选项 id",
    "event_id": "事件卡 id",
    "eid": "事件 id（Intent 短名）",
    "intent_name": "IntentBus 意图名",
    "locale": "语言 id（zh/en）",
    "d": "Dictionary 泛型入参",
    "rr": "`RegionRun` 实例",
    "raw": "存档原始 Variant",
    "delta": "增减量",
    "prob": "概率 0~1",
    "on": "布尔开关",
    "member_id": "成员 id",
}

RETURN_HINT: dict[str, str] = {
    "void": "## 无返回值。",
    "String": "## @return 空串=成功；非空=机器错误码。",
    "bool": "## @return 是否成功或条件成立。",
    "int": "## @return 整数结果（计数/下标/容量）。",
    "float": "## @return 浮点结果（量/比率/工时）。",
    "Dictionary": "## @return 结果字典；缺失语义键时可能为空 {}。",
    "Array": "## @return 数组结果（列表/选项）。",
    "PackedStringArray": "## @return 字符串数组。",
    "Segment": "## @return 段实例；不存在时为 null。",
    "RunState": "## @return 重建后的 RunState。",
}


def rel_key(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def parse_signature(lines: list[str], start: int) -> tuple[str, list[tuple[str, str]], str]:
    """Return (name, [(param, type)], return_type)."""
    chunk: list[str] = []
    i = start
    while i < len(lines):
        chunk.append(lines[i])
        if lines[i].rstrip().endswith(":"):
            break
        i += 1
    text = " ".join(s.strip() for s in chunk)
    m = re.search(
        r"func\s+(\w+)\s*\((.*?)\)\s*(?:->\s*([\w.]+))?",
        text.replace("\t", " "),
    )
    if not m:
        return "", [], ""
    name = m.group(1)
    ret = m.group(3) or "void"
    params_raw = m.group(2).strip()
    params: list[tuple[str, str]] = []
    if params_raw:
        for part in PARAM_SPLIT.split(params_raw):
            part = part.strip()
            if not part:
                continue
            if ":" in part:
                pname, ptype = part.split(":", 1)
                pname = pname.strip()
                ptype = ptype.strip().split("=")[0].strip()
            else:
                pname, ptype = part, ""
            if pname in ("self", "_self"):
                continue
            params.append((pname, ptype))
    return name, params, ret


def collect_doc_above(lines: list[str], func_i: int) -> tuple[int, list[str]]:
    j = func_i - 1
    while j >= 0 and lines[j].strip() == "":
        j -= 1
    end = j
    docs: list[str] = []
    while j >= 0 and lines[j].strip().startswith("##"):
        docs.insert(0, lines[j])
        j -= 1
    return j + 1, docs


def should_enrich(docs: list[str]) -> bool:
    nonempty = [d for d in docs if d.strip() != "##"]
    if not nonempty:
        return True
    if any("@param" in d or "@return" in d for d in docs):
        return False
    if len(nonempty) >= 3:
        return False
    return True


def summary_line(docs: list[str]) -> str:
    for d in docs:
        if d.strip() != "##":
            return d.strip()
    return ""


def context_lines(rel: str, name: str) -> list[str]:
    if rel in EXTRA and name in EXTRA[rel]:
        return EXTRA[rel][name]
    out: list[str] = []
    if rel == "economy/day_settle.gd" and name.startswith("_step_"):
        out.append("## 日结子步骤：仅 `DaySettle.run` 顺序调用；不直接响应 Intent。")
    elif rel == "economy/fuel_f04.gd":
        out.append("## F04 子函数：`DaySettle.run` 步骤 0/3 前读 `driveHoursToday` 与气候乘子。")
    elif rel.startswith("rhythm/"):
        out.append("## 节拍层 Service：日结、换区、段建造时调用；HUD 只读派生乘子。")
    elif rel == "gameplay/segment_build.gd":
        out.append("## `NEW_RUN` 薄入口；onSegmentBuild 加厚在 RegionService.build_segment。")
    elif rel == "gameplay/station_defer_service.gd":
        out.append("## HUD 搁置/遗弃提示专用；不改要约结算逻辑。")
    elif rel.startswith("gameplay/") and name.startswith("_"):
        out.append("## 模块内部实现；调用方限于本文件或同层 Service。")
    elif rel.startswith("gameplay/") and not name.startswith("_"):
        out.append("## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。")
    elif rel == "content/event_catalog.gd":
        out.append("## 事件卡只读缓存；写 state 走 EventOps / EventDraw。")
    elif rel.startswith("content/"):
        out.append("## 事件内容层；由 EventService / RegionService 段建造钩子调用。")
    elif rel == "data/save_service.gd":
        out.append("## Autoload SaveService；SAVE_GAME / LOAD_GAME 唯一落盘入口。")
    elif rel == "data/config_db.gd":
        out.append("## Autoload ConfigDb；玩法只读 require/get_table，禁止硬编码常数。")
    elif rel.startswith("data/"):
        out.append("## 数据平台层；Autoload 或静态工具，不经 Intent 直改局内逻辑。")
    elif rel == "app/intent_bus.gd":
        out.append("## Autoload IntentBus；presentation → gameplay 唯一信号入口。")
    elif rel.startswith("app/"):
        out.append("## 应用层 Autoload；串联 Intent 与各 Service。")
    elif rel == "content/event_ops.gd":
        out.append("## 事件 op 管线：`EventOps.choose_option` / `fire_delayed` 唯一写 state 入口。")
    elif rel == "data/save_schema.gd" and name.startswith("_"):
        out.append("## 序列化辅助；对外请用 `to_save_dict` / `from_save_dict`。")
    elif rel == "domain/run_state.gd":
        out.append("## RunState 实例方法；不触发日结或 Intent。")
    return out


def param_lines(params: list[tuple[str, str]]) -> list[str]:
    out: list[str] = []
    for pname, ptype in params:
        hint = PARAM_HINT.get(pname)
        if hint:
            out.append(f"## @param {pname} {hint}")
        else:
            tail = f"（{ptype}）" if ptype else ""
            out.append(f"## @param {pname}{tail}")
    return out


def return_line(ret: str, func_name: str) -> str | None:
    if ret == "void":
        return RETURN_HINT["void"]
    if func_name.startswith("can_") and ret == "String":
        return "## @return 空串=允许；非空=阻断原因码。"
    if func_name.startswith("errors_"):
        return "## @return 失败原因列表；空=通过。"
    return RETURN_HINT.get(ret, f"## @return `{ret}`。")


def build_doc_block(rel: str, name: str, params: list[tuple[str, str]], ret: str, old_docs: list[str]) -> list[str]:
    summary = summary_line(old_docs)
    if not summary:
        summary = f"## {name}"
    elif not summary.startswith("##"):
        summary = "## " + summary.lstrip("#").strip()
    block: list[str] = [summary, "##"]
    block.extend(context_lines(rel, name))
    # EXTRA may already include @return for add etc.
    has_return_in_extra = any("@return" in x for x in block)
    block.extend(param_lines(params))
    rline = return_line(ret, name)
    if rline and not has_return_in_extra:
        if ret != "void" or not params:
            block.append(rline)
    return block


def process_file_v2(path: Path) -> bool:
    lines = path.read_text(encoding="utf-8").splitlines()
    rel = rel_key(path)
    new_lines = lines[:]
    i = 0
    file_changed = False
    while i < len(new_lines):
        if not FUNC_START.match(new_lines[i]):
            i += 1
            continue
        name, params, ret = parse_signature(new_lines, i)
        doc_start, docs = collect_doc_above(new_lines, i)
        sig_end = i
        while sig_end < len(new_lines) and not new_lines[sig_end].rstrip().endswith(":"):
            sig_end += 1
        if should_enrich(docs):
            block = build_doc_block(rel, name, params, ret, docs)
            new_lines[doc_start:i] = block
            delta = len(block) - (i - doc_start)
            i = sig_end + 1 + delta
            file_changed = True
        else:
            i = sig_end + 1

    if file_changed:
        text = "\n".join(new_lines)
        if path.read_text(encoding="utf-8").endswith("\n"):
            text += "\n"
        path.write_text(text, encoding="utf-8")
    return file_changed


def main() -> int:
    n = 0
    for rel in CORE:
        p = ROOT / rel
        if not p.is_file():
            print("skip missing", rel)
            continue
        if process_file_v2(p):
            n += 1
            print("enriched", rel)
    print("files_enriched", n)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())