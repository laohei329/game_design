# -*- coding: utf-8 -*-
"""阶段零 A：固定种子 × 策略 × N 局，对照 modules/10-validation.md config25 十项闸（可自动化部分）。"""
from __future__ import annotations

import argparse
import math
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
_SIM = ROOT / "sim"
if str(_SIM) not in sys.path:
    sys.path.insert(0, str(_SIM))

from engine import STRATS, RunState, run_one  # noqa: E402

SEED_BASE_DEFAULT = 100_003
MAX_DAY_DEFAULT = 240


@dataclass
class ItemCheck:
    num: int
    ok: bool
    status: str  # pass | fail | skip
    detail: str


def _has_bad_numbers(state: RunState) -> Optional[str]:
    for attr in ("food", "water", "fuel", "parts", "med", "body"):
        v = getattr(state, attr)
        if v is None or (isinstance(v, float) and (math.isnan(v) or math.isinf(v))):
            return f"{attr} invalid"
        if v < -1e-6:
            return f"{attr}<0"
    return None


def summarize(states: List[RunState]) -> Dict[str, Any]:
    n = max(1, len(states))
    ok120 = sum(1 for s in states if s.day >= 120 and not s.failed)
    pop20 = sum(1 for s in states if s.peak_onboard >= 20)
    beds20 = sum(1 for s in states if s.beds20_day is not None)
    fuel_fail = sum(1 for s in states if s.failed == "fuel")
    early_gap = sum(1 for s in states if s.day < 5 and (s.food <= 0 or s.water <= 0))
    drought8 = sum(1 for s in states if s.max_drought >= 8)

    peaks = sorted(s.peak_onboard for s in states)
    peak_med = float(peaks[n // 2]) if peaks else 0.0

    death_counts: Counter = Counter()
    for s in states:
        death_counts.update(s.deaths)
    total_deaths = sum(death_counts.values()) or 1
    max_share = max(death_counts.values()) / total_deaths if death_counts else 0.0
    noncombat_kinds = sum(
        1 for k in ("starvation", "dehydration", "disease", "collision") if death_counts.get(k, 0) > 0
    )

    tech_reach = {line: {1: 0, 2: 0, 3: 0} for line in ("power", "armor", "radar", "living")}
    for s in states:
        for line, attr in (
            ("power", "power_tech"),
            ("armor", "armor_tech"),
            ("radar", "radar_tech"),
            ("living", "living_tech"),
        ):
            lv = int(getattr(s, attr))
            for need in (1, 2, 3):
                if lv >= need:
                    tech_reach[line][need] += 1
    tech_ok = all(tech_reach[line][need] / n >= 0.05 for line in tech_reach for need in (1, 2, 3))

    nan_fail = sum(1 for s in states if _has_bad_numbers(s) is not None)

    return {
        "n": n,
        "surv120": ok120 / n,
        "pop20_rate": pop20 / n,
        "beds20_rate": beds20 / n,
        "fuel_fail_rate": fuel_fail / n,
        "peak_med": peak_med,
        "death_max_share": max_share,
        "noncombat_death_kinds": noncombat_kinds,
        "tech_ok": tech_ok,
        "tech_reach": tech_reach,
        "early_resource_gap_before_day5": early_gap / n,
        "drought_ge8_rate": drought8 / n,
        "nan_or_neg_rate": nan_fail / n,
        "deaths_total": dict(death_counts),
    }


def evaluate_items(cons: Dict[str, Any], exp: Dict[str, Any]) -> List[ItemCheck]:
    items: List[ItemCheck] = []

    i1_ok = cons["nan_or_neg_rate"] == 0 and exp["nan_or_neg_rate"] == 0
    items.append(
        ItemCheck(
            1,
            i1_ok,
            "pass" if i1_ok else "fail",
            f"nan/neg cons={cons['nan_or_neg_rate']:.1%} exp={exp['nan_or_neg_rate']:.1%}",
        )
    )

    i2_ok = cons["surv120"] >= 0.40 and exp["surv120"] >= 0.40
    items.append(
        ItemCheck(
            2,
            i2_ok,
            "pass" if i2_ok else "fail",
            f"surv≥120d cons={cons['surv120']:.0%} exp={exp['surv120']:.0%} (need ≥40% each)",
        )
    )

    i3_ok = (
        cons["death_max_share"] <= 0.70
        and exp["death_max_share"] <= 0.70
        and cons["noncombat_death_kinds"] >= 2
        and exp["noncombat_death_kinds"] >= 2
    )
    items.append(
        ItemCheck(
            3,
            i3_ok,
            "pass" if i3_ok else "fail",
            f"death_peak cons={cons['death_max_share']:.0%} exp={exp['death_max_share']:.0%}; "
            f"noncombat_kinds con={cons['noncombat_death_kinds']} exp={exp['noncombat_death_kinds']}",
        )
    )

    i4_ok = cons["tech_ok"] and exp["tech_ok"]
    items.append(ItemCheck(4, i4_ok, "pass" if i4_ok else "fail", f"four-line Lv1-3≥5%: con={cons['tech_ok']} exp={exp['tech_ok']}"))

    drought_ok = cons["drought_ge8_rate"] <= 0.10 and exp["drought_ge8_rate"] <= 0.10
    items.append(
        ItemCheck(
            5,
            drought_ok,
            "pass" if drought_ok else "fail",
            f"drought≥8 con={cons['drought_ge8_rate']:.1%} exp={exp['drought_ge8_rate']:.1%} (≤10%)",
        )
    )

    pop20_delta = exp["pop20_rate"] - cons["pop20_rate"]
    i6_ok = pop20_delta >= 0.05 or exp["beds20_rate"] >= cons["beds20_rate"]
    items.append(
        ItemCheck(
            6,
            i6_ok,
            "pass" if i6_ok else "fail",
            f"pop20Δ={pop20_delta:.0%} beds20 con={cons['beds20_rate']:.0%} exp={exp['beds20_rate']:.0%}",
        )
    )

    items.append(ItemCheck(7, True, "skip", "search≤3/点：引擎计数存在，待 telemetry 平均闸"))

    i8_ok = exp["pop20_rate"] >= 0.30 and pop20_delta >= 0.05 and exp["peak_med"] >= 12
    items.append(
        ItemCheck(
            8,
            i8_ok,
            "pass" if i8_ok else "fail",
            f"exp pop20={exp['pop20_rate']:.0%} peak_med={exp['peak_med']:.0f} (need ≥30%, +5pp, med≥12)",
        )
    )

    items.append(ItemCheck(9, True, "skip", "冬季燃料手算：见 10 §1.2（条件过）"))
    items.append(ItemCheck(10, True, "skip", "冬季食物手算：见 10 §1.2（条件过）"))

    return items


def run_batch(runs: int, seed_base: int, max_day: int) -> Tuple[Dict[str, Dict[str, Any]], List[str]]:
    errors: List[str] = []
    out: Dict[str, Dict[str, Any]] = {}
    for strat in STRATS:
        states: List[RunState] = []
        for i in range(runs):
            seed = seed_base + i * 997 + (0 if strat.risk < 0.5 else 17_013)
            try:
                st = run_one(seed, strat, max_day)
                bad = _has_bad_numbers(st)
                if bad:
                    errors.append(f"{strat.name} seed={seed}: {bad}")
                states.append(st)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{strat.name} seed={seed}: {exc}")
        out[strat.name] = summarize(states)
    return out, errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Stage-zero A Monte Carlo (config25 gates)")
    parser.add_argument("--runs", type=int, default=250, help="runs per strategy (total = 2×runs)")
    parser.add_argument("--seed-base", type=int, default=SEED_BASE_DEFAULT)
    parser.add_argument("--max-day", type=int, default=MAX_DAY_DEFAULT)
    parser.add_argument("--strict", action="store_true", help="fail exit if any automated item fails")
    args = parser.parse_args()

    stats, errors = run_batch(args.runs, args.seed_base, args.max_day)
    if "conservative" not in stats or "expansion" not in stats:
        print("run_zero_a: FAIL no strategies")
        return 1

    cons, exp = stats["conservative"], stats["expansion"]
    print(f"run_zero_a: runs={args.runs}/strat max_day={args.max_day} seed_base={args.seed_base}")
    for name, row in stats.items():
        print(f"  [{name}] surv120={row['surv120']:.0%} pop20={row['pop20_rate']:.0%} "
              f"fuel_fail={row['fuel_fail_rate']:.0%} peak_med={row['peak_med']:.0f}")
    items = evaluate_items(cons, exp)
    print("  --- config25 automated items ---")
    fail_any = False
    for it in items:
        mark = it.status.upper()
        print(f"  Item {it.num:2d} [{mark:4s}] {it.detail}")
        if it.status == "fail":
            fail_any = True
    if errors:
        print("  runner_errors:")
        for e in errors[:8]:
            print("   ", e)
        fail_any = True

    if fail_any and args.strict:
        print("run_zero_a: FAIL")
        return 1
    if fail_any:
        print("run_zero_a: WARN (re-run with --strict to exit 1)")
        return 0
    print("run_zero_a: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())