# -*- coding: utf-8 -*-
"""事件权重蒙特卡洛：固定种子大量抽样，检测零权重与异常主导卡。"""
from __future__ import annotations

import random
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_SIM = ROOT / "sim"
if str(_SIM) not in sys.path:
    sys.path.insert(0, str(_SIM))

from event_loader import EventDrawContext, build_event_weights, load_event_catalog  # noqa: E402


def _tag_mass(weights: dict, catalog: dict, tag: str) -> float:
    total = 0.0
    for eid, w in weights.items():
        tags = catalog.get(eid, {}).get("tags") or []
        if tag in tags:
            total += w
    return total


def _draw_n(
    n: int,
    seed: int,
    ctx: EventDrawContext,
    season: str = "summer",
    year: int = 1,
    catalog: dict | None = None,
) -> Counter:
    rng = random.Random(seed)
    catalog = catalog or load_event_catalog()
    counts: Counter = Counter()
    for _ in range(n):
        weights = build_event_weights(season=season, year=year, ctx=ctx, catalog=catalog)
        total = sum(weights.values())
        if total <= 0:
            raise RuntimeError("all weights zero")
        r = rng.random() * total
        picked = None
        for eid, w in weights.items():
            r -= w
            if r <= 0:
                picked = eid
                break
        if picked is None:
            picked = next(iter(weights))
        counts[picked] += 1
    return counts


def main() -> int:
    n = 1500
    errs: list[str] = []
    catalog = load_event_catalog()

    ctx_ok = EventDrawContext.from_population(
        scenario_event_rate=1.0,
        food=40.0,
        water=40.0,
        onboard=4,
        beds=6,
        fuel=80.0,
        fuel_cap=100.0,
        raid_weight_delta=0.0,
    )
    baseline = _draw_n(n, 42, ctx_ok, catalog=catalog)
    top_id, top_n = baseline.most_common(1)[0]
    top_share = top_n / n
    if top_share > 0.85:
        errs.append(f"baseline top card {top_id} share={top_share:.1%} (>85%)")

    ctx_low_food = EventDrawContext.from_population(
        scenario_event_rate=1.0,
        food=2.0,
        water=40.0,
        onboard=4,
        beds=6,
        fuel=80.0,
        fuel_cap=100.0,
        raid_weight_delta=0.0,
    )
    w_ok = build_event_weights(season="summer", year=1, ctx=ctx_ok, catalog=catalog)
    w_low = build_event_weights(season="summer", year=1, ctx=ctx_low_food, catalog=catalog)
    if _tag_mass(w_low, catalog, "supply") <= _tag_mass(w_ok, catalog, "supply"):
        errs.append("low food should increase supply-tag weight mass")

    ctx_raid = EventDrawContext.from_population(
        scenario_event_rate=1.0,
        food=40.0,
        water=40.0,
        onboard=4,
        beds=6,
        fuel=80.0,
        fuel_cap=100.0,
        raid_weight_delta=0.4,
    )
    ctx_forced = EventDrawContext.from_population(
        scenario_event_rate=1.0,
        food=40.0,
        water=40.0,
        onboard=4,
        beds=6,
        fuel=80.0,
        fuel_cap=100.0,
        raid_weight_delta=0.4,
        forced_low_content=True,
    )
    w_raid = build_event_weights(season="summer", year=1, ctx=ctx_raid, catalog=catalog)
    w_forced = build_event_weights(season="summer", year=1, ctx=ctx_forced, catalog=catalog)
    if _tag_mass(w_forced, catalog, "raid") >= _tag_mass(w_raid, catalog, "raid"):
        errs.append("forced_low_content should reduce raid-tag weight mass")

    print(f"probe_event_weight_mc: draws={n} top_share={top_share:.1%} ({top_id})")
    if errs:
        print("probe_event_weight_mc: FAIL")
        for e in errs:
            print(" ", e)
        return 1
    print("probe_event_weight_mc: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())