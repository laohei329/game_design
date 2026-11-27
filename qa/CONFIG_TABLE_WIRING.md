# 配置表 ↔ 客户端接线清单

> 自动生成基线：`configVersion` 25 · 对照 `data/manifest.json`  
> 校验：`python sim/validate_config_db.py --stage s2` · Godot：`SmokeAssertions.M1_REQUIRE_PATHS`

## 已接（运行时 `ConfigDb` / `LocaleDb`）

| manifest 键 | 建议入口 | 典型路径 |
|-------------|----------|----------|
| `balance` | `DaySettle`, `FuelF04`, `Calendar`, `GameSession`, `SearchRules`, `HaulService`, `ClimateService`, `TechService`, `TrainService` | `balance.fuel.base`, `balance.start.*`, `balance.greenhouse.*`, `balance.search.*`, `balance.haul.*` |
| `stations` | `StationService`, `RegionService` | `stations.guaranteeAfter`（权威）；镜像 `balance.stations.*` |
| `carriages` | `TrainService`, `FuelF04`, `StationService` | `carriages.templates.*.fuelPerDayAdd` |
| `regions` | `RegionService` | `regions.regions.<id>` |
| `point_types` | `SearchService`, `RegionService` | `point_types.types.*` |
| `weather` | `WeatherDraw`, `ClimateService` | `weather.weathers` |
| `climate_influences` | `WeatherDraw` | `climate_influences.presets` |
| `upgrades` | `TechService`, `tech_panel` | `upgrades.lines` |
| `combat` | `CombatL1`, `PointEncounterService` | `combat.l1Unit`, `combat.l1Success`, `combat.searchEncounter` |
| `combat_targets` | `CombatL1` | `combat_targets.targets` |
| `hud_hints` | `StationService`, `StationDeferService` | `hud_hints.*` |
| `events_index` | `EventCatalog` | 索引；单卡 `res://data/events/**/*.json` |
| `event_draw_rules` | `EventDraw` | 池权重 |
| `localization_*` | `LocaleDb` / `LocaleApi` | `data/localization/*.csv` |
| `archetypes` | **`MemberRoster`**（`startPartyTemplate` + `namePools`） | `archetypes.startPartyTemplate.members` |

## 未接 / 待分期（数据在盘，玩法未读）

| manifest 键 | 建议接入 Service | 典型 `require` / `get_table` |
|-------------|-------------------|-------------------------------|
| `gear` | `CombatL1`（`power_p` / 战损） | `gear.types.ranged.rangedBonus` 等 |
| `abilities` | 战前页 / `MemberRoster` 觉醒 | `abilities.abilities[]`, `abilities.maxAwakenedPerRun` |
| `disease` | 新 `DiseaseService` 或 `DaySettle` 尾步 | `disease.streakThreshold`, `disease.treatment.defaultDays` |
| `items` | `InventoryService.stock_cap` / 药剂 | `items.potions`, `items.coreSix` |
| `equipment` | `TrainService` 挂车、`DaySettle` 产出加成 | `equipment.equipment.<id>.foodWaterBonus` → 对齐 `balance.equip.*` |
| `difficulty` | `GameSession._new_run` | `difficulty.defaultId`, `difficulty.tiers.<id>` |
| `combat_objectives` | `CombatL1` / 战斗 UI | `combat_objectives.objectives[].locKey` → `LocaleApi` |
| `combat_trauma` | 战后 `MemberRoster` | `combat_trauma.tags` |
| `combat_adaptation` | P2+ 批次三 | 占位，禁止运行时默认启用 |
| `migrations_manifest` | `SaveService` 链 | 契约已由 `save_schema.gd` + `migrations/v*.gd` 实现 |

## 刻意双通道

- **事件文案**：机制 `events/**/*.json`；五语 `events_*.csv` + `sync_event_locale.py import`
- **区域名**：`regions.json` 内 `{en,zh,…}` → `LocaleApi.from_locale_block`

## 本地工具

```powershell
python tools/audit_locale_keys.py --write   # → qa/locale-key-audit.md
```