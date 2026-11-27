# -*- coding: utf-8 -*-
"""Incident 对照端：与 client IncidentStress / IncidentDirector 同表（无 Godot）。"""
from __future__ import annotations

from pathlib import Path
from typing import Any

from config_db import ConfigDb


def load_incident_types(repo: Path) -> dict[str, Any]:
    db = ConfigDb.from_repo(repo)
    db.load_all()
    root = db.require("incidents.types")
    if not isinstance(root, dict):
        return {}
    return root


def load_predicates(repo: Path) -> dict[str, Any]:
    db = ConfigDb.from_repo(repo)
    db.load_all()
    root = db.require("stress.predicates")
    if not isinstance(root, dict):
        return {}
    return root


def feature_flags(repo: Path) -> dict[str, bool]:
    db = ConfigDb.from_repo(repo)
    db.load_all()
    flags = db.require("balance.featureFlags")
    if not isinstance(flags, dict):
        return {
            "useLegacyEventCards": False,
            "useIncidentDirector": True,
            "loadLegacyEventCatalog": False,
        }
    return {
        "useLegacyEventCards": bool(flags.get("useLegacyEventCards", False)),
        "useIncidentDirector": bool(flags.get("useIncidentDirector", True)),
        "loadLegacyEventCatalog": bool(flags.get("loadLegacyEventCatalog", False)),
    }


def predicate_met(pred_id: str, snap: dict[str, Any], preds: dict[str, Any]) -> bool:
    row = preds.get(pred_id)
    if not isinstance(row, dict):
        return False
    signal = str(row.get("signal", ""))
    cmp = str(row.get("compare", ""))
    if signal == "food" and cmp == "lt":
        return float(snap.get("food", 0)) < float(snap.get("food_need", 0))
    if signal == "water" and cmp == "lt":
        return float(snap.get("water", 0)) < float(snap.get("water_need", 0))
    if signal == "onboard":
        ob = int(snap.get("onboard", 0))
        beds = int(snap.get("beds", 0))
        if row.get("extra") == "onboard_lt_beds":
            if float(snap.get("food", 0)) >= float(snap.get("food_need", 0)):
                return False
            return ob < beds
        min_b = int(row.get("minBeds", 0))
        if cmp == "gte" and min_b > 0:
            return ob >= beds and beds >= min_b
        if cmp == "lt":
            return ob < beds
    if signal == "unclaimed_loot":
        return bool(snap.get("unclaimed_loot", False)) == bool(row.get("value", True))
    if signal == "guard_on_duty":
        return bool(snap.get("guard_on_duty", False)) == bool(row.get("value", True))
    if signal == "forced_low_content":
        return bool(snap.get("forced_low_content", False)) == bool(row.get("value", True))
    if signal == "fuel_fill" and cmp == "lt":
        return float(snap.get("fuel_fill", 1.0)) < float(row.get("value", 0.35))
    if signal == "day_end_recruit":
        ob2 = int(snap.get("onboard", 0))
        beds2 = int(snap.get("beds", 0))
        if ob2 >= beds2:
            return False
        return int(snap.get("last_recruit_success_day", -1)) != int(snap.get("day_total", 0))
    return False


def triggers_pass(row: dict[str, Any], snap: dict[str, Any], preds: dict[str, Any]) -> bool:
    any_list = row.get("triggersAny")
    if isinstance(any_list, list) and any_list:
        return any(predicate_met(str(p), snap, preds) for p in any_list)
    all_list = row.get("triggersAll")
    if isinstance(all_list, list) and all_list:
        return all(predicate_met(str(p), snap, preds) for p in all_list)
    return True


def eligible_for_hook(
    types: dict[str, Any],
    snap: dict[str, Any],
    hook: str,
    preds: dict[str, Any],
) -> list[tuple[str, dict[str, Any]]]:
    out: list[tuple[str, dict[str, Any]]] = []
    for tid, row in types.items():
        if not isinstance(row, dict):
            continue
        if str(row.get("hook", "")) != hook:
            continue
        if not triggers_pass(row, snap, preds):
            continue
        out.append((str(tid), row))
    return out