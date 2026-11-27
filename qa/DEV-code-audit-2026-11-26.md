# Godot 客户端 · 代码层审计（2026-11-26 · S2 刷新）

> 范围：**接线、可编译性、自动化冒烟、S2 事件链、已知缺陷与债务**；不含数值手感与 30 日真人试玩。  
> 自动化：`powershell tools/run_all_smoke.ps1` → **PASS**（含 15 日 probe · `save_kill` · 区域/科技/战斗/事件/op/读档弹窗）

---

## 1. 工程规模

| 项 | 值 |
|----|-----|
| GDScript | ≈62 个 `client/scripts/**/*.gd`（含 Intent 三域 · 冒烟分片；续审 [R2](DEV-code-audit-2026-11-26-r2.md)） |
| 主场景 | `run_main.tscn` + `event_modal.tscn` |
| Autoload | ConfigDb · **LocaleDb** · Rng · Telemetry · Save · IntentBus · GameSession |
| QA | `headless_smoke` · `headless_save_kill` · `errors_event_*` · `soft_lock_probe` |

---

## 2. Intent 矩阵（§12.9）

| Intent | 处理方 | 状态 |
|--------|--------|------|
| S1a 全线（日结/驾驶/进站/搜索/遗弃/存读） | `SessionIntentRouter` → 三域 + 服务 | **已** |
| `PICK_REGION` / 科技四线 | `RegionService` · `TechService` | **已**（薄） |
| 战斗 L1 五条 | `CombatL1` · `combat_panel` | **部分**（L2 未接） |
| `CHOOSE_EVENT_OPTION` | `EventOps` | **已** |
| 点位遭遇 | `PointEncounterService` ← `ASSIGN_SEARCH` | **已**（概率薄配置） |

未接线 Intent：一律 `push_warning("unhandled")`（`game_session.gd` → `SessionIntentRouter`）。详见 [GODOT_ARCH §4.4](../modules/GODOT_ARCH.md)。

---

## 3. 核心模块（摘要）

| 模块 | 状态 | 备注 |
|------|------|------|
| `event_catalog` / `event_draw` / `event_ops` / `event_service` / `event_modal` | **部分** | 120 卡可抽；加权抽卡为 sim 子集；见 §5 |
| `point_encounter_service` | **部分** | `combat.searchEncounter`；同点同日一次 |
| `combat_l1` | **部分** | `open_from_template`；L2/L3 无 |
| `region_service` + `region_pick` | **部分** | `EventDraw.on_segment_build`；教程前不抽 |
| `save_schema` | **部分** | v12：`eventResolved`/`eventOptionId`/`delayedEvents`(含 snapshot)/`eventWeightHistory` |
| `day_settle` | **部分** | `EventOps.process_due_delayed_events`；6–8 仍薄 |
| `locale_db` | **部分** | `tr_key`+TranslationServer；**禁止**定义 `func tr()`（与 `Object.tr` 冲突） |
| `train_service.reconcile_outdoor_tasks` | **已** | 日结后清孤立 `taskState` |

证据：`qa/DEV-S2-01-event-modal.md` · `qa/DEV-S2-02-event-ops.md` · `qa/DEV-M3-04-combat-l1.md`

---

## 4. 自动化

| 套件 | 覆盖 |
|------|------|
| `run_all_smoke.ps1` | … · 三选一 · 科技 · L1 · **事件+点位遭遇** · **op 全量烟测** · **未决读档弹窗** · **snapshot 空堆** · **日钟 runtime 存读（槽 93）** · `errors_outdoor_day_clock_p0_a` |
| `run_save_kill_smoke.ps1` | 双进程槽 92 |

---

## 4.1 日钟 · 饥渴 · 户外（2026-11-26 加厚）

| 组件 | 状态 | 备注 |
|------|------|------|
| `GameSession._process` | **已** | `day_delta` chunk；`sim_time_frozen()`；饥渴 emit 0.25s 节流 |
| `PopulationConsumption` | **已** | tick + `reconcile_day_end`；`runtime.foodAppliedToday` |
| `GameClock` outdoor | **已** | eligible−tick；冒烟 P0-A |
| `SaveService` / `runtime` | **已** | 半日续玩；**须** `write_state`（非裸 `to_save_dict`） |
| `END_DAY` | **已** | `_force_end_game_day`（无头日结仍全） |
| `DriveService` 抛锚 | **薄** | 8b → 2 游戏小时 `breakdown_stop_hours_remaining` |
| DaySettle 4–8 | **批量** | 见 [02 §8](modules/02-resources.md) S1b 声明 |
| sim 逐人饥渴 | **无** | 见 [10 §1](modules/10-validation.md) |

---

## 5. 发现项（按严重性）

### P1 — 设计对齐但实现不完整

| 项 | 说明 |
|----|------|
| ~~`weight_mod.args.eventTag`~~ | **已修**：`Segment.eventTagWeights` + `EventDraw` 按卡 tags 累加 |
| ~~延迟 `spawn_threat`~~ | **已修**：`pending_threat` 入档；`SET_DRIVE_INTENT stop` / 日结前 `try_open_pending_threat` |
| `recruit_roll` | 薄：`try_recruit_one` 杂工占位，无 sim 岗位/特技 |
| `event_draw` 上下文 | 未接药师/守卫当班、`forced_low_content`、点堆未领loot 等 sim 加权因子 |

### P2 — 可维护性 / 噪声

| 项 | 说明 |
|----|------|
| ~~ConfigDb 启动~~ | **已修**：CSV 登记 `_localeCsv` 占位，由 `LocaleDb` 专载 |
| ~~`event_modal` 文案~~ | **已修**：`LocaleDb.from_locale_block` |
| ~~`event_draw._weight_for_card`~~ | **已修**：`ctx.get(...)` |
| `SoftLockProbe` | 审计前 `HaulService.recall_haul` 为探测方便，**非**玩法规则 |

### P3 — 当前卡牌未触达（09 表有、卡池无）

`loyalty_delta` · `injury_add` · `disease_roll` · `loot_steal` · `offer_clear` — 卡 JSON 中**未出现**；`EventOps` 遇未知 `op` → `push_warning` + `unknown_op`。

### 已通过 / 低风险

- 卡牌在用 `op` 集合与 `KNOWN_OPS` **一致**（grep 全事件库）。
- 段内事件：`event_resolved` + `event_option_id` 防重开；`event_modal_open` 不入盘；`sync_after_load` 恢复未决。
- `capture=snapshot`：入 `snapshot`；触发时空堆不还原（09）；`sourceEventId@fireOnDay` 去重。
- 存档：`delayedEvents` · `climateInfluences` · segment `eventId` 随 `regionRun` 持久化。

---

## 6. 建议下一步（代码）

1. ~~DEV-S2-03 eventTag / pending_threat / ConfigDb CSV / event_modal~~ — **2026-11-26 已落地**，冒烟含 tag 权重与前进入队开战。
2. sim 子集加权因子（药师/守卫、`forced_low_content`）仍缺。
3. 未实现 op（`loyalty_delta` 等）遇卡即用才需补。

---

## 7. 修订链

| 文档 | 同步 |
|------|------|
| `开发计划.md` §14.1 表「`event_*`」 | 本审计后应标 **部分** |
| `qa/DEV-functional-checklist.md` | 待人工补 S2/J 条 |
| 上次审计 | 同日早版（S2 未接）；本版覆盖 S2 薄切片 |
| **续审 R2** | [DEV-code-audit-2026-11-26-r2.md](DEV-code-audit-2026-11-26-r2.md)（Intent 拆分 · 库存 · 冒烟 · §8 勘误） |

---

## 8. 硬编码 · 表/存档格式 · 逻辑（原 Pass 2）

> 聚焦：硬编码、表/存档一致性、与 09/06/sim 偏差。Locale 键：`tools/audit_locale_keys.py` **OK**。

### 8.1 硬编码（违反「数值进表」或易漂移）

| 严重 | 位置 | 现状 | 建议 |
|------|------|------|------|
| ~~P1~~ | `inventory_service.gd` | ~~`BASE` 硬编码~~ | **已接** `balance.inventory`（2026-11-26 清债） |
| ~~P1~~ | `run_state.fuel_cap()` | ~~fallback~~ | **已接** `PopulationRules` → `balance.fuelTank.*`（2026-11-26） |
| ~~P1~~ | `drive_service.travel_speed_kmh` | ~~写死~~ | **已接** `balance.travel.{corridorMult,tacticalBaseKmh,tacticalDivisor}`（2026-11-26 续审） |
| ~~P2~~ | `event_draw._build_ctx` | ~~scenario 固定~~ | **已接** `scenario_event_rate()` × difficulty；**已补** sim 子集（药师/守卫/loot/raid/低压/低油） |
| ~~P2~~ | `event_ops` / `day_settle` / 搜索搬运 | ~~硬编码~~ | **已接** `PopulationRules` + `balance.population.*` |
| **P2** | `game_session._new_run` | 三节车 id/模板写死数组 | 未来读 `balance.start.carriages` 或 `carriages.json` 开局包 |
| **P2** | `member_roster.START_CAR_IDS` | 与 `_new_run` 车厢 id 双份维护 | 合并单一来源 |
| **P3** | `combat_l1.THREAT_ALIAS` | `horde_small`/`rotter` → 真实 id | **数据侧**修好模板 id；别名仅兜底（见 §8.2.3） |
| **P3** | `tech_service` | `stageZeroSmokeMaxLv` 在 `upgrades.json` | 命名像冒烟专用却参与正式升级上限，宜改名或分表 |

**相对规范**：`SearchRules`、`day_settle` 步骤 4–8 大部分用 `ConfigDb.require` — 方向正确。

### 8.2 表数据与存储格式一致性

#### 8.2.1 ConfigDb 与 manifest

| 项 | 状态 |
|----|------|
| JSON 表 | `manifest.files` → `tables[name]` 对象根 |
| CSV 表 | 跳过 JSON 解析；**LocaleDb** + **LocaleApi** 专载 |
| Python sim `ConfigDb` | CSV 入 `_csv_tables`；Godot 不解析 CSV 行 — **双端语义不同但均不报错** |
| 静默降级 | 多处 `get_table(...).get(key, default)` **不** `require` → 缺表时行为与策划表脱节 |

#### 8.2.2 存档 `save v12` vs 09 §3

| 字段 | 09 / 设计 | 客户端 `SaveSchema` | 一致性 |
|------|-----------|---------------------|--------|
| 段 `raidWeightDelta` | 要 | 有 | **部分**：与 `eventTagWeights` 双轨（见 §8.3） |
| 段 `eventTagWeights` | 未写进 09 正文 | **有**（S2-03） | **超前**：文档须补 |
| `world.pendingThreat` | 无（sim 内存） | **有** | 客户端扩展，合理 |
| `world.lastRecruitSuccessDay` | **要**（06 §2.2 日结补抽） | **有** | **OK**（R2 复核） |
| `world.lootPiles[]` | 一致 | OK | OK |
| 读档 `lootPiles` | 权威覆盖段内堆 | `apply_world_list` 先 `_clear_all_piles` | **OK**（R2 复核） |

#### 8.2.3 战斗模板 id、`data/` 双份树

- `combat.searchEncounter` 中 `hospital` → `rotter` 不在 `combat-targets.json`（宜改表或补行）。
- `client/data` 与仓库 `data/` 需 junction/CI diff（冒烟未校验）。

### 8.3 逻辑问题（摘要）

| 严重 | 问题 |
|------|------|
| **P1** | `raidWeightDelta` ↔ `eventTagWeights.raid` 双轨（镜像在 `SaveSchema`/Segment，09 文档仍缺） |
| **P2** | `PointEncounterService` horde 硬分支；`try_open_pending_threat` 与模态叠层 |
| **P3** | `event_draw` 与 sim 加权因子不全 |

### 8.4 建议优先级

1. 09 §3 补字段与 `raid` tag 镜像规则。  
2. 数据：`rotter` / `combat.threatTemplateAliases` 表化。  
3. ~~存档：`lastRecruitSuccessDay`；空 `lootPiles` 清堆~~ — **已关**（R2）；缺省库存统一 `balance.start` 仍可选。  
4. 配置债：库存、走廊速度、`scenario_event_rate`、轻伤阈值 → `balance.json`。  
5. CI：`validate_data_ci.py`；`data/` ↔ `client/data/`。