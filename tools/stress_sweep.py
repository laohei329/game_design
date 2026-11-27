# -*- coding: utf-8 -*-
"""阶段 6：合成应力快照 → 列出触发的 incident 类型（对照 client 谓词）。"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_SIM = ROOT / "sim"
if str(_SIM) not in sys.path:
    sys.path.insert(0, str(_SIM))

from incident_sim import (  # noqa: E402
    eligible_for_hook,
    feature_flags,
    load_incident_types,
    load_predicates,
)

# 命名场景：用于验收「调应力 → 触发集单调变化」
SCENARIOS: dict[str, dict] = {
    "baseline_full_bellies": {
        "food": 40.0,
        "water": 40.0,
        "food_need": 20.0,
        "water_need": 15.0,
        "onboard": 4,
        "beds": 4,
        "fuel_fill": 0.8,
        "unclaimed_loot": False,
        "guard_on_duty": False,
        "forced_low_content": False,
        "day_total": 10,
        "last_recruit_success_day": -1,
    },
    "food_stress": {
        "food": 5.0,
        "water": 40.0,
        "food_need": 20.0,
        "water_need": 15.0,
        "onboard": 4,
        "beds": 4,
        "fuel_fill": 0.8,
        "unclaimed_loot": False,
        "guard_on_duty": False,
        "forced_low_content": False,
        "day_total": 10,
        "last_recruit_success_day": -1,
    },
    "beds_open_recruit": {
        "food": 30.0,
        "water": 30.0,
        "food_need": 20.0,
        "water_need": 15.0,
        "onboard": 3,
        "beds": 6,
        "fuel_fill": 0.5,
        "unclaimed_loot": False,
        "guard_on_duty": False,
        "forced_low_content": False,
        "day_total": 10,
        "last_recruit_success_day": -1,
    },
    "loot_and_guard": {
        "food": 30.0,
        "water": 30.0,
        "food_need": 20.0,
        "water_need": 15.0,
        "onboard": 4,
        "beds": 4,
        "fuel_fill": 0.8,
        "unclaimed_loot": True,
        "guard_on_duty": True,
        "forced_low_content": False,
        "day_total": 10,
        "last_recruit_success_day": -1,
    },
    "day_end_recruit": {
        "food": 20.0,
        "water": 20.0,
        "food_need": 20.0,
        "water_need": 15.0,
        "onboard": 3,
        "beds": 6,
        "fuel_fill": 0.6,
        "unclaimed_loot": False,
        "guard_on_duty": False,
        "forced_low_content": False,
        "day_total": 12,
        "last_recruit_success_day": 11,
    },
}


def _assert_monotonic() -> None:
    types = load_incident_types(ROOT)
    preds = load_predicates(ROOT)
    base = {t for t, _ in eligible_for_hook(types, SCENARIOS["baseline_full_bellies"], "onSegmentBuild", preds)}
    food = {t for t, _ in eligible_for_hook(types, SCENARIOS["food_stress"], "onSegmentBuild", preds)}
    assert "supply_food_pressure" in food
    assert "supply_food_pressure" not in base
    beds = {t for t, _ in eligible_for_hook(types, SCENARIOS["beds_open_recruit"], "onSegmentBuild", preds)}
    assert "recruit_segment_offer" in beds
    day = {t for t, _ in eligible_for_hook(types, SCENARIOS["day_end_recruit"], "onDayEnd", preds)}
    assert "recruit_day_end" in day


def main() -> int:
    types = load_incident_types(ROOT)
    preds = load_predicates(ROOT)
    flags = feature_flags(ROOT)
    print(f"stress_sweep: types={len(types)} flags={flags}")
    for name, snap in SCENARIOS.items():
        seg = [t for t, _ in eligible_for_hook(types, snap, "onSegmentBuild", preds)]
        day = [t for t, _ in eligible_for_hook(types, snap, "onDayEnd", preds)]
        print(f"  {name}: segment={seg or '-'} day_end={day or '-'}")
    try:
        _assert_monotonic()
    except AssertionError as exc:
        print("stress_sweep: FAIL", exc)
        return 1
    print("stress_sweep: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())