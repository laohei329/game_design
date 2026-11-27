#!/usr/bin/env python3
"""Heuristic scan: balance-like literals in client gameplay layers (no Godot required)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCAN_DIRS = [
    ROOT / "client/scripts/gameplay",
    ROOT / "client/scripts/economy",
    ROOT / "client/scripts/rhythm",
    ROOT / "client/scripts/content",
    ROOT / "client/scripts/domain",
]

EXCLUDE_FILES = {
    "population_rules.gd",
    "config_db.gd",
    "balance_start.gd",
    "save_schema.gd",
    "rng_service.gd",
}

# Numeric lines that are usually structural / epsilon, not balance.
NOISE = re.compile(
    r"0\.0{3,}1|0\.001|0\.0001|TYPE_|clampf\(|mini\(|maxi\(|maxf\(|minf\(|"
    r"round\(|floorf\(|ceilf\(|int\(|float\(|str\(|bool\(|"
    r"Time\.|% |\[%|slot|index|version|tick"
)

RULES: list[tuple[str, re.Pattern[str], str]] = [
    (
        "R1-procedural",
        re.compile(r"randi_range\(\s*\d+\s*,\s*\d+\s*\)"),
        "段/点数量或均匀掷骰",
    ),
    (
        "R1-procedural",
        re.compile(r"length_km\s*\*\s*\(\s*0\.\d+"),
        "车站 progressKm 沿段长比例",
    ),
    (
        "R1-procedural",
        re.compile(r'stationCountWeights",\s*\{'),
        "站数权重表写在 .get 第二参",
    ),
    (
        "R1-procedural",
        re.compile(r'\.get\("baseWeight"\s*,'),
        "点位 baseWeight 缺键默认",
    ),
    (
        "R2-daysettle",
        re.compile(r"zero_streak\s*>=\s*3|breakdown_counter\s*>=\s*3"),
        "三连零 / 故障计数阈",
    ),
    (
        "R2-daysettle",
        re.compile(r"breakdown_stop_hours_remaining\s*=\s*[\d.]"),
        "故障停驶小时",
    ),
    (
        "R3-event",
        re.compile(r'rules\.get\("[^"]+"\s*,\s*[0-9]'),
        "event_draw_rules 缺键默认",
    ),
    (
        "R4-haul",
        re.compile(r"\*\s*0\.85"),
        "专长工时乘子",
    ),
    (
        "R4-haul",
        re.compile(r'hoursTotal"\s*,\s*0\.4'),
        "搬运任务默认工时",
    ),
    (
        "R5-station-ui",
        re.compile(r"fuel_add\s*>=\s*2"),
        "高油耗搁置阈",
    ),
    (
        "R5-combat",
        re.compile(r'layerDefault"\s*,\s*"'),
        "遭遇模板层默认",
    ),
    (
        "R5-combat",
        re.compile(r"slots\.size\(\)\s*>=\s*8"),
        "编队槽上限",
    ),
    (
        "R7-domain",
        re.compile(r'lengthKm"\s*,\s*50'),
        "段长读档默认",
    ),
]


def scan_file(path: Path) -> list[tuple[str, str, int, str, str]]:
    out: list[tuple[str, str, int, str, str]] = []
    text = path.read_text(encoding="utf-8")
    rel = path.relative_to(ROOT).as_posix()
    for lineno, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if "ConfigDb.require" in s:
            continue
        for round_id, pattern, note in RULES:
            if pattern.search(s):
                out.append((rel, round_id, lineno, note, s))
                break
    return out


def main() -> int:
    all_hits: list[tuple[str, str, int, str, str]] = []
    for base in SCAN_DIRS:
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.gd")):
            if path.name in EXCLUDE_FILES:
                continue
            all_hits.extend(scan_file(path))

    by_round: dict[str, list] = {}
    for h in all_hits:
        by_round.setdefault(h[1], []).append(h)

    print(f"scan_hardcode_gd: {len(all_hits)} rule hits in {len(SCAN_DIRS)} dirs")
    for rnd in sorted(by_round.keys()):
        print(f"\n## {rnd} ({len(by_round[rnd])})")
        for rel, _, lineno, note, s in by_round[rnd]:
            print(f"  {rel}:{lineno}  # {note}")
            print(f"    {s[:140]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())