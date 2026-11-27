#!/usr/bin/env python3
"""One-shot splitter: smoke_assertions.gd -> themed modules + facade."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "client/scripts/qa/smoke_assertions.gd"

ASSIGNMENTS: dict[str, list[str]] = {
    "smoke_assertions_helpers.gd": [
        "_intent_drive",
        "_intent_assign_search",
        "first_member_id",
        "_clear_search_tasks",
        "_snapshot_burn_inputs",
        "_telemetry_has",
    ],
    "smoke_assertions_core.gd": [
        "errors_main_scenes_load",
        "errors_config_paths",
        "errors_start_crew",
        "errors_fuel_uses_config",
        "audit_after_triplet_end_day",
        "errors_start_precision",
    ],
    "smoke_assertions_world.gd": [
        "errors_climate_region_mult",
        "errors_guarantee_offer",
        "audit_tutorial_hang",
        "errors_min_power_rule",
        "errors_abandon_cargo",
        "errors_search_telemetry",
        "errors_combat_l1",
        "errors_tech_power_lv1",
        "errors_region_pick_tundra",
    ],
    "smoke_assertions_outdoor.gd": [
        "errors_outdoor_day_clock_p0_a",
        "errors_runtime_day_clock_save_roundtrip",
    ],
    "smoke_assertions_events.gd": [
        "errors_event_and_point_encounter",
        "errors_event_ops_full",
        "errors_event_snapshot_and_load_pending",
        "errors_recruit_morale_save",
    ],
}

CLASS_NAMES = {
    "smoke_assertions_helpers.gd": "SmokeAssertionsHelpers",
    "smoke_assertions_core.gd": "SmokeAssertionsCore",
    "smoke_assertions_world.gd": "SmokeAssertionsWorld",
    "smoke_assertions_outdoor.gd": "SmokeAssertionsOutdoor",
    "smoke_assertions_events.gd": "SmokeAssertionsEvents",
}

MODULE_BLURB = {
    "smoke_assertions_helpers.gd": "## 冒烟共用：Intent 驱动与搜索复位辅助。",
    "smoke_assertions_core.gd": "## 冒烟：场景/配置/开局与三选一日结差分。",
    "smoke_assertions_world.gd": "## 冒烟：气候/车站/搜索 cap/战斗/科技/区域。",
    "smoke_assertions_outdoor.gd": "## 冒烟：户外日钟与 runtime 存档 roundtrip。",
    "smoke_assertions_events.gd": "## 冒烟：事件链、op 全量、读档与招募 morale。",
}


def parse_blocks(text: str) -> tuple[list[str], dict[str, str]]:
    lines = text.splitlines(keepends=True)
    const_m1: list[str] = []
    blocks: dict[str, str] = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("const M1_REQUIRE_PATHS"):
            while i < len(lines):
                const_m1.append(lines[i])
                i += 1
                if lines[i - 1].rstrip().endswith("]"):
                    break
            continue
        m = re.match(r"^(static func )(\w+)", line)
        if m:
            name = m.group(2)
            chunk = [line]
            i += 1
            while i < len(lines):
                nxt = lines[i]
                if re.match(r"^(static func |const |class_name )", nxt):
                    break
                chunk.append(nxt)
                i += 1
            blocks[name] = "".join(chunk)
            continue
        i += 1
    return const_m1, blocks


def replace_calls(body: str) -> str:
    body = body.replace("_intent_drive(", "SmokeAssertionsHelpers._intent_drive(")
    body = body.replace("_intent_assign_search(", "SmokeAssertionsHelpers._intent_assign_search(")
    body = body.replace("_clear_search_tasks(", "SmokeAssertionsHelpers._clear_search_tasks(")
    body = body.replace("_snapshot_burn_inputs(", "SmokeAssertionsHelpers._snapshot_burn_inputs(")
    body = body.replace("_telemetry_has(", "SmokeAssertionsHelpers._telemetry_has(")
    body = body.replace("first_member_id(", "SmokeAssertionsHelpers.first_member_id(")
    return body


def outdoor_header() -> str:
    return (
        'const _GameClock := preload("res://scripts/rhythm/game_clock.gd")\n'
        'const _PopulationConsumption := preload("res://scripts/economy/population_consumption.gd")\n\n'
    )


def helpers_header() -> str:
    return ""


def write_module(filename: str, blocks: dict[str, str], const_m1: list[str]) -> None:
    cn = CLASS_NAMES[filename]
    names = ASSIGNMENTS[filename]
    parts = [
        f"class_name {cn}\n",
        "extends RefCounted\n",
        MODULE_BLURB[filename] + "\n\n",
    ]
    if filename == "smoke_assertions_outdoor.gd":
        parts.append(outdoor_header())
    if filename == "smoke_assertions_core.gd" and const_m1:
        parts.extend(const_m1)
        parts.append("\n")
    for name in names:
        if name not in blocks:
            raise SystemExit(f"missing func {name} in source")
        body = blocks[name]
        if filename != "smoke_assertions_helpers.gd":
            body = replace_calls(body)
        parts.append(body)
        if not body.endswith("\n"):
            parts.append("\n")
    out = ROOT / "client/scripts/qa" / filename
    out.write_text("".join(parts), encoding="utf-8")


def write_facade(all_public: list[str]) -> None:
    forwards = []
    for fn in all_public:
        if fn.startswith("_"):
            continue
        target = None
        for mod, fns in ASSIGNMENTS.items():
            if fn in fns:
                target = CLASS_NAMES[mod]
                break
        if target is None:
            raise SystemExit(f"no module for public {fn}")
        # copy signature from blocks - use simple delegate
        forwards.append(
            f"static func {fn}(*args):\n"
            f'\treturn {target}.{fn}(*args)\n\n'
        )

    # GDScript doesn't support *args - need explicit signatures from source
    text = SRC.read_text(encoding="utf-8")
    _, blocks = parse_blocks(text)
    delegates = []
    for fn in all_public:
        if fn.startswith("_"):
            continue
        target = None
        for mod, fns in ASSIGNMENTS.items():
            if fn in fns:
                target = CLASS_NAMES[mod]
                break
        sig = blocks[fn].split("->")[0].replace("static func ", "").strip()
        ret = ""
        if "->" in blocks[fn]:
            ret_part = blocks[fn].split("->", 1)[1].split(":", 1)[0].strip()
            ret = f" -> {ret_part}"
        delegates.append(f"static func {sig}{ret}:\n\treturn {target}.{fn}(")
        # build arg list from signature
        inner = sig[sig.find("(") + 1 : sig.rfind(")")]
        if inner.strip():
            args = [a.split(":")[0].strip().split("=")[0].strip() for a in inner.split(",")]
            delegates[-1] += ", ".join(args)
        delegates[-1] += ")\n\n"

    facade = (
        "class_name SmokeAssertions\n"
        "extends RefCounted\n"
        "## 无头冒烟断言库（headless_smoke.gd 调用，非玩家运行时）。\n"
        "## 薄门面：按主题委托至 `SmokeAssertions*` 模块。\n\n"
        + "".join(delegates)
    )
    # helpers exposed for headless if any
    for h in ASSIGNMENTS["smoke_assertions_helpers.gd"]:
        if h.startswith("_"):
            continue
        sig = blocks[h].split("->")[0].replace("static func ", "").strip()
        ret = ""
        if "->" in blocks[h]:
            ret_part = blocks[h].split("->", 1)[1].split(":", 1)[0].strip()
            ret = f" -> {ret_part}"
        inner = sig[sig.find("(") + 1 : sig.rfind(")")]
        argcall = ""
        if inner.strip():
            args = [a.split(":")[0].strip().split("=")[0].strip() for a in inner.split(",")]
            argcall = ", ".join(args)
        facade += f"static func {sig}{ret}:\n\treturn SmokeAssertionsHelpers.{h}({argcall})\n\n"

    SRC.write_text(facade, encoding="utf-8")


def main() -> None:
    text = SRC.read_text(encoding="utf-8")
    const_m1, blocks = parse_blocks(text)
    for filename in ASSIGNMENTS:
        if filename == "smoke_assertions_helpers.gd":
            write_module(filename, blocks, [])
        else:
            write_module(filename, blocks, const_m1 if filename == "smoke_assertions_core.gd" else [])
    public = list(blocks.keys())
    write_facade(public)
    print("split ok:", ", ".join(ASSIGNMENTS.keys()))


if __name__ == "__main__":
    main()