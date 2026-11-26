# -*- coding: utf-8 -*-
"""Stage-zero A runner. Smoke by default; --runs 200 for fuller sample."""
from __future__ import annotations

import argparse
import statistics
from collections import Counter

from engine import STRATS, run_one


def summarize(strat_name: str, states) -> dict:
    n = len(states)
    ok120 = 0
    pop20 = 0
    death_counts = Counter()
    fail_counts = Counter()
    upgrades = Counter()
    peaks = []
    peak_cars = []
    hung = []
    hang_rates = []
    droughts = []
    droughts_raw = []
    stations = []
    beds20_days = []
    tech_reach = {
        "power": Counter(),
        "armor": Counter(),
        "radar": Counter(),
        "living": Counter(),
    }
    for s in states:
        failed_before_120 = s.failed is not None and s.day <= 120
        if not failed_before_120 and s.day > 120:
            ok120 += 1
        if s.peak_onboard >= 20:
            pop20 += 1
        if s.failed:
            fail_counts[s.failed] += 1
        death_counts.update(s.deaths)
        upgrades.update(s.upgrades_picked)
        peaks.append(s.peak_onboard)
        peak_cars.append(s.peak_cars)
        hung.append(s.cars_hung)
        hang_rates.append(s.cars_hung / max(1, s.stations_visited))
        droughts.append(s.max_drought)
        droughts_raw.append(s.max_drought_raw)
        stations.append(s.stations_visited)
        if s.beds20_day is not None:
            beds20_days.append(s.beds20_day)
        for line, lv in (
            ("power", s.power_tech),
            ("armor", s.armor_tech),
            ("radar", s.radar_tech),
            ("living", s.living_tech),
        ):
            for need in (1, 2, 3):
                if lv >= need:
                    tech_reach[line][need] += 1

    total_deaths = sum(death_counts.values()) or 1
    max_share = max(death_counts.values()) / total_deaths if death_counts else 0
    non_combat_classes = sum(
        1 for k in ("starvation", "dehydration", "disease", "collision") if death_counts[k] > 0
    )

    tech_ok = all(
        tech_reach[line][need] / n >= 0.05
        for line in ("power", "armor", "radar", "living")
        for need in (1, 2, 3)
    )
    drought_ge8 = sum(1 for d in droughts if d >= 8) / n
    drought_raw_ge8 = sum(1 for d in droughts_raw if d >= 8) / n

    return {
        "strat": strat_name,
        "n": n,
        "surv120": ok120 / n,
        "pop20_rate": pop20 / n,
        "fuel_fail_rate": fail_counts["fuel"] / n,
        "peak_med": statistics.median(peaks) if peaks else 0,
        "peak_cars_med": statistics.median(peak_cars) if peak_cars else 0,
        "hung_med": statistics.median(hung) if hung else 0,
        "hang_rate_med": statistics.median(hang_rates) if hang_rates else 0,
        "stations_med": statistics.median(stations) if stations else 0,
        "drought_ge8_rate": drought_ge8,
        "drought_raw_ge8_rate": drought_raw_ge8,
        "beds20_med": statistics.median(beds20_days) if beds20_days else None,
        "beds20_rate": len(beds20_days) / n,
        "death_max_share": max_share,
        "non_combat_classes": non_combat_classes,
        "upgrades": dict(upgrades),
        "tech_reach": {
            line: {need: tech_reach[line][need] / n for need in (1, 2, 3)}
            for line in ("power", "armor", "radar", "living")
        },
        "tech_ok": tech_ok,
        "deaths": dict(death_counts),
        "fails": dict(fail_counts),
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=40, help="runs per strategy")
    ap.add_argument("--days", type=int, default=240)
    args = ap.parse_args()

    print(f"Doomsday Train zero-A smoke | runs/strat={args.runs} days={args.days}")
    print("(Simplified model — not a formal pass certificate)\n")

    all_rows = []
    for idx, strat in enumerate(STRATS):
        states = [
            run_one(seed=10_000 * (idx + 1) + 997 * i, strat=strat, max_day=args.days)
            for i in range(args.runs)
        ]
        row = summarize(strat.name, states)
        all_rows.append(row)
        print(f"== {row['strat']} ==")
        print(f"  survive≥120d: {row['surv120']:.0%}")
        print(f"  peak onboard med: {row['peak_med']:.0f} | pop20 hit: {row['pop20_rate']:.0%}")
        b20 = row["beds20_med"]
        b20s = f"{b20:.0f}" if b20 is not None else "—"
        print(f"  beds≥20 rate: {row['beds20_rate']:.0%} | beds20 day med: {b20s}")
        print(f"  fuel fail: {row['fuel_fail_rate']:.0%}")
        print(
            f"  cars peak med: {row['peak_cars_med']:.0f} | hung med: {row['hung_med']:.0f} | "
            f"stations med: {row['stations_med']:.0f}"
        )
        print(
            f"  drought≥8 (acquire): {row['drought_ge8_rate']:.0%} | "
            f"incl. ai_skip: {row['drought_raw_ge8_rate']:.0%}"
        )
        print(
            f"  death max share: {row['death_max_share']:.0%} | "
            f"non-combat classes: {row['non_combat_classes']}"
        )
        print(f"  upgrades: {row['upgrades']}")
        tr = row["tech_reach"]
        print(
            "  tech reach Lv1/2/3: "
            + " | ".join(
                f"{ln} {tr[ln][1]:.0%}/{tr[ln][2]:.0%}/{tr[ln][3]:.0%}"
                for ln in ("power", "armor", "radar", "living")
            )
        )
        print(f"  four-line Lv1–3 ≥5%: {'YES' if row['tech_ok'] else 'NO'}")
        print(f"  fail types: {row['fails']}\n")

    if len(all_rows) >= 2:
        c, e = all_rows[0], all_rows[1]
        hung_delta = (
            (e["hung_med"] - c["hung_med"]) / c["hung_med"] if c["hung_med"] > 0 else 0.0
        )
        pop20_delta = e["pop20_rate"] - c["pop20_rate"]
        item6_pass = pop20_delta >= 0.05 or e["beds20_rate"] >= c["beds20_rate"]
        print(
            f"Item6 expansion contrast: pop20 {c['pop20_rate']:.0%} vs {e['pop20_rate']:.0%} (Δ{pop20_delta:.0%}) | "
            f"beds20 rate {c['beds20_rate']:.0%} vs {e['beds20_rate']:.0%} | "
            f"peak_cars {c['peak_cars_med']:.0f} vs {e['peak_cars_med']:.0f} | "
            f"hungΔ {hung_delta:.0%} (legacy ref)"
        )
        print(
            f"  Item6 rule (10 §1 #6 config25): {'PASS' if item6_pass else 'FAIL'} "
            f"(pop20Δ≥5pp or beds20_exp≥con)"
        )
        item8_pass = (
            e["pop20_rate"] >= 0.30
            and pop20_delta >= 0.05
            and c["peak_med"] >= 12
            and e["peak_med"] >= 12
        )
        print(
            f"  Item8 rule (10 §1 #8 config25): {'PASS' if item8_pass else 'FAIL'} "
            f"(exp pop20≥30%, +5pp vs con, peak_med≥12)"
        )
        item2_pass = c["surv120"] >= 0.40 and e["surv120"] >= 0.40
        print(
            f"  Item2 surv≥120d (config25): {'PASS' if item2_pass else 'FAIL'} "
            f"({c['surv120']:.0%} / {e['surv120']:.0%}, need ≥40% each)"
        )

    print("\nChecklist vs modules/10-validation.md + OPEN_LOOPS:")
    print("  [~] 1 resource guard: engine clamp")
    print("  [Y] 2/3/4/8: see rates (AUDIT K baseline)")
    print("  [~] 5 drought: acquire-only streak≥8 rate above (excl. ai_skip); guaranteeAfter=4")
    print("  [~] 6 expansion cars: contrast line above")
    print("  [~] 7 search≤3: actions capped in engine (no per-node mean yet)")
    print("  [~] 9/10 winter: 10-validation.md §1.2 conditional pass")
    print("\nSee modules/OPEN_LOOPS.md. Zero-B: 10-validation.md §2. data/balance.json config 25.")


if __name__ == "__main__":
    main()
