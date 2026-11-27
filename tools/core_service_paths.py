#!/usr/bin/env python3
"""Paths (under client/scripts/) treated as core Service for doc enrichment."""
from __future__ import annotations

# Keep sorted by layer: app → gameplay → economy → rhythm → content → domain → data
CORE_SERVICE_PATHS: list[str] = [
    "app/game_session.gd",
    "app/intent_bus.gd",
    "gameplay/combat_l1.gd",
    "gameplay/drive_service.gd",
    "gameplay/event_service.gd",
    "gameplay/haul_service.gd",
    "gameplay/inventory_service.gd",
    "gameplay/loot_pile_service.gd",
    "gameplay/point_encounter_service.gd",
    "gameplay/region_service.gd",
    "gameplay/search_rules.gd",
    "gameplay/search_service.gd",
    "gameplay/segment_build.gd",
    "gameplay/station_defer_service.gd",
    "gameplay/station_service.gd",
    "gameplay/tech_service.gd",
    "gameplay/train_service.gd",
    "economy/day_settle.gd",
    "economy/fuel_f04.gd",
    "economy/population_consumption.gd",
    "rhythm/calendar.gd",
    "rhythm/climate_service.gd",
    "rhythm/game_clock.gd",
    "rhythm/weather_draw.gd",
    "content/event_catalog.gd",
    "content/event_draw.gd",
    "content/event_ops.gd",
    "domain/member_roster.gd",
    "domain/run_state.gd",
    "data/config_db.gd",
    "data/save_schema.gd",
    "data/save_service.gd",
]