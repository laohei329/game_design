# -*- coding: utf-8 -*-
"""Remove capture:snapshot from delayed ops when targetType is party (A6-L1)."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVENTS = ROOT / "data" / "events"


def strip_file(path: Path) -> int:
    data = json.loads(path.read_text(encoding="utf-8"))
    n = 0
    for opt in data.get("options", []) or []:
        if opt.get("targetType") == "party" and opt.get("capture") == "snapshot":
            del opt["capture"]
            n += 1
    if n:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return n


def main() -> int:
    total = 0
    for path in sorted(EVENTS.rglob("*.json")):
        if path.name.startswith("_"):
            continue
        total += strip_file(path)
    print(f"strip_party_snapshot_capture: removed {total} capture field(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())