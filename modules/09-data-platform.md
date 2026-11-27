# 模块：数据 · 存档 · 埋点 · MOD

> 所属层：数据层  
> 原则：数值不硬编码；配置与存档结构版本分离

---

## 1. 配置目录

```
/data
  carriages.json / stations.json / upgrades.json / regions.json / point_types.json
  equipment.json / gear.json / abilities.json / events/*.json / archetypes.json / balance.json / combat.json
  items.json / combat-objectives.json / combat-targets.json
  combat-trauma.json / combat-adaptation.json / disease.json
  difficulty.json / weather.json / climate_influences.json
  manifest.json / localization/*.csv
  migrations/*.js   ← 仅官方，MOD 不得提供可执行迁移
```

**落盘状态**：上列 P1 战斗/人口/本地化表 **已落**（见 `data/P1_README.md`）；`migrations/*.js` **S1b 客户端**；MOD 脚本 **不做**。

`weather.json`：**已落** [`data/weather.json`](../data/weather.json)；天气 id、`weightBySeason`、`tempMod`、`waterMod`、`speedClimate`、`visibilityMult`、`weatherPressure`、`nodeWeightMods`（见 [01](01-time-season.md) §7）；**sim 权威来源**（`engine` / `sweep` 经 `point_types.load_weather_*`）。  
`incidents.json` / `stress.json`：**段叙事主表**（[06-incident-migration](06-incident-migration.md)）。  
`events/_index.json`：**Legacy** · 登记在 `manifest.legacyFiles`（Godot `files` 不载）；索引 [`archive/events-legacy/README.md`](../archive/events-legacy/README.md)。冻结新卡；`useLegacyEventCards` / `loadLegacyEventCatalog` 控制读盘。  
`hud_hints.json`：**已落** [`data/hud_hints.json`](../data/hud_hints.json)；TIPS/进站 defer 阈值（不改 balance）。  
`climate_influences.json`：**已落** [`data/climate_influences.json`](../data/climate_influences.json)；区域预设 `presets["region.*"]`（`tempMod`、`weatherBias`、`waterMod`、`speedMult`、`pressureAdd`；见 01 §4）。  
`difficulty.json`：**已落** [`data/difficulty.json`](../data/difficulty.json)；首发仅 `normal` 一档（见下表）。  
`time` 日历键：`secondsPerDay=180`，`daysPerSeason=30`，`seasonsPerYear=4`，`driveHoursPerDayCap`，`metabolismMultByIntent.{stop|forward|reverse}`，`outdoorWorkRequiresIntent`（日钟见 [01 §2.3](01-time-season.md)）。  
`balance` / 库存：核心六元 + `scrap`/`seed`/`chem`/`cloth` + `potion.awaken`/`upgrade`/`catalyst`；转换式见 [02](02-resources.md)。  
`abilities.json`：`costCatalyst` / `costMedicine`（不再用 raw crystal 字段）。  
`archetypes.json`：成员原型含 `specialties[]`（0–2）与默认 `job` 倾向。  
岗位枚举：`grower|crafter|purifier|pharmacist|radar_op|engineer|guard|labor|none`（[04 §4.2](04-population.md)；无 `medic`）。  
专长枚举：`scavenge|repair|medicine|pharmacy|farming|haul|combat_drill`。  
`balance.power.unattendedFaultChance=0.10`。  
`manifest.json`：当前 `configVersion` 见仓库 [`data/manifest.json`](../data/manifest.json)（**实体 30**，2026-11-27）。改配置必须递增；十项模拟闸阈仍记 config25（[10 §1.1](10-validation.md)）；`dataHash` 由构建生成。全库对齐：`python tools/sync_config_version.py`。  
`balance.json`：**已落** [`data/balance.json`](../data/balance.json)，与 [10 §1.1](10-validation.md) 对齐。  
**P1 包（S1b）已落**：[`combat.json`](../data/combat.json)、[`gear.json`](../data/gear.json)、[`abilities.json`](../data/abilities.json)、[`archetypes.json`](../data/archetypes.json)、[`disease.json`](../data/disease.json)、[`items.json`](../data/items.json)、`combat-*.json`、`localization/*.csv`、`migrations/manifest.json` — 清单见 [`data/P1_README.md`](../data/P1_README.md)。  
存档迁移 **实现**仍在 Godot `client/scripts/data/migrations/`（见 [GODOT_ARCH](GODOT_ARCH.md)）；禁止一次交全空壳以外的未文档化表。  
`weather.json`：`ash_haze.nodeWeightMods.medicine_point = 1.15`（与 01 §7.1 对齐）。  
`equipment.json`：**已落** [`data/equipment.json`](../data/equipment.json)；主设备 id 与 [03 §3.4](03-train.md) 表一致。  
`regions.json`：每词条 `regionFuelMult` + `pointTypeWeightMods`（[06 §1.2](06-region-events.md)）。  
`point_types.json`：点位 type 基权、中值、库存主键与 `simYield`（[02 §7](02-resources.md)）。  
存档须含（交叉闭环最小集）：
- 日历：`year` / `season` / `dayInSeason` / `dayTotal`
- 气候：`weatherId`、`climateInfluences[]`、派生倍率缓存可重算但建议存
- `RegionRun` 全量：`segmentIndex`/`segmentCount`/`regionFuelMult`/`pointTypeWeightMods`/`segments[]`（每段含 `progressKm`、`stations[]`（含 offer）、`points[{id,type,remainingYield,depleted,lootPile?}]`、`eventId`、`eventResolved`、`eventOptionId`、`built`、`segmentFuelSurcharge`、`raidWeightDelta`、`eventTagWeights`（tag→delta；`raid` 须与 `raidWeightDelta` 镜像）、`pressureClass`）
- `world.pressureHistory[2]`（跨跨度保留）
- 日结：`foodZeroStreak`/`waterZeroStreak`/`fuelZeroStreak`/`moraleZeroStreak`
- 日钟（`runtime`）：`dayClockFraction`、`simDayFractionToday`、`outdoorEligibleFractionToday`、`outdoorTickFractionToday`、`foodAppliedToday`/`waterAppliedToday`、`breakdownStopHoursRemaining`（缺键旧档按 0；完整写盘经 `SaveService.write_state`）
- 行驶：`driveHoursToday`/`reverseHoursToday`；`driveIntent`；`train.breakdownCounter`
- 编队：`formations[]`（≤4）、`activeFormationId`
- 科技资格：`train.blueprints.{power,armor,radar,living}`（布尔；Lv4/5 只读；与 `upgrades.json` `lines` 一致）
- 收留：`world.lastRecruitSuccessDay`
- 成员：`members[]` 须含 `hunger`/`thirst`（float 0–100；缺键读档 `patch_members` 补 0）及 §4 其余字段
- 失护：`unattendedFault[]`（含 `carId`、`startedAtDayTotal`、解除截止）
- 种植供暖：`world.heatingEnabled`（默认 `false`，见 01 §8.1.1；入冬提示开关）
- 战斗中：`combatSession?`（结构见 [05 §6.2](05-combat.md)；无会话则禁止残留 `in_combat`）

**配置键归属（正文已引用，须进对应 json）**：

| 键 | 文件 | 基线 | 权威模块 |
|---|---|---|---|
| `greenhouse.seedConsumePerRackDay` | balance.json | 0.05 | 02 §3 |
| `greenhouse.heatingFuelPerCarDay` | balance.json | 0.30（百分点/节/日） | 01 §8.1.1 |
| `greenhouse.heatingMult` | balance.json | 0.95（无供暖 0.50） | 01 §8.1.1 |
| `fuel.craftFuelPerDay` | balance.json | 0.5（百分点） | 02 §3.2 |
| `balance.crystalHiddenChance` | balance.json | **0.09** | 02 §3.1 |
| `balance.power.unattendedFaultChance` | balance.json | 0.10 | 04 §4.7 |
| `combat.l1Unit` | combat.json | 8 | 05 §6.1 |
| `combat.combatEnduranceP` / `combatEnduranceE` | combat.json | 1.0 | 05 §7 |
| `time.driveHoursPerDayCap` | balance.json `time.*` | **1.0** | 03 §6.2 |
| `stations.tutorialForcePointTypes` | stations.json | `supermarket`,`water_plant` | 06 §0.1 |
| `point_types.seasonWeightMods` | point_types.json | 见 01 §6 | 06 §3 |
| `ability.proficiencyPerSuccess` | balance.json | 20 | 04 §8.1 |
| `ability.proficiencyPerFail` | balance.json | 5 | 04 §8.1 |
| `ability.proficiencyThreshold` | balance.json | 60 | 04 §8.1 |
| `population.injuredHpThreshold` / `mood*` / `morale*` | balance.json | 30 / 0–100 / −60·±13·16 | 04 §9 · DaySettle · EventOps |
| `population.jobAssignLaborKeepMin` | balance.json | 2 | 日末 `MemberRoster.assign_daily_jobs` |
| `population.moodDaily*` | balance.json | 见 sim `morale_settle` | `MemberMorale.settle_daily_moods`（`DaySettle` 7b） |
| `fuelTank.baseAmount` / `perCargoSize` | balance.json | 60 / 10 | `RunState.fuel_cap` |
| `stations.segmentLengthMin/Max` | stations.json | 40 / 60 | 06 §0 |
| `stations.guaranteeAfter` | stations.json | 4 | 03 §5 |
| `stations.emptyChance` | stations.json | 0.10 | 06 §1.1 |
| `stations.nonePoolChance` | stations.json | 0.08 | 06 §1.1 |
| `stations.spurChance` | stations.json | 0.35 | 06 §1.4 |
| `stations.spurLengthKmMin/Max` | stations.json | 12 / 24 | 06 §1.4 |
| `regions.*.spurChanceMult` | regions.json | 缺省 1.0；military/mine 1.25 | 06 §1.4 |
| `stations.tutorialRegion` | stations.json | urban | 06 §0.1 |
| `stations.stationCountWeights` | stations.json | p0/p1/p2=0.35/0.45/0.20 | 06 §1.1 |
| `train.abandonPartsCost` | balance.json | 1 | 03 §4.1 |
| `train.abandonScrapRatio` | balance.json | 0.35 | 03 §4.1 |
| `train.abandonFuelCostPct` | balance.json | 0.01 | 03 §4.1 |
| `train.abandonAiFuelFillMax` | balance.json | 0.35（仅 sim AI） | 03 §4.1 |
| `train.abandonAiMinCars` | balance.json | 12（仅 sim AI） | 03 §4.1 |
| `workshop.precisionStart` | balance.json | **40** | 03 §7 |
| `workshop.precisionPerCraftDay` | balance.json | +1 | 03 §7 |
| `workshop.precisionIdleDecay` | balance.json | −1 | 03 §7 |
| `workshop.partsPerPrecision` | balance.json | 300（日产=precision/300） | 02 §3.2 / 03 §7 |
| `upgrades.*.cost` | upgrades.json | 见 03 §7 表 | 03 §7 |
| `upgrades.precisionGate` | upgrades.json | Lv1..5 = 20/40/60/80/100 | 03 §7 |
| `start.water` / `start.food` | balance.json | 24 / 20 | 02 §10 |
| `radar.visionBase` | balance.json | 1 | 03 §7 |
| `radar.visionPerStaffedCar` | balance.json | 1 | 03 §7 |
| `radar.visionPerLevel` | balance.json | 1 | 03 §7 |
| `radar.threatMitigationPerLevel` | balance.json | 0.08（地板 0.60） | 03 §7 |
| `equip.cargo_rack.foodWaterBonus` | equipment.json | 8 | 02 §6 |
| `regions.*.regionFuelMult` | regions.json | 缺省 1.0；tundra 1.3 | 06 §1.2 / 02 §4 |
| `regions.*.pointTypeWeightMods` | regions.json | 见 06 §1.2 | 06 §1.2 |
| `climate_influences.presets` | climate_influences.json | 见 01 §4.4 | 01 §4 |
| `difficulty.defaultId` | difficulty.json | `normal` | 本节 |
| `difficulty.tiers.normal` | difficulty.json | 乘子全 1.0；`eventDrawRate` × `balance.eventDraw.scenarioEventRate` | 本节 |
| `balance.seasonPressure` | balance.json | 春1/夏1.2/秋0.8/冬1.5 | 01 §6 |
| `balance.yearThreatPerYear` | balance.json | 0.15 | 01 §6 |
| `balance.inventory.*` | balance.json | S1a 库存上限基线 + 货舱增量 | 02 §6 |
| `balance.fuelTank.*` | balance.json | S1a 油库绝对容量 | 02 §6 / 客户端薄模型 |
| `balance.travel.*` | balance.json | 走廊速度 `corridorMult`× tactical | 03 §6.2 |
| `balance.eventDraw.scenarioEventRate` | balance.json | 段事件加权全局乘子（难度档未接前 1.0） | 06 §2.3 |
| `combat.threatTemplateAliases` | combat.json | 卡内/遭遇模板 id → `combat-targets` | 05 §6 |
| `stations.*` | **stations.json**（权威） | sim 进站/区段 | 06 §1 / 03 §5 |
| `balance.stations.*` | balance.json | **仅镜像** `guaranteeAfter` 等；须与 stations.json 一致 | 交叉校验 |
| `stations.poolOfferChance` | stations.json | 0.9（零 A sim） | 03 §5 |

---

## 2. 两套版本号

| 字段 | 职责 |
|---|---|
| `configVersion` / `dataHash` | 内容配置兼容；不一致 → 可载入，标自定义，不计标准成就；**不**跑结构迁移 |
| `version.save` | 存档结构；当前 **12**；过低走官方迁移链 |

迁移链：`v2_to_v3` → … → `v9_to_v10`（供暖）→ `v10_to_v11`（返程/抛锚/压力史）→ **`v11_to_v12`（编队/图纸/点位/战斗会话）**。

`v4_to_v5`：旧 `type` → `attrs` + `templateId`；`function` 用 JSON null；有工坊则 `precision` 缺省 **40**（与 [03 §7](03-train.md) / `workshop.precisionStart` 对齐；**禁止**再默认 60）；删除 `research.active.daysLeft`。  
装备：若仍有 `weaponKits`，迁移为 `gear.ranged += n`，`gear.melee += ⌊n/2⌋`，`gear.defense += ⌊n/3⌋`，再删 `weaponKits`。  
`v5_to_v6`：库存补 `potion.*` 键（缺省 0）；异能消耗字段 `cost`/`crystal` → `costCatalyst`；旧存档若曾「直接吞晶核觉醒」保持已有异能，不补药剂。  
`v6_to_v7`：成员 `skill`（标量）→ `specialties[]`（0–1 元素）；`job` 非法旧值映射到闭合枚举（未知 → `none`）；补 `combatRoster` 与 `job=guard` 一致性（guard → roster true）。  
`v7_to_v8`：`job=medic` → `pharmacist`；医疗槽互斥字段删除。  
`v8_to_v9`：补 `world.regionRun` / `segments[]` 缺省骨架；`foodZeroStreak`/`waterZeroStreak`/`fuelZeroStreak`/`moraleZeroStreak`；`reverseHoursToday=0`；`world.lastRecruitSuccessDay=-1`；动力 `unattendedFault[]`（无时间戳则视为当日触发）；成员 `abilities[]` 缺 `proficiency` 则补 **0**；缺 `activeFormationId` 则指向第一套编队；缺 `weatherId`/`climateInfluences` 则按当前段重跑一次 `recomputeClimate`（**不**重抽天气：无 `weatherId` 时用季节表抽一次并写入，仅迁移兜底）。  
`v9_to_v10`：补 `world.heatingEnabled = false`（默认关，与 01 §8.1.1 一致）；粮仓上限 40→60 只对后续入库生效，不追溯截断已存粮。  
`v10_to_v11`：补 `world.pressureHistory = [null, null]`；`train.breakdownCounter = 0`；成员 `abilities[]` 缺 `cooldownUntilDay` → **0**；已有 `precision` 值保留（含历史误迁为 60 的旧档，**不**强制改 40——仅缺省路径用 40）。  
`v11_to_v12`：补 `formations[]`/`activeFormationId`（缺则按名册生成默认编队）；`train.blueprints` 四键 `power|armor|radar|living` 缺省 `false`（若存在废弃键 `life` → 迁至 `living` 后删 `life`）；`driveIntent=stop`；`regionRun.regionFuelMult`（按当前 `regionId` 回填，未知则 1.0）与空 `pointTypeWeightMods{}`；各段 `points[]` 缺字段则按 type 中值×2.5 补 `remainingYield`；`raidWeightDelta=0`；`combatSession=null` 并清除成员残留 `in_combat`→`idle`。  
**S1b 写档**：`train.abandonCount` 缺省 **0**（[§3.1](#31-遗弃车厢carriages-变更与埋点样例)；未升 `version.save` 前由客户端缺省补键）。

---

## 3. 存档

仅本地：Windows `%LOCALAPPDATA%\DoomsdayTrain\saves\` 等。  
自动 5 槽 / 手动 20 / 铁人单槽。手动必须暂停。  
原子写 `.tmp` → fsync → rename；CRC；一代 `.bak`。

必须持久化（漏一项读档即漂移）：

| 域 | 字段 |
|---|---|
| 列车 | `carriages[]`、`bodyHp`、`breakdownCounter`、`abandonCount`（本局遗弃次数，默认 0）、四线科技等级、`blueprints{power,armor,radar,living}`、`precision`、瞬时速度、`driveIntent` |
| 编队 | `formations[]`（≤4；slots/reserve）、`activeFormationId` |
| 车站发现 | 每站 `entered`、当前车厢要约 offer、`guaranteeFailStreak` |
| 成员 | `hp/loyalty/mood/disease/antibodies/traits` + job/task/injuries/abilities(`id,lv,proficiency,cooldownUntilDay`)/loadout/combatRoster |
| 任务 | `taskState` + payload（pointId、进度 0–1、returningEta 游戏小时）；搬运单（物资快照） |
| 世界 | `lootPiles[]`（扁平 `[{pointId, inventoryKey, amount}]`；**空数组表示清堆**）、`regionRun`（见 [§1 交叉闭环](#1-配置目录) 段字段）、`pressureHistory[2]`、`weatherId`、`climateInfluences[]`、`lastRecruitSuccessDay`（**−1**=从未）、`pendingThreat`（见下）、`heatingEnabled`、日历、行驶小时、各 ZeroStreak、`moraleOffset`、`eventWeightHistory[]`、`lastEventPrimaryTag` |

#### 3.0.1 `world.pendingThreat` · 段 `eventTagWeights`

| 字段 | 语义 | 读写 |
|---|---|---|
| `world.pendingThreat` | 延迟开战：`{ threatTemplateId, source?, eventId?, pointId? }`；由 `spawn_threat`（前进）或事件 immediate 写入 | **入盘**；`SET_DRIVE_INTENT stop` / 日结前 `CombatL1.try_open_pending_threat` **消费**（清空并入战斗 encounter）；与 `pendingCombat`、面板旗标**不入盘** |
| `segment.eventTagWeights` | `eventTag` → 累加 delta（`weight_mod` op）；驱动 `EventDraw` 按卡 `tags` 加权 | **入盘**于 `regionRun.segments[]` |
| `segment.raidWeightDelta` | **镜像**：`eventTag=raid` 的累加结果；旧档仅 `raidWeightDelta` 时读档补 `eventTagWeights.raid` | 写盘时**双写**；`EventOps.weight_mod` 须同步（见上表 `weight_mod` 行） |
| 战斗 | `combatSession?`（[05 §6.2](05-combat.md)）；**不入盘**：`pendingCombat`、面板旗标 |
| 其它 | RNG；`eventFlags`；`delayedEvents[]`（步骤 −1；payload 见下表）；动力失护（起止日） |

`delayedEvents.payload` 最小字段：`{ targetType: member\|party\|point\|segment\|global, targetId?, op, args, capture: snapshot\|live }`。  
- `op` = 延迟动作代号（下表）；≠ 运算符。  
- `capture=snapshot`：按**写入时快照**结算；`live`：按**触发时活目标**结算（≠存档备份、≠直播）。  
同一 `id+fireOnDay` 只执行一次（去重保留先写入者）。

**`op` 枚举与目标失效（权威）**：

| op | 典型 target | snapshot | live 且目标失效 |
|---|---|---|---|
| `grant_item` / `remove_item` | global / member | `amount` **须为正**；扣库存只用 `remove_item` | 跳过 |
| `recruit_roll` | global | `args:{ p }` 当日收留检定；失败不写 `member` | 跳过 |
| `mood_delta` / `loyalty_delta` | member / **party** | member：对人结算，死人跳过；party：对**全体存活成员**各应用 delta | member 失效 → 跳过 |
| `injury_add` / `disease_roll` | member | 死人跳过 | 同左 |
| `spawn_threat` | segment / global | `args:{ threatTemplateId }`；段已离开本跨度 → 对已卸载 segment 跳过 | 段不在当前 RegionRun → 跳过 |
| `weight_mod` | segment | `args:{ eventTag, delta }`；累加 `segment.eventTagWeights[eventTag]`；`eventTag=raid` 时同步 `raidWeightDelta`；段已卸载 → 跳过 | 同左 |
| `loot_steal` / `loot_halve` | **point**（`targetId`=点位 id）或 segment（`loot_halve` 扫本段点位） | 点位堆已空 → 无操作成功；**不**凭 snapshot 变出新堆 | 堆不存在 → 跳过 |
| `grant_influence` / `clear_influence` | global | 按快照 id 写入/清除后 `recomputeClimate` | influence 已过期且 live → 跳过 |
| `flag_set` | global | 总是可写 | 同左 |
| `offer_clear` | segment | 清该段站**车厢要约** | 段不在 → 跳过 |

成员死亡：**任何** `capture` 均不得复活或回写已删 `memberId`。跨段返程后延迟事件仍可打本跨度内 segment/point；**跨度结束后**指向旧 segment 的 live 事件跳过。

驶离区段**不得**丢弃 lootPiles。`built=true`（已 onSegmentBuild）段读档**禁止**重抽天气/事件。  
车站车厢要约：**跨度结束清除**；段间前进不清（[03 §5](03-train.md) / [06 §0](06-region-events.md)）。

**车站车厢要约的「完好/受损/残骸」必须存**（挂车前的发现态）。  
**首发不持久化**（正文尚无消费规则）：已加挂车厢的逐格 `damageState` 战场层、`tacticalHistory`。禁止提前写入空字段。

### 3.1 遗弃车厢：`carriages[]` 变更与埋点样例

规则权威：[03 §4.1](03-train.md)。实现：`ABANDON_CARRIAGE`（[GODOT_ARCH §4.2](GODOT_ARCH.md)）。  
**存档**：从 `train.carriages[]` **按 `id` 删除整对象**；禁止留 tombstone、禁止把脱钩节写入 `lootPiles`。同时更新库存、`train.abandonCount++`、清理指向该 `carId` 的 `unattendedFault[]` 条目（若有）。

**遗弃前**（片段，`dayTotal=47`，停靠进站后）：

```json
{
  "dayTotal": 47,
  "parts": 6,
  "scrap": 3,
  "fuel": 82.4,
  "train": {
    "driveIntent": "stop",
    "abandonCount": 0,
    "carriages": [
      { "id": "car_pwr", "templateId": "power", "size": 3, "armor": 20, "speedBonus": 20 },
      { "id": "car_liv", "templateId": "living", "size": 2, "armor": 10 },
      { "id": "car_cgo", "templateId": "cargo", "size": 3, "armor": 10 },
      { "id": "car_arm", "templateId": "armor", "size": 2, "armor": 85, "equipment": [{ "id": "armor_frame", "slot": 0 }] }
    ]
  }
}
```

**`ABANDON_CARRIAGE` 确认后（遗弃 `car_arm`）** — 同槽存档应变为：

```json
{
  "dayTotal": 47,
  "parts": 5,
  "scrap": 4,
  "fuel": 81.2,
  "train": {
    "driveIntent": "stop",
    "abandonCount": 1,
    "carriages": [
      { "id": "car_pwr", "templateId": "power", "size": 3, "armor": 20, "speedBonus": 20 },
      { "id": "car_liv", "templateId": "living", "size": 2, "armor": 10 },
      { "id": "car_cgo", "templateId": "cargo", "size": 3, "armor": 10 }
    ]
  }
}
```

上例数值：`parts 6→5`（`train.abandonPartsCost=1`）；`scrap 3→4`（`repairCost(armor)=5`，`⌊5×0.35⌋=1`）；`fuel` 扣 `fuel_cap×0.01`（F04 切割油，见 03 §4.1）。**不**改 `guaranteeFailStreak`（与拒挂 offer 无关）。

**运营埋点 `carriage_abandon`**（写本地分析日志或日后上报；**不必**整段持久化进存档，但 SaveService 可在写档前刷一条）：

```json
{
  "event": "carriage_abandon",
  "dayTotal": 47,
  "carId": "car_arm",
  "templateId": "armor",
  "carsAfter": 3,
  "fuelFill": 0.31,
  "partsSpent": 1,
  "scrapGranted": 1,
  "fuelSpent": 1.2,
  "driveIntent": "stop",
  "stationContext": true
}
```

`fuelFill` / `carsAfter` 为 **遗弃结算后** 快照（与 03 埋点说明一致）。`stationContext=true` 表示发生在进站停靠流程内（便于与途中停靠区分，字段可选）。

**读档约束**：`carId` 在 `members[].carId`、编队引用、进行中任务里若仍指向已删 id → **迁移/校验失败**，须拒绝载入并打日志（实现侧 Guard）。

---

## 4. 运营埋点

`run_start` / `day_pass` / `station_enter` / `carriage_found` / `carriage_add` / `carriage_abandon` / `station_choice` / `member_death` / `upgrade_buy` / `combat_*` / `ability_proc`（异能每次判定，含失败）/ `combat_burst_proc`（`combat_drill` 爆发每次判定）/ `job_assign` / `relation_change` / `carriage_blocked` / `run_end`

禁止混用旧名 `skill_proc`。Steam 侧看 Demo 转化与首周评论增速；愿望单仅参考。

### 4.2 开发遥测草案（S1a · 本地 JSONL）

实现：`client/scripts/data/telemetry_service.gd` → `user://telemetry.jsonl`（一行一事件）。**非**成就/元进度；可关选项后置。

| event | 用途 | 建议字段 |
|---|---|---|
| `carriage_abandon` | 03 §4.1 · Item 对照 | `dayTotal`, `carId`, `templateId`, `carsAfter`, `fuelFill`, `partsSpent`, `scrapGranted`, `fuelSpent`, `driveIntent`, `stationContext` |
| `search_assign` | **10 §1 #7** 单点搜索次数 | `dayTotal`, `pointId`, `memberCount`, `searchesOnPointToday`, `cap`（基线 3） |
| `offer_defer_shown` | 08 defer UI | `reasonCode`, `tipId`, `offerTemplateId`, `fuelFill` |

读档后 **不**回放 telemetry；分析按文件或零 B 导出。

---

## 4.1 元进度存档（跨局）

路径：`%LOCALAPPDATA%\DoomsdayTrain\meta.json`（与单局 `saves/` 分列）。  
字段：`codex.members[]` / `codex.lastWords[]` / `codex.events[]` / `codex.carriages[]` / `stats{km,daysLived,deathCauses…}`。  
**只读收集**（[07 §2](07-endings-meta.md)）；禁止写入属性加成或解锁数值成长（红线 #11）。  
`version.meta` 独立递增；与 `version.save` 无关。

---

## 5. MOD

首发：新增事件/车厢/词条/成员包；覆盖 balance 标自定义。  
不开放逻辑脚本（默认）。架构必须在系统阶段预留（红线 #10）。
