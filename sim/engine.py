# -*- coding: utf-8 -*-
"""Minimal Doomsday Train day-loop for stage-zero A smoke tests (spec v1.52 / design v1.3.33).

Time model: season/year → weather (per segment) → cold/heat → climate mults;
yearProd on F05/F32; seasonal region pick + autumn stockpile AI.
Loads data/balance.json when present (configVersion from file).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import json
import random

try:
    from sim.point_types import (
        compute_type_weights,
        load_point_types,
        load_regions,
        load_weather_engine,
        load_weather_raw,
        load_season_pressure,
        load_stations_config,
        normalized_weights,
        pool_multiplier,
        region_ids,
        station_count_choice_weights,
        year_threat_multiplier,
    )
except ImportError:
    from point_types import (
        compute_type_weights,
        load_point_types,
        load_regions,
        load_weather_engine,
        load_weather_raw,
        load_season_pressure,
        load_stations_config,
        normalized_weights,
        pool_multiplier,
        region_ids,
        station_count_choice_weights,
        year_threat_multiplier,
    )


SEASON_LEN = 30
YEAR_LEN = 120

HEATING_FUEL_PER_CAR = 0.30
HEATING_MULT = 0.95
NO_HEAT_WINTER_MULT = 0.50
GREENHOUSE_DAY = 4.0

SEGMENT_DAYS = 8
DRIVE_HOURS_CAP = 1.0
SEARCH_HOURS_BUDGET = 4.0  # 04 §5：日均可派搜索游戏小时（停靠为主）
POOL_MULT = pool_multiplier()
L1_UNIT = 8.0              # 05 §6.1
HUNGER_DISEASE_P = 0.35    # 04 §7：streak 首次≥3 进入潜伏检定
HALLWAY_DISEASE_P = 0.05

# 02 §7.1 / data/point_types.json（权威 type 键；sim 收窄见 simYield）
load_point_types()
SEED_CONSUME_PER_RACK = 0.05  # 02 §3
TECH_PREC = [20, 40, 60]      # Lv1–3；Lv4/5 需图纸，本冒烟不上
TECH_PARTS = [2, 4, 6]
TECH_MED = [0, 1, 0]          # Lv2 要药
TECH_CATALYST = [0, 0, 1]     # Lv3 要催化
TECH_FUEL = [1.0, 0.0, 0.0]   # Lv1 扣 1% 燃料
BALANCE_CONFIG_VERSION: Optional[int] = None
START_FOOD: float = 20.0
START_WATER: float = 24.0
START_FUEL: float = 88.0
START_PARTS: float = 6.0
START_MED: float = 4.0
START_SEED: float = 1.0
START_PRECISION: float = 40.0
ABANDON_PARTS_COST: float = 1.0
ABANDON_SCRAP_RATIO: float = 0.35
ABANDON_FUEL_COST_PCT: float = 0.01
ABANDON_AI_FUEL_MAX: float = 0.35
ABANDON_AI_MIN_CARS: int = 12
MAX_SEARCH_PER_POINT: int = 3
FUEL_TANK_BASE: float = 60.0
FUEL_TANK_PER_CARGO: float = 10.0
SEASON_BASE_TEMP: Dict[str, float] = {
    "spring": 0.0,
    "summer": 1.0,
    "autumn": 0.0,
    "winter": -1.0,
}
CLIMATE_COLD_FOOD_FUEL: Dict[str, Dict[str, float]] = {}
CLIMATE_HEAT_WATER: Dict[str, float] = {}

SEARCH_YIELD_MULT_BASE = 0.90
SEARCH_YIELD_MULT_PER_TEAM = 0.08
SEARCH_YIELD_MULT_CAP = 1.25
SCAVENGE_SKILL_DIVISOR = 0.85
SEARCH_YIELD_JITTER_MIN = 0.55
SEARCH_YIELD_JITTER_SPAN = 0.5

FUEL_BASE = 3.0
FUEL_EXTRA_LOCO = 0.5
FUEL_TRACTION_PER_LOCO = 0.08
FUEL_TRACTION_PER_TECH = 0.08
FUEL_TRACTION_FLOOR = 0.4
FUEL_CRAFT_PER_DAY = 0.5
REPAIR_PARTS: Dict[str, int] = {"living": 3, "cargo": 3, "default": 5, "tutorialLiving": 1}
CRYSTAL_HIDDEN_CHANCE: float = 0.09


def _apply_balance_json() -> None:
    """Overlay freeze constants from data/balance.json if available."""
    global SEASON_LEN, YEAR_LEN, HEATING_FUEL_PER_CAR, HEATING_MULT
    global NO_HEAT_WINTER_MULT, GREENHOUSE_DAY, DRIVE_HOURS_CAP
    global SEED_CONSUME_PER_RACK, L1_UNIT, TECH_PREC, TECH_PARTS, TECH_MED
    global TECH_CATALYST, TECH_FUEL, BALANCE_CONFIG_VERSION
    global START_FOOD, START_WATER, START_FUEL, START_PARTS, START_MED, START_SEED, START_PRECISION
    global ABANDON_PARTS_COST, ABANDON_SCRAP_RATIO, ABANDON_FUEL_COST_PCT
    global ABANDON_AI_FUEL_MAX, ABANDON_AI_MIN_CARS
    global SEASON_BASE_TEMP, MAX_SEARCH_PER_POINT, FUEL_TANK_BASE, FUEL_TANK_PER_CARGO
    global CLIMATE_COLD_FOOD_FUEL, CLIMATE_HEAT_WATER
    global SEARCH_YIELD_MULT_BASE, SEARCH_YIELD_MULT_PER_TEAM, SEARCH_YIELD_MULT_CAP
    global SCAVENGE_SKILL_DIVISOR, SEARCH_YIELD_JITTER_MIN, SEARCH_YIELD_JITTER_SPAN
    global FUEL_BASE, FUEL_EXTRA_LOCO, FUEL_TRACTION_PER_LOCO, FUEL_TRACTION_PER_TECH
    global FUEL_TRACTION_FLOOR, FUEL_CRAFT_PER_DAY, REPAIR_PARTS, CRYSTAL_HIDDEN_CHANCE
    root = Path(__file__).resolve().parents[1]
    path = root / "data" / "balance.json"
    if not path.is_file():
        return
    data = json.loads(path.read_text(encoding="utf-8"))
    BALANCE_CONFIG_VERSION = int(data.get("configVersion", 0)) or None
    t = data.get("time", {})
    SEASON_LEN = int(t.get("daysPerSeason", SEASON_LEN))
    YEAR_LEN = int(SEASON_LEN * t.get("seasonsPerYear", 4))
    DRIVE_HOURS_CAP = float(t.get("driveHoursPerDayCap", DRIVE_HOURS_CAP))
    gh = data.get("greenhouse", {})
    HEATING_FUEL_PER_CAR = float(gh.get("heatingFuelPerCarDay", HEATING_FUEL_PER_CAR))
    HEATING_MULT = float(gh.get("heatingMult", HEATING_MULT))
    NO_HEAT_WINTER_MULT = float(gh.get("noHeatWinterMult", NO_HEAT_WINTER_MULT))
    GREENHOUSE_DAY = float(gh.get("fullOutputPerDay", GREENHOUSE_DAY))
    SEED_CONSUME_PER_RACK = float(gh.get("seedConsumePerRackDay", SEED_CONSUME_PER_RACK))
    combat_path = root / "data" / "combat.json"
    combat = data.get("combat", {})
    if combat_path.is_file():
        combat_data = json.loads(combat_path.read_text(encoding="utf-8"))
        L1_UNIT = float(combat_data.get("l1Unit", combat.get("l1Unit", L1_UNIT)))
    else:
        L1_UNIT = float(combat.get("l1Unit", L1_UNIT))
    tech = data.get("tech", {})
    if "precisionGate" in tech:
        TECH_PREC = list(tech["precisionGate"][:3])
    if "parts" in tech:
        TECH_PARTS = list(tech["parts"][:3])
    if "med" in tech:
        TECH_MED = list(tech["med"][:3])
    if "catalyst" in tech:
        TECH_CATALYST = list(tech["catalyst"][:3])
    if "fuelCostLv1" in tech:
        TECH_FUEL = [float(tech["fuelCostLv1"]), 0.0, 0.0]
    start = data.get("start", {})
    if start:
        START_FOOD = float(start.get("food", START_FOOD))
        START_WATER = float(start.get("water", START_WATER))
        START_FUEL = float(start.get("fuel", START_FUEL))
        START_PARTS = float(start.get("parts", START_PARTS))
        START_MED = float(start.get("med", START_MED))
        START_SEED = float(start.get("seed", START_SEED))
        START_PRECISION = float(start.get("precision", START_PRECISION))
    tr = data.get("train", {})
    if tr:
        ABANDON_PARTS_COST = float(tr.get("abandonPartsCost", ABANDON_PARTS_COST))
        ABANDON_SCRAP_RATIO = float(tr.get("abandonScrapRatio", ABANDON_SCRAP_RATIO))
        ABANDON_FUEL_COST_PCT = float(tr.get("abandonFuelCostPct", ABANDON_FUEL_COST_PCT))
        ABANDON_AI_FUEL_MAX = float(tr.get("abandonAiFuelFillMax", ABANDON_AI_FUEL_MAX))
        ABANDON_AI_MIN_CARS = int(tr.get("abandonAiMinCars", ABANDON_AI_MIN_CARS))
    sbt = t.get("seasonBaseTemp")
    if isinstance(sbt, dict):
        SEASON_BASE_TEMP = {str(k): float(v) for k, v in sbt.items()}
    search = data.get("search", {})
    MAX_SEARCH_PER_POINT = int(search.get("maxAssignPerPointPerDay", MAX_SEARCH_PER_POINT))
    SEARCH_YIELD_MULT_BASE = float(search.get("yieldMultBase", SEARCH_YIELD_MULT_BASE))
    SEARCH_YIELD_MULT_PER_TEAM = float(search.get("yieldMultPerTeamEff", SEARCH_YIELD_MULT_PER_TEAM))
    SEARCH_YIELD_MULT_CAP = float(search.get("yieldMultCap", SEARCH_YIELD_MULT_CAP))
    SCAVENGE_SKILL_DIVISOR = float(search.get("scavengeSkillDivisor", SCAVENGE_SKILL_DIVISOR))
    SEARCH_YIELD_JITTER_MIN = float(search.get("yieldJitterMin", SEARCH_YIELD_JITTER_MIN))
    SEARCH_YIELD_JITTER_SPAN = float(search.get("yieldJitterSpan", SEARCH_YIELD_JITTER_SPAN))
    ft = data.get("fuelTank", {})
    FUEL_TANK_BASE = float(ft.get("baseAmount", FUEL_TANK_BASE))
    FUEL_TANK_PER_CARGO = float(ft.get("perCargoSize", FUEL_TANK_PER_CARGO))
    cold_tbl = data.get("climateColdFoodFuel")
    if isinstance(cold_tbl, dict):
        CLIMATE_COLD_FOOD_FUEL = {
            str(k): {str(fk): float(fv) for fk, fv in (v or {}).items() if isinstance(v, dict)}
            for k, v in cold_tbl.items()
        }
    heat_w = data.get("climateHeatWater")
    if isinstance(heat_w, dict):
        CLIMATE_HEAT_WATER = {str(k): float(v) for k, v in heat_w.items()}
    fuel_cfg = data.get("fuel", {})
    if fuel_cfg:
        FUEL_BASE = float(fuel_cfg.get("base", FUEL_BASE))
        FUEL_EXTRA_LOCO = float(fuel_cfg.get("extraLocoAdd", FUEL_EXTRA_LOCO))
        FUEL_TRACTION_PER_LOCO = float(fuel_cfg.get("tractionPerLoco", FUEL_TRACTION_PER_LOCO))
        FUEL_TRACTION_PER_TECH = float(fuel_cfg.get("tractionPerPowerTech", FUEL_TRACTION_PER_TECH))
        FUEL_TRACTION_FLOOR = float(fuel_cfg.get("tractionFloor", FUEL_TRACTION_FLOOR))
        FUEL_CRAFT_PER_DAY = float(fuel_cfg.get("craftFuelPerDay", FUEL_CRAFT_PER_DAY))
    carriages_path = root / "data" / "carriages.json"
    if carriages_path.is_file():
        cdata = json.loads(carriages_path.read_text(encoding="utf-8"))
        rp = cdata.get("repairParts", {})
        if isinstance(rp, dict):
            REPAIR_PARTS = {str(k): int(v) for k, v in rp.items()}
    CRYSTAL_HIDDEN_CHANCE = float(data.get("crystalHiddenChance", CRYSTAL_HIDDEN_CHANCE))


def _cold_climate(cold: float, field: str, defaults: Tuple[float, float, float]) -> float:
    if cold >= 2:
        tier = "cold2"
        d = defaults[0]
    elif cold >= 1:
        tier = "cold1"
        d = defaults[1]
    elif cold >= 0.5:
        tier = "cold0_5"
        d = defaults[2]
    else:
        return 1.0
    row = CLIMATE_COLD_FOOD_FUEL.get(tier, {})
    return float(row.get(field, d))


_apply_balance_json()

# 06 §1.2 + data/regions.json（点位权重键对齐 point_types）
REGIONS = load_regions()
REGION_IDS = region_ids()

SEASON_PRESSURE = load_season_pressure()
STATIONS_CFG = load_stations_config()
GUARANTEE_AFTER = int(STATIONS_CFG.get("guaranteeAfter", 4))
POOL_OFFER_CHANCE = float(STATIONS_CFG.get("poolOfferChance", 0.9))
STATION_COUNT_KEYS, STATION_COUNT_WEIGHTS = station_count_choice_weights()

# 01 §7.1 · data/weather.json
WEATHER = load_weather_engine()


def season_of(day: int) -> str:
    d = (day - 1) % YEAR_LEN
    idx = min(3, d // max(1, SEASON_LEN))
    return ("spring", "summer", "autumn", "winter")[idx]


def year_of(day: int) -> int:
    return (day - 1) // YEAR_LEN + 1


def day_in_season(day: int) -> int:
    return (day - 1) % SEASON_LEN  # 0-based


def year_prod(day: int) -> float:
    """01 §9：只乘 F05/F32。"""
    return 0.95 ** (year_of(day) - 1)


def weather_col(day: int) -> int:
    """春=0 夏=1 秋=2 冬年1–2=3 冬年≥3=4。"""
    s = season_of(day)
    if s == "spring":
        return 0
    if s == "summer":
        return 1
    if s == "autumn":
        return 2
    return 4 if year_of(day) >= 3 else 3


@dataclass
class Car:
    template_id: str
    size: int
    function: Optional[str]
    armor: int
    speed_bonus: int
    efficiency: int
    fuel_per_day: float
    advanced: bool = False

    @property
    def is_locomotive(self) -> bool:
        return self.template_id == "power"


def starter_train() -> List[Car]:
    return [
        Car("power", 3, None, 20, 20, 0, 0.0),
        Car("living", 2, None, 10, 0, 0, 1.0),
        Car("cargo", 3, None, 10, 0, 0, 1.0),
    ]


@dataclass
class Member:
    hp: int = 100
    alive: bool = True
    job: str = "labor"  # 04 §4.2
    disease: str = "none"  # none | latent | sick
    disease_days: int = 0
    has_scavenge: bool = False
    combat_roster: bool = False


def starter_members() -> List[Member]:
    """04 §4.3.1：四人开局 job=none（专长/roster 与 archetypes 同构）。"""
    return [
        Member(job="none"),
        Member(job="none", combat_roster=True),
        Member(job="none", has_scavenge=True),
        Member(job="none"),
    ]


@dataclass
class Node:
    ptype: str
    res: str
    median: float
    pool: float


@dataclass
class Climate:
    weather_id: str = "clear"
    effective_temp: float = 0.0
    cold: float = 0.0
    heat: float = 0.0
    food: float = 1.0
    water: float = 1.0
    fuel: float = 1.0
    greenhouse: float = 1.0  # cold≥1 时由供暖改写
    speed: float = 1.0
    node_fuel_mod: float = 1.0


@dataclass
class RunState:
    day: int = 1
    food: float = field(default_factory=lambda: START_FOOD)
    water: float = field(default_factory=lambda: START_WATER)
    fuel: float = field(default_factory=lambda: START_FUEL)
    parts: float = field(default_factory=lambda: START_PARTS)
    med: float = field(default_factory=lambda: START_MED)
    crystal: float = 0
    potion_catalyst: float = 0
    seed: float = field(default_factory=lambda: START_SEED)  # 02 §10 开局
    body: float = 100
    cars: List[Car] = field(default_factory=starter_train)
    members: List[Member] = field(default_factory=starter_members)
    power_tech: int = 0
    armor_tech: int = 0
    radar_tech: int = 0
    living_tech: int = 0
    precision: Optional[float] = None
    recruited_today: bool = False
    starve_food_days: int = 0
    starve_water_days: int = 0
    food_disease_armed: bool = True   # streak 跨入≥3 可检；归零后重新武装
    water_disease_armed: bool = True
    fuel_zero_days: int = 0
    no_carriage_stations: int = 0
    no_carriage_miss_raw: int = 0
    stations_visited: int = 0
    distance_km: float = 0.0
    region_id: str = "urban"
    region_fuel_mult: float = 1.0
    region_temp: float = 0.0
    region_bias: Dict[str, float] = field(default_factory=dict)
    point_mods: Dict[str, float] = field(default_factory=dict)
    segments_in_run: int = 0
    segment_count: int = 3
    climate: Climate = field(default_factory=Climate)
    heating_enabled: bool = False
    deaths: Dict[str, int] = field(default_factory=lambda: {
        "starvation": 0, "dehydration": 0, "combat": 0, "collision": 0, "disease": 0, "morale": 0
    })
    upgrades_picked: Dict[str, int] = field(default_factory=lambda: {
        "power": 0, "armor": 0, "radar": 0, "living": 0
    })
    peak_onboard: int = 4
    peak_cars: int = 3
    cars_hung: int = 0  # 成功加挂次数（第 6 项对照）
    cars_abandoned: int = 0  # 03 §4.1 遗弃计数（对照）
    max_drought: int = 0  # 连续「无可获得」峰值（no_offer+unaffordable，对齐 03 §5）
    max_drought_raw: int = 0  # 含 AI 拒挂的连续未挂峰值（对照用）
    drought_miss_kinds: Dict[str, int] = field(
        default_factory=lambda: {"no_offer": 0, "unaffordable": 0, "ai_skip": 0}
    )
    failed: Optional[str] = None
    tutorial_done: bool = False
    nodes: List[Node] = field(default_factory=list)
    stations_left: int = 0
    segment_start_day: int = 1
    beds20_day: Optional[int] = None  # 床位首次≥20 的 dayTotal
    # 昨日行驶档（日结 F04）；开局按停靠
    last_spd_coef: float = 0.3
    last_drive_h: float = 0.0
    segment_fuel_surcharge: float = 0.0  # bypass 等非战附加，对齐 balance.fuel × (1+surcharge)

    def onboard(self) -> int:
        return sum(1 for m in self.members if m.alive)

    def beds(self) -> int:
        living = sum(c.size * 2 for c in self.cars if c.template_id == "living")
        return living + 2 * self.living_tech

    def loco_count(self) -> int:
        return min(3, sum(1 for c in self.cars if c.is_locomotive))

    def fuel_cap(self) -> float:
        return FUEL_TANK_BASE + sum(c.size * FUEL_TANK_PER_CARGO for c in self.cars if c.template_id == "cargo")

    def life_mult(self) -> float:
        return 1.0 + 0.10 * self.living_tech

    def stock_cap_food(self) -> float:
        base = 60 + sum(c.size * 10 for c in self.cars if c.template_id == "cargo")
        return base * self.life_mult()

    def stock_cap_water(self) -> float:
        return self.stock_cap_food()

    def stock_cap_parts(self) -> float:
        base = 20 + sum(round(c.size * 10 / 3) for c in self.cars if c.template_id == "cargo")
        return base * self.life_mult()

    def stock_cap_med(self) -> float:
        base = 15 + sum(round(c.size * 5 / 3) for c in self.cars if c.template_id == "cargo")
        return base * self.life_mult()

    def stock_cap_seed(self) -> float:
        base = 20 + sum(c.size * 4 for c in self.cars if c.template_id == "cargo")
        return base * self.life_mult()

    def car_count(self) -> int:
        return len(self.cars)

    def greenhouse_racks(self) -> int:
        """sim：每节种植 1 架（efficiency 满）。"""
        return sum(1 for c in self.cars if c.function == "greenhouse")


def traction(state: RunState) -> float:
    n = state.loco_count()
    return max(
        FUEL_TRACTION_FLOOR,
        1.0 - FUEL_TRACTION_PER_LOCO * min(3, n) - FUEL_TRACTION_PER_TECH * float(state.power_tech),
    )


def fuel_day(state: RunState, speed_coef: float = 1.0, craft: bool = False) -> float:
    """02 §4：全日折合耗油率（%）；读 balance.fuel + 区段附加（对齐 FuelF04）。"""
    add = sum(c.fuel_per_day for c in state.cars)
    add += FUEL_EXTRA_LOCO * max(0, state.loco_count() - 1)
    craft_add = FUEL_CRAFT_PER_DAY if craft else 0.0
    surcharge = max(0.0, float(state.segment_fuel_surcharge))
    mult = min(
        speed_coef * state.climate.fuel * state.region_fuel_mult * (1.0 + surcharge),
        3.0,
    )
    return (FUEL_BASE + add) * traction(state) * mult + craft_add


def armor_cars(state: RunState) -> int:
    return sum(1 for c in state.cars if c.armor >= 70)


def train_dr(state: RunState) -> float:
    """03 §6.4：0.30×armorCars + 0.06×armorTechLv，封顶 0.80。"""
    return min(0.30 * armor_cars(state) + 0.06 * state.armor_tech, 0.80)


def count_job(state: RunState, job: str) -> int:
    return sum(1 for m in state.members if m.alive and m.job == job)


def assign_jobs(state: RunState) -> None:
    """04 §4.3 自动填槽：grower → purifier → engineer → crafter → radar_op。"""
    alive = [m for m in state.members if m.alive]
    for m in alive:
        m.job = "none"
    slots: List[str] = []
    gh_n = sum(1 for c in state.cars if c.function == "greenhouse")
    wc_n = sum(1 for c in state.cars if c.function == "water")
    ws_n = sum(1 for c in state.cars if c.function == "workshop")
    rd_n = sum(1 for c in state.cars if c.template_id == "radar")
    loco_n = sum(1 for c in state.cars if c.is_locomotive)
    med_n = sum(1 for c in state.cars if c.function == "medical" or c.template_id == "medical")
    slots += ["grower"] * gh_n
    slots += ["purifier"] * wc_n
    slots += ["engineer"] * min(3, loco_n)
    slots += ["crafter"] * min(2 * ws_n, 4)
    slots += ["pharmacist"] * med_n
    slots += ["radar_op"] * rd_n
    reserve_guard = 1 if len(alive) > len(slots) else 0
    i = 0
    for job in slots:
        if i >= len(alive) - reserve_guard:
            break
        alive[i].job = job
        i += 1
    for m in alive[i:]:
        m.job = "guard" if count_job(state, "guard") == 0 else "labor"


def panel_speed_cap(state: RunState) -> float:
    bonuses = sorted(
        (c.speed_bonus for c in state.cars if c.is_locomotive), reverse=True
    )[:3]
    return float(60 + sum(bonuses) + 5 * state.power_tech) * state.climate.speed


def recompute_climate(state: RunState) -> None:
    """01 §8：effectiveTemp → cold/heat → 消耗/温室/速度。"""
    wid = state.climate.weather_id
    w = WEATHER.get(wid, WEATHER["clear"])
    temp_mod, water_mod, speed_c, node_fuel, _ = w
    base = SEASON_BASE_TEMP[season_of(state.day)]
    eff = max(-2.0, min(2.0, base + temp_mod + state.region_temp))
    cold = max(0.0, -eff)
    heat = max(0.0, eff)
    food_c = _cold_climate(cold, "food", (1.40, 1.25, 1.10))
    fuel_c = _cold_climate(cold, "fuel", (1.56, 1.43, 1.15))
    if heat >= 1:
        water_temp = CLIMATE_HEAT_WATER.get("heat1", 1.5)
    elif heat >= 0.5:
        water_temp = CLIMATE_HEAT_WATER.get("heat0_5", 1.2)
    else:
        water_temp = 1.0
    # 冷侧温室默认未供暖；供暖在日结 3b 改写
    gh = HEATING_MULT if (cold >= 1 and state.heating_enabled) else (
        NO_HEAT_WINTER_MULT if cold >= 1 else 1.0
    )
    state.climate.effective_temp = eff
    state.climate.cold = cold
    state.climate.heat = heat
    state.climate.food = food_c
    state.climate.water = water_temp * water_mod
    state.climate.fuel = fuel_c
    state.climate.greenhouse = gh
    state.climate.speed = speed_c
    state.climate.node_fuel_mod = node_fuel


def draw_weather(state: RunState, rng: random.Random) -> str:
    col = weather_col(state.day)
    bias = state.region_bias
    ids = list(WEATHER.keys())
    weights = []
    for wid in ids:
        raw = WEATHER[wid][4][col]
        weights.append(raw * bias.get(wid, 1.0))
    if sum(weights) <= 0:
        return "clear"
    return rng.choices(ids, weights=weights, k=1)[0]


def choose_region(state: RunState, rng: random.Random) -> str:
    """玩家三选一近似：按季/库存偏置；秋储+冬雪原抬权（油墙多样化腿之一）。"""
    season = season_of(state.day)
    fuel_fill = state.fuel / max(1.0, state.fuel_cap())
    food_fill = state.food / max(1.0, state.stock_cap_food())
    water_fill = state.water / max(1.0, state.stock_cap_water())
    w = {rid: 1.0 for rid in REGION_IDS}
    cars_n = state.car_count()
    dis = day_in_season(state.day)
    # 冬季保底雪原：模拟「三选一必出雪原」后的玩家选取
    if season == "winter":
        force_p = 0.86 if (fuel_fill < 0.78 or cars_n >= 8) else 0.62
        if rng.random() < force_p:
            return "tundra"
    # 秋中起保底雪原（入冬罐）
    if season == "autumn" and dis >= 12 and fuel_fill < 0.85:
        force_p = 0.55 if dis >= 20 else 0.32
        if rng.random() < force_p:
            return "tundra"
    if season in ("autumn", "winter") or (season == "summer" and dis >= 15):
        w["tundra"] *= 3.0 if fuel_fill < 0.70 else 2.0
    if season == "winter":
        w["tundra"] *= 2.3
    if season == "autumn":
        w["tundra"] *= 1.25 if dis >= 10 else 1.1
    if cars_n >= 12 or fuel_fill < 0.50:
        w["tundra"] *= 1.65
    if season == "summer" or water_fill < 0.45:
        w["valley"] *= 2.4 if season == "summer" else 2.0
        if season == "summer" and fuel_fill >= 0.55:
            w["tundra"] *= 0.85
    if food_fill < 0.50:
        w["urban"] *= 1.8
        w["valley"] *= 1.4
    if state.parts < 6:
        w["mine"] *= 1.5
        w["military"] *= 1.3
    if state.seed < max(2, state.greenhouse_racks()):
        w["valley"] *= 2.0
    if season == "spring":
        w["urban"] *= 1.6
        w["valley"] *= 1.3
    if food_fill < 0.60:
        w["plague"] *= 0.35
        w["military"] *= 0.45
        w["mine"] *= 0.55
        w["urban"] *= 1.5
        w["valley"] *= 1.4
    if fuel_fill < 0.40:
        w["tundra"] *= 2.4
        w["urban"] *= 0.65
        w["plague"] *= 0.5
    ids = list(w.keys())
    return rng.choices(ids, weights=[w[i] for i in ids], k=1)[0]


def want_second_loco(state: RunState, strat: Strategy) -> bool:
    """动力多样化：第二动力是杠杆之一。

    扩张编组涨得快 → 硬条件更早挂；保守可在油尚可时先走动力科技几天。
    """
    locos = sum(1 for c in state.cars if c.is_locomotive)
    if locos >= 2:
        return False
    cars = state.car_count()
    fuel_fill = state.fuel / max(1.0, state.fuel_cap())
    expand = strat.risk >= 0.5
    loco_day = 38 if expand else 42
    loco_cars = 5 if expand else 7
    # 硬需求（扩张更早挂，编组涨得快）
    if cars >= loco_cars or fuel_fill < 0.50:
        return True
    if fuel_fill < 0.55 and cars >= (5 if expand else 6):
        return True
    # 仅保守：科技 Lv0 软缓（扩张不缓，否则 idle 先爆）
    if (
        not expand
        and state.power_tech == 0
        and state.day < loco_day
        and cars < 7
        and fuel_fill >= 0.55
    ):
        return False
    if state.day >= loco_day and cars >= 5:
        return True
    return False


def start_region_run(
    state: RunState, rng: random.Random, force_id: Optional[str] = None
) -> None:
    rid = force_id or choose_region(state, rng)
    meta = REGIONS[rid]
    state.region_id = rid
    state.region_fuel_mult = meta["fuel_mult"]
    state.region_temp = meta["temp"]
    state.region_bias = dict(meta["bias"])
    state.point_mods = dict(meta["mods"])
    state.segment_count = rng.randint(3, 5)
    state.segments_in_run = 0


def overlap(cars: List[Car], fn: str) -> float:
    n = sum(1 for c in cars if c.function == fn)
    return 0.90 ** max(0, n - 2)


def greenhouse_day(state: RunState) -> float:
    """F05：需 grower 在岗；种子系数；yearProd × greenhouseClimate。"""
    growers = count_job(state, "grower")
    if growers <= 0:
        return 0.0
    racks = state.greenhouse_racks()
    seed_coef = 1.0 if (racks > 0 and state.seed >= racks) else 0.5
    pen = overlap(state.cars, "greenhouse")
    yp = year_prod(state.day)
    gh_c = state.climate.greenhouse
    total = 0.0
    staffed = 0
    for c in state.cars:
        if c.function != "greenhouse":
            continue
        if staffed >= growers:
            break
        # farming 专长未建模 → 无 ×1.10
        total += GREENHOUSE_DAY * (c.efficiency / 100.0) * pen * gh_c * yp * seed_coef
        staffed += 1
    if seed_coef >= 1.0 and racks > 0 and total > 0:
        state.seed = max(0.0, state.seed - SEED_CONSUME_PER_RACK * staffed)
    return total


def watercar_day(state: RunState) -> float:
    """F32：需 fuel>0 + purifier 在岗；× yearProd。"""
    if state.fuel <= 0:
        return 0.0
    purifiers = count_job(state, "purifier")
    if purifiers <= 0:
        return 0.0
    pen = overlap(state.cars, "water")
    yp = year_prod(state.day)
    total = 0.0
    staffed = 0
    for c in state.cars:
        if c.function != "water":
            continue
        if staffed >= purifiers:
            break
        base = 15 if c.advanced else 10
        total += base * (c.efficiency / 100.0) * pen * yp
        staffed += 1
    return total


def food_consume(state: RunState) -> float:
    return state.onboard() * 0.9 * state.climate.food


def water_consume(state: RunState) -> float:
    return state.onboard() * 0.8 * state.climate.water


@dataclass
class Strategy:
    name: str
    prefer_carriage: bool
    prefer_power_tech: bool
    accept_recruit: bool
    risk: float


def pop_soft_cap(state: RunState) -> int:
    """01 §10 软目标：年1 冬 12–16；年2 夏起冲 20+。"""
    y = year_of(state.day)
    s = season_of(state.day)
    if y == 1:
        if s == "spring":
            return 14
        if s == "summer":
            return 14
        if s == "autumn":
            return 15
        return 16
    if y == 2:
        if s == "spring":
            return 18
        if s == "summer":
            return 24  # 验收冲 20
        return 26
    return 30


def resources_ok_for_recruit(state: RunState) -> bool:
    """用「可撑日数」而非仓容百分比——开局仓大、库存看着很少。"""
    pop = max(1, state.onboard())
    food_days = state.food / max(0.1, pop * 0.9 * state.climate.food)
    water_days = state.water / max(0.1, pop * 0.8 * state.climate.water)
    fuel_fill = state.fuel / max(1.0, state.fuel_cap())
    season = season_of(state.day)
    y = year_of(state.day)
    if season == "autumn" and y == 1 and food_days < 8:
        return False
    if season == "winter" and (food_days < 4 or fuel_fill < 0.28):
        return False
    if season == "summer" and y == 1:
        need_w = 3.5 if state.climate.heat >= 1 else 2.5
        return food_days >= 2.2 and water_days >= need_w
    if y >= 2 and season == "summer":
        # 床≥20 冲人：脉冲期内再降门槛（AI），不改设计基率
        if state.beds() >= 20 and state.onboard() < 20:
            gh_ok = count_job(state, "grower") >= 2
            wa_ok = count_job(state, "purifier") >= 1
            in_pulse = (
                state.beds20_day is not None
                and 0 <= state.day - state.beds20_day < 14
            )
            if in_pulse:
                need_f = 2.4 if gh_ok else 3.0
                need_w = 2.4 if wa_ok else 3.0
                return food_days >= need_f and water_days >= need_w and fuel_fill >= 0.16
            need_f = 3.0 if gh_ok else 3.8
            need_w = 3.2 if wa_ok else 3.8
            return food_days >= need_f and water_days >= need_w and fuel_fill >= 0.20
        return food_days >= 3 and water_days >= 3 and fuel_fill >= 0.20
    if y >= 2:
        return food_days >= 3.5 and water_days >= 3.5
    return food_days >= 2.2 and water_days >= 2.2


def beds20_pulse_days(strat: Strategy) -> int:
    """扩张加长到 14 日；保守仍 10 日。"""
    return 14 if strat.risk >= 0.5 else 10


def in_beds20_pulse(state: RunState, strat: Strategy) -> bool:
    """床到位后连续 N 日冲人窗口。"""
    if state.beds20_day is None or state.onboard() >= 20:
        return False
    return 0 <= state.day - state.beds20_day < beds20_pulse_days(strat)


def in_beds20_tail(state: RunState, strat: Strategy) -> bool:
    """脉冲结束后仍人&lt;20：扩张再跟 7 日温和日结。"""
    if strat.risk < 0.5 or state.beds20_day is None or state.onboard() >= 20:
        return False
    elapsed = state.day - state.beds20_day
    return beds20_pulse_days(strat) <= elapsed < beds20_pulse_days(strat) + 7


def try_recruit(state: RunState, rng: random.Random, strat: Strategy) -> None:
    """06 §2.2 近似：段内期望 + 日结；床到位脉冲（扩张更长）。"""
    if not strat.accept_recruit or state.recruited_today:
        return
    if state.onboard() >= pop_soft_cap(state):
        return
    if not resources_ok_for_recruit(state):
        return
    pop = state.onboard()
    beds = state.beds()
    y = year_of(state.day)
    season = season_of(state.day)
    pulse = in_beds20_pulse(state, strat)
    p = 0.12
    if y >= 2 and season in ("spring", "summer"):
        p = 0.34 if season == "summer" else 0.26
        if beds >= 20 and pop < 20:
            p = min(0.52, p + 0.16)
            if strat.risk >= 0.5:
                p = min(0.58, p + 0.08)
            if count_job(state, "grower") >= 2:
                p = min(0.60, p + 0.05)
        elif beds >= 16 and pop < 18:
            p = min(0.42, p + 0.08)
    elif y >= 2:
        p = 0.20
    # 脉冲：段内收留再抬（冲 pop≥50%）
    if pulse:
        p = min(0.80, p + (0.24 if strat.risk >= 0.5 else 0.14))
    elif in_beds20_tail(state, strat):
        p = min(0.55, p + 0.10)
    if state.food < pop * 2:
        p = min(p * 1.3, 0.50)
    if pop >= beds:
        if y < 2:
            return
        p *= 0.35
    if rng.random() < p:
        m = Member(job="none", has_scavenge=(rng.random() < 0.22))
        # 名册封顶 + 冲人期不上册，压战斗死因峰值
        roster_n = sum(1 for x in state.members if x.alive and x.combat_roster)
        roster_cap = 3 if strat.risk >= 0.5 else 2
        roster_p = 0.08 if (beds >= 20 and pop < 20) else 0.16
        if pulse or in_beds20_tail(state, strat):
            roster_p = 0.0
        if roster_n >= roster_cap:
            roster_p = 0.0
        if rng.random() < roster_p:
            m.combat_roster = True
        state.members.append(m)
        state.recruited_today = True


def beds_target(state: RunState, strat: Optional[Strategy] = None) -> int:
    """年2 夏硬目标床位 ≥20；扩张提前抬目标（AI）。"""
    y = year_of(state.day)
    s = season_of(state.day)
    expand = strat is not None and strat.risk >= 0.5
    if y >= 2 and s == "summer":
        return 20
    if y >= 2 and s == "spring":
        return 18 if expand else 16
    if y == 1 and s in ("autumn", "winter"):
        return 15 if expand else 14  # 扩张略收，少挂 idle
    if expand and y == 1 and s == "summer" and state.day >= 55:
        return 12
    return 8


def try_tech_upgrade(state: RunState, strat: Strategy) -> None:
    """03 §7 四线 Lv1–3（同成本表）；AI 按缺口选线。"""
    if state.precision is None:
        return
    lines = []
    fuel_fill = state.fuel / max(1.0, state.fuel_cap())
    beds_tight = state.onboard() >= state.beds() - 1
    y = year_of(state.day)
    cars_n = state.car_count()
    need_beds = state.beds() < beds_target(state, strat)
    season = season_of(state.day)
    # 动力多样化：油压时动力科技与挂车并重（科技可在单动力上降牵引）
    fuel_push = (
        fuel_fill < 0.58
        or cars_n >= 9
        or season == "winter"
        or (season == "autumn" and day_in_season(state.day) >= 10)
        or (state.power_tech < 2 and strat.prefer_power_tech)
    )
    if need_beds or beds_tight or (y == 1 and state.day >= 70 and state.living_tech < 2):
        lines.append("living")
    if fuel_push:
        lines.insert(0, "power")
    if state.power_tech < 2 and (fuel_fill < 0.60 or cars_n >= 7):
        lines.insert(0, "power")  # 科技腿先于装甲
    if (not need_beds) and state.beds() >= 20 and state.power_tech < 3:
        lines.insert(0, "power")
    if y >= 2 and state.living_tech < 2 and need_beds:
        lines.insert(0, "living")
    if need_beds and strat.risk >= 0.5 and state.living_tech < 2:
        lines.insert(0, "living")
    # 油紧时生活仍可插队，但不压掉动力 Lv1
    if need_beds and state.power_tech >= 1 and fuel_fill >= 0.45:
        pass
    # 油紧时少升装甲（挂装甲车另计）；车体危急仍可
    if fuel_fill >= 0.48 and (state.body < 75 or (strat.risk >= 0.5 and not need_beds)):
        lines.append("armor")
    elif state.body < 50:
        lines.append("armor")
    lines.append("radar")
    lines.append("power")
    lines.append("living")
    # 去重保序
    seen = set()
    ordered = []
    for ln in lines:
        if ln not in seen:
            seen.add(ln)
            ordered.append(ln)
    level_of = {
        "power": state.power_tech,
        "armor": state.armor_tech,
        "radar": state.radar_tech,
        "living": state.living_tech,
    }
    for ln in ordered:
        lv = level_of[ln]
        if lv >= 3:
            continue
        need_p = TECH_PREC[lv]
        if state.precision < need_p:
            continue
        if state.parts < TECH_PARTS[lv]:
            continue
        if state.med < TECH_MED[lv]:
            continue
        if state.potion_catalyst < TECH_CATALYST[lv]:
            continue
        if state.fuel < TECH_FUEL[lv]:
            continue
        state.parts -= TECH_PARTS[lv]
        state.med -= TECH_MED[lv]
        state.potion_catalyst -= TECH_CATALYST[lv]
        state.fuel -= TECH_FUEL[lv]
        if ln == "power":
            state.power_tech += 1
        elif ln == "armor":
            state.armor_tech += 1
        elif ln == "radar":
            state.radar_tech += 1
        else:
            state.living_tech += 1
        state.upgrades_picked[ln] += 1
        level_of[ln] += 1
        break  # 每日至多升 1 级


def party_search_hours(n: int, team_eff: float) -> float:
    """04 §5.3：时长 = max(0.5, 人数修正 × 人数/队伍效率)。"""
    if n <= 0 or team_eff <= 0:
        return 1.0
    headcount_mod = 0.85 ** (n - 1)
    return max(0.5, 1.0 * headcount_mod * (n / team_eff))


def pick_search_party(state: RunState, rng: random.Random) -> List[Member]:
    """1–4 可派人；发病不可派；优先 scavenge 专长与杂工。"""
    pool = [
        m for m in state.members
        if m.alive and m.disease != "sick"
    ]
    if not pool:
        return []
    pool.sort(key=lambda m: (
        0 if m.has_scavenge else 1,
        0 if m.job == "labor" else 1,
        0 if m.job in ("none", "guard") else 1,
    ))
    food_fill = state.food / max(1.0, state.stock_cap_food())
    want = 3 if food_fill < 0.50 else 2
    if food_fill < 0.30:
        want = 4
    want = min(4, max(1, want), len(pool))
    return pool[:want]


def apply_disease_tick(state: RunState, rng: random.Random) -> None:
    """04 §7：缺粮跨入检定 + 病程 + 过道软压 + 薄治疗。"""
    # streak 首次 ≥3
    if state.starve_food_days >= 3 and state.food_disease_armed:
        state.food_disease_armed = False
        for m in state.members:
            if m.alive and m.disease == "none" and rng.random() < HUNGER_DISEASE_P:
                m.disease = "latent"
                m.disease_days = 0
    if state.starve_food_days == 0:
        state.food_disease_armed = True
    if state.starve_water_days >= 3 and state.water_disease_armed:
        state.water_disease_armed = False
        for m in state.members:
            if m.alive and m.disease == "none" and rng.random() < HUNGER_DISEASE_P:
                m.disease = "latent"
                m.disease_days = 0
    if state.starve_water_days == 0:
        state.water_disease_armed = True

    # 过道软压
    if state.onboard() > state.beds() and rng.random() < HALLWAY_DISEASE_P:
        hallway = [m for m in state.members if m.alive and m.disease == "none"]
        if hallway:
            m = rng.choice(hallway)
            m.disease = "latent"
            m.disease_days = 0

    # 疫区薄加压：健康者 2%/日
    if state.region_id == "plague":
        for m in state.members:
            if m.alive and m.disease == "none" and rng.random() < 0.02:
                m.disease = "latent"
                m.disease_days = 0

    # 治疗：药剂师 + 药 → 加速康复
    pharm = count_job(state, "pharmacist")
    if pharm >= 1 and state.med >= 1:
        sick = [m for m in state.members if m.alive and m.disease == "sick"]
        if sick:
            state.med -= 1
            t = sick[0]
            t.disease_days += 2  # 疗程压缩
            if t.disease_days >= 7:
                t.disease = "none"
                t.disease_days = 0

    # 病程推进
    for m in state.members:
        if not m.alive or m.disease == "none":
            continue
        m.disease_days += 1
        if m.disease == "latent" and m.disease_days >= 1:
            m.disease = "sick"
            m.disease_days = 0
        elif m.disease == "sick":
            m.hp -= 4
            if rng.random() < 0.10:
                m.alive = False
                state.deaths["disease"] += 1
                continue
            if m.hp <= 0:
                m.alive = False
                state.deaths["disease"] += 1
                continue
            if m.disease_days >= 7:
                m.disease = "none"
                m.disease_days = 0
                m.hp = min(100, m.hp + 10)


def combat_pressure(state: RunState) -> float:
    """01 §7：season × yearThreat + weatherPressure + region pressureAdd."""
    season = season_of(state.day)
    p = SEASON_PRESSURE[season] * year_threat_multiplier(year_of(state.day))
    wrow = load_weather_raw().get(state.climate.weather_id, {})
    p += float(wrow.get("weatherPressure", 0.0))
    p += float(REGIONS.get(state.region_id, {}).get("pressure", 0.0))
    return p


def resolve_combat_day(state: RunState, rng: random.Random, strat: Strategy) -> None:
    """05 §6：L1 检定；敌众/高压 → L2 薄多回合（丰富战斗死因）。"""
    pressure = combat_pressure(state)
    encounter = 0.055 * strat.risk * min(1.7, 0.7 + 0.35 * pressure)
    # 冲人口窗口：少开战，保人
    pop_push = state.beds() >= 20 and state.onboard() < 20 and year_of(state.day) >= 2
    if pop_push:
        encounter *= 0.55
    if state.climate.weather_id in ("blizzard", "fog", "night_rain"):
        encounter *= max(0.60, 1.0 - 0.08 * state.radar_tech)
    if state.region_id == "military":
        encounter *= 1.2
    if rng.random() >= encounter:
        return

    roster = [m for m in state.members if m.alive and m.combat_roster and m.disease != "sick"]
    if not roster:
        roster = [m for m in state.members if m.alive and m.job == "guard" and m.disease != "sick"]
    if not roster:
        if rng.random() < 0.4:
            state.food = max(0.0, state.food - rng.uniform(1.0, 3.0))
        return

    p_force = 10.0 * len(roster) + 0.35 * (12 * armor_cars(state) + 4 * state.armor_tech)
    # 冲人口期压 L2；否则高压/军事/扩张风险可升级
    l2_p = 0.38
    if pop_push:
        l2_p = 0.14
    elif strat.risk >= 0.55:
        l2_p = 0.24
    use_l2 = (
        pressure >= 1.7 and rng.random() < l2_p
    ) or (state.region_id == "military" and rng.random() < (0.16 if pop_push else 0.28)) or (
        strat.risk >= 0.55 and (not pop_push) and rng.random() < 0.16
    )
    if use_l2:
        n_enemy = rng.randint(6, 12)
    else:
        n_enemy = rng.randint(2, 5)
        if pressure >= 1.8 and rng.random() < 0.25:
            n_enemy = rng.randint(6, 9)
            use_l2 = True

    e_force = n_enemy * L1_UNIT * year_threat_multiplier(year_of(state.day))
    d = p_force / (p_force + e_force)

    if not use_l2:
        success = max(0.15, min(0.90, 0.35 + 0.45 * d))
        if rng.random() < success:
            return
        if rng.random() < 0.5:
            victim = rng.choice(roster)
            victim.hp -= rng.randint(18, 35)
            if victim.hp <= 0:
                victim.alive = False
                state.deaths["combat"] += 1
        else:
            for m in roster:
                m.hp -= 8
                if m.hp <= 0:
                    m.alive = False
                    state.deaths["combat"] += 1
        return

    # L2 薄会话：3 回合，按 D 分摊受伤；终局可能阵亡
    progress_p = 0.0
    progress_e = 0.0
    for _ in range(3):
        alive_r = [m for m in roster if m.alive]
        if not alive_r:
            break
        if rng.random() < d:
            progress_p += 1.0
            # 轻伤
            if rng.random() < 0.35:
                m = rng.choice(alive_r)
                m.hp -= rng.randint(4, 10)
        else:
            progress_e += 1.0
            m = rng.choice(alive_r)
            m.hp -= rng.randint(10, 22)
            if m.hp <= 0:
                m.alive = False
                state.deaths["combat"] += 1
    # 敌方进度更高 → 额外伤亡
    if progress_e > progress_p:
        alive_r = [m for m in roster if m.alive]
        if alive_r and rng.random() < 0.55:
            m = rng.choice(alive_r)
            m.hp -= rng.randint(15, 40)
            if m.hp <= 0:
                m.alive = False
                state.deaths["combat"] += 1
        alive2 = [m for m in roster if m.alive]
        if alive2 and rng.random() < 0.25:
            m2 = rng.choice(alive2)
            m2.hp -= rng.randint(12, 28)
            if m2.hp <= 0:
                m2.alive = False
                state.deaths["combat"] += 1


def choose_travel_speed(state: RunState, strat: Strategy) -> float:
    """避撞 + 省油（动力多样化腿：压速/停靠，不单靠挂动力）。"""
    cap = panel_speed_cap(state)
    body = state.body
    fuel_fill = state.fuel / max(1.0, state.fuel_cap())
    locos = sum(1 for c in state.cars if c.is_locomotive)
    # 单动力时更早压速，用时间换油
    single_loco = locos < 2
    if body < 30:
        target = 12.0
    elif body < 50:
        target = 25.0
    elif body < 70:
        target = 40.0
    else:
        target = cap
    # 避撞：两侧都压车体阈值
    if body < 85:
        target = min(target, 40.0)
    if body < 65 or (strat.risk <= 0.35 and body < 60):
        target = min(target, 25.0)
    cars_n = state.car_count()
    # 长编组 / 单动力：更早停靠档（额度仍 1h，系数 0.3）
    if cars_n >= 14 and fuel_fill < 0.55:
        target = min(target, 12.0)
    elif cars_n >= 10 and fuel_fill < 0.40:
        target = min(target, 12.0)
    # 单动力压速：保守更敢停；扩张只在油紧时停，以免秋储跑不动
    if single_loco and strat.risk <= 0.35:
        if cars_n >= 7 and fuel_fill < 0.55:
            target = min(target, 12.0)
        elif fuel_fill < 0.48:
            target = min(target, 25.0)
    elif single_loco and fuel_fill < 0.40 and cars_n >= 8:
        target = min(target, 12.0)
    if strat.risk <= 0.35:
        if cars_n >= 8 and fuel_fill < 0.50:
            target = min(target, 12.0)
        elif fuel_fill < 0.45:
            target = min(target, 25.0)
    else:
        # 扩张：更早停靠换油（编组涨得快）
        if cars_n >= 8 and fuel_fill < 0.55:
            target = min(target, 12.0)
        elif cars_n >= 10 and fuel_fill < 0.50:
            target = min(target, 12.0)
        elif fuel_fill < 0.42:
            target = min(target, 25.0)
    if fuel_fill < 0.22 or (state.fuel < 18 and state.climate.cold >= 1):
        target = min(target, 12.0)
    elif fuel_fill < 0.40 and state.climate.cold >= 1:
        target = min(target, 25.0)
    elif fuel_fill < 0.35:
        target = min(target, 40.0)
    return max(0.0, min(cap, target))


def apply_day(state: RunState, rng: random.Random, strat: Strategy) -> None:
    if state.failed:
        return

    state.recruited_today = False
    assign_jobs(state)

    # —— 日间：维修 / 行驶意图 / 搜刮 / 进站 / 收留 ——
    crafters = count_job(state, "crafter")
    if state.body < 70 and state.parts >= 2 and crafters >= 1:
        state.parts -= 2
        state.body = min(100.0, state.body + 8)

    inst = 0.0
    spd_coef = 0.3
    if state.fuel > 0:
        inst = choose_travel_speed(state, strat)
        if inst <= 12:
            spd_coef = 0.3
        elif inst <= 40:
            spd_coef = 0.8
        else:
            spd_coef = 1.0
        travel_km = 2.5 * (inst / 30.0) * DRIVE_HOURS_CAP if inst > 0 else 0.0
        state.distance_km += travel_km
        # 避撞：扩张也降碰撞率；车体已伤再减半
        col_p = 0.022 * strat.risk
        if state.body < 70:
            col_p *= 0.55
        if inst > 12 and rng.random() < col_p:
            dmg = 12 * (inst / 40) ** 2 * (1.0 - train_dr(state))
            state.body -= dmg
            if state.body <= 0:
                state.body = 0
                state.failed = "body"
                state.deaths["collision"] += 1
                return

    state.last_spd_coef = spd_coef
    state.last_drive_h = DRIVE_HOURS_CAP if inst > 12 else 0.0

    seg_age = state.day - state.segment_start_day
    fuel_fill_day = state.fuel / max(1.0, state.fuel_cap())
    # 进站日程先于重建，避免点位日清空后永远到不了 day 3/5
    if state.stations_left > 0 and seg_age in (3, 5):
        state.stations_left -= 1
        _station(state, rng, strat)

    pools_empty = (not state.nodes) or all(n.pool <= 0 for n in state.nodes)
    # 雪原：池未空且油未满时最多再留 2 日榨油；点空必须走
    seg_limit = SEGMENT_DAYS
    if (not pools_empty) and state.region_id == "tundra" and fuel_fill_day < 0.72:
        seg_limit = SEGMENT_DAYS + 2
    if pools_empty and seg_age >= 5:
        _build_segment(state, rng)
    elif seg_age >= seg_limit:
        _build_segment(state, rng)

    _scavenge(state, rng)

    # 晶核→催化（02 §5.4 薄模型：医疗+药剂师）
    if state.crystal >= 1 and count_job(state, "pharmacist") >= 1:
        n = int(state.crystal)
        state.crystal -= n
        state.potion_catalyst = min(10.0, state.potion_catalyst + n * 2)

    try_recruit(state, rng, strat)
    # 先标记床到位日，再日结补抽（脉冲依赖 beds20_day）
    if state.beds20_day is None and state.beds() >= 20:
        state.beds20_day = state.day

    # 日结补抽：基率 0.05；床到位后 10 日脉冲抬高
    if not state.recruited_today and state.onboard() < state.beds() and resources_ok_for_recruit(state):
        p_end = 0.05
        if in_beds20_pulse(state, strat):
            p_end = 0.45 if strat.risk >= 0.5 else 0.28
        elif in_beds20_tail(state, strat):
            p_end = 0.22
        elif state.beds() >= 20 and state.onboard() < 20 and year_of(state.day) >= 2:
            p_end = 0.28 if strat.risk >= 0.5 else 0.16
        if rng.random() < p_end:
            state.members.append(
                Member(job="none", has_scavenge=(rng.random() < 0.22), combat_roster=False)
            )
            state.recruited_today = True

    season = season_of(state.day)
    food_fill = state.food / max(1.0, state.stock_cap_food())

    # —— 日结（02 §8）：气候 → 粮水 → F04 → 供暖 → 产 → 工坊 → 归零 ——
    recompute_climate(state)
    assign_jobs(state)  # 收留后重填岗

    state.food -= food_consume(state)
    state.water -= water_consume(state)
    if state.food <= 0:
        state.food = 0
        state.starve_food_days += 1
    else:
        state.starve_food_days = 0
    if state.water <= 0:
        state.water = 0
        state.starve_water_days += 1
    else:
        state.starve_water_days = 0

    craft_on = count_job(state, "crafter") > 0 and any(
        c.function == "workshop" for c in state.cars
    )
    # 油紧停造零件（+0.5%/日附加），扩张更早停
    fuel_for_craft = state.fuel / max(1.0, state.fuel_cap())
    if strat.risk >= 0.5:
        craft_floor = 0.48 if state.car_count() >= 8 else 0.40
    else:
        craft_floor = 0.42 if state.car_count() >= 10 else 0.35
    if fuel_for_craft < craft_floor:
        craft_on = False
    if state.fuel > 0:
        drive_h = DRIVE_HOURS_CAP
        idle_h = 24.0 - drive_h
        burn = (
            fuel_day(state, speed_coef=spd_coef, craft=craft_on) * (drive_h / 24.0)
            + fuel_day(state, speed_coef=0.3, craft=craft_on) * (idle_h / 24.0)
        )
        state.fuel -= burn

    green_cars = sum(1 for c in state.cars if c.function == "greenhouse")
    state.heating_enabled = False
    fuel_fill_now = state.fuel / max(1.0, state.fuel_cap())
    if state.climate.cold >= 1 and green_cars and state.fuel > 8.0:
        need = HEATING_FUEL_PER_CAR * green_cars
        # 油墙多样化：油紧时停供暖（粮尚可）；长编组门槛更高
        heat_floor = 0.45 if green_cars >= 3 or state.car_count() >= 10 else 0.38
        heat_ok = (
            fuel_fill_now >= heat_floor
            or state.starve_food_days > 0
            or food_fill < 0.40
        )
        if heat_ok and state.fuel >= need + 5.0 and (
            food_fill < 0.95 or state.starve_food_days > 0 or season == "winter"
        ):
            state.heating_enabled = True
            state.fuel -= need
            state.climate.greenhouse = HEATING_MULT
        else:
            state.climate.greenhouse = NO_HEAT_WINTER_MULT
    elif state.climate.cold >= 1:
        state.climate.greenhouse = NO_HEAT_WINTER_MULT

    state.fuel = min(state.fuel_cap(), max(0.0, state.fuel))

    if state.fuel <= 0:
        state.fuel = 0
        state.fuel_zero_days += 1
        if state.fuel_zero_days >= 3:
            state.failed = "fuel"
            return
    else:
        state.fuel_zero_days = 0

    if state.food < state.stock_cap_food():
        state.food = min(state.stock_cap_food(), state.food + greenhouse_day(state))
    state.water = min(state.stock_cap_water(), state.water + watercar_day(state))

    # 工坊：须 crafter 在岗才造零件 / +precision；空转 −1
    if any(c.function == "workshop" for c in state.cars):
        if state.precision is None:
            state.precision = 40.0
        crafter_n = count_job(state, "crafter")
        if crafter_n > 0:
            slots = min(crafter_n, 2 * sum(1 for c in state.cars if c.function == "workshop"))
            state.parts = min(
                state.stock_cap_parts(),
                state.parts + slots * (state.precision / 300.0),
            )
            state.precision = min(100.0, state.precision + 1)
        else:
            state.precision = max(0.0, state.precision - 1)
        try_tech_upgrade(state, strat)

    # 疾病（可与 F39 同日）
    apply_disease_tick(state, rng)

    if state.starve_food_days >= 3 or state.starve_water_days >= 3:
        for m in state.members:
            if not m.alive:
                continue
            m.hp -= 20
            if m.hp <= 0:
                m.alive = False
                if state.starve_food_days >= 3 and state.starve_water_days >= 3:
                    key = (
                        "starvation"
                        if state.deaths["starvation"] <= state.deaths["dehydration"]
                        else "dehydration"
                    )
                elif state.starve_food_days >= 3:
                    key = "starvation"
                else:
                    key = "dehydration"
                state.deaths[key] += 1

    if state.onboard() == 0:
        state.failed = "wipe"
        return

    state.peak_onboard = max(state.peak_onboard, state.onboard())
    resolve_combat_day(state, rng, strat)

    if state.onboard() == 0:
        state.failed = "wipe"
        return

    state.day += 1


def _point_type_draw(state: RunState) -> Tuple[List[str], List[float]]:
    weights = compute_type_weights(
        season=season_of(state.day),
        region_id=state.region_id,
        point_mods=state.point_mods,
        weather_id=state.climate.weather_id,
        radar_tech=state.radar_tech,
    )
    return normalized_weights(weights)


def _build_segment(state: RunState, rng: random.Random) -> None:
    if state.segments_in_run >= state.segment_count or (
        not state.tutorial_done and state.segments_in_run == 0 and state.day <= 1
    ):
        if not state.tutorial_done and state.day <= 2:
            start_region_run(state, rng, force_id="urban")
        else:
            start_region_run(state, rng)

    state.segments_in_run += 1
    # onSegmentBuild：抽天气 → 气候 → 点位
    state.climate.weather_id = draw_weather(state, rng)
    recompute_climate(state)

    n = 4 if rng.random() < 0.5 else 3
    types = load_point_types()
    keys, probs = _point_type_draw(state)
    kinds = rng.choices(keys, weights=probs, k=n)
    if not state.tutorial_done and state.segments_in_run == 1:
        stations_cfg = load_stations_config()
        force_types = list(stations_cfg.get("tutorialForcePointTypes") or [])
        for ftype in force_types:
            if ftype not in kinds and ftype in types:
                if len(kinds) >= n:
                    kinds[-1] = ftype
                else:
                    kinds.append(ftype)
    state.nodes = []
    for ptype in kinds:
        meta = types[ptype]
        med = float(meta["median"])
        sim_yield = str(meta["simYield"])
        state.nodes.append(Node(ptype, sim_yield, med, med * POOL_MULT))
    state.stations_left = rng.choices(STATION_COUNT_KEYS, weights=STATION_COUNT_WEIGHTS)[0]
    state.segment_start_day = state.day
    if not state.tutorial_done:
        state.stations_left = 1
    if rng.random() < CRYSTAL_HIDDEN_CHANCE:
        state.crystal += 1


def _needs(state: RunState) -> dict:
    """搜刮优先级：随季节/气候抬燃油与粮水目标（秋储 + 冬缓冲）。"""
    pop = state.onboard()
    season = season_of(state.day)
    dis = day_in_season(state.day)
    food_target = pop * 2.0
    water_target = pop * 1.5
    fuel_target = 40.0 + 8.0 * state.climate.cold

    # 开局春：先扣后产（02 §8）更吃库存，粮目标抬高
    if season == "spring" or state.day <= 40:
        food_target = max(food_target, state.stock_cap_food() * 0.55, pop * 5.0)
        water_target = max(water_target, pop * 2.5)

    if season == "summer":
        # 夏热：水优先；夏末顺带囤油
        water_target = max(water_target, state.stock_cap_water() * 0.75, pop * 3.0)
        if state.climate.heat >= 1:
            water_target = max(water_target, state.stock_cap_water() * 0.90)
        if dis >= 15:
            fuel_target = max(fuel_target, state.fuel_cap() * 0.55)
            food_target = max(food_target, state.stock_cap_food() * 0.55)
    if season == "autumn":
        food_target = max(food_target, state.stock_cap_food() * 0.90)
        water_target = max(water_target, state.stock_cap_water() * 0.70)
        autumn_fill = 0.84 if dis >= 12 else 0.80
        fuel_target = max(fuel_target, state.fuel_cap() * autumn_fill)
    elif season == "winter":
        food_target = max(food_target, pop * 4.0)
        fuel_target = max(fuel_target, state.fuel_cap() * 0.68, 70.0)
        if state.region_id == "tundra":
            fuel_target = max(fuel_target, state.fuel_cap() * 0.78)
        water_target = max(water_target, pop * 2.0)

    fuel_gap = max(0.0, fuel_target - state.fuel)
    water_gap = max(0.0, water_target - state.water)
    fuel_w = 2.5 if state.fuel < 30 or (season == "winter" and state.fuel < 50) else 2.0
    if season == "autumn":
        fuel_w = 3.0 if dis >= 12 else 2.8
    if season == "winter":
        fuel_w = 3.15
    if state.fuel / max(1.0, state.fuel_cap()) < 0.40:
        fuel_w += 0.20
    water_w = 2.6 if season == "summer" or state.climate.heat >= 0.5 else 1.4
    racks = max(1, state.greenhouse_racks())
    seed_target = max(float(racks + 2), 6.0)
    if season in ("spring", "summer", "autumn"):
        seed_target = max(seed_target, 8.0)
    food_gap = max(0.0, food_target - state.food)
    food_w = 2.2 if food_gap > pop * 1.5 or state.starve_food_days > 0 else 1.0
    # 种植未满员时更依赖搜粮
    growers = count_job(state, "grower")
    if growers < state.greenhouse_racks():
        food_w *= 1.5
    return {
        "food": food_gap * food_w,
        "water": water_gap * water_w,
        "fuel": fuel_gap * fuel_w,
        "parts": max(0.0, 10.0 - state.parts),
        "med": max(0.0, 6.0 - state.med),
        "mixed": food_gap * 0.5 * food_w,
        "seed": max(0.0, seed_target - state.seed) * 2.0,
    }


def _add(state: RunState, res: str, amount: float) -> None:
    if res == "food" or res == "mixed":
        food_amt = amount if res == "food" else amount * 0.55
        state.food = min(state.stock_cap_food(), state.food + food_amt)
    elif res == "water":
        state.water = min(state.stock_cap_water(), state.water + amount)
    elif res == "fuel":
        state.fuel = min(state.fuel_cap(), state.fuel + amount)
    elif res == "parts":
        state.parts = min(state.stock_cap_parts(), state.parts + amount)
    elif res == "med":
        state.med = min(state.stock_cap_med(), state.med + amount)
    elif res == "seed":
        # farm：主种子 + 少食
        state.seed = min(state.stock_cap_seed(), state.seed + amount)
        state.food = min(state.stock_cap_food(), state.food + amount * 0.35)


def _scavenge(state: RunState, rng: random.Random) -> None:
    """04 §5.3：按派人效率折合当日搜索次数；有杂工则入库（无堆滞留模型）。"""
    party = pick_search_party(state, rng)
    if not party:
        return
    div = max(0.001, SCAVENGE_SKILL_DIVISOR)
    team_eff = sum((1.0 / div) if m.has_scavenge else 1.0 for m in party)
    hours = party_search_hours(len(party), team_eff)
    # 效率高 → 同预算内更多点搜；封顶 3（避免日清空跳过进站窗）
    actions = max(1, min(MAX_SEARCH_PER_POINT, int(SEARCH_HOURS_BUDGET / hours + 1e-6)))
    yield_mult = min(
        SEARCH_YIELD_MULT_CAP,
        SEARCH_YIELD_MULT_BASE + SEARCH_YIELD_MULT_PER_TEAM * team_eff,
    )
    has_hauler = count_job(state, "labor") >= 1 or any(
        m.job == "labor" for m in party
    )
    fuel_fill_sc = state.fuel / max(1.0, state.fuel_cap())
    food_days_sc = state.food / max(0.1, max(1, state.onboard()) * 0.9 * state.climate.food)
    # 雪原油紧且粮尚可：多榨一轮，并偏燃料点
    if state.region_id == "tundra" and fuel_fill_sc < 0.72 and food_days_sc >= 3.0:
        actions = min(MAX_SEARCH_PER_POINT, actions + 1)
    for _ in range(actions):
        avail = [n for n in state.nodes if n.pool > 0]
        if not avail:
            return
        need = _needs(state)
        prefer_fuel = (
            state.region_id == "tundra"
            and fuel_fill_sc < 0.75
            and food_days_sc >= 2.5
        )
        fuel_nodes = [n for n in avail if n.res == "fuel"] if prefer_fuel else []
        if fuel_nodes:
            node = rng.choice(fuel_nodes)
        else:
            best = max(need.get(n.res, 0.0) for n in avail)
            if best <= 0:
                node = rng.choice(avail)
            else:
                node = rng.choice([n for n in avail if need.get(n.res, 0.0) == best])
        jitter = SEARCH_YIELD_JITTER_MIN + rng.random() * SEARCH_YIELD_JITTER_SPAN
        take = min(node.pool, node.median * jitter * yield_mult)
        node.pool -= take
        if has_hauler:
            _add(state, node.res, take)
        else:
            # 无杂工：只入库 55%（临时堆滞留近似）
            _add(state, node.res, take * 0.55)


def _car_repair_cost(car: Car) -> int:
    return int(REPAIR_PARTS.get(car.template_id, REPAIR_PARTS.get("default", 5)))


def _can_abandon_car(state: RunState, index: int) -> bool:
    if index < 0 or index >= len(state.cars):
        return False
    if state.cars[index].is_locomotive and sum(1 for c in state.cars if c.is_locomotive) <= 1:
        return False
    onboard = state.onboard()
    beds_after = state.beds()
    for i, c in enumerate(state.cars):
        if i == index and c.template_id == "living":
            beds_after -= c.size * 2
    return beds_after >= onboard


def _abandon_carriage(state: RunState, index: int) -> bool:
    """03 §4.1 — sim 省略 scrap/床位绑定；只扣 parts+油并移除节。"""
    if not _can_abandon_car(state, index):
        return False
    if state.parts < ABANDON_PARTS_COST:
        return False
    car = state.cars[index]
    state.parts -= ABANDON_PARTS_COST  # scrap 不建模；仅保留切割成本
    fuel_cut = state.fuel_cap() * ABANDON_FUEL_COST_PCT
    state.fuel = max(0.0, state.fuel - fuel_cut)
    del state.cars[index]
    state.cars_abandoned += 1
    _ = int(_car_repair_cost(car) * ABANDON_SCRAP_RATIO)
    return True


def _pick_abandon_index(state: RunState) -> Optional[int]:
    gh = sum(1 for c in state.cars if c.template_id == "greenhouse")
    wt = sum(1 for c in state.cars if c.template_id == "water")
    priority = {
        "armor": 6,
        "radar": 5,
        "workshop": 4,
        "cargo": 2,
        "living": 1,
        "shell": 1,
        "medical": 3,
    }
    best: Optional[Tuple[int, float, int]] = None
    for i, c in enumerate(state.cars):
        if not _can_abandon_car(state, i):
            continue
        if c.template_id == "greenhouse" and gh <= 1:
            continue
        if c.template_id == "water" and wt <= 1:
            continue
        score = (priority.get(c.template_id, 2), c.fuel_per_day, i)
        if best is None or score > best:
            best = score
    return best[2] if best else None


def _maybe_abandon_at_station(state: RunState, strat: Strategy) -> None:
    fuel_fill = state.fuel / max(1.0, state.fuel_cap())
    if fuel_fill > ABANDON_AI_FUEL_MAX or state.car_count() < ABANDON_AI_MIN_CARS:
        return
    if not strat.prefer_carriage and fuel_fill > ABANDON_AI_FUEL_MAX * 0.85:
        return
    idx = _pick_abandon_index(state)
    if idx is not None:
        _abandon_carriage(state, idx)


def _miss_carriage(state: RunState, kind: str) -> None:
    """kind: no_offer | unaffordable | ai_skip（后两者之外不计入 guaranteeFailStreak）。"""
    state.drought_miss_kinds[kind] = state.drought_miss_kinds.get(kind, 0) + 1
    state.no_carriage_miss_raw += 1
    state.max_drought_raw = max(state.max_drought_raw, state.no_carriage_miss_raw)
    if kind == "ai_skip":
        return
    state.no_carriage_stations += 1
    state.max_drought = max(state.max_drought, state.no_carriage_stations)


def _station(state: RunState, rng: random.Random, strat: Strategy) -> None:
    state.stations_visited += 1

    if state.crystal >= 1 and any(
        c.function == "medical" or c.template_id == "medical" for c in state.cars
    ):
        # 有医疗车即可配催化（sim：不强制当日 pharmacist 已赋值，日环会填）
        n = int(state.crystal)
        state.crystal -= n
        state.potion_catalyst = min(10.0, state.potion_catalyst + n * 2)

    if not state.tutorial_done and 3 <= state.day <= 8:
        state.cars.append(Car("living", 2, None, 10, 0, 0, 1.0))
        state.parts = max(0, state.parts - 1)
        state.cars_hung += 1
        state.peak_cars = max(state.peak_cars, state.car_count())
        state.tutorial_done = True
        state.no_carriage_stations = 0
        state.no_carriage_miss_raw = 0
        return

    rolled_offer = rng.random() < POOL_OFFER_CHANCE
    guarantee_forced = False
    found = rolled_offer
    if not found:
        if state.no_carriage_stations >= GUARANTEE_AFTER:
            found = True
            guarantee_forced = True
        else:
            _miss_carriage(state, "no_offer")
            return

    car = _pick_car(state, rng, strat)
    repair = _car_repair_cost(car)
    if guarantee_forced:
        repair = min(repair, max(1, int(state.parts)))
    # 保守留零件缓冲；扩张油紧时也对高耗车加缓冲
    buffer = 0 if strat.prefer_carriage else 2
    if car.function in ("greenhouse", "water") or state.starve_food_days > 0:
        buffer = 0
    elif car.is_locomotive:
        buffer = 0  # 立刻挂第二动力（燃料墙）
    elif not strat.prefer_carriage and state.onboard() < 10:
        buffer = 1
    fuel_fill = state.fuel / max(1.0, state.fuel_cap())
    if fuel_fill < 0.28 and car.fuel_per_day >= 2.0:
        _miss_carriage(state, "ai_skip")
        return
    # 扩张挂车节流：油紧拒装甲；≥12 节只放行货/动力/刚需产能与年2冲床
    if strat.prefer_carriage and fuel_fill < 0.55:
        if car.template_id == "armor" and state.body >= 48:
            _miss_carriage(state, "ai_skip")
            return
        if state.car_count() >= 12:
            y_now = year_of(state.day)
            need_live = (
                car.template_id == "living"
                and y_now >= 2
                and state.beds() < 20
            )
            allow = (
                car.is_locomotive
                or car.template_id == "cargo"
                or car.function in ("greenhouse", "water")
                or need_live
            )
            if not allow:
                _miss_carriage(state, "ai_skip")
                return
        elif (
            state.car_count() >= 10
            and car.template_id in ("radar", "workshop")
            and state.body >= 55
        ):
            _miss_carriage(state, "ai_skip")
            return
    # 保守：预留零件给第二动力；扩张靠上面油门槛挡装甲
    locos = sum(1 for c in state.cars if c.is_locomotive)
    if (
        not strat.prefer_carriage
        and locos < 2
        and car.template_id in ("armor", "radar", "workshop")
        and state.parts < repair + buffer + 5
    ):
        _miss_carriage(state, "ai_skip")
        return
    if state.parts >= repair + buffer:
        state.parts -= repair
        state.cars.append(car)
        state.cars_hung += 1
        state.peak_cars = max(state.peak_cars, state.car_count())
        state.no_carriage_stations = 0
        state.no_carriage_miss_raw = 0
    else:
        _miss_carriage(state, "unaffordable")
    _maybe_abandon_at_station(state, strat)


def greenhouse_target(pop: int) -> int:
    """按需求估种植节数，但不超过可派 grower 人数（留 eng/guard/purifier）。"""
    need = pop * 0.9 * 1.25
    labor_cap = max(1, pop - 3)  # 至少留动力/守卫/净水各 1
    best_n, best_out = 1, 0.0
    for n in range(1, min(13, labor_cap + 1)):
        out = n * GREENHOUSE_DAY * 0.90 ** max(0, n - 2) * HEATING_MULT
        if out >= need:
            return n
        if out > best_out:
            best_n, best_out = n, out
    return min(best_n, labor_cap)


def _pick_car(state: RunState, rng: random.Random, strat: Strategy) -> Car:
    pop = state.onboard()
    season = season_of(state.day)
    fuel_fill = state.fuel / max(1.0, state.fuel_cap())
    gh = sum(1 for c in state.cars if c.function == "greenhouse")
    wc = sum(1 for c in state.cars if c.function == "water")
    cargo_n = sum(1 for c in state.cars if c.template_id == "cargo")
    locos = sum(1 for c in state.cars if c.is_locomotive)
    food_supply = gh * GREENHOUSE_DAY * 0.90 ** max(0, gh - 2) * 0.95 * year_prod(state.day)
    water_supply = wc * 10 * 0.90 ** max(0, wc - 2) * year_prod(state.day)
    food_need = food_consume(state)
    water_need = water_consume(state)
    food_gap = food_need - food_supply
    water_gap = water_need - water_supply

    y = year_of(state.day)
    # 第二动力（硬条件）与货厢油容并重：无货厢且秋储期可插一节货
    if (
        cargo_n < 1
        and season == "autumn"
        and fuel_fill < 0.70
        and not want_second_loco(state, strat)
    ):
        return Car("cargo", 3, None, 10, 0, 0, 1.0)
    if want_second_loco(state, strat):
        return Car("power", 3, None, 20, 20, 0, 0.0)
    # 冲床：扩张年1 夏末起挂休息车；油紧且床已≥14 时让路给油容/动力
    if state.beds() < beds_target(state, strat):
        living_day = 60 if strat.risk >= 0.5 else 70
        defer_living = fuel_fill < 0.45 and state.beds() >= 14 and y == 1
        if not defer_living and (y >= 2 or (y == 1 and state.day >= living_day)):
            return Car("living", 2, None, 10, 0, 0, 1.0)
    if fuel_fill < 0.38 and state.car_count() >= 9:
        # 油紧：货厢油容优先于第三节动力
        if cargo_n < 3:
            return Car("cargo", 3, None, 10, 0, 0, 1.0)
        if locos < 3 and state.power_tech >= 1 and state.car_count() >= 14:
            return Car("power", 3, None, 20, 20, 0, 0.0)
    # 至少 1 净水 + 1 种植，避免纯水车饿死
    if wc < 1:
        return Car("water", 2, "water", 10, 0, 100, 1.0)
    if gh < 1:
        return Car("greenhouse", 2, "greenhouse", 10, 0, 100, 1.0)
    if (season == "summer" or state.climate.heat >= 0.5 or water_gap > food_gap) and wc < 2:
        return Car("water", 2, "water", 10, 0, 100, 1.0)
    if season == "summer" and (water_gap > 0 or state.climate.heat >= 0.5) and wc < 3:
        return Car("water", 2, "water", 10, 0, 100, 1.0)
    # 扩张油紧：多种植=多供暖，gh≥2 且油&lt;0.45 时不再加种植
    gh_block = strat.risk >= 0.5 and fuel_fill < 0.45 and gh >= 2
    if gh < greenhouse_target(pop) and food_gap > 0 and not gh_block:
        return Car("greenhouse", 2, "greenhouse", 10, 0, 100, 1.0)
    if state.crystal >= 1 and not any(
        c.function == "medical" or c.template_id == "medical" for c in state.cars
    ):
        return Car("medical", 2, "medical", 10, 0, 0, 1.0)
    if season == "autumn" and cargo_n < 3:
        return Car("cargo", 3, None, 10, 0, 0, 1.0)
    if season in ("autumn", "summer") and cargo_n < 2:
        return Car("cargo", 3, None, 10, 0, 0, 1.0)
    # 扩张油紧优先货厢油容
    if strat.risk >= 0.5 and fuel_fill < 0.50 and cargo_n < 3:
        return Car("cargo", 3, None, 10, 0, 0, 1.0)
    if water_gap > food_gap and wc < 3:
        return Car("water", 2, "water", 10, 0, 100, 1.0)
    if gh < greenhouse_target(pop) and food_gap / max(1.0, food_need) >= water_gap / max(1.0, water_need):
        return Car("greenhouse", 2, "greenhouse", 10, 0, 100, 1.0)
    if water_gap > 0 and wc < 3:
        return Car("water", 2, "water", 10, 0, 100, 1.0)
    if (
        state.body < 55
        and armor_cars(state) < 1
        and fuel_fill >= 0.55
        and state.car_count() < 14
    ):
        return Car("armor", 4, None, 80, 0, 0, 2.0)
    if not any(c.template_id == "radar" for c in state.cars) and y >= 1 and state.day > 60:
        return Car("radar", 2, None, 10, 0, 0, 1.0)
    if pop < pop_soft_cap(state) and state.beds() <= pop and not (season == "autumn" and y == 1):
        return Car("living", 2, None, 10, 0, 0, 1.0)
    if not any(c.function == "workshop" for c in state.cars):
        return Car("workshop", 3, "workshop", 20, 0, 60, 1.0)

    roll = rng.random()
    if roll < 0.18:
        return Car("living", 2, None, 10, 0, 0, 1.0)
    if roll < 0.40:
        return Car("cargo", 3, None, 10, 0, 0, 1.0)
    if roll < 0.58:
        return Car("greenhouse", 2, "greenhouse", 10, 0, 100, 1.0)
    if roll < 0.72:
        return Car("water", 2, "water", 10, 0, 100, 1.0)
    if roll < 0.84:
        return Car("workshop", 3, "workshop", 20, 0, 60, 1.0)
    if roll < 0.93:
        return Car("power", 3, None, 20, 20, 0, 0.0)
    if fuel_fill >= 0.60 and state.car_count() < 12:
        return Car("armor", 4, None, 80, 0, 0, 2.0)
    return Car("cargo", 3, None, 10, 0, 0, 1.0)


def run_one(seed: int, strat: Strategy, max_day: int = 240) -> RunState:
    rng = random.Random(seed)
    state = RunState()
    start_region_run(state, rng, force_id="urban")
    _build_segment(state, rng)
    recompute_climate(state)
    while state.day <= max_day and not state.failed:
        apply_day(state, rng, strat)
    return state


STRATS = [
    Strategy("conservative", prefer_carriage=False, prefer_power_tech=True, accept_recruit=True, risk=0.3),
    Strategy("expansion", prefer_carriage=True, prefer_power_tech=True, accept_recruit=True, risk=0.7),
]
