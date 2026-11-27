# -*- coding: utf-8 -*-
"""A6 batch-0 sign-off: H3 sim, H4 locale, optional Godot H1/H2 (A6Batch0Probe)."""
from __future__ import annotations

import os
import random
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


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


def check_h3() -> tuple[bool, list[str]]:
    from sim.engine import RunState, STRATS, apply_day, run_one, start_region_run, _build_segment

    lines: list[str] = []
    rng = random.Random(42)
    state = RunState()
    start_region_run(state, rng, force_id="urban")
    _build_segment(state, rng)
    if not state.nodes:
        return False, ["FAIL H3 day1 nodes empty"]
    lines.append(f"OK H3 day1 nodes={len(state.nodes)}")

    state = run_one(42, STRATS[0], 12)
    if state.stations_visited < 1:
        return False, lines + [f"FAIL H3 no station by day12 stations={state.stations_visited}"]
    state2 = RunState()
    rng2 = random.Random(42)
    start_region_run(state2, rng2, force_id="urban")
    _build_segment(state2, rng2)
    first_station = None
    for _ in range(9):
        apply_day(state2, rng2, STRATS[0])
        if state2.stations_visited >= 1:
            first_station = state2.day
            break
    if first_station is None or first_station > 8:
        return False, lines + [f"FAIL H3 first station day={first_station}"]
    lines.append(f"OK H3 first station day={first_station} (3–8)")
    if state2.tutorial_done:
        lines.append("OK H3 tutorial_done")
    else:
        lines.append("WARN H3 tutorial_done still false at probe stop (may need more days)")
    return True, lines


def check_h4() -> tuple[bool, list[str]]:
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "audit_locale_keys.py")],
        capture_output=True,
        text=True,
        cwd=str(ROOT),
    )
    tail = (proc.stdout or proc.stderr or "").strip().splitlines()
    summary = tail[-3:] if tail else []
    if proc.returncode != 0:
        return False, ["FAIL H4 audit_locale_keys"] + summary
    return True, ["OK H4 audit_locale_keys"] + summary


def check_godot_h1_h2() -> tuple[bool, list[str]]:
    exe = _godot_bin()
    if exe is None:
        return True, ["SKIP Godot H1/H2 (set GODOT_BIN)"]
    script = ROOT / "client" / "scripts" / "debug" / "a6_probe_runner.gd"
    proc = subprocess.run(
        [str(exe), "--headless", "--path", str(ROOT / "client"), "--script", str(script)],
        capture_output=True,
        text=True,
        timeout=30,
        cwd=str(ROOT / "client"),
    )
    out = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0:
        return False, [f"FAIL Godot probe exit={proc.returncode}", out[-800:]]
    return True, ["OK Godot A6Batch0Probe", out.strip().splitlines()[-1] if out.strip() else ""]


def main() -> int:
    ok = True
    for fn in (check_h3, check_h4, check_godot_h1_h2):
        part_ok, lines = fn()
        ok = ok and part_ok
        for ln in lines:
            print(ln)
    print("probe_a6_signoff:", "OK" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT))
    raise SystemExit(main())