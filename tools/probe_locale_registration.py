# -*- coding: utf-8
"""locale：CSV 组、.translation 文件、project.godot 注册三向一致。"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_LOC = ROOT / "data" / "localization"
CLIENT_DATA = ROOT / "client" / "data" / "localization"
PROJECT = ROOT / "client" / "project.godot"

STEMS = ("ui", "combat", "abilities", "events_general", "events_season", "events_year")
LANGS = ("en", "zh", "de", "ru", "es")


def _translation_paths_from_godot() -> set[str]:
    text = PROJECT.read_text(encoding="utf-8", errors="replace")
    block = re.search(
        r"locale/translations=PackedStringArray\((.*?)\)",
        text,
        re.DOTALL,
    )
    if not block:
        return set()
    return set(re.findall(r'"([^"]+\.translation)"', block.group(1)))


def main() -> int:
    errs: list[str] = []
    expected: set[str] = set()
    for stem in STEMS:
        csv = DATA_LOC / f"{stem}.csv"
        if not csv.is_file():
            errs.append(f"missing CSV data/localization/{stem}.csv")
            continue
        for lang in LANGS:
            rel = f"res://data/localization/{stem}.{lang}.translation"
            expected.add(rel)
            for base in (DATA_LOC, CLIENT_DATA):
                tpath = base / f"{stem}.{lang}.translation"
                if not tpath.is_file():
                    errs.append(f"missing file {tpath.relative_to(ROOT)}")
                    break

    reg = _translation_paths_from_godot()
    if len(reg) < len(expected):
        errs.append(f"project.godot translations={len(reg)} expected>={len(expected)}")
    missing_reg = expected - reg
    if missing_reg:
        errs.append(f"not in project.godot: {sorted(missing_reg)[:5]}")

    print(f"probe_locale_registration: expected={len(expected)} registered={len(reg)}")
    if errs:
        print("probe_locale_registration: FAIL")
        for e in errs[:15]:
            print(" ", e)
        return 1
    print("probe_locale_registration: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())