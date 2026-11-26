# -*- coding: utf-8 -*-
"""Load data/events/_index.json + cards; segment event draw (06 §2.3)."""
from __future__ import annotations

import json
import random
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

ROOT = Path(__file__).resolve().parents[1]
DATA_ROOT = ROOT / "data"
EVENTS_ROOT = DATA_ROOT / "events"

_INDEX: Optional[dict] = None
_CATALOG: Optional[Dict[str, dict]] = None
_DRAW_RULES: Optional[dict] = None


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_event_draw_rules() -> dict:
    global _DRAW_RULES
    if _DRAW_RULES is not None:
        return _DRAW_RULES
    path = DATA_ROOT / "event_draw_rules.json"
    if not path.is_file():
        _DRAW_RULES = {}
        return _DRAW_RULES
    _DRAW_RULES = _read_json(path)
    return _DRAW_RULES


def load_event_index() -> dict:
    global _INDEX
    if _INDEX is not None:
        return _INDEX
    path = EVENTS_ROOT / "_index.json"
    if not path.is_file():
        raise RuntimeError("data/events/_index.json missing")
    _INDEX = _read_json(path)
    return _INDEX


def _card_path(event_id: str, index: dict) -> Path:
    if event_id.startswith("gen_"):
        return EVENTS_ROOT / "general" / f"{event_id}.json"
    if event_id.startswith("yr_"):
        return EVENTS_ROOT / "year" / f"{event_id}.json"
    prefix = event_id.split("_", 1)[0]
    season_map = {"spr": "spring", "sum": "summer", "aut": "autumn", "win": "winter"}
    season = season_map.get(prefix)
    if season:
        return EVENTS_ROOT / "season" / season / f"{event_id}.json"
    raise KeyError(event_id)


def load_event_catalog() -> Dict[str, dict]:
    global _CATALOG
    if _CATALOG is not None:
        return _CATALOG
    index = load_event_index()
    catalog: Dict[str, dict] = {}
    ids: List[str] = []
    ids.extend(index["buckets"]["general"]["eventIds"])
    for row in index["buckets"]["season"]["bySeason"].values():
        ids.extend(row["eventIds"])
    ids.extend(index["buckets"]["year"]["eventIds"])
    for eid in ids:
        path = _card_path(eid, index)
        if not path.is_file():
            raise RuntimeError(f"event card missing: {path}")
        catalog[eid] = _read_json(path)
    _CATALOG = catalog
    return catalog


def eligible_event_ids(*, season: str, year: int) -> List[str]:
    catalog = load_event_catalog()
    out: List[str] = []
    for eid, card in catalog.items():
        bucket = card.get("bucket", "general")
        if bucket == "season" and card.get("season") != season:
            continue
        if bucket == "year" and year < int(card.get("minYear", 2)):
            continue
        out.append(eid)
    return out


def primary_tag(card: dict) -> str:
    tags = card.get("tags") or []
    return str(tags[0]) if tags else "mood"


@dataclass
class EventDrawContext:
    scenario_event_rate: float = 1.0
    food: float = 0.0
    water: float = 0.0
    food_need: float = 0.0
    water_need: float = 0.0
    onboard: int = 0
    beds: int = 0
    fuel: float = 0.0
    fuel_cap: float = 100.0
    raid_weight_delta: float = 0.0
    forced_low_content: bool = False
    region_id: str = "urban"
    has_pharmacist_on_duty: bool = False
    has_guard_on_duty: bool = False
    has_unclaimed_loot: bool = False
    recent_weight_event_ids: List[str] = field(default_factory=list)
    last_segment_primary_tag: Optional[str] = None

    @classmethod
    def from_population(
        cls,
        *,
        scenario_event_rate: float,
        food: float,
        water: float,
        onboard: int,
        beds: int,
        fuel: float,
        fuel_cap: float,
        raid_weight_delta: float,
        rules: Optional[dict] = None,
        **kwargs: Any,
    ) -> "EventDrawContext":
        rules = rules or load_event_draw_rules()
        fpc = float(rules.get("foodNeedPerCapita", 2.0))
        wpc = float(rules.get("waterNeedPerCapita", 1.5))
        return cls(
            scenario_event_rate=scenario_event_rate,
            food=food,
            water=water,
            food_need=onboard * fpc,
            water_need=onboard * wpc,
            onboard=onboard,
            beds=beds,
            fuel=fuel,
            fuel_cap=max(fuel_cap, 1.0),
            raid_weight_delta=raid_weight_delta,
            **kwargs,
        )


def _event_weight_impl(card: dict, ctx: EventDrawContext, rules: Optional[dict] = None) -> float:
    """Weighted draw multiplier for one card (06 §2.3 + config)."""
    rules = rules or load_event_draw_rules()
    w = float(card.get("weight", 1.0)) * float(card.get("yieldScale", 1.0)) * ctx.scenario_event_rate
    tags: Set[str] = set(card.get("tags") or [])
    ptag = primary_tag(card)

    if "supply" in tags:
        if ctx.food < ctx.food_need:
            w += float(rules.get("supplyFoodBoost", 0.4))
        if ctx.water < ctx.water_need:
            w += float(rules.get("supplyWaterBoost", 0.35))

    if "recruit" in tags:
        if ctx.onboard >= ctx.beds and ctx.beds > 0:
            w *= float(rules.get("recruitBedsFullMult", 0.35))
        else:
            w *= float(rules.get("recruitHasBedsMult", 1.25))
        if ctx.food < ctx.food_need and ctx.onboard < ctx.beds:
            w *= float(rules.get("recruitLowFoodMult", 1.3))

    raid_tags = set(rules.get("raidDeltaTags", ["raid"]))
    if tags & raid_tags:
        w += ctx.raid_weight_delta
        if ctx.has_unclaimed_loot:
            w += float(rules.get("unclaimedLootRaidBoost", 0.25))
        if ctx.has_guard_on_duty:
            w *= float(rules.get("guardOnDutyRaidMult", 0.85))

    if "mood" in tags and w > 0:
        w *= float(rules.get("moodTagDampenMult", 0.9))

    pharma = rules.get("pharmacistOnDutyTagBoost") or {}
    if ctx.has_pharmacist_on_duty and ctx.region_id == pharma.get("regionOnly", "plague"):
        boost_tags = set(pharma.get("tags") or [])
        if tags & boost_tags:
            w += float(pharma.get("delta", 0.2))

    if ctx.forced_low_content:
        flp = rules.get("forcedLowPressure") or {}
        if ptag in set(flp.get("boostTags") or []):
            w += float(flp.get("tagBoost", 0.5))
        suppress = flp.get("suppressTagMult") or {}
        for t in tags:
            if t in suppress:
                w *= float(suppress[t])

    low_fuel = rules.get("lowFuelSupplyBoost") or {}
    fuel_fill = ctx.fuel / ctx.fuel_cap if ctx.fuel_cap > 0 else 1.0
    if fuel_fill < float(low_fuel.get("fuelFillBelow", 0.35)):
        if tags & set(low_fuel.get("tags") or ["supply"]):
            w += float(low_fuel.get("tagBoost", 0.25))

    wid = str(card.get("weightEventId", card.get("id", "")))
    nr = rules.get("noRepeatWeightEventId") or {}
    window = int(nr.get("windowSegmentsInRun", 2))
    if wid in ctx.recent_weight_event_ids[-window:]:
        w *= float(nr.get("weightMult", 0.12))

    trp = rules.get("tagRepeatPenalty") or {}
    if ctx.last_segment_primary_tag and ptag == ctx.last_segment_primary_tag:
        w *= float(trp.get("lastPrimaryTagMult", 0.35))

    return max(0.0, w)


def build_event_weights(
    *,
    season: str,
    year: int,
    ctx: EventDrawContext,
    catalog: Optional[Dict[str, dict]] = None,
) -> Dict[str, float]:
    catalog = catalog or load_event_catalog()
    rules = load_event_draw_rules()
    weights: Dict[str, float] = {}
    for event_id in eligible_event_ids(season=season, year=year):
        card = catalog[event_id]
        value = _event_weight_impl(card, ctx, rules)
        if value > 0:
            weights[event_id] = value
    return weights


def draw_event_id(
    rng: random.Random,
    *,
    season: str,
    year: int,
    ctx: EventDrawContext,
    catalog: Optional[Dict[str, dict]] = None,
) -> str:
    weights = build_event_weights(season=season, year=year, ctx=ctx, catalog=catalog)
    catalog = catalog or load_event_catalog()
    if not weights:
        pool = eligible_event_ids(season=season, year=year)
        return pool[rng.randrange(len(pool))]
    total = sum(weights.values())
    pick = rng.random() * total
    acc = 0.0
    for eid, w in weights.items():
        acc += w
        if pick <= acc:
            return eid
    return next(iter(weights))


def event_weight(
    card: dict,
    ctx: Optional[EventDrawContext] = None,
    rules: Optional[dict] = None,
    *,
    scenario_event_rate: float = 1.0,
    food: float = 0.0,
    food_need: float = 0.0,
    onboard: int = 0,
    beds: int = 0,
    raid_weight_delta: float = 0.0,
    **extra: Any,
) -> float:
    if ctx is None:
        ctx = _legacy_ctx(
            scenario_event_rate=scenario_event_rate,
            food=food,
            food_need=food_need,
            onboard=onboard,
            beds=beds,
            raid_weight_delta=raid_weight_delta,
            **extra,
        )
    return _event_weight_impl(card, ctx, rules)


def _legacy_ctx(
    *,
    scenario_event_rate: float,
    food: float,
    food_need: float,
    onboard: int,
    beds: int,
    raid_weight_delta: float,
    **extra: Any,
) -> EventDrawContext:
    return EventDrawContext.from_population(
        scenario_event_rate=scenario_event_rate,
        food=food,
        water=extra.get("water", food),
        onboard=onboard,
        beds=beds,
        fuel=float(extra.get("fuel", 50.0)),
        fuel_cap=float(extra.get("fuel_cap", 100.0)),
        raid_weight_delta=raid_weight_delta,
        forced_low_content=bool(extra.get("forced_low_content", False)),
        region_id=str(extra.get("region_id", "urban")),
        has_pharmacist_on_duty=bool(extra.get("has_pharmacist_on_duty", False)),
        has_guard_on_duty=bool(extra.get("has_guard_on_duty", False)),
        has_unclaimed_loot=bool(extra.get("has_unclaimed_loot", False)),
        recent_weight_event_ids=list(extra.get("recent_weight_event_ids") or []),
        last_segment_primary_tag=extra.get("last_segment_primary_tag"),
    )