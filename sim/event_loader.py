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


def _require_rule(rules: dict, key: str, *, ctx: str = "event_draw_rules") -> float:
    if key not in rules:
        raise KeyError(f"{ctx} missing {key!r}")
    return float(rules[key])


def _require_block(rules: dict, key: str, *, ctx: str = "event_draw_rules") -> dict:
    if key not in rules:
        raise KeyError(f"{ctx} missing block {key!r}")
    block = rules[key]
    if not isinstance(block, dict):
        raise TypeError(f"{ctx}.{key} must be object")
    return block


def _require_list(rules: dict, key: str, *, ctx: str = "event_draw_rules") -> List[Any]:
    if key not in rules:
        raise KeyError(f"{ctx} missing list {key!r}")
    block = rules[key]
    if not isinstance(block, list):
        raise TypeError(f"{ctx}.{key} must be array")
    return block


def _require_str(block: dict, key: str, *, ctx: str) -> str:
    if key not in block:
        raise KeyError(f"{ctx} missing {key!r}")
    return str(block[key])


def validate_event_draw_rules(rules: dict) -> None:
    """结构与必填键（与 data/event_draw_rules.json 一致）；加载后调用。"""
    for key in (
        "foodNeedPerCapita",
        "waterNeedPerCapita",
        "supplyFoodBoost",
        "supplyWaterBoost",
        "recruitBedsFullMult",
        "recruitHasBedsMult",
        "recruitLowFoodMult",
        "unclaimedLootRaidBoost",
        "guardOnDutyRaidMult",
        "moodTagDampenMult",
    ):
        _require_rule(rules, key)
    _require_list(rules, "raidDeltaTags")
    pharma = _require_block(rules, "pharmacistOnDutyTagBoost")
    _require_list(pharma, "tags", ctx="pharmacistOnDutyTagBoost")
    _require_rule(pharma, "delta", ctx="pharmacistOnDutyTagBoost")
    _require_str(pharma, "regionOnly", ctx="pharmacistOnDutyTagBoost")
    flp = _require_block(rules, "forcedLowPressure")
    _require_list(flp, "boostTags", ctx="forcedLowPressure")
    _require_rule(flp, "tagBoost", ctx="forcedLowPressure")
    suppress = _require_block(flp, "suppressTagMult", ctx="forcedLowPressure")
    if not isinstance(suppress, dict) or not suppress:
        raise TypeError("forcedLowPressure.suppressTagMult must be non-empty object")
    low_fuel = _require_block(rules, "lowFuelSupplyBoost")
    _require_rule(low_fuel, "fuelFillBelow", ctx="lowFuelSupplyBoost")
    _require_rule(low_fuel, "tagBoost", ctx="lowFuelSupplyBoost")
    _require_list(low_fuel, "tags", ctx="lowFuelSupplyBoost")
    nr = _require_block(rules, "noRepeatWeightEventId")
    _require_rule(nr, "windowSegmentsInRun", ctx="noRepeatWeightEventId")
    _require_rule(nr, "weightMult", ctx="noRepeatWeightEventId")
    trp = _require_block(rules, "tagRepeatPenalty")
    _require_rule(trp, "lastPrimaryTagMult", ctx="tagRepeatPenalty")


def load_event_draw_rules() -> dict:
    global _DRAW_RULES
    if _DRAW_RULES is not None:
        return _DRAW_RULES
    path = DATA_ROOT / "event_draw_rules.json"
    if not path.is_file():
        raise RuntimeError("data/event_draw_rules.json missing")
    _DRAW_RULES = _read_json(path)
    validate_event_draw_rules(_DRAW_RULES)
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
        fpc = _require_rule(rules, "foodNeedPerCapita")
        wpc = _require_rule(rules, "waterNeedPerCapita")
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
    if "weight" not in card or "yieldScale" not in card:
        raise KeyError(f"event card {card.get('id', '?')} missing weight or yieldScale")
    w = float(card["weight"]) * float(card["yieldScale"]) * ctx.scenario_event_rate
    tags: Set[str] = set(card.get("tags") or [])
    ptag = primary_tag(card)

    if "supply" in tags:
        if ctx.food < ctx.food_need:
            w += _require_rule(rules, "supplyFoodBoost")
        if ctx.water < ctx.water_need:
            w += _require_rule(rules, "supplyWaterBoost")

    if "recruit" in tags:
        if ctx.onboard >= ctx.beds and ctx.beds > 0:
            w *= _require_rule(rules, "recruitBedsFullMult")
        else:
            w *= _require_rule(rules, "recruitHasBedsMult")
        if ctx.food < ctx.food_need and ctx.onboard < ctx.beds:
            w *= _require_rule(rules, "recruitLowFoodMult")

    raid_tags = set(str(t) for t in _require_list(rules, "raidDeltaTags"))
    if tags & raid_tags:
        w += ctx.raid_weight_delta
        if ctx.has_unclaimed_loot:
            w += _require_rule(rules, "unclaimedLootRaidBoost")
        if ctx.has_guard_on_duty:
            w *= _require_rule(rules, "guardOnDutyRaidMult")

    if "mood" in tags and w > 0:
        w *= _require_rule(rules, "moodTagDampenMult")

    pharma = _require_block(rules, "pharmacistOnDutyTagBoost")
    if ctx.has_pharmacist_on_duty and ctx.region_id == _require_str(
        pharma, "regionOnly", ctx="pharmacistOnDutyTagBoost"
    ):
        boost_tags = set(str(t) for t in _require_list(pharma, "tags", ctx="pharmacistOnDutyTagBoost"))
        if tags & boost_tags:
            w += _require_rule(pharma, "delta", ctx="pharmacistOnDutyTagBoost")

    if ctx.forced_low_content:
        flp = _require_block(rules, "forcedLowPressure")
        boost_tags = set(str(t) for t in _require_list(flp, "boostTags", ctx="forcedLowPressure"))
        if ptag in boost_tags:
            w += _require_rule(flp, "tagBoost", ctx="forcedLowPressure")
        suppress = _require_block(flp, "suppressTagMult", ctx="forcedLowPressure")
        for t in tags:
            if t in suppress:
                w *= float(suppress[t])

    low_fuel = _require_block(rules, "lowFuelSupplyBoost")
    fuel_fill = ctx.fuel / ctx.fuel_cap if ctx.fuel_cap > 0 else 1.0
    if fuel_fill < _require_rule(low_fuel, "fuelFillBelow", ctx="lowFuelSupplyBoost"):
        fuel_tags = set(str(t) for t in _require_list(low_fuel, "tags", ctx="lowFuelSupplyBoost"))
        if tags & fuel_tags:
            w += _require_rule(low_fuel, "tagBoost", ctx="lowFuelSupplyBoost")

    wid = str(card.get("weightEventId", card.get("id", "")))
    nr = _require_block(rules, "noRepeatWeightEventId")
    window = int(_require_rule(nr, "windowSegmentsInRun", ctx="noRepeatWeightEventId"))
    if wid in ctx.recent_weight_event_ids[-window:]:
        w *= _require_rule(nr, "weightMult", ctx="noRepeatWeightEventId")

    trp = _require_block(rules, "tagRepeatPenalty")
    if ctx.last_segment_primary_tag and ptag == ctx.last_segment_primary_tag:
        w *= _require_rule(trp, "lastPrimaryTagMult", ctx="tagRepeatPenalty")

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