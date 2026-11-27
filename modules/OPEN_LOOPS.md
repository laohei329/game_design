# 未闭环总账 · 剩余风险（v1.3.33）

> 人做 / 可玩构建项搁置。**里程碑验收**：[MILESTONES](MILESTONES.md)。客户端：[GODOT_ARCH](GODOT_ARCH.md)。提示：[08 §4](08-presentation.md)。验收全文：[10](10-validation.md)。

---

## 1. 缺口总览（L）

| ID | 缺口 | 状态 | 备注 |
|---|---|---|---|
| L1 | 零 B 真人填表 | **包就绪 · 场次搁置** | [10 §2](10-validation.md) |
| L2 | 零 A 5/6/7 | **部分** | **#6 已过**（config25）；#5 drought、#7 搜索均值埋点仍 **~** |
| L3 | 第 9/10 手算 | **文档齐 · 签字搁置** | [10 §1.2](10-validation.md) |
| L4 | balance.json | **已关** | |
| L5 | STAGE1 data | **已扩** | manifest 全表 + events ready |
| L6 | 提示进游戏 | **暂缓·先不用** | 表在 [08 §4](08-presentation.md)；不挡 S1 |
| L7 | 规格标注 | **已关** | |
| L8 | 30 日可玩 | **搁置** | 计划在 GODOT_ARCH §9–10 |
| L9 | 故意开口 | **有意不关** | 定居点等 |
| **L10** | **事件卡 → Incident** | **进行中** | [06-incident-migration.md](06-incident-migration.md)；默认自发开；**待** [30 日手签](../qa/DEV-incident-30d-signoff.md) |

---

## 2. 设计剩余风险

> **命名**：本节 **DR1–DR7** = 设计/工程风险账；**勿与** [08 §4](08-presentation.md) 玩家软规则 **R1–R6**（油紧/挂车/遗弃等）混读。

| # | 严重度 | 议题 | 建议 |
|---|---|---|---|
| **DR1** | **已裁定** | Item6 vs 油紧节流 | [10 §1](10-validation.md) config25 阈：pop20/beds20，不要求 hungΔ15% |
| **DR2** | 高 | 客户端切片未完 | `client/` **S0 骨架**已落；S1a 可玩/UI 仍 [GODOT_ARCH §9–10](GODOT_ARCH.md) |
| DR3 | 低 | 事件文案 | **五语 CSV 管线**（`sync_event_locale`）；高亮卡继续手改 CSV/JSON |
| DR4 | 中 | spur 仅配置 | S2 实现 |
| DR5 | 低 | combat/abilities **P1 表已落** | 客户端加载 + S1b L1 验收 |
| DR6 | 低 | SEASON_BASE_TEMP 硬编码 | 可进 balance |
| DR7 | 低 | 手算未签字 | 主策再签 |
| **DR8** | **部分** | 120 卡与自发双轨 | 冻结新卡 · 默认 incident；legacy 开关+`legacyFiles` 对照 |

**总判**：设计债（D/O）已清；堵在 **DR2（S1a 可玩切片）** 与 L1/L8。

冒烟基线 K（**config 25** · 闸已对齐）：存活 **46%/**48%**（≥40%），pop≥20 **23%/**32%**（#8 过），燃料失败 **71%/**69%**（参考），四线 **YES**，Item6 **PASS**（新口径）。

---

## 3. 明确不做（直至有构建/真人）

- 开零 B 场次、填问卷  
- 实现游戏内 TIPS UI（L6）  
- 催手算签字  
- 解冻 ×1.40 / F04、或为对齐冒烟/新玩法改 balance 乘子（见 [10 §1.1](10-validation.md)）  

---

## 4. 建议优先级

1. Godot 工程 S0 → S1a（[GODOT_ARCH](GODOT_ARCH.md)）  
2. Godot **S1b** 30 日（DR1 已裁定，见 10 §1 config25 阈）  
3. 零 B → 事件文案精修  

---

## 5. 重新审计追加（2026-11-26）

基线：设计 v1.3.33 / 执行规格 v1.52 / 实体 **`configVersion` 30**（零 A 闸口径仍记 config25）/ 存档 **`version.save` 12**。  
口径：先查设计与规则逻辑闭环，再登记配置、内容、工程补充项。以下是**新增发现**，不覆盖上文缺口编号。

### 5.1 设计与规则逻辑（优先处理）

| 编号 | 等级 | 需优化或补充 | 证据 | 建议 |
|---|---|---|---|---|
| **A1** | **已关** | 战斗基线威胁标定 | [05 §9](05-combat.md)：`E=P0/(1−0.15×N)` 验收 | |
| **A2** | **已关** | 事件 `op` / `targetType` | [09 §3](09-data-platform.md) + 卡内 `remove_item` | |
| **A3** | **已关** | 教程粮水点位 | [06 §0.1](06-region-events.md) + `stations.tutorialForcePointTypes` + sim | |
| **A4** | **已关** | `moraleOffset` 下限 −60 | [04 §9.2](04-population.md) · [10 §2](10-validation.md) S1 | |
| **A5** | **已关** | Item6 vs 油紧节流（= **DR1**） | [10 §1](10-validation.md) config25 验收阈 | |

### 5.2 配置实体与文档一致性

| 编号 | 等级 | 需优化或补充 | 证据 | 建议 |
|---|---|---|---|---|
| **B1** | **已关** | 开局 `parts/med` | `balance.start` **6/4** 对齐 [02 §10](02-resources.md) | 改数须重跑 zero A |
| **B2** | **已关** | `tech.catalyst` | `[0,0,1,2,3]` 对齐 `upgrades.json` | |
| **B3** | **已关** | 09 键表路径 | `greenhouse.*` / `fuel.*` / `time.*` / `combat.json` / `crystalHiddenChance` | |
| **B4** | **已关** | 配置目录状态 | 09 §1 落盘说明 + P1_README | |
| **B5** | **已关** | `shell` 模板 | [03 §2](03-train.md) 第十种空壳 | |
| **B6** | **已关** | `living.beds` 含义 | [03 §3.2](03-train.md) 预览 vs 设备派生 | |

### 5.3 内容、表现与工程附件

| 编号 | 等级 | 需优化或补充 | 证据 | 建议 |
|---|---|---|---|---|
| **C1** | **已关** | T9 / T10 | [08 §4](08-presentation.md) P1 表 | |
| **C2** | **已关** | **事件五语 120** | `events_{general,season,year}.csv` + `sync_event_locale.py --bucket` | 细调走 CSV；机制仍手改 JSON |
| **C3** | **已关** | 事件 sweep 报告 | 历史报告已删；按需重跑 sweep | |
| **C4** | 低 | 「壳」文案统一 | 03 §1 已用 `templateId`；全库扫尾可后置 | |
| **C5** | **已关** | GODOT_ARCH 排版 | 反斜杠已清 | |
| **C6** | **已关** | `seasonWeightMods` | `point_types.json` + 01 §6 注 | |

### 5.4 本次结论

- 审计 **16 项**中 **15 项已关**；未关：**C4** 命名扫尾。  
- **config25**：主策接受数字 + [10 §1](10-validation.md) 阈值修订（2026-11-26）。  
- 工程类旧缺口（客户端、真人测试、手算签字、30 日可玩）沿用上文 L1–L9。

### 5.5 一致性复检（2026-11-26 · 二轮）

| 主题 | 处理 |
|---|---|
| 键路径 | 02/03/09 统一 `greenhouse.seedConsumePerRackDay`、`time.driveHoursPerDayCap`、`seasonWeightMods` |
| 双表权威 | `upgrades.json` 科技成本；`stations.json` 进站；`balance.stations` 仅镜像 |
| Sim 开局 | `engine` 从 `balance.start` 读粮水零件药；sweep 教程点位读 `tutorialForcePointTypes` |
| 士气下限 | sweep 实现 `morale_offset ≥ −60` |
| 自动校验 | `config_db` 交叉：`start 6/4`、`tech`↔`upgrades`、`stations` 镜像、教程点位 |
| 冒烟数字 | [10 §1](10-validation.md) config25 阈与 AUDIT K 对齐；**#2 #6 #8 过** |

### 5.6 一致性复检（2026-11-26 · 遗弃车厢 + 命名）

| 编号 | 等级 | 主题 | 结论 / 待办 |
|---|---|---|---|
| **D1** | **已修** | **R 编号撞车** | OPEN_LOOPS 风险改 **DR1–DR7**；08 保留玩家 **R1–R6**（R6=甩节） |
| **D2** | 中 | **§4.1 多义** | **03 §4.1**=遗弃；**09 §4.1**=元进度；引用须带模块号 |
| **D3** | 中 | **遗弃 vs 工坊** | 03 已澄清：**不需**在岗 `crafter`；与 §4 首句「改装类」并列，非工坊工位动作 |
| **D4** | 中 | **sim 未全建模** | 无 scrap 入账、无 0.5 日、无成员 `carId`；AI 仅扩张偏置 + 保守≈不甩（油≤0.2975）|
| **D5** | **已关** | **config 校验** | `config_db` 交叉：`balance.train.*` + `hud_hints.abandonCarriage` |
| **D6** | **已裁定** | **冻结数字不再摇参** | **不重写 AUDIT K**；本地 48/62 仅参考。sim 遗弃 AI **不进** config25 冻结基线；乘子/阈 **等开发实测再改**（[10 §1.1](10-validation.md)） |
| **D7** | **已关** | **T1 文案** | T1 已含 R6 甩节；R1 小节标题仍「五条路」（表内 5 行 + T11/R6 扩展） |
| **D8** | 低 | **Item6「资源允许」** | 10 §1 子样本 hung 仍 **可选**；与「不必管资源允许」的产品取向一致，客户端验收时定稿 |
| **D9** | **已关** | **architecture 循环** | [architecture §2](architecture.md) 已写停靠脱钩；[09 §3.1](09-data-platform.md) 存档/埋点样例 |

### 5.7 多轮全面审计（2026-11-26 · 第三轮）

> `config_db` **0 error**；`run_zero_a` 默认种子 **#2/#6/#8 过**（冻结不重写 AUDIT K）。下列为**发现与优化项**，不全关单。

#### A. 命名与引用（高混淆）

| ID | 严重度 | 发现 | 建议 |
|---|---|---|---|
| A7 | **已关** | OPEN_LOOPS 风险 **DR*** | 全库无陈旧 `OPEN_LOOPS R[0-9]` 链（2026-11-26） |
| A8 | 低 | **总判**曾写「堵 DR1」（已裁定） | 已改堵 **DR2** |
| A9 | 低 | **§4.1** 四处不同义（含 **01** 影响因子） | architecture §8.1 已登记；引用带模块前缀 |

#### B. 配置与校验

| ID | 严重度 | 发现 | 建议 |
|---|---|---|---|
| B7 | 低 | `balance.stations` 镜像**未含** `spurChance` 等全键 | 保持「只镜像校验键」策略；扩镜像时同步 config_db |
| B8 | 低 | `hud_hints` **configVersion 25** 与 manifest 一致 | 新增键不强制升版（冻结政策） |
| B9 | **已关** | `hud_hints` 分期 | [GODOT_ARCH §2](GODOT_ARCH.md) S1a 读 defer；TIPS UI S3 |

#### C. Sim ↔ 权威

| ID | 严重度 | 发现 | 建议 |
|---|---|---|---|
| C7 | 中 | 遗弃：**无 scrap、无 0.5 日、无成员 carId**（D4） | 客户端全模；sim 保持简模直至实测解冻 |
| C8 | 低 | 高耗拒挂：`fuel_per_day≥2` vs hud **0.28** 阈值 | 设计一致；sim 与 hud 已对齐 |
| C9 | **部分** | Item7 埋点 | 客户端 `search_assign`（[09 §4.2](09-data-platform.md)）；sim 仍无逐点导出 |
| C10 | 低 | `SEASON_BASE_TEMP` 仍在 `engine.py`（**DR6**） | 进 balance 可选，冻结期不改 |

#### D. 文档自洽

| ID | 严重度 | 发现 | 建议 |
|---|---|---|---|
| D10 | **已关** | 燃料墙 52/55 叙事 | [10 §1](10-validation.md) 标 **历史 v1.3.23**；闸看 config25 |
| D11 | 低 | architecture §7「数值须经零 A 校准」与 §1.1 **已冻结** 语气并存 | 理解为：冻结后改数走解冻，非持续校准 |
| D12 | 低 | **R1 标题「五条路」** vs T1/R6 六手段 | 保留标题；T1 已兜底（D7） |
| D13 | 低 | **C4** 壳/模板文案扫尾仍开 | 内容债，不挡 S0 |

#### E. 工程缺口

| ID | 严重度 | 发现 | 建议 |
|---|---|---|---|
| E1 | **部分** | `client/` | S0 + 日结/日历/气候脚本 + `END_DAY`；无 `run_main`/可点闭环 UI |
| E2 | **部分** | 迁移 GD | `v11_to_v12.gd` + `runtime_save_patch`；全链 S1b |
| E3 | **部分** | `ABANDON_CARRIAGE` | `train_service.gd` + GameSession；缺 UI 确认流 |
| E4 | **已关** | `abandonCount` | SaveService / RuntimeSavePatch 缺省 0（save 12） |

#### F. 优化项（非闸）

| ID | 类型 | 项 |
|---|---|---|
| F1 | **部分** | `station_defer_service.gd` 已读阈值；进站 UI 待接 |
| F2 | **已关** | `telemetry_service.gd` → `user://telemetry.jsonl` |
| F3 | QA | Item6「资源允许」子样本：客户端定稿后再定 |
| F4 | **已关** | 10 §1 #7 链 [09 §4.2](09-data-platform.md) |
| F5 | 叙事 | 新手摘要脱钩（可选） |

### 5.8 审计执行项（2026-11-26 · 按 §5.7 顺序）

| 顺序 | 项 | 状态 |
|---|---|---|
| 1 | S0/S1a 骨架：ConfigDb · Intent · defer · abandon | **已落** `client/` |
| 2 | 遥测 `carriage_abandon` / `search_assign` | **已落** 09 §4.2 + TelemetryService |
| 3 | save 12 `abandonCount` 缺省 | **已落** SaveService + patch |
| 4 | D10 历史燃料闸 · A7 引用扫尾 | **已关** |

### 5.9 日钟多轮审计（2026-11-26 · 闭环债）

基线：**`configVersion=27`**（十项 AUDIT K / Item 规则仍称 config25 见 [10 §1.1](10-validation.md)）。

| 序 | ID | 处理 | 状态 |
|---|---|---|---|
| 1 | S1 | 冒烟 `errors_runtime_day_clock_save_roundtrip`（槽 93） | **已关** |
| 2 | T3 | `_process` → `sim_time_frozen()` | **已关** |
| 3 | T1 | `END_DAY` → `_force_end_game_day` 补 tick 再日界 | **已关** |
| 4 | E1 | 抛锚 `breakdownStopHoursRemaining` + `DriveService.tick_breakdown_stop` | **已关（薄）** |
| 5 | T4 | 饥渴 `state_changed` 0.25s 节流 | **已关** |
| 6 | U1 | 本表 + [archive DEV-code-audit](../archive/qa-history/DEV-code-audit-2026-11-26.md) §7 | **已关** |
| 7 | T2/S3 | `restore` 认 `simDayFractionToday`；SaveSchema 注释写盘路径 | **已关** |

### 5.10 多入口收敛（M1–M7 · 2026-11-26）

| ID | 处理 |
|---|---|
| M1 | 饥渴扣减 → `InventoryService.remove`（food/water） |
| M2 | F04/供暖/科技/遗弃/鸣笛 → `remove(fuel)` |
| M3 | `SaveService.load_into_game_session` + `GameSession.apply_loaded_run` |
| M4 | `sim_time_frozen` = 暂停 + `get_tree().paused` 仅 |
| M5 | `state_changed` vs 搜索 `_process` 注释约定 |
| M6 | 对外 `ClimateService.refresh()`；`recompute` 仅内部 |
| M7 | 冒烟 `_intent_drive` / `_intent_assign_search`（cap 测仍直连 `assign_search`） |

### 5.11 续审 R2（2026-11-26 · Intent 拆分后）

| ID | 状态 | 项 |
|---|---|---|
| R2-A | **已关** | §8 过时：`lastRecruitSuccessDay` 入盘 · 空 `lootPiles` 清堆 · 玩法层六元无直减 · `ClimateService.recompute` 无外呼 |
| R2-B | **已关** | `SessionIntentRouter` + 冒烟分文件 + GODOT_ARCH §4.4–4.5 |
| R2-C | **已关** | 走廊速度 · 士气/轻伤/车身 · `fuel_cap` → `PopulationRules` / `balance.population` |
| R2-G | **已关** | `MemberMorale.settle_daily_moods`（sim 床位/无岗/配给/生活线）；`assign_daily_jobs` 日末/加挂 |
| R2-D | **已关** | 09 §3.0.1 `eventTagWeights` / `pendingThreat` |
| R2-E | **已关** | `SearchService.localize_err`（Intent 域不再调 `_search_err_zh`） |
| R2-F | **已关** | `Segment.from_dict` + SaveSchema 去重 |

### 5.12 模块审计第 3 批扫尾（2026-11-27）

| ID | 状态 | 项 |
|---|---|---|
| A3-C5 | **已关** | `GODOT_ARCH` 目录表：`inventory_service` 归 `gameplay/` |
| A3-T4/T5 | **已关** | `region_fuel_mult_active` + `DEV_TOGGLE_REGION_FUEL`；`GameClock.next_speed_after` / `speed_hotkey_tier` |
| A3-E3/E4/E5 | **已关** | 删 `onboard_pop`；缺键 `require`；`balance.start.carriages` 单源 |
| A3-G3/G4/G5 | **已关** | 车站 `affordable`；`combat.l1Armor*`；[qa/RF-11.md](../qa/RF-11.md) |
| A3-U1 | **已关** | `SELECT_ABANDON_CARRIAGE`；调试倍率走 Intent |
| A3-S7 | **已关** | `sync_event_locale` / `annotate` / `enrich_core_service_docs` 文案与死分支 |
| A3-S6 | **已关** | `validate_data_ci` CSV 镜像 + 威胁别名表 + 事件卡字段/op；`config_db` 卡级 op/configVersion |
