# -*- coding: utf-8 -*-
"""U2 最小回归：ConfigDb 全表加载 + event_ops_sim 段级 loot_halve。"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_SIM = ROOT / "sim"
if str(_SIM) not in sys.path:
    sys.path.insert(0, str(_SIM))

from config_db import ConfigDb  # noqa: E402
from event_ops_sim import apply_loot_halve  # noqa: E402


def _loot_halve_segment_case() -> None:
    piles = {
        "pt_a": {"food": 10.0, "water": 4.0},
        "pt_b": {"food": 8.0},
        "pt_old": {"food": 99.0},
    }
    apply_loot_halve(
        piles,
        target_type="segment",
        target_id="",
        ratio=0.35,
        segment_point_ids=["pt_a", "pt_b"],
    )
    assert abs(piles["pt_a"]["food"] - 6.5) < 1e-6, piles["pt_a"]
    assert abs(piles["pt_b"]["food"] - 5.2) < 1e-6, piles["pt_b"]
    assert piles["pt_old"]["food"] == 99.0


def _require_carriage_beds() -> None:
    db = ConfigDb.from_repo(ROOT)
    db.load_all()
    assert int(db.require("carriages.livingBedsPerSize")) == 2
    assert int(db.require("carriages.techBedsPerLivingLevel")) == 2


def _require_hardcode_round_keys() -> None:
    db = ConfigDb.from_repo(ROOT)
    db.load_all()
    assert int(db.require("stations.regionRunSegmentCountMin")) == 3
    assert int(db.require("stations.segmentPointsMax")) == 4
    assert float(db.require("balance.haul.haulSpecialtyMult")) == 0.85
    assert int(db.require("balance.population.breakdownCounterTrigger")) == 3
    assert int(db.require("combat.formationMaxSlots")) == 8
    assert float(db.require("hud_hints.fuelFill.highBurnFuelPerDayMin")) == 2.0
    assert float(db.require("event_draw_rules.recruitBedsFullMult")) == 0.35
    assert db.require("balance.featureFlags.useLegacyEventCards") is False
    assert db.require("balance.featureFlags.useIncidentDirector") is True
    assert db.require("balance.featureFlags.loadLegacyEventCatalog") is False
    assert "events_index" in db.tables
    assert str(db.require("incidents.types.supply_food_pressure.hook")) == "onSegmentBuild"


def _require_combat_l1_fail() -> None:
    db = ConfigDb.from_repo(ROOT)
    db.load_all()
    if db.errors:
        raise AssertionError("config_db errors: " + "; ".join(db.errors[:5]))
    inj = db.require("combat.l1Fail.injuryHpLoss")
    assert float(inj) == 12.0, f"injuryHpLoss={inj}"


def _negative_s2_event_card() -> None:
    """篡改一张事件卡（删 weight + 非法 op）→ run_validation(s2) 必须失败。"""
    import json
    from config_db import run_validation  # noqa: E402

    gen_dir = ROOT / "data" / "events" / "general"
    targets = sorted(gen_dir.glob("gen_*.json"))
    if not targets:
        raise AssertionError("no gen_*.json for negative s2 test")
    path = targets[0]
    raw = path.read_text(encoding="utf-8")
    card = json.loads(raw)
    if "weight" not in card:
        raise AssertionError(f"{path.name}: missing weight for tamper test")
    backup = raw
    weight = card.pop("weight")
    for opt in card.get("options") or []:
        if isinstance(opt, dict) and isinstance(opt.get("immediate"), dict):
            opt["immediate"]["op"] = "__tamper_invalid_op__"
            break
    path.write_text(json.dumps(card, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    try:
        import event_loader  # noqa: E402

        event_loader._CATALOG = None
        code, msgs = run_validation(repo_root=ROOT, stage="s2")
        if code == 0:
            raise AssertionError("expected run_validation(s2) FAIL after tampered card")
        joined = " ".join(msgs)
        if "missing weight" not in joined and "unknown op" not in joined:
            card["weight"] = weight
            raise AssertionError(f"expected missing weight or unknown op in msgs: {msgs[:5]}")
    finally:
        path.write_text(backup, encoding="utf-8")
        import event_loader  # noqa: E402

        event_loader._CATALOG = None


def main() -> int:
    errs: list[str] = []
    try:
        db = ConfigDb.from_repo(ROOT)
        rc = db.load_all()
        if rc != 0:
            errs.extend(db.errors or ["config_db load failed"])
        else:
            cv = int(db.manifests.get("configVersion", 0))
            if cv < 1:
                errs.append("manifest configVersion missing")
        from config_db import run_validation  # noqa: E402

        vcode, vmsgs = run_validation(repo_root=ROOT, stage="s2")
        if vcode != 0:
            errs.extend(vmsgs[:20] or ["run_validation(s2) failed"])
        _negative_s2_event_card()
    except Exception as exc:  # noqa: BLE001
        errs.append(f"config_db: {exc}")

    try:
        _loot_halve_segment_case()
        _require_combat_l1_fail()
        _require_carriage_beds()
        _require_hardcode_round_keys()
        from event_loader import (  # noqa: E402
            EventDrawContext,
            _event_weight_impl,
            load_event_catalog,
            load_event_draw_rules,
        )

        rules = load_event_draw_rules()
        sample = next(iter(load_event_catalog().values()))
        ctx = EventDrawContext.from_population(
            scenario_event_rate=1.0,
            food=10.0,
            water=10.0,
            onboard=4,
            beds=4,
            fuel=50.0,
            fuel_cap=100.0,
            raid_weight_delta=0.0,
            rules=rules,
        )
        w = _event_weight_impl(sample, ctx, rules)
        if w <= 0.0:
            raise AssertionError("event_weight_impl returned non-positive for sample card")
        from incident_sim import feature_flags, load_incident_types  # noqa: E402

        types = load_incident_types(ROOT)
        assert len(types) >= 8
        assert "recruit_day_end" in types
        ff = feature_flags(ROOT)
        assert ff["useLegacyEventCards"] is False
        assert ff["useIncidentDirector"] is True
    except Exception as exc:  # noqa: BLE001
        errs.append(f"event_ops_sim: {exc}")

    import subprocess

    try:
        rc = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "stress_sweep.py")],
            cwd=str(ROOT),
            check=False,
            capture_output=True,
            text=True,
        )
        if rc.returncode != 0:
            errs.append(f"stress_sweep exit {rc.returncode}: {rc.stderr.strip() or rc.stdout.strip()}")
    except Exception as exc:  # noqa: BLE001
        errs.append(f"stress_sweep: {exc}")

    if errs:
        print("smoke_config: FAIL")
        for e in errs:
            print(" ", e)
        return 1
    print("smoke_config: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())