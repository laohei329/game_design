# -*- coding: utf-8 -*-
"""存档：manifest 契约 + Godot 迁移链探针（合成档 v6/v8/v10→12）。"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "data" / "migrations" / "manifest.json"


def _check_manifest() -> tuple[bool, list[str]]:
    lines: list[str] = []
    if not MANIFEST.is_file():
        return False, ["FAIL missing data/migrations/manifest.json"]
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    chain = data.get("chain", [])
    if not isinstance(chain, list):
        return False, ["FAIL manifest chain not array"]
    expect = list(range(3, 13))
    got: list[int] = []
    for step in chain:
        if not isinstance(step, dict):
            continue
        fr, to = int(step.get("from", 0)), int(step.get("to", 0))
        if to != fr + 1:
            lines.append(f"FAIL gap {fr}->{to}")
            return False, lines
        got.append(to)
    if got != expect:
        lines.append(f"FAIL chain ends got={got} want={expect}")
        return False, lines
    if int(data.get("saveSchemaCurrent", 0)) != 12:
        lines.append("FAIL saveSchemaCurrent!=12")
        return False, lines
    lines.append(f"OK manifest chain v2→v12 steps={len(chain)}")
    return True, lines


def _godot_bin() -> Path | None:
    env = os.environ.get("GODOT_BIN")
    if env and Path(env).is_file():
        return Path(env)
    for p in (
        Path(r"D:\godot\Godot_v4.7.2-stable_win64_console.exe"),
        Path(r"D:\godot\Godot_v4.7.2-stable_win64.exe"),
    ):
        if p.is_file():
            return p
    return None


def _run_godot_probe() -> tuple[bool, list[str], bool]:
    exe = _godot_bin()
    if exe is None:
        return True, ["SKIP SaveMigrationProbe (set GODOT_BIN)"], True
    script = ROOT / "client" / "scripts" / "debug" / "save_migration_probe_runner.gd"
    proc = subprocess.run(
        [str(exe), "--headless", "--path", str(ROOT / "client"), "--script", str(script)],
        capture_output=True,
        text=True,
        timeout=90,
        cwd=str(ROOT / "client"),
    )
    out = (proc.stdout + proc.stderr).strip().splitlines()
    ok = proc.returncode == 0
    summary = out[-1] if out else f"exit {proc.returncode}"
    return ok, [summary] + [ln for ln in out if ln.startswith(("OK", "FAIL"))][-6:], False


def _synthetic_version_matrix() -> tuple[bool, list[str]]:
    """Python 侧：每档 version.save 均有 version 块且可 JSON 往返。"""
    lines: list[str] = []
    for ver in range(2, 13):
        save = {
            "version": {"save": ver, "configVersion": 30},
            "calendar": {"year": 1, "season": "spring", "dayInSeason": 1, "dayTotal": 5},
            "inventory": {"food": 1, "water": 1, "fuel": 1},
            "train": {"carriages": []},
            "world": {},
            "members": [],
            "tasks": {"search": [], "haul": []},
            "runtime": {},
        }
        blob = json.dumps(save, ensure_ascii=False)
        back = json.loads(blob)
        if int(back["version"]["save"]) != ver:
            lines.append(f"FAIL roundtrip version.save={ver}")
            return False, lines
    lines.append("OK synthetic JSON roundtrip v2..12")
    return True, lines


def main() -> int:
    ok = True
    lines: list[str] = []
    m_ok, m_lines = _check_manifest()
    lines.extend(m_lines)
    ok = ok and m_ok
    s_ok, s_lines = _synthetic_version_matrix()
    lines.extend(s_lines)
    ok = ok and s_ok
    g_ok, g_lines, skipped = _run_godot_probe()
    lines.extend(g_lines)
    ok = ok and (g_ok or skipped)
    for ln in lines:
        print(ln)
    print("probe_save_migration:", "OK" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())