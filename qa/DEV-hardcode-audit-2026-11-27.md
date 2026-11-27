# 硬编码专项审计（2026-11-27）

> 依据：`modules/GODOT_ARCH.md` §2.1 · 第三轮审计 E-4/E-10 · `BalanceStart` 单点。  
> 方法：`client/scripts/**/*.gd` 与 `sim/*.py` 对照 `data/*.json`。（自动化 runner 已于 2026-11-27 移除。）

## 1. 已闭合（本轮修复）

| 区域 | 原问题 | 处理 |
|---|---|---|
| `population_consumption.gd` | `reconcile_day_end` 12/18/8/15 | `balance.population.reconcile*` |
| 同上 | `tick` 中 `* 12.0`、口渴扣血 `* 0.6` | `tickPartialShortfallPenalty` / `thirstStarvingHpLossFraction` |
| `search_service.gd` | `poolMultiplier` 默认 2.5 | `point_types.poolMultiplier` |
| 同上 | 队效 `0.9 + 0.02n` | `balance.search.teamEffBase` / `teamEffPerMember` |
| `point_encounter_service.gd` | 遭遇率/模板 `default` 0.18 / shambler | `combat.searchEncounter.*` + `ConfigDb.has` 分型 |
| `station_service.gd` | `poolOfferChance`/`emptyChance`/`conditionWeights` 字面默认 | `stations.*` require |
| `manifest` vs `balance` | CV 27/28 分裂 | 实体 **29** + `tools/sync_config_version.py` |
| H-1 | `region_service.gd` 压力档 0.25/0.7 | `event_draw_rules.pressureClassRoll.*` |
| H-2 | `combat_l1.gd` l1Success/nonCombat 默认值 | `combat.*` ConfigDb.require + `negotiateMoodBonus` |
| H-3 | `search_service.gd` median/jitter/hoursTotal | `point_types.fallbackMedian` · `balance.search.yieldJitter*` · `SearchRules.hours_per_task()` |
| H-4 | `train_service.gd` repair 默认 5 | `carriages.repairParts.{template}` / `default` |
| H-5 | `climate_service.gd` weather 默回退 | `weather.weathers.{id}` / `clear` require |
| H-6 | `event_ops.gd` recruit/loot 默认 | `balance.eventOps.defaultRecruitRollP` / `defaultLootHalveRatio` |
| H-7 | `sim/engine.py` 搜索产出乘子 | `balance.search.yieldMult*` · `scavengeSkillDivisor` · jitter |

| U1 | `combat_l1` layerRouting/l1Fail/moodCombatWinL1 | `combat.*` require；`l1Fail.injuryHpLoss` 补表 |
| U1 | `region_service` 段长 / nonePool / 教程修理 | `stations.*` require |
| U1 | `station_service` fuelPerDayAdd / size / offer | `carriages.templates.*` require |
| U1b | `train_service` 床位 `size*2` 默认 | `carriages.livingBedsPerSize` · `techBedsPerLivingLevel` · `carriage_size()` |
| U2-R3 | `event_draw.gd` 权重 `.get` 兜底 | `_rule_f` / `_rule_dict` → `event_draw_rules.*` require |
| U2-R1 | `region_service` 段/点/站距/权重 | `stations.*` 新键 · `point_types.types.*.baseWeight` |
| U2-R2 | `day_settle` 三连零 / 故障停驶 | `balance.population.fuelZeroStreakFail` 等 · `PopulationRules` |
| U2-R4 | `haul_service` | `balance.haul.haulSpecialtyMult` · `hoursPerTask` 回退 |
| U2-R5 | `combat_l1` · `station_defer` | `combat.formationMaxSlots` · `tpl.layerDefault` · `hud_hints.fuelFill.highBurnFuelPerDayMin` |

## 2. 多轮扫描（2026-11-27 晚 · R1–R7）

**方法**：`python tools/scan_hardcode_gd.py`（启发式，扫 `gameplay/` `economy/` `rhythm/` `content/` `domain/`）；人工对照 `data/*.json` 与 `modules/GODOT_ARCH.md` §0。

| 轮 | 范围 | 命中 | 建议动作 | 优先级 |
|---|---|---:|---|---|
| **R0** | H-1…H-7 · U1 · U1b | — | 已闭（§1） | — |
| **R1** | `region_service.gd` 程序化 | 0 | **已闭**（U2-R1） | — |
| **R2** | `day_settle.gd` 三连零 / 故障 | 0 | **已闭**（U2-R2） | — |
| **R3** | `event_draw.gd` 权重 | 0 | **已闭**（U2-R3） | — |
| **R4** | `haul_service.gd` | 0 | **已闭**（U2-R4） | — |
| **R5** | 战斗 / 进站 UI | 0 | **已闭**（U2-R5） | — |
| **R6** | `sim/engine.py` 模块顶常数 | 40+ | 对照 `balance.json` 已 H-7 部分；余 `SEASON_LEN`、开局量、供暖、segment 等 **sim-only** — 见 [RF-11](RF-11.md)，非 client 闸 | 低（parity） |
| **R7** | 存档 / 实体缺省 | 多 | `save_schema` · `hp/mood` get 默认 · `segment.lengthKm` 50 — **可接受**（09 迁移语义） | 接受 |

**说明**：`fuel_f04.gd` 的 `tpl.get("fuelPerDayAdd", 0.0)`、`tech_service` 升级行 `.get("parts",0)` 属**行内可选列**，不算 balance 乘子。

## 3. 低优先级 / 可接受

| 类 | 说明 |
|---|---|
| 成员字段 `get(hp,100)`、`get(mood,70)` | 运行时实体缺省，非 balance 乘子 |
| UI / 冒烟探针数值 | 无头 qa 脚本目录已删 |
| `clampf(..., 0, 100)` | 饥渴 0–100 域，与规格一致 |
| `third_party/` | 与玩法配置无关 |

## 4. 纪律检查

- **开局**：`BalanceStart` + `RunState` 零默认 ✓  
- **人口日耗**：`PopulationConsumption` → `balance.population.*` require ✓（`reconcile_day_end` + `tick` 短缺口已配置化）  
- **跨端**：见 [RF-11.md](RF-11.md)；搜索 jitter/乘子 sim 已读 `balance.search`（H-7）  

## 5. 复核

```bash
python tools/sync_config_version.py
python tools/check_doc_consistency.py
python tools/smoke_config.py   # 含 stress_sweep
python tools/stress_sweep.py
python tools/scan_hardcode_gd.py   # 多轮硬编码启发式（§2 R1–R7）
```

**收口顺序建议**：R1–R5 **已完成**（U2）；下一批 **R6**（sim parity）或收紧 `station_defer` / `event_draw` 难度表 `.get`。