# -*- coding: utf-8 -*-
"""综合时间事件模拟：按现行设计规则扫描日历、气候、区段、事件、资源与人口闭环。

对齐：设计 v1.3.33 / 规格 v1.52 / configVersion 25 / version.save 12。
用途：找设计闭环与数值风险；不是正式阶段零过关证书。
"""
from __future__ import annotations

import argparse
import math
import random
import statistics
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    from sim.event_loader import (
        EventDrawContext,
        draw_event_id,
        eligible_event_ids,
        load_event_catalog,
        primary_tag,
    )
except ImportError:
    from event_loader import (
        EventDrawContext,
        draw_event_id,
        eligible_event_ids,
        load_event_catalog,
        primary_tag,
    )

try:
    from sim.point_types import (
        compute_type_weights,
        load_point_types,
        load_regions,
        load_weather_sweep,
        load_season_pressure,
        load_stations_config,
        pool_multiplier,
        sim_yield_for,
        station_count_choice_weights,
        year_threat_multiplier,
    )
except ImportError:
    from point_types import (
        compute_type_weights,
        load_point_types,
        load_regions,
        load_weather_sweep,
        load_season_pressure,
        load_stations_config,
        pool_multiplier,
        sim_yield_for,
        station_count_choice_weights,
        year_threat_multiplier,
    )

REGIONS = load_regions()
POOL_MULTIPLIER = pool_multiplier()

SEASON_LENGTH = 30
YEAR_LENGTH = 120
DRIVE_HOUR_CAP = 1.0
STATIONS_CFG = load_stations_config()
GUARANTEE_AFTER = int(STATIONS_CFG.get("guaranteeAfter", 4))
SEASON_PRESSURE = load_season_pressure()
MAX_PIECE_SEARCH_PER_POINT_PER_DAY = 3

SEASONS = ("spring", "summer", "autumn", "winter")
SEASON_NAMES = {"spring": "春", "summer": "夏", "autumn": "秋", "winter": "冬"}
SEASON_BASE_TEMP = {"spring": 0.0, "summer": 1.0, "autumn": 0.0, "winter": -1.0}
WEATHER = load_weather_sweep()
EVENT_CATALOG = load_event_catalog()

def season_at(day: int) -> str:
    return SEASONS[((day - 1) % YEAR_LENGTH) // SEASON_LENGTH]


def year_at(day: int) -> int:
    return (day - 1) // YEAR_LENGTH + 1


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def weighted_pick(rng: random.Random, weights: Dict[str, float]) -> str:
    items = [(key, max(0.0, float(value))) for key, value in weights.items()]
    total = sum(value for _, value in items)
    if total <= 0:
        return rng.choice(list(weights.keys()))
    roll = rng.random() * total
    for key, value in items:
        roll -= value
        if roll <= 0:
            return key
    return items[-1][0]


@dataclass
class Carriage:
    template_id: str
    size: int
    function: Optional[str] = None
    armor: int = 0
    speed_bonus: int = 0
    efficiency: int = 0
    fuel_add: float = 0.0
    advanced: bool = False


@dataclass
class Member:
    member_id: int
    hp: float = 100.0
    alive: bool = True
    job: str = "none"
    mood: float = 60.0
    specialty: Optional[str] = None
    disease_stage: str = "none"
    disease_days: int = 0
    death_cause: Optional[str] = None


@dataclass
class Point:
    point_id: str
    ptype: str
    pool: float
    searches_today: int = 0


@dataclass
class Station:
    position_km: float
    size: str
    none_pool: bool
    empty: bool
    offer: Optional[dict] = None
    visited: bool = False


@dataclass
class Segment:
    segment_index: int
    length_km: float
    progress_km: float = 0.0
    built: bool = False
    weather_id: Optional[str] = None
    weather_draw_count: int = 0
    pressure_class: Optional[str] = None
    forced_low_content: bool = False
    points: List[Point] = field(default_factory=list)
    stations: List[Station] = field(default_factory=list)
    event_id: Optional[str] = None
    surcharge: float = 0.0
    raid_weight_delta: float = 0.0


@dataclass
class RegionRun:
    region_id: str
    segment_count: int
    segments: List[Segment]
    index: int = 0
    fuel_mult: float = 1.0
    point_mods: Dict[str, float] = field(default_factory=dict)
    recent_weight_event_ids: List[str] = field(default_factory=list)
    last_segment_primary_tag: Optional[str] = None

    @property
    def current(self) -> Segment:
        return self.segments[self.index]


@dataclass
class DelayedEvent:
    event_id: str
    fire_day: int
    target_type: str
    target_id: Optional[str]
    op: str
    args: dict
    capture: str
    snapshot: Optional[dict] = None


@dataclass
class Scenario:
    name: str
    strategy: str
    event_rate: float = 1.0
    threat_rate: float = 1.0
    heating: bool = True
    reverse_probe: bool = False
    tutorial_supply_guard: bool = False


@dataclass
class State:
    seed: int
    scenario: Scenario
    day: int = 1
    food: float = 20.0
    water: float = 24.0
    fuel: float = 88.0
    parts: float = 6.0
    medicine: float = 4.0
    scrap: float = 2.0
    seed_stock: float = 1.0
    chem: float = 0.0
    cloth: float = 1.0
    crystal: float = 0.0
    potion_catalyst: float = 0.0
    body_hp: float = 100.0
    breakdown_counter: int = 0
    carriages: List[Carriage] = field(default_factory=lambda: [
        Carriage("power", 3, None, 20, 20, 0, 0.0),
        Carriage("living", 2, None, 10, 0, 0, 1.0),
        Carriage("cargo", 3, None, 10, 0, 0, 1.0),
    ])
    members: List[Member] = field(default_factory=list)
    next_member_id: int = 5
    power_tech: int = 0
    armor_tech: int = 0
    radar_tech: int = 0
    living_tech: int = 0
    precision: Optional[float] = None
    blueprints: Dict[str, bool] = field(default_factory=lambda: {"power": False, "armor": False, "radar": False, "living": False})
    food_zero_streak: int = 0
    water_zero_streak: int = 0
    fuel_zero_streak: int = 0
    morale_zero_streak: int = 0
    morale_offset: float = 0.0
    food_went_zero: bool = False
    water_went_zero: bool = False
    region_run: Optional[RegionRun] = None
    weather_id: str = "clear"
    climate_influences: List[dict] = field(default_factory=list)
    climate: Dict[str, float] = field(default_factory=dict)
    pressure_history: List[Optional[str]] = field(default_factory=lambda: [None, None])
    delayed_events: List[DelayedEvent] = field(default_factory=list)
    event_flags: Dict[str, int] = field(default_factory=dict)
    loot_piles: Dict[str, Dict[str, float]] = field(default_factory=dict)
    last_recruit_success_day: int = -1
    today_speed_coef: float = 0.3
    today_forward_hours: float = 0.0
    today_reverse_hours: float = 0.0
    travel_budget_exhausted: bool = False
    stats: Counter = field(default_factory=Counter)
    anomalies: Counter = field(default_factory=Counter)
    deaths: Counter = field(default_factory=Counter)
    first_food_zero_day: Optional[int] = None
    first_water_zero_day: Optional[int] = None
    first_fuel_zero_day: Optional[int] = None
    peak_pop: int = 4
    failed: Optional[str] = None
    reverse_probe_day: int = 80
    reverse_probe_done: bool = False


def starter_members() -> List[Member]:
    return [
        Member(1, job="engineer", specialty="repair"),
        Member(2, job="guard", specialty="combat_drill"),
        Member(3, job="labor", specialty="haul"),
        Member(4, job="labor", specialty="scavenge"),
    ]


def onboard(state: State) -> int:
    return sum(1 for member in state.members if member.alive)


def beds(state: State) -> int:
    base = sum(car.size * 2 for car in state.carriages if car.template_id == "living")
    return base + 2 * state.living_tech


def cargo_size(state: State) -> int:
    return sum(car.size for car in state.carriages if car.template_id == "cargo")


def cap_of(state: State, res: str) -> float:
    life_mult = 1 + 0.10 * state.living_tech
    cargo = cargo_size(state)
    if res == "food" or res == "water":
        return (60 + cargo * 10) * life_mult
    if res == "parts":
        return (20 + round(cargo * 10 / 3)) * life_mult
    if res == "medicine" or res == "chem":
        return (15 + round(cargo * 5 / 3)) * life_mult
    if res == "fuel":
        return 100 + cargo * 6
    if res == "scrap":
        return (30 + cargo * 8) * life_mult
    if res == "seed":
        return (20 + cargo * 4) * life_mult
    if res == "cloth":
        return (20 + cargo * 5) * life_mult
    if res == "crystal":
        return 5.0
    if res == "potion_upgrade":
        return 5.0
    if res == "potion_catalyst":
        return 10.0
    return math.inf


def add_resource(state: State, res: str, amount: float) -> float:
    if not math.isfinite(amount):
        state.anomalies["库存出现 NaN 或无穷"] += 1
        return 0.0
    cap = cap_of(state, res)
    old = getattr(state, res, 0.0)
    new = clamp(old + amount, 0.0, cap)
    if new < -1e-9:
        state.anomalies["库存为负"] += 1
    if new > cap + 1e-9:
        state.anomalies["库存超过上限"] += 1
    setattr(state, res, new)
    return new - old


def recompute_climate(state: State) -> None:
    season = season_at(state.day)
    weather = WEATHER[state.weather_id]
    influence_temp = clamp(sum(float(inf.get("tempMod", 0.0)) for inf in state.climate_influences), -1.5, 1.5)
    effective_temp = clamp(SEASON_BASE_TEMP[season] + weather["temp"] + influence_temp, -2.0, 2.0)
    cold = max(0.0, -effective_temp)
    heat = max(0.0, effective_temp)
    water_mod_product = 1.0
    speed_mod_product = 1.0
    pressure_add = 0.0
    for inf in state.climate_influences:
        water_mod_product *= float(inf.get("waterMod", 1.0))
        speed_mod_product *= float(inf.get("speedMult", 1.0))
        pressure_add += float(inf.get("pressureAdd", 0.0))
    water_temp = 1.5 if heat >= 1 else (1.2 if heat >= 0.5 else 1.0)
    food_climate = 1.40 if cold >= 2 else (1.25 if cold >= 1 else (1.10 if cold >= 0.5 else 1.0))
    fuel_climate = 1.56 if cold >= 2 else (1.43 if cold >= 1 else (1.15 if cold >= 0.5 else 1.0))
    greenhouse = 1.0 if cold < 1 else (0.95 if state.scenario.heating else 0.50)
    year_threat = year_threat_multiplier(year_at(state.day))
    pressure = SEASON_PRESSURE[season] * year_threat + weather["pressure"] + pressure_add
    state.climate = {
        "effectiveTemp": effective_temp,
        "coldIndex": cold,
        "heatIndex": heat,
        "foodClimate": food_climate,
        "waterClimate": water_temp * weather["water"] * water_mod_product,
        "fuelClimate": fuel_climate,
        "greenhouseClimate": greenhouse,
        "speedClimate": weather["speed"] * speed_mod_product,
        "pressure": pressure,
        "yearThreat": year_threat,
    }


def pressure_class(value: float) -> str:
    if value >= 2.0:
        return "high"
    if value <= 1.2:
        return "low"
    return "mid"


def weather_weights(state: State) -> Dict[str, float]:
    season = season_at(state.day)
    year = year_at(state.day)
    idx = 3 if season == "winter" and year <= 2 else (4 if season == "winter" else SEASONS.index(season))
    weights = {}
    for weather_id, table in WEATHER.items():
        value = float(table["w"][idx])
        for inf in state.climate_influences:
            value *= float(inf.get("weatherBias", {}).get(weather_id, 1.0))
        weights[weather_id] = value
    if sum(weights.values()) <= 0:
        return {wid: float(table["w"][idx]) for wid, table in WEATHER.items()}
    return weights


def point_weights(state: State, segment: Segment) -> Dict[str, float]:
    if state.region_run is None:
        return {}
    return compute_type_weights(
        season=season_at(state.day),
        region_id=state.region_run.region_id,
        point_mods=state.region_run.point_mods,
        weather_id=state.weather_id,
        radar_tech=state.radar_tech,
        include_sweep_only=True,
        horde_weather_boost=True,
    )


def start_region_run(state: State, rng: random.Random, force_region: Optional[str] = None) -> None:
    region_id = force_region or rng.choice(list(REGIONS.keys()))
    meta = REGIONS[region_id]
    count = rng.randint(3, 5)
    seg_min = float(STATIONS_CFG.get("segmentLengthMin", 40))
    seg_max = float(STATIONS_CFG.get("segmentLengthMax", 60))
    segments = [Segment(i, rng.uniform(seg_min, seg_max)) for i in range(count)]
    state.region_run = RegionRun(
        region_id=region_id,
        segment_count=count,
        segments=segments,
        index=0,
        fuel_mult=meta["fuel_mult"],
        point_mods=dict(meta["mods"]),
    )
    state.stats["跨度开始"] += 1
    for segment in segments:
        for station in segment.stations:
            station.offer = None
    for point_id in list(state.loot_piles.keys()):
        if point_id.startswith("segment-") and not point_id.startswith(f"segment-{state.day}-"):
            pass


def expire_influences_before_segment(state: State) -> None:
    removed = False
    kept = []
    for inf in state.climate_influences:
        if "expiresSegment" in inf:
            inf["expiresSegment"] -= 1
            if inf["expiresSegment"] <= 0:
                removed = True
                continue
        kept.append(inf)
    state.climate_influences = kept
    if removed:
        recompute_climate(state)


def set_region_influence(state: State) -> None:
    state.climate_influences = [inf for inf in state.climate_influences if inf.get("source") != "region"]
    region_id = state.region_run.region_id if state.region_run else "urban"
    meta = REGIONS[region_id]
    state.climate_influences.append({
        "id": f"region.{region_id}",
        "source": "region",
        "tempMod": meta["temp"],
        "weatherBias": dict(meta["bias"]),
        "waterMod": 1.0,
        "speedMult": 1.0,
        "pressureAdd": meta["pressure"],
    })


def build_segment(state: State, rng: random.Random) -> None:
    if state.region_run is None:
        start_region_run(state, rng, force_region="urban")
    expire_influences_before_segment(state)
    set_region_influence(state)
    segment = state.region_run.current

    segment.weather_id = weighted_pick(rng, weather_weights(state))
    state.weather_id = segment.weather_id
    segment.weather_draw_count += 1
    if segment.weather_draw_count != 1:
        state.anomalies["同一区段天气抽取次数异常"] += 1
    recompute_climate(state)
    segment.built = True

    two_high = state.pressure_history[0] == "high" and state.pressure_history[1] == "high"
    segment.pressure_class = pressure_class(state.climate["pressure"])
    segment.forced_low_content = two_high
    if two_high and segment.pressure_class != "low":
        state.anomalies["连续两高压未强制低压内容"] += 1
    state.pressure_history = [state.pressure_history[1], segment.pressure_class]

    segment.points = []
    count = rng.choice([3, 3, 4])
    weights = point_weights(state, segment)
    for i in range(count):
        ptype = weighted_pick(rng, weights)
        types = load_point_types()
        median = float(types[ptype]["median"])
        segment.points.append(Point(f"seg{state.day}-point{i}", ptype, median * POOL_MULTIPLIER))

    if state.day <= 2 and state.region_run.index == 0:
        required = list(STATIONS_CFG.get("tutorialForcePointTypes") or ["supermarket", "water_plant"])
        types = load_point_types()
        for index, ptype in enumerate(required):
            if ptype not in types:
                continue
            median = float(types[ptype]["median"])
            if index < len(segment.points):
                segment.points[index].ptype = ptype
                segment.points[index].pool = median * POOL_MULTIPLIER
            else:
                segment.points.append(
                    Point(f"seg{state.day}-guard{index}", ptype, median * POOL_MULTIPLIER)
                )

    sc_keys, sc_weights = station_count_choice_weights()
    station_count = int(rng.choices(sc_keys, weights=sc_weights, k=1)[0])
    if state.day <= 2 and state.region_run.index == 0:
        station_count = 1
    for i in range(station_count):
        if state.day <= 2 and state.region_run.index == 0:
            position = segment.length_km * 0.5
            size, none_pool, empty = "small", False, False
        else:
            position = segment.length_km * rng.uniform(0.25, 0.85)
            size_w = STATIONS_CFG.get("sizeWeights", {"small": 0.5, "medium": 0.35, "large": 0.15})
            size = weighted_pick(rng, {k: float(v) for k, v in size_w.items()})
            none_pool = rng.random() < float(STATIONS_CFG.get("nonePoolChance", 0.08))
            empty = rng.random() < float(STATIONS_CFG.get("emptyChance", 0.1))
        station = Station(position, size, none_pool, empty)
        if not none_pool and not empty:
            station.offer = make_offer(state, rng, size, forced_living=(state.day <= 2 and state.region_run.index == 0))
        segment.stations.append(station)

    event_id = draw_event(state, rng, segment)
    segment.event_id = event_id
    apply_event(state, rng, segment, event_id)
    state.stats["区段建成"] += 1


def make_offer(state: State, rng: random.Random, size: str, forced_living: bool = False) -> dict:
    if forced_living:
        return {"templateId": "living", "condition": "damaged", "cost": 1}
    pools = STATIONS_CFG.get("pools", {})
    pool = list(pools.get(size, pools.get("small", ["living", "cargo"])))
    template = rng.choice(pool)
    cost = 1 if template in {"living", "cargo", "shell"} else rng.choice([2, 3, 4, 5])
    cond_w = STATIONS_CFG.get("conditionWeights", {"intact": 0.15, "damaged": 0.6, "wreck": 0.25})
    conditions = list(cond_w.keys())
    c_probs = [float(cond_w[c]) for c in conditions]
    return {
        "templateId": template,
        "condition": rng.choices(conditions, weights=c_probs)[0],
        "cost": cost,
    }


def resolve_target_id(
    state: State, segment: Segment, target_type: str, rng: random.Random
) -> Optional[str]:
    if target_type in {"member", "party"}:
        living = [m for m in state.members if m.alive]
        return str(rng.choice(living).member_id) if living else None
    if target_type in {"segment", "point"}:
        return segment.points[0].point_id if segment.points else None
    return None


def exec_op_now(
    state: State,
    rng: random.Random,
    segment: Segment,
    op: str,
    args: dict,
    target_type: str = "global",
) -> None:
    if op == "grant_item":
        add_resource(state, args.get("res", "food"), float(args.get("amount", 0)))
    elif op == "mood_delta":
        delta = float(args.get("delta", 0))
        if target_type == "party":
            living = [m for m in state.members if m.alive]
            if living:
                pick = rng.choice(living)
                pick.mood = clamp(pick.mood + delta, 0, 100)
        else:
            member = next(
                (m for m in state.members if str(m.member_id) == str(args.get("memberId"))),
                None,
            )
            if member and member.alive:
                member.mood = clamp(member.mood + delta, 0, 100)
    elif op == "grant_influence":
        inf = dict(args)
        inf.setdefault("source", "event")
        state.climate_influences.append(inf)
        recompute_climate(state)
        state.stats["事件改气候即时重算"] += 1
    elif op == "recruit_roll":
        prob = float(args.get("p", 0.7))
        if onboard(state) < beds(state) and rng.random() < prob:
            recruit_member(state, rng)
            state.stats["区段收留"] += 1
    elif op == "flag_set":
        state.event_flags[str(args.get("key", "flag"))] = int(bool(args.get("value", True)))


def apply_event_option(
    state: State,
    rng: random.Random,
    segment: Segment,
    event_id: str,
    option: dict,
) -> None:
    immediate = option.get("immediate")
    if immediate:
        exec_op_now(
            state,
            rng,
            segment,
            str(immediate.get("op")),
            dict(immediate.get("args") or {}),
            str(immediate.get("targetType", "global")),
        )
    delay = int(option.get("delayDays", 0))
    if delay > 0 and option.get("op"):
        target_type = str(option.get("targetType", "global"))
        target_id = resolve_target_id(state, segment, target_type, rng)
        capture = str(option.get("capture", "live"))
        queue_delayed(
            state,
            event_id,
            delay,
            target_type,
            target_id,
            str(option["op"]),
            dict(option.get("args") or {}),
            capture,
        )


def staff_on_duty(state: State, job: str) -> bool:
    return any(m.alive and m.job == job for m in state.members)


def draw_event(state: State, rng: random.Random, segment: Segment) -> str:
    season = season_at(state.day)
    year = year_at(state.day)
    fuel_cap = 100.0 + sum(30 for c in state.carriages if c.template_id == "cargo")
    has_loot = any(p.pool > 0.01 for p in segment.points)
    rr = state.region_run
    assert rr is not None
    ctx = EventDrawContext.from_population(
        scenario_event_rate=state.scenario.event_rate,
        food=state.food,
        water=state.water,
        onboard=onboard(state),
        beds=beds(state),
        fuel=state.fuel,
        fuel_cap=fuel_cap,
        raid_weight_delta=segment.raid_weight_delta,
        forced_low_content=segment.forced_low_content,
        region_id=rr.region_id,
        has_pharmacist_on_duty=staff_on_duty(state, "pharmacist"),
        has_guard_on_duty=staff_on_duty(state, "guard"),
        has_unclaimed_loot=has_loot,
        recent_weight_event_ids=list(rr.recent_weight_event_ids),
        last_segment_primary_tag=rr.last_segment_primary_tag,
    )
    event_id = draw_event_id(rng, season=season, year=year, ctx=ctx, catalog=EVENT_CATALOG)
    card = EVENT_CATALOG[event_id]
    rr.recent_weight_event_ids.append(str(card.get("weightEventId", event_id)))
    rr.last_segment_primary_tag = primary_tag(card)
    return event_id


def queue_delayed(state: State, event_id: str, delay: int, target_type: str, target_id: Optional[str], op: str, args: dict, capture: str = "live") -> None:
    snapshot = None
    if capture == "snapshot":
        snapshot = {
            "food": state.food,
            "water": state.water,
            "fuel": state.fuel,
            "parts": state.parts,
            "medicine": state.medicine,
            "pile": dict(state.loot_piles.get(target_id or "", {})),
        }
    state.delayed_events.append(DelayedEvent(event_id, state.day + delay, target_type, target_id, op, dict(args), capture, snapshot))


def apply_event(state: State, rng: random.Random, segment: Segment, event_id: str) -> None:
    card = EVENT_CATALOG.get(event_id)
    if card is None:
        state.anomalies["未知事件ID"] += 1
        return
    state.stats[f"事件:{event_id}"] += 1
    option = rng.choice(card["options"])
    apply_event_option(state, rng, segment, event_id, option)


def process_delayed_events(state: State) -> None:
    due = [event for event in state.delayed_events if event.fire_day <= state.day]
    state.delayed_events = [event for event in state.delayed_events if event.fire_day > state.day]
    fired_keys = set()
    for event in due:
        key = (event.event_id, event.fire_day)
        if key in fired_keys:
            state.anomalies["延迟事件重复结算"] += 1
            continue
        fired_keys.add(key)
        state.stats["延迟事件结算"] += 1

        if event.op == "mood_delta":
            member = next((m for m in state.members if str(m.member_id) == str(event.target_id)), None)
            if member is None or not member.alive:
                state.stats["延迟事件目标失效跳过"] += 1
                continue
            member.mood = clamp(member.mood + float(event.args.get("delta", 0)), 0, 100)

        elif event.op == "grant_item":
            add_resource(state, event.args.get("res", "food"), float(event.args.get("amount", 0)))

        elif event.op == "loot_halve":
            pile = state.loot_piles.get(event.target_id or "", {})
            if not pile or sum(pile.values()) <= 0:
                state.stats["空临时堆不凭快照生成物资"] += 1
                continue
            for res in list(pile.keys()):
                pile[res] *= 1 - float(event.args.get("ratio", 0.5))
                if pile[res] < 0.01:
                    pile.pop(res, None)

        elif event.op == "clear_influence":
            target_id = event.args.get("id") or event.target_id
            before = len(state.climate_influences)
            state.climate_influences = [inf for inf in state.climate_influences if inf.get("id") != target_id]
            if len(state.climate_influences) != before:
                recompute_climate(state)
                state.stats["事件改气候即时重算"] += 1

        elif event.op == "grant_influence":
            state.climate_influences.append(dict(event.args))
            recompute_climate(state)
            state.stats["事件改气候即时重算"] += 1

        elif event.op == "spawn_threat":
            current = state.region_run.current if state.region_run else None
            if current is None or event.target_id != current.points[0].point_id if current and current.points else True:
                state.stats["延迟威胁目标失效跳过"] += 1
            else:
                state.pending_threat = event.args.get("threatTemplateId", "horde_small")

        elif event.op == "weight_mod":
            current = state.region_run.current if state.region_run else None
            if current is None:
                state.stats["延迟权重目标失效跳过"] += 1
            else:
                current.raid_weight_delta += float(event.args.get("delta", 0))
                state.stats["延迟权重只改本段缓存"] += 1

        elif event.op == "flag_set":
            state.event_flags[str(event.args.get("key", "flag"))] = int(
                bool(event.args.get("value", True))
            )


def recruit_member(state: State, rng: random.Random) -> None:
    member = Member(state.next_member_id, job="none", specialty=rng.choice([None, "scavenge", "repair", "medicine", None]))
    state.next_member_id += 1
    state.members.append(member)
    state.last_recruit_success_day = state.day
    assign_jobs(state)


def assign_jobs(state: State) -> None:
    need = []
    need += ["grower"] * sum(1 for car in state.carriages if car.function == "greenhouse")
    need += ["purifier"] * sum(1 for car in state.carriages if car.function == "water")
    need += ["engineer"] * sum(1 for car in state.carriages if car.template_id == "power")
    need += ["crafter"] * 2 * sum(1 for car in state.carriages if car.function == "workshop")
    need += ["pharmacist"] * sum(1 for car in state.carriages if car.function == "medical")
    need += ["radar_op"] * sum(1 for car in state.carriages if car.function == "radar")
    pool = [m for m in state.members if m.alive and m.job in {"none", "labor"}]
    labor_keep = sum(1 for m in state.members if m.alive and m.job == "labor")
    for job in need:
        if not pool:
            break
        candidate = max(pool, key=lambda m: (1 if m.specialty == job else 0, m.mood, -m.member_id))
        if candidate.job == "labor":
            if labor_keep <= 2:
                continue
            labor_keep -= 1
        candidate.job = job
        pool.remove(candidate)


def add_carriage(state: State, offer: dict) -> None:
    template = offer["templateId"]
    function_map = {"workshop": "workshop", "medical": "medical", "radar": "radar", "greenhouse": "greenhouse", "water": "water"}
    size = 3 if template in {"power", "workshop", "cargo"} else 2
    armor = 80 if template == "armor" else (20 if template == "power" else 10)
    speed_bonus = 20 if template == "power" else 0
    efficiency = 100 if template in {"greenhouse", "water"} else 0
    fuel_add = 2.0 if template == "armor" else (0.5 if template == "power" else (0.0 if template == "cargo" else 1.0))
    state.carriages.append(Carriage(template, size, function_map.get(template), armor, speed_bonus, efficiency, fuel_add))
    state.stats["车厢加挂"] += 1
    assign_jobs(state)


def traction(state: State) -> float:
    loco = min(3, sum(1 for c in state.carriages if c.template_id == "power"))
    return max(0.40, 1 - 0.08 * loco - 0.08 * state.power_tech)


def panel_speed_cap(state: State) -> float:
    speed_bonuses = sorted((c.speed_bonus for c in state.carriages if c.template_id == "power"), reverse=True)[:3]
    cap = 60 + sum(speed_bonuses) + 5 * state.power_tech
    cap *= state.climate.get("speedClimate", 1.0)
    if state.body_hp < 30:
        cap *= 0.70
    return max(0.0, cap)


def choose_speed(state: State, rng: random.Random) -> float:
    cap = panel_speed_cap(state)
    if state.scenario.strategy == "conservative":
        target = 25 if state.body_hp < 70 else 40
    else:
        target = cap if state.body_hp >= 70 else 40
    if state.body_hp < 30:
        target = min(target, 12)
    return min(cap, target)


def fuel_rate(state: State) -> float:
    add = sum(c.fuel_add for c in state.carriages)
    add += 0.5 * max(0, min(3, sum(1 for c in state.carriages if c.template_id == "power")) - 1)
    if state.precision is not None and rng_workshop_active(state):
        add += 0.5
    mult = min(state.today_speed_coef * state.climate["fuelClimate"] * state.region_run.fuel_mult * (1 + state.region_run.current.surcharge), 3.0) if state.region_run else 1.0
    return (3 + add) * traction(state) * mult


def rng_workshop_active(state: State) -> bool:
    return any(c.function == "workshop" for c in state.carriages)


def greenhouse_output(state: State) -> float:
    cars = [c for c in state.carriages if c.function == "greenhouse"]
    if not cars or not any(m.alive and m.job == "grower" for m in state.members):
        return 0.0
    penalty = 0.90 ** max(0, len(cars) - 2)
    total = 0.0
    for car in cars:
        total += 4.0 * (car.efficiency / 100.0) * penalty * state.climate["greenhouseClimate"] * (0.95 ** (year_at(state.day) - 1))
        if any(m.alive and m.job == "grower" and m.specialty == "farming" for m in state.members):
            total *= 1.10
    return total


def water_output(state: State) -> float:
    if state.fuel <= 0:
        return 0.0
    cars = [c for c in state.carriages if c.function == "water"]
    if not cars or not any(m.alive and m.job == "purifier" for m in state.members):
        return 0.0
    penalty = 0.90 ** max(0, len(cars) - 2)
    total = 0.0
    for car in cars:
        base = 15 if car.advanced else 10
        total += base * (car.efficiency / 100.0) * penalty * (0.95 ** (year_at(state.day) - 1))
    return total


def travel(state: State, rng: random.Random) -> None:
    if state.fuel <= 0 or state.region_run is None:
        return
    segment = state.region_run.current
    speed = choose_speed(state, rng)
    state.today_speed_coef = 0.3 if speed <= 12 else (0.8 if speed <= 40 else 1.0)
    if speed <= 12:
        state.today_forward_hours = 0.0
        return
    km = 2.5 * (speed / 30.0) * DRIVE_HOUR_CAP
    state.today_forward_hours = DRIVE_HOUR_CAP
    segment.progress_km += km

    if speed > 12 and rng.random() < 0.03 * (1.0 if state.scenario.strategy == "expansion" else 0.4):
        armor_cars = sum(1 for c in state.carriages if c.armor >= 70)
        train_damage_reduction = min(0.30 * armor_cars + 0.06 * state.armor_tech, 0.80)
        damage = 12 * (speed / 40.0) ** 2 * (1 - train_damage_reduction)
        state.body_hp -= damage
        state.stats["碰撞"] += 1
        if state.body_hp <= 0:
            state.body_hp = 0
            state.failed = "body"
            state.deaths["collision"] += 1

    for station in segment.stations:
        if not station.visited and segment.progress_km >= station.position_km:
            station.visited = True
            visit_station(state, rng, station)

    while segment.progress_km >= segment.length_km:
        overshoot = segment.progress_km - segment.length_km
        segment.surcharge = 0.0
        segment.raid_weight_delta = 0.0
        if state.region_run.index + 1 < state.region_run.segment_count:
            state.region_run.index += 1
            state.region_run.current.progress_km = overshoot
        else:
            for old_segment in state.region_run.segments:
                for station in old_segment.stations:
                    station.offer = None
            start_region_run(state, rng)
        segment = state.region_run.current
        if not segment.built:
            build_segment(state, rng)

    if state.scenario.reverse_probe and state.day >= state.reverse_probe_day and not state.reverse_probe_done:
        state.reverse_probe_done = True
        while state.region_run.index > 0:
            state.region_run.index -= 1
            state.region_run.current.progress_km = max(0.0, state.region_run.current.length_km - 5)
        state.region_run.current.progress_km = 0.0
        state.today_reverse_hours = 1.0
        if state.region_run.index == 0:
            state.stats["返程探针到达首段零点"] += 1


def visit_station(state: State, rng: random.Random, station: Station) -> None:
    state.stats["进站"] += 1
    if station.none_pool or station.empty:
        state.stats["无可获得车厢"] += 1
        return
    if station.offer is None:
        state.stats["无可获得车厢"] += 1
        return
    if station.offer["condition"] == "wreck":
        state.stats["无可获得车厢"] += 1
        return
    cost = station.offer["cost"]
    if state.parts < cost:
        state.stats["无可获得车厢"] += 1
        return
    state.parts -= cost
    add_carriage(state, station.offer)
    station.offer = None


def needs(state: State) -> Dict[str, float]:
    pop = onboard(state)
    season = season_at(state.day)
    food_climate = state.climate.get("foodClimate", 1.0)
    water_climate = state.climate.get("waterClimate", 1.0)
    food_target = pop * 0.9 * food_climate * 5.0
    water_target = pop * 0.8 * water_climate * 5.0
    fuel_target = 55.0
    if season == "autumn":
        food_target = max(food_target, cap_of(state, "food") * 0.90)
        water_target = max(water_target, cap_of(state, "water") * 0.70)
        fuel_target = max(fuel_target, cap_of(state, "fuel") * 0.55)
    elif season == "winter":
        food_target = max(food_target, pop * 4.0)
        fuel_target = max(fuel_target, 55.0)
    return {
        "food": max(0.0, food_target - state.food),
        "water": max(0.0, water_target - state.water),
        "fuel": max(0.0, fuel_target - state.fuel) * 2,
        "parts": max(0.0, 10 - state.parts),
        "med": max(0.0, 6 - state.medicine),
        "scrap": max(0.0, 8 - state.scrap),
        "seed": max(0.0, 4 - state.seed_stock),
    }


def search_and_haul(state: State, rng: random.Random) -> None:
    if state.region_run is None:
        return
    segment = state.region_run.current
    for point in segment.points:
        point.searches_today = 0
    searches = 2 if state.scenario.strategy == "expansion" else 1
    for _ in range(searches):
        available = [p for p in segment.points if p.pool > 0]
        if not available:
            break
        want = needs(state)
        types = load_point_types()
        best = max(want.get(sim_yield_for(p.ptype), 0.0) for p in available)
        if best <= 0:
            point = rng.choice(available)
        else:
            point = rng.choice(
                [p for p in available if want.get(sim_yield_for(p.ptype), 0.0) == best]
            )
        point.searches_today += 1
        if point.searches_today > MAX_PIECE_SEARCH_PER_POINT_PER_DAY:
            state.anomalies["单点当日搜索超过三次"] += 1
        res = sim_yield_for(point.ptype)
        median = float(types[point.ptype]["median"])
        amount = min(point.pool, median * rng.uniform(0.6, 1.4))
        point.pool -= amount
        pile = state.loot_piles.setdefault(point.point_id, {})
        pile[res] = pile.get(res, 0.0) + amount
        state.stats["搜索"] += 1
    haul_capacity = sum(1 for m in state.members if m.alive and m.job == "labor")
    for point_id, pile in list(state.loot_piles.items()):
        if haul_capacity <= 0:
            break
        for res, amount in list(pile.items()):
            if amount <= 0:
                pile.pop(res, None)
                continue
            accepted = add_resource(state, res, amount)
            pile[res] -= accepted
            if pile[res] <= 0.01:
                pile.pop(res, None)
            if accepted > 0:
                state.stats["搬运"] += 1
                haul_capacity -= 1
                break


def encounter(state: State, rng: random.Random) -> None:
    if state.failed or state.region_run is None:
        return
    pressure = state.climate.get("pressure", 1.0)
    chance = 0.04 + 0.02 * (pressure - 1.0) + (0.03 if season_at(state.day) == "winter" else 0.0)
    pile_total = sum(sum(pile.values()) for pile in state.loot_piles.values())
    chance += 0.02 * (1 if pile_total > 0 else 0)
    if getattr(state, "pending_threat", None):
        chance += 0.25
        state.pending_threat = None
    chance *= state.scenario.threat_rate
    if rng.random() >= chance:
        return

    threat_type = "raiders" if rng.random() < 0.5 or state.region_run.region_id in {"military", "urban"} else "horde"
    state.stats[f"遭遇:{threat_type}"] += 1
    guard_count = sum(1 for m in state.members if m.alive and m.job == "guard")
    formation_power = max(1, guard_count * 12 + sum(1 for c in state.carriages if c.armor >= 70) * 12 + 4 * state.armor_tech)
    threat_power = rng.uniform(8, 14) * (1 + 0.15 * (year_at(state.day) - 1))
    d = formation_power / (formation_power + threat_power)

    if state.scenario.strategy == "conservative":
        path = "negotiation" if guard_count else "detour"
    else:
        path = "assault" if guard_count else "horn"
    path_chance = clamp(0.25 + 0.50 * d - (0.15 if threat_type == "raiders" else 0.0), 0.10, 0.85)

    if path == "assault":
        progress_player = 0.0
        progress_enemy = 0.0
        for _ in range(4):
            progress_player += formation_power * rng.uniform(0.20, 0.30) / threat_power
            progress_enemy += threat_power * rng.uniform(0.20, 0.30) * (1 - min(0.15 * max(1, guard_count), 0.60)) / formation_power
        success = progress_player > progress_enemy
    else:
        success = rng.random() < path_chance

    if success:
        state.stats["非战斗或战斗成功"] += 1
        return

    state.stats["遭遇失败"] += 1
    alive = [m for m in state.members if m.alive]
    if alive:
        victim = rng.choice(alive)
        victim.hp -= 15 if path != "assault" else 25
        if victim.hp <= 0:
            victim.alive = False
            victim.death_cause = "combat"
            state.deaths["combat"] += 1
    if path == "detour":
        for pile in state.loot_piles.values():
            for res in list(pile.keys()):
                pile[res] *= 0.5
                if pile[res] < 0.01:
                    pile.pop(res, None)
    if path == "assault":
        for pile in state.loot_piles.values():
            pile.clear()


def apply_disease(state: State, rng: random.Random, cross_threshold: bool) -> None:
    if cross_threshold:
        for member in state.members:
            if member.alive and member.disease_stage == "none" and rng.random() < 0.25:
                member.disease_stage = "latent"
                member.disease_days = 0
                state.stats["缺粮水触发潜伏"] += 1
    for member in state.members:
        if not member.alive:
            continue
        if member.disease_stage == "none":
            continue
        member.disease_days += 1
        if member.disease_stage == "latent" and member.disease_days >= 1:
            member.disease_stage = "ill"
            member.disease_days = 0
            state.stats["疾病发病"] += 1
        elif member.disease_stage == "ill":
            member.hp -= 4
            if rng.random() < 0.10:
                member.alive = False
                member.death_cause = "disease"
                state.deaths["disease"] += 1
                continue
            if member.disease_days >= 7:
                member.disease_stage = "none"
                member.disease_days = 0
                state.stats["疾病康复"] += 1


def morale_settle(state: State) -> None:
    alive_members = [m for m in state.members if m.alive]
    bedded_ids = {m.member_id for m in alive_members[:beds(state)]}
    for member in alive_members:
        delta = -1.5
        if member.job != "none":
            delta += 0.0
        else:
            delta -= 2.0
        if member.member_id in bedded_ids:
            delta += 1.0
        else:
            delta -= 3.0
        if state.food > 0 and state.water > 0:
            delta += 0.8
        member.mood = clamp(member.mood + delta + 0.2 * state.living_tech, 0, 100)
    penalty_today = state.food_went_zero or state.water_went_zero
    if penalty_today:
        if state.food_went_zero:
            state.morale_offset = max(-60.0, state.morale_offset - 13)
        if state.water_went_zero:
            state.morale_offset = max(-60.0, state.morale_offset - 16)
    elif state.morale_offset < 0:
        state.morale_offset = min(0.0, state.morale_offset + 2)
    elif state.morale_offset > 0:
        state.morale_offset = max(0.0, state.morale_offset - 1)
    living = [m for m in state.members if m.alive]
    if not living:
        return
    collective = clamp(statistics.mean(m.mood for m in living) + state.morale_offset, 0, 100)
    if collective <= 0:
        state.morale_zero_streak += 1
    else:
        state.morale_zero_streak = 0
    if state.morale_zero_streak >= 3:
        state.failed = "morale"


def day_settle(state: State, rng: random.Random) -> None:
    process_delayed_events(state)
    recompute_climate(state)

    speed_coef = (1.0 * state.today_forward_hours + 0.8 * state.today_reverse_hours + 0.3 * (24 - state.today_forward_hours - state.today_reverse_hours)) / 24
    state.today_speed_coef = clamp(speed_coef, 0.3, 1.3)
    fuel_burn = fuel_rate(state)
    state.fuel = min(cap_of(state, "fuel"), max(0.0, state.fuel - fuel_burn))

    state.today_forward_hours = 0.0
    state.today_reverse_hours = 0.0

    food_deduct = onboard(state) * 0.9 * state.climate["foodClimate"]
    water_deduct = onboard(state) * 0.8 * state.climate["waterClimate"]
    state.food = max(0.0, state.food - food_deduct)
    state.water = max(0.0, state.water - water_deduct)
    state.food_went_zero = state.food == 0
    state.water_went_zero = state.water == 0
    state.food_zero_streak = state.food_zero_streak + 1 if state.food_went_zero else 0
    state.water_zero_streak = state.water_zero_streak + 1 if state.water_went_zero else 0
    if state.food_went_zero and state.first_food_zero_day is None:
        state.first_food_zero_day = state.day
    if state.water_went_zero and state.first_water_zero_day is None:
        state.first_water_zero_day = state.day

    green_cars = sum(1 for c in state.carriages if c.function == "greenhouse")
    heated = False
    if state.scenario.heating and season_at(state.day) == "winter" and green_cars:
        heat_cost = 0.30 * green_cars
        if state.fuel >= heat_cost:
            state.fuel -= heat_cost
            state.climate["greenhouseClimate"] = 0.95
            heated = True
        else:
            state.climate["greenhouseClimate"] = 0.50
    elif season_at(state.day) == "winter" and green_cars:
        state.climate["greenhouseClimate"] = 0.50

    state.fuel = min(cap_of(state, "fuel"), max(0.0, state.fuel))
    if state.fuel == 0:
        state.fuel_zero_streak += 1
        if state.first_fuel_zero_day is None:
            state.first_fuel_zero_day = state.day
    else:
        state.fuel_zero_streak = 0

    state.food = min(cap_of(state, "food"), state.food + greenhouse_output(state))
    if state.fuel > 0:
        state.water = min(cap_of(state, "water"), state.water + water_output(state))

    if rng_workshop_active(state):
        if state.precision is None:
            state.precision = 40.0
        state.parts = min(cap_of(state, "parts"), state.parts + state.precision / 300.0)
        state.precision = min(100.0, state.precision + 1)

    cross_threshold = (state.food_zero_streak == 3) or (state.water_zero_streak == 3)
    if state.food_zero_streak >= 3 or state.water_zero_streak >= 3:
        for member in state.members:
            if not member.alive:
                continue
            member.hp -= 20
            if member.hp <= 0:
                member.alive = False
                member.death_cause = "starvation" if state.food_zero_streak >= state.water_zero_streak else "dehydration"
                state.deaths[member.death_cause] += 1
    apply_disease(state, rng, cross_threshold)

    if state.fuel_zero_streak >= 3 and not state.failed:
        state.failed = "fuel"
    if onboard(state) == 0 and not state.failed:
        state.failed = "wipe"

    morale_settle(state)

    if state.last_recruit_success_day != state.day and state.scenario.strategy == "conservative":
        if onboard(state) < beds(state) and rng.random() < 0.05:
            recruit_member(state, rng)
            state.stats["日结补抽收留"] += 1

    if state.body_hp < 30:
        if state.breakdown_counter >= 3:
            state.stats["抛锚"] += 1
            state.breakdown_counter = 0
        else:
            state.breakdown_counter += 1
    else:
        state.breakdown_counter = 0

    state.peak_pop = max(state.peak_pop, onboard(state))
    if state.failed is None:
        state.day += 1


def run_one(seed: int, scenario: Scenario, max_day: int) -> State:
    rng = random.Random(seed)
    state = State(seed=seed, scenario=scenario)
    state.members = starter_members()
    start_region_run(state, rng, force_region="urban")
    build_segment(state, rng)
    while state.day <= max_day and state.failed is None:
        travel(state, rng)
        if state.failed:
            break
        search_and_haul(state, rng)
        encounter(state, rng)
        day_settle(state, rng)
    return state


def summarize(states: List[State]) -> dict:
    n = max(1, len(states))
    survival120 = sum(1 for s in states if (s.failed is None or s.day > 120)) / n
    survival240 = sum(1 for s in states if s.failed is None and s.day > 240) / n
    fail_counts = Counter(s.failed or "alive" for s in states)
    death_counts = Counter()
    anomaly_counts = Counter()
    event_counts = Counter()
    first_food = [s.first_food_zero_day for s in states if s.first_food_zero_day is not None]
    first_water = [s.first_water_zero_day for s in states if s.first_water_zero_day is not None]
    first_fuel = [s.first_fuel_zero_day for s in states if s.first_fuel_zero_day is not None]
    fail_days = [s.day for s in states if s.failed is not None]
    peaks = [s.peak_pop for s in states]
    for state in states:
        death_counts.update(state.deaths)
        anomaly_counts.update(state.anomalies)
        event_counts.update({k: v for k, v in state.stats.items() if k.startswith("事件:")})
    total_deaths = sum(death_counts.values()) or 1
    return {
        "n": len(states),
        "survival120": survival120,
        "survival240": survival240,
        "fails": dict(fail_counts),
        "deaths": dict(death_counts),
        "death_max_share": max(death_counts.values(), default=0) / total_deaths,
        "first_food_zero_median": statistics.median(first_food) if first_food else None,
        "first_water_zero_median": statistics.median(first_water) if first_water else None,
        "first_fuel_zero_median": statistics.median(first_fuel) if first_fuel else None,
        "fail_day_median": statistics.median(fail_days) if fail_days else None,
        "peak_pop_median": statistics.median(peaks) if peaks else 0,
        "pop20_rate": sum(1 for s in states if s.peak_pop >= 20) / n,
        "anomalies": dict(anomaly_counts),
        "events": dict(event_counts),
    }


def findings(scenarios: List[Tuple[Scenario, dict]]) -> List[dict]:
    result = []
    for scenario, summary in scenarios:
        def add(level: str, issue: str, evidence: str, suggestion: str) -> None:
            result.append({"level": level, "scenario": scenario.name, "issue": issue, "evidence": evidence, "suggestion": suggestion})

        if summary["survival120"] < 0.50:
            add("高", "存活到 120 日低于验收线", f"{scenario.name}：{summary['survival120']:.0%}", "先查燃料失败与饥渴失败，不改冬季加油站 ×1.40")
        fail = summary["fails"]
        if fail.get("morale", 0) / max(1, summary["n"]) >= 0.20:
            add("高", "士气失败集中出现", f"{scenario.name}：{fail.get('morale', 0)}/{summary['n']}", "复核床位扩张、过道惩罚与缺粮时士气偏移是否互相叠加")
        if fail.get("fuel", 0) / max(1, summary["n"]) >= 0.35:
            add("高", "燃料失败成为主失败", f"{scenario.name}：{fail.get('fuel', 0)}/{summary['n']}", "再审秋储燃油目标、雪原出现权重与代表编组手算")
        if summary["death_max_share"] > 0.70:
            add("中", "单一死因占比超过 70%", f"{scenario.name}：{summary['death_max_share']:.0%}", "增加非战斗死因或降低饥渴连锁")
        if summary["first_food_zero_median"] is not None and summary["first_food_zero_median"] < 5:
            add("高", "食物缺口早于第 5 日", f"中位第 {summary['first_food_zero_median']:.0f} 日", "复核开局食物 20、教程站可达日与搜索效率")
        if summary["first_water_zero_median"] is not None and summary["first_water_zero_median"] < 8:
            add("高", "饮水缺口早于第一段可离开日", f"中位第 {summary['first_water_zero_median']:.0f} 日", "复核首段点位是否可能无水厂、开局水 24 与教程段长")
        if summary["fail_day_median"] is not None and summary["fail_day_median"] < 30:
            add("高", "失败集中在首月", f"失败中位第 {summary['fail_day_median']:.0f} 日", "检查教程段补给保底、床位与士气链，避免开局即锁死")
        if summary["pop20_rate"] < 0.50:
            add("中", "第 240 日前达到 20 人不足半数", f"{scenario.name}：{summary['pop20_rate']:.0%}", "复核收留期望、床位扩张与秋季抑收留是否过强")
        for anomaly, count in summary["anomalies"].items():
            level = "高" if "重复" in anomaly or "超过上限" in anomaly or "为负" in anomaly else "中"
            add(level, anomaly, f"{scenario.name}：{count} 次", "回到对应模块补权威口径")
    return result


def write_report(path: Path, scenarios: List[Tuple[Scenario, dict]], findings_list: List[dict], runs: int, days: int) -> None:
    lines = [
        "# 综合时间事件模拟报告",
        "",
        f"> 基线：设计 v1.3.31 / 规格 v1.51 · 每场景 {runs} 局 · 每局至第 {days} 日 · 种子固定",
        "> 口径：本脚本只找设计闭环与数值风险，不等同正式阶段零过关证书。",
        "",
        "## 场景结果",
        "",
        "| 场景 | ≥120 日 | ≥240 日 | 失败中位日 | 失败构成 | 食物缺口中位日 | 饮水缺口中位日 | 人口峰值中位 | 达到 20 人 |",
        "|---|---:|---:|---:|---|---:|---:|---:|---:|",
    ]
    for scenario, row in scenarios:
        fail = row["fails"]
        lines.append(
            f"| {scenario.name} | {row['survival120']:.0%} | {row['survival240']:.0%} | "
            f"{row['fail_day_median'] if row['fail_day_median'] is not None else '-'} | {fail} | "
            f"{row['first_food_zero_median'] if row['first_food_zero_median'] is not None else '-'} | "
            f"{row['first_water_zero_median'] if row['first_water_zero_median'] is not None else '-'} | "
            f"{row['peak_pop_median']:.0f} | {row['pop20_rate']:.0%} |"
        )
    lines += ["", "## 发现", ""]
    if not findings_list:
        lines.append("- 未触发自动告警。")
    else:
        lines.append("| 等级 | 场景 | 问题 | 证据 | 建议 |")
        lines.append("|---|---|---|---|---|")
        for item in findings_list:
            lines.append(f"| {item['level']} | {item['scenario']} | {item['issue']} | {item['evidence']} | {item['suggestion']} |")
    lines += ["", "## 说明", "", "- 天气每段只抽一次；事件延迟按 `fireOnDay` 结算；车厢要约只在本区域跨度内保留。", "- 本脚本记录异常而不改权威文档；具体修复仍需回写对应模块。", ""]
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="综合时间事件模拟：找设计闭环与数值风险")
    parser.add_argument("--runs", type=int, default=80, help="每场景局数")
    parser.add_argument("--days", type=int, default=240, help="每局最大游戏日")
    parser.add_argument("--out", default="TIME_EVENT_SWEEP.md", help="报告输出路径；相对 sim/ 目录解析")
    args = parser.parse_args()

    base = Path(__file__).resolve().parent
    scenarios = [
        Scenario("基准·保守", "conservative"),
        Scenario("基准·扩张", "expansion"),
        Scenario("高强度事件·保守", "conservative", event_rate=1.8, threat_rate=1.5),
        Scenario("返程探针·保守", "conservative", reverse_probe=True),
        Scenario("教程补给保底对照·保守", "conservative", tutorial_supply_guard=True),
    ]
    results: List[Tuple[Scenario, dict]] = []
    for index, scenario in enumerate(scenarios):
        states = [run_one(seed=2_000_000 + index * 100_000 + i * 7919, scenario=scenario, max_day=args.days) for i in range(args.runs)]
        row = summarize(states)
        results.append((scenario, row))
        print(f"== {scenario.name} ==")
        print(f"  ≥120日 {row['survival120']:.0%} | ≥240日 {row['survival240']:.0%} | 燃料失败 {row['fails'].get('fuel',0)/max(1,row['n']):.0%}")
        print(f"  失败中位日 {row['fail_day_median']} | 食物缺口中位日 {row['first_food_zero_median']} | 饮水缺口中位日 {row['first_water_zero_median']}")
        print(f"  人口峰值中位 {row['peak_pop_median']:.0f} | 达到20人 {row['pop20_rate']:.0%} | 最大死因 {row['death_max_share']:.0%}")
        print(f"  失败构成 {row['fails']}")
        print(f"  异常 {row['anomalies']}\n")

    found = findings(results)
    report_path = base / args.out
    write_report(report_path, results, found, args.runs, args.days)
    print(f"自动告警 {len(found)} 项；报告：{report_path}")


if __name__ == "__main__":
    main()
