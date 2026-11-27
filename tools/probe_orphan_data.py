# -*- coding: utf-8 -*-
"""孤儿数据：顶层 JSON 须在 manifest；事件盘文件 ⊆ index；event_hooks 可读。"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
MANIFEST = DATA / "manifest.json"
EVENT_INDEX = DATA / "events" / "_index.json"
HOOKS = DATA / "events" / "event_hooks_registry.json"


def _manifest_paths() -> set[str]:
    m = json.loads(MANIFEST.read_text(encoding="utf-8"))
    out: set[str] = set()
    for rel in list(m.get("files", {}).values()) + list(m.get("legacyFiles", {}).values()):
        out.add(str(rel).replace("\\", "/"))
    return out


def main() -> int:
    errs: list[str] = []
    listed = _manifest_paths()

    for path in sorted(DATA.glob("*.json")):
        if path.name == "manifest.json":
            continue
        if path.name not in {Path(p).name for p in listed}:
            rel = path.name
            if rel not in {Path(p).name for p in listed}:
                full_rel = path.relative_to(DATA).as_posix()
                if full_rel not in listed and not any(p.endswith(full_rel) for p in listed):
                    errs.append(f"top-level data JSON not in manifest files: {full_rel}")

    if not HOOKS.is_file():
        errs.append("missing data/events/event_hooks_registry.json (design reference)")
    else:
        try:
            json.loads(HOOKS.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errs.append(f"event_hooks_registry.json invalid: {exc}")

    index = json.loads(EVENT_INDEX.read_text(encoding="utf-8"))
    ids: set[str] = set()
    buckets = index.get("buckets", {})
    if isinstance(buckets.get("general"), dict):
        ids.update(buckets["general"].get("eventIds", []))
    season_bucket = buckets.get("season")
    if isinstance(season_bucket, dict):
        for season_row in (season_bucket.get("bySeason") or {}).values():
            if isinstance(season_row, dict):
                ids.update(season_row.get("eventIds", []))
    if isinstance(buckets.get("year"), dict):
        ids.update(buckets["year"].get("eventIds", []))

    for eid in sorted(ids):
        if not list(DATA.glob(f"events/**/{eid}.json")):
            errs.append(f"indexed event missing file: {eid}")

    on_disk = {
        p.stem
        for p in DATA.glob("events/**/*.json")
        if p.name not in ("_index.json", "event_hooks_registry.json")
    }
    extra = on_disk - ids
    if extra:
        errs.append(f"event json on disk not in index ({len(extra)}): {sorted(extra)[:8]}")

    print(f"probe_orphan_data: manifest_files={len(listed)} indexed_events={len(ids)}")
    if errs:
        print("probe_orphan_data: FAIL")
        for e in errs[:25]:
            print(" ", e)
        return 1
    print("probe_orphan_data: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())