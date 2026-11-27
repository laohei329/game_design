#!/usr/bin/env python3
"""Ensure every GDScript func has ## doc comment immediately above the signature."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "client" / "scripts"

FUNC_START = re.compile(r"^(\s*)(static\s+)?func\s+(\w+)\s*[\(:]")


def has_doc_above(out: list[str]) -> bool:
    j = len(out) - 1
    while j >= 0 and out[j].strip() == "":
        j -= 1
    return j >= 0 and out[j].strip().startswith("##")


def find_sig_end(lines: list[str], start: int) -> int:
    i = start
    while i < len(lines):
        if lines[i].rstrip().endswith(":"):
            return i
        i += 1
    return start


def leading_body_docs(lines: list[str], body_start: int) -> tuple[list[str], int]:
    docs: list[str] = []
    i = body_start
    while i < len(lines):
        s = lines[i].strip()
        if s == "":
            i += 1
            continue
        if s.startswith("##"):
            docs.append(s if s.startswith("##") else "## " + s)
            i += 1
            continue
        break
    return docs, i


def default_doc(name: str, is_static: bool) -> str | None:
    """Return None to skip auto-generated placeholder docs."""
    _SKIP = {
        "_ready",
        "_unhandled_input",
        "_close",
        "toggle",
        "emit_intent",
        "load_all",
        "get_table",
        "require",
        "record",
        "to_dict",
        "audit",
    }
    if name in _SKIP or name.startswith("_on_") or name in ("_sync", "_refresh"):
        return None
    if name.startswith("errors_"):
        return None
    if name.startswith("_"):
        return None
    if is_static:
        return None
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

        sig_start = i
        sig_end = find_sig_end(lines, sig_start)
        is_static = m.group(2) is not None
        name = m.group(3)

        body_start = sig_end + 1
        hoisted, body_content_start = leading_body_docs(lines, body_start)

        if not has_doc_above(out):
            if out and out[-1].strip() != "":
                out.append("")
            if hoisted:
                out.extend(hoisted)
                changed = True
            else:
                auto = default_doc(name, is_static)
                if auto:
                    out.append(auto)
                    changed = True
        elif hoisted:
            changed = True

        for k in range(sig_start, sig_end + 1):
            out.append(lines[k])

        i = body_content_start

    new_text = "\n".join(out)
    if path.read_text(encoding="utf-8").endswith("\n"):
        new_text += "\n"

    if new_text != path.read_text(encoding="utf-8"):
        path.write_text(new_text, encoding="utf-8")
        return True
    return False


def main() -> int:
    n = 0
    for p in sorted(ROOT.rglob("*.gd")):
        if process_file(p):
            n += 1
            print("updated", p)
    print("files_updated", n)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())