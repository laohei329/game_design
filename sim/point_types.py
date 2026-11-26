"""Canonical point types (data/point_types.json) and regions (data/regions.json)."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]

_CLIMATE_PRESETS: Optional[Dict[str, Dict[str, Any]]] = None

_POINT_TYPES: Optional[Dict[str, Dict[str, Any]]] = None
_POOL_MULT: float = 2.5
_SEASON_WEIGHT_MODS: Dict[str, Dict[str, float]] = {}
_REGIONS: Optional[Dict[str, Dict[str, Any]]] = None
_STATIONS: Optional[Dict[str, Any]] = None
_SEASON_PRESSURE: Optional[Dict[str, float]] = None
_YEAR_THREAT_PER: Optional[float] = None
_WEATHER_ENGINE: Optional[Dict[str, Tuple[float, float, float, float, Tuple[int, ...]]]] = None
_WEATHER_SWEEP: Optional[Dict[str, Dict[str, Any]]] = None
_WEATHER_RAW: Optional[Dict[str, Dict[str, Any]]] = None


def _read_json(name: str) -> dict:
    path = ROOT / "data" / name
    if not path.is_file():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def load_point_types() -> Dict[str, Dict[str, Any]]:
    global _POINT_TYPES, _POOL_MULT, _SEASON_WEIGHT_MODS
    if _POINT_TYPES is not None:
        return _POINT_TYPES
    data = _read_json("point_types.json")
    _POOL_MULT = float(data.get("poolMultiplier", 2.5))
    _SEASON_WEIGHT_MODS = dict(
        data.get("seasonWeightMods", data.get("seasonYieldMods", {}))
    )
    _POINT_TYPES = dict(data.get("types", {}))
    return _POINT_TYPES


def pool_multiplier() -> float:
    load_point_types()
    return _POOL_MULT


def season_weight_mods() -> Dict[str, Dict[str, float]]:
    load_point_types()
    return _SEASON_WEIGHT_MODS


def season_yield_mods() -> Dict[str, Dict[str, float]]:
    """Deprecated alias — multiplies spawn weights only, not pile yield."""
    return season_weight_mods()


def pool_type_ids(*, include_sweep_only: bool = False) -> List[str]:
    types = load_point_types()
    out: List[str] = []
    for tid, meta in types.items():
        if not meta.get("inPool", True):
            continue
        if meta.get("sweepOnly") and not include_sweep_only:
            continue
        out.append(tid)
    return out


def load_climate_presets() -> Dict[str, Dict[str, Any]]:
    global _CLIMATE_PRESETS
    if _CLIMATE_PRESETS is not None:
        return _CLIMATE_PRESETS
    data = _read_json("climate_influences.json")
    _CLIMATE_PRESETS = dict(data.get("presets", {}))
    return _CLIMATE_PRESETS


def load_regions() -> Dict[str, Dict[str, Any]]:
    global _REGIONS
    if _REGIONS is not None:
        return _REGIONS
    data = _read_json("regions.json")
    presets = load_climate_presets()
    catalog: Dict[str, Dict[str, Any]] = {}
    for rid, row in data.get("regions", {}).items():
        inf_id = row.get("climateInfluenceId", f"region.{rid}")
        preset = presets.get(inf_id, {})
        catalog[rid] = {
            "fuel_mult": float(row.get("regionFuelMult", 1.0)),
            "temp": float(preset.get("tempMod", row.get("tempMod", 0.0))),
            "mods": dict(row.get("pointTypeWeightMods", {})),
            "bias": dict(preset.get("weatherBias", {})),
            "pressure": float(preset.get("pressureAdd", 0.0)),
        }
    _REGIONS = catalog
    return catalog


def region_ids() -> List[str]:
    return list(load_regions().keys())


def load_stations_config() -> Dict[str, Any]:
    global _STATIONS
    if _STATIONS is not None:
        return _STATIONS
    data = _read_json("stations.json")
    if not data:
        raise RuntimeError("data/stations.json missing")
    _STATIONS = data
    return data


def station_count_choice_weights() -> Tuple[List[int], List[float]]:
    w = load_stations_config().get("stationCountWeights", {"0": 0.35, "1": 0.45, "2": 0.2})
    keys = sorted(int(k) for k in w.keys())
    return keys, [float(w[str(k)]) for k in keys]


def load_season_pressure() -> Dict[str, float]:
    global _SEASON_PRESSURE
    if _SEASON_PRESSURE is not None:
        return _SEASON_PRESSURE
    data = _read_json("balance.json")
    raw = data.get("seasonPressure") or {
        "spring": 1.0,
        "summer": 1.2,
        "autumn": 0.8,
        "winter": 1.5,
    }
    _SEASON_PRESSURE = {str(k): float(v) for k, v in raw.items()}
    return _SEASON_PRESSURE


def year_threat_multiplier(year: int) -> float:
    global _YEAR_THREAT_PER
    if _YEAR_THREAT_PER is None:
        data = _read_json("balance.json")
        _YEAR_THREAT_PER = float(data.get("yearThreatPerYear", 0.15))
    return 1.0 + _YEAR_THREAT_PER * max(0, year - 1)


def load_weather_raw() -> Dict[str, Dict[str, Any]]:
    global _WEATHER_RAW
    if _WEATHER_RAW is not None:
        return _WEATHER_RAW
    data = _read_json("weather.json")
    _WEATHER_RAW = dict(data.get("weathers", {}))
    return _WEATHER_RAW


def load_weather_engine() -> Dict[str, Tuple[float, float, float, float, Tuple[int, ...]]]:
    """engine.py：`id → (tempMod, waterMod, speedClimate, nodeFuelMod, weights×5)`。"""
    global _WEATHER_ENGINE
    if _WEATHER_ENGINE is not None:
        return _WEATHER_ENGINE
    catalog: Dict[str, Tuple[float, float, float, float, Tuple[int, ...]]] = {}
    for wid, w in load_weather_raw().items():
        raw_w = [int(x) for x in w.get("weightBySeason", [0, 0, 0, 0, 0])]
        while len(raw_w) < 5:
            raw_w.append(0)
        catalog[wid] = (
            float(w.get("tempMod", 0.0)),
            float(w.get("waterMod", 1.0)),
            float(w.get("speedClimate", 1.0)),
            float(w.get("nodeFuelMod", 1.0)),
            tuple(raw_w[:5]),
        )
    if not catalog:
        raise RuntimeError("data/weather.json: missing or empty weathers")
    _WEATHER_ENGINE = catalog
    return catalog


def load_weather_sweep() -> Dict[str, Dict[str, Any]]:
    """run_time_event_sweep：`id → {temp, water, speed, vision, pressure, node, w}`。"""
    global _WEATHER_SWEEP
    if _WEATHER_SWEEP is not None:
        return _WEATHER_SWEEP
    catalog: Dict[str, Dict[str, Any]] = {}
    for wid, w in load_weather_raw().items():
        weights = [float(x) for x in w.get("weightBySeason", [0, 0, 0, 0, 0])]
        while len(weights) < 5:
            weights.append(0.0)
        catalog[wid] = {
            "temp": float(w.get("tempMod", 0.0)),
            "water": float(w.get("waterMod", 1.0)),
            "speed": float(w.get("speedClimate", 1.0)),
            "vision": float(w.get("visibilityMult", 1.0)),
            "pressure": float(w.get("weatherPressure", 0.0)),
            "node": dict(w.get("nodeWeightMods", {})),
            "w": weights[:5],
        }
    if not catalog:
        raise RuntimeError("data/weather.json: missing or empty weathers")
    _WEATHER_SWEEP = catalog
    return catalog


def weather_point_mods(weather_id: str) -> Dict[str, float]:
    """weather.json nodeWeightMods + nodeFuelMod → per canonical type multiplier."""
    w = load_weather_raw().get(weather_id, {})
    node_mods = dict(w.get("nodeWeightMods", {}))
    fuel_mod = float(w.get("nodeFuelMod", 1.0))
    types = load_point_types()
    per_type: Dict[str, float] = {}
    for tid, meta in types.items():
        m = 1.0
        key = meta.get("weightModKey")
        if key == "fuel":
            m *= fuel_mod
        elif key and key in node_mods:
            m *= float(node_mods[key])
        per_type[tid] = m
    return per_type


def compute_type_weights(
    *,
    season: str,
    region_id: str,
    point_mods: Dict[str, float],
    weather_id: str,
    radar_tech: int = 0,
    include_sweep_only: bool = False,
    horde_weather_boost: bool = False,
) -> Dict[str, float]:
    types = load_point_types()
    season_mods = season_yield_mods().get(season, {})
    w_mods = weather_point_mods(weather_id)
    weights: Dict[str, float] = {}
    for tid, meta in types.items():
        if not meta.get("inPool", True):
            if include_sweep_only and meta.get("sweepOnly"):
                pass
            else:
                continue
        if meta.get("sweepOnly") and not include_sweep_only:
            continue
        if meta.get("militaryOnly") and region_id != "military":
            continue
        value = float(meta.get("baseWeight", 0.0))
        if value <= 0:
            continue
        value *= float(point_mods.get(tid, 1.0))
        sim_yield = str(meta.get("simYield", tid))
        value *= float(season_mods.get(sim_yield, 1.0))
        value *= float(w_mods.get(tid, 1.0))
        if tid == "horde" and horde_weather_boost and weather_id in {
            "night_rain",
            "blizzard",
            "fog",
        }:
            value *= max(0.60, 1.0 - 0.08 * radar_tech)
        weights[tid] = max(0.0, value)
    return weights


def sim_yield_for(ptype: str) -> str:
    meta = load_point_types()[ptype]
    return str(meta.get("simYield", ptype))


def normalized_weights(weights: Dict[str, float]) -> Tuple[List[str], List[float]]:
    keys = list(weights.keys())
    vals = [weights[k] for k in keys]
    total = sum(vals)
    if total <= 0:
        uniform = 1.0 / len(keys) if keys else 1.0
        return keys, [uniform] * len(keys)
    return keys, [v / total for v in vals]