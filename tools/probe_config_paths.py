# -*- coding: utf-8 -*-
"""提取 GD/Python 中 ConfigDb.require 路径并交叉校验 manifest / has()。"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_SIM = ROOT / "sim"
if str(_SIM) not in sys.path:
    sys.path.insert(0, str(_SIM))

from config_db import ConfigDb, ConfigLoadError  # noqa: E402

REQUIRE_RE = re.compile(
    r'(?:ConfigDb|db)\.require\s*\(\s*["\']([^"\']+)["\']'
    r'|config_require(?:_float)?\s*\(\s*["\']([^"\']+)["\']'
)


def _is_static_path(path: str) -> bool:
    if not path or path.endswith(".") or "%" in path or "+" in path:
        return False
    if path.count(".") < 1:
        return False
    return True
SKIP_PATHS = frozenset({"__no_such.probe.path"})
SCAN_ROOTS = (
    ROOT / "client" / "scripts",
    ROOT / "sim",
    ROOT / "tools",
)


def collect_require_paths() -> dict[str, set[str]]:
    by_file: dict[str, set[str]] = {}
    for base in SCAN_ROOTS:
        if not base.is_dir():
            continue
        for path in base.rglob("*"):
            if path.suffix not in {".gd", ".py"}:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            rel = path.relative_to(ROOT).as_posix()
            found: set[str] = set()
            for m in REQUIRE_RE.finditer(text):
                p = m.group(1) or m.group(2)
                if p and _is_static_path(p):
                    found.add(p)
            if found:
                by_file[rel] = found
    return by_file


def main() -> int:
    db = ConfigDb.from_repo(ROOT)
    if db.load_all() != 0:
        print("probe_config_paths: FAIL load", db.errors[:5])
        return 1

    by_file = collect_require_paths()
    all_paths: set[str] = set()
    for paths in by_file.values():
        all_paths |= paths
    all_paths -= SKIP_PATHS

    missing: list[tuple[str, str]] = []
    for rel, paths in sorted(by_file.items()):
        for p in sorted(paths):
            if p in SKIP_PATHS:
                continue
            try:
                db.require(p)
            except ConfigLoadError:
                missing.append((rel, p))

    bal = db.get_table("balance")
    dead_mirror = isinstance(bal, dict) and "stations" in bal

    manifest = json.loads((ROOT / "data" / "manifest.json").read_text(encoding="utf-8"))
    table_names = set(manifest.get("files", {})) | set(manifest.get("legacyFiles", {}))
    orphan_roots: list[str] = []
    for name in db.tables:
        if name not in table_names and not name.startswith("localization_"):
            orphan_roots.append(name)

    errs: list[str] = []
    if missing:
        for rel, p in missing[:40]:
            errs.append(f"require missing: {p} (in {rel})")
        if len(missing) > 40:
            errs.append(f"... +{len(missing) - 40} more missing paths")
    if dead_mirror:
        errs.append("balance.stations mirror block still present (use stations.json)")
    if orphan_roots:
        errs.append(f"unexpected table roots in memory: {sorted(orphan_roots)}")

    print(f"probe_config_paths: scanned {len(by_file)} files, {len(all_paths)} unique paths")
    if errs:
        print("probe_config_paths: FAIL")
        for e in errs:
            print(" ", e)
        return 1
    print("probe_config_paths: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())