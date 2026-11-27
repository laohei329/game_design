# -*- coding: utf-8 -*-
"""Event op helpers for Python sim (parity with client EventOps)."""
from __future__ import annotations

from typing import Dict, Iterable, List, Mapping, MutableMapping


def scale_pile_dict(pile: MutableMapping[str, float], ratio: float) -> None:
    """Multiply pile values by (1 - ratio); drop near-zero keys."""
    r = max(0.0, min(1.0, float(ratio)))
    factor = 1.0 - r
    dead: List[str] = []
    for key, val in list(pile.items()):
        new_v = float(val) * factor
        if new_v <= 1e-6:
            dead.append(str(key))
        else:
            pile[key] = new_v
    for k in dead:
        pile.pop(k, None)


def apply_loot_halve(
    loot_piles: MutableMapping[str, Mapping[str, float]],
    *,
    target_type: str,
    target_id: str,
    ratio: float,
    segment_point_ids: Iterable[str] | None = None,
) -> None:
    """`loot_halve`：segment 扫全段点堆；否则单点。"""
    if str(target_type).lower() == "segment" or not target_id:
        ids = list(segment_point_ids or loot_piles.keys())
        for pid in ids:
            raw = loot_piles.get(pid)
            if not isinstance(raw, dict):
                continue
            pile = dict(raw)
            scale_pile_dict(pile, ratio)
            loot_piles[pid] = pile
        return
    pile_raw = loot_piles.get(target_id)
    if not isinstance(pile_raw, dict):
        return
    pile = dict(pile_raw)
    scale_pile_dict(pile, ratio)
    loot_piles[target_id] = pile


def prune_loot_piles(
    loot_piles: MutableMapping[str, Mapping[str, float]],
    valid_point_ids: Iterable[str],
) -> None:
    """区段切换：仅保留当前段点位键（OA-M4）。"""
    keep = {str(x) for x in valid_point_ids}
    for key in list(loot_piles.keys()):
        if str(key) not in keep:
            loot_piles.pop(key, None)