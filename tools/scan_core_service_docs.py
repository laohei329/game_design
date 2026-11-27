#!/usr/bin/env python3
"""List core service funcs with no doc or single short ## line."""
from __future__ import annotations

import re
import sys
from pathlib import Path

_TOOLS = Path(__file__).resolve().parent
if str(_TOOLS) not in sys.path:
    sys.path.insert(0, str(_TOOLS))

from core_service_paths import CORE_SERVICE_PATHS as CORE  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent / "client" / "scripts"
FUNC = re.compile(r"^(\s*)(static\s+)?func\s+(\w+)")


def main() -> int:
    no_doc: list[str] = []
    short: list[str] = []
    single: list[str] = []
    for rel in CORE:
        p = ROOT / rel
        if not p.exists():
            print("missing", rel)
            continue
        lines = p.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            m = FUNC.match(line)
            if not m or m.group(3) == "_ready":
                continue
            j = i - 1
            docs: list[str] = []
            while j >= 0 and lines[j].strip() == "":
                j -= 1
            while j >= 0 and lines[j].strip().startswith("##"):
                docs.insert(0, lines[j])
                j -= 1
            nonempty = [d for d in docs if d.strip() != "##"]
            name = m.group(3)
            key = f"{rel}:{name}"
            if not nonempty:
                no_doc.append(key)
            elif len(nonempty) == 1:
                single.append(key)
                if len(nonempty[0]) < 55:
                    short.append(f"{key} | {nonempty[0]}")
    print("core_files", len(CORE))
    print("no_doc", len(no_doc))
    for x in no_doc:
        print(" ", x)
    print("single_line_only", len(single))
    print("short_single", len(short))
    for x in short[:30]:
        print(" ", x)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())