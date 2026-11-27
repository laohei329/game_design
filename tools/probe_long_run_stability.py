# -*- coding: utf-8 -*-
"""长局稳定性：30–240 日 sim 跑批，监控失败率与结构字段无异常爆炸。"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_SIM = ROOT / "sim"
if str(_SIM) not in sys.path:
    sys.path.insert(0, str(_SIM))

from engine import STRATS, run_one  # noqa: E402

HORIZONS = (30, 60, 120, 240)
SEEDS = (100003, 100019, 100043)


def _run_horizon(max_day: int, seed: int) -> list[str]:
    errs: list[str] = []
    for strat in STRATS:
        st = run_one(seed, strat, max_day)
        if st.day < 5 and st.failed:
            errs.append(f"{strat.name} seed={seed} early fail day={st.day} reason={st.failed}")
        if st.peak_onboard > 80:
            errs.append(f"{strat.name} seed={seed} peak_onboard={st.peak_onboard}>80")
        if st.car_count() > 40:
            errs.append(f"{strat.name} seed={seed} cars={st.car_count()}>40")
        if st.max_drought > 20:
            errs.append(f"{strat.name} seed={seed} max_drought={st.max_drought}>20")
        total_deaths = sum(st.deaths.values())
        if total_deaths > 200:
            errs.append(f"{strat.name} seed={seed} deaths={total_deaths}>200")
    return errs


def main() -> int:
    all_errs: list[str] = []
    for max_day in HORIZONS:
        for seed in SEEDS:
            all_errs.extend(_run_horizon(max_day, seed))
    print(f"probe_long_run_stability: horizons={HORIZONS} seeds={len(SEEDS)}")
    if all_errs:
        print("probe_long_run_stability: FAIL")
        for e in all_errs[:20]:
            print(" ", e)
        if len(all_errs) > 20:
            print(f"  … +{len(all_errs) - 20} more")
        return 1
    print("probe_long_run_stability: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())