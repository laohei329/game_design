# Godot 客户端 · 代码分层与分期验收

> **平台**：Godot **4.x** · 单机 PC（Steam）· Windows 优先  
> **语言**：**GDScript**（全栈默认；不混 C# 玩法逻辑）  
> **配置权威**：仓库 [`data/`](../data/) · `configVersion` **30**（验收闸 config25）· 存档 `version.save` **12**  
> 对齐：[architecture](../architecture.md) §3–4 · [09](09-data-platform.md) · [02 §8](02-resources.md) · [08 §4](08-presentation.md)  
> **本页含**：代码分层 + 阶段一玩法切片 + S2 事件接入  
> **状态**：**S1a 可玩**；**S1b 入口部分接入**（三选一 · 科技 Lv1 · L1 薄）；**M3 未过**（30 日 ×3 人未签）。**勾选**：[开发计划 §12](../开发计划.md#12-godot-单人实施client) · **审计**：[qa/整体审计报告-第六轮.md](../qa/整体审计报告-第六轮.md)

---

## 0. 已确认决策

| 项 | 决定 |
|---|---|
| 引擎 | Godot 4 |
| 语言 | GDScript |
| 表现 | 2D 侧视 + 长车列表（08） |
| 数值调试 | **禁止**玩法常数硬编码；一律 `data/*.json` |
| Python `sim/` | 数值库（`engine` 等）；**不**链进运行时；固定 runner 按需重建 |
| `third_party/` | **烘焙工具**（不进包）：`pixelfx-godot/godot` · 天气参考：`godot-weather-2D` |
| `assets/vfx_portable/` | **可移植 VFX**（PNG/JSON/SpriteFrames）→ 任意 Godot 工程，无 pixelfx 运行时（见 [`assets/vfx_portable/README.md`](../assets/vfx_portable/README.md)） |
| 工程根建议 | 仓库旁 `client/`（Godot 项目），`data/` 用复制或 junction 指向本仓库 `data/` |

---

## 1. 代码分层（对照设计六层）

```
┌──────────────────────────────────────────────────────────────┐
│ presentation/   场景 · UI · 镜头 · 音效 · 本地化展示          │  ← 设计「表现层」
├──────────────────────────────────────────────────────────────┤
│ content/        事件卡装载 · 文案键 · 成员生成壳（可后置）      │  ← 设计「内容层」
├──────────────────────────────────────────────────────────────┤
│ gameplay/       驾驶 · 进站 · 搜索 · 战斗入口 · 三选一 · 结局  │  ← 设计「玩法层」
├──────────────────────────────────────────────────────────────┤
│ economy/        库存 · 日结 F04/F05/F32 · 转换 · 种植/净水    │  ← 设计「经济层」
├──────────────────────────────────────────────────────────────┤
│ rhythm/         日历 · 天气抽取 · ClimateInfluence · pressure │  ← 设计「节拍层」
├──────────────────────────────────────────────────────────────┤
│ data/           ConfigDb · Save · 迁移 · RNG · Manifest      │  ← 设计「数据层」
└──────────────────────────────────────────────────────────────┘
         ↑ 仅 data/ 与 Save 读写磁盘；上层只读 ConfigDb API
```

### 1.1 目录

```
res://
  data/                          # → 仓库 data/（构建复制）
  scripts/
    data/
      config_db.gd               # Autoload ConfigDb
      balance_start.gd           # balance.start 单点（NEW_RUN / 存档缺字段回填）
      save_service.gd            # Autoload SaveService
      rng_service.gd             # Autoload RngService
      migrations/
        v11_to_v12.gd            # … 按 09 链
    domain/                      # 纯 RefCounted / Resource，无 Node
      population_rules.gd        # balance.population / fuelTank 阈值 API
      run_state.gd
      carriage.gd
      member.gd
      region_run.gd
      segment.gd
      station.gd
      point.gd
      climate_state.gd
    rhythm/
      calendar.gd
      climate_service.gd         # recompute() 唯一写入口
      weather_draw.gd
    economy/
      member_morale.gd           # 日结逐人 mood（sim morale_settle 成员环）
      day_settle.gd
      production_service.gd
      fuel_f04.gd
    gameplay/
      inventory_service.gd       # 库存增减/cap（S0 单入口；物理目录在 gameplay/）
      region_service.gd
      segment_build.gd
      drive_service.gd
      station_service.gd
      search_service.gd
      tech_service.gd
      train_service.gd
      combat_l1.gd
    content/
      event_catalog.gd
      event_draw.gd
      event_ops.gd
    app/
      game_session.gd            # Autoload GameSession
      intent_bus.gd              # Autoload IntentBus
      session_intent_router.gd     # Intent 表驱动分发（Lifecycle→Train→World）
      session_intents_lifecycle.gd # 局周期 / 时间 / 供暖 / 存读档
      session_intents_train.gd     # 驾驶 · 搜索/搬运 · 进站 · 遗弃
      session_intents_world.gd     # 三选一 · 科技 · 战斗 · 事件选项
    presentation/
      hud_top.gd
      rail_view.gd
      train_list.gd
      station_panel.gd
      region_pick.gd
      event_modal.gd
      debug_overlay.gd
  scenes/
    boot.tscn
    main_menu.tscn
    run_main.tscn
    ui/
      hud_top.tscn
      station_panel.tscn
      region_pick.tscn
      event_modal.tscn
```

### 1.2 依赖方向（硬规则）

```
presentation → IntentBus + 只读 GameSession.state
gameplay     → economy / rhythm / content / domain
economy      → rhythm / data / domain
rhythm       → data / domain
content      → data / domain
data         → （无向上依赖）
domain       → （无服务依赖；可被任意层引用）
```

禁止：`presentation` 直接改库存/气候/RegionRun；禁止在 Node 脚本写玩法字面量阈值。

### 1.3 Autoload 清单

| 名 | 脚本 | 职责 |
|---|---|---|
| `ConfigDb` | `config_db.gd` | 启动加载 manifest 与全表；`get_path` / `require` |
| `RngService` | `rng_service.gd` | 局内 RNG；可序列化种子 |
| `GameSession` | `game_session.gd` | 持有 `RunState`；订阅 `IntentBus`，意图经 `SessionIntentRouter` 分域处理 |
| `IntentBus` | `intent_bus.gd` | UI → 玩法意图信号 |
| `SaveService` | `save_service.gd` | 路径、原子写、迁移、槽位 |

---

## 2. 配置驱动

### 2.1 铁律

1. 玩法数值 / 权重 / 阈值 / 模板 id → **只来自 json**  
2. `ConfigDb.require("balance.fuel.base")`；缺键 → **启动失败并打印完整路径**  
3. 调参：改 json → 开发菜单 Reload Config（**仅未开局或下一局生效**；进行中默认不热更）  
4. 改键语义 → `configVersion++`；对照 [10 §1.1](10-validation.md) / [09](09-data-platform.md)  
5. **开局**（`NEW_RUN`、读档 `inventory` 缺字段、`RuntimeSavePatch` precision 等）数值与编组 → 只经 `data/balance_start.gd`（`BalanceStart`）；玩法层勿再散写 `balance.start.*`

### 2.2 ConfigDb API（约定）

```
load_all() -> Error
reload_all() -> Error          # 开发用
has(path: String) -> bool
require(path: String) -> Variant
get_table(name: String) -> Dictionary   # "balance" | "stations" | …
config_version() -> int
```

路径例：`balance.start.fuel`、`stations.guaranteeAfter`、`weather.weathers.clear.tempMod`。

### 2.3 表 → 模块 → 分期

| 配置 | 消费方 | 分期 |
|---|---|---|
| `manifest.json` | ConfigDb | S0 |
| `balance.json` | economy / rhythm / tech / 开局 | S0 |
| `weather.json` | weather_draw / climate | S0 |
| `climate_influences.json` | climate / region | S0 |
| `regions.json` | region_service | S0 |
| `stations.json` | segment_build / station | S0 |
| `point_types.json` | segment_build / search | S0 |
| `carriages.json` / `equipment.json` | train_service | S0–S1a |
| `upgrades.json` | tech_service | S1b |
| `difficulty.json` | 开局 | S1b |
| `hud_hints.json` | presentation / tips | S1a 读 `offerDeferCodes`/阈值；全量 TIPS UI **S3（L6）** |
| `events/*` | event_* | **S2** |
| `combat*` / `abilities` | combat / 异能 | S2–S3 |

### 2.4 允许留在代码

- 与设计对齐的枚举 / id 校验  
- 日结步骤顺序、迁移函数骨架  
- 非平衡 UI 像素  

---

## 3. RunState 最小字段（S0 / S1a）

权威全集见 [09 §3](09-data-platform.md)。下列为 **S1a 必须可存于内存** 的子集（S1b 存档再落盘）。

| 域 | 字段 |
|---|---|
| 日历 | `year`, `season`, `dayInSeason`, `dayTotal` |
| 资源 | `food/water/fuel/parts/med/crystal` + 材料四元按需 |
| 气候 | `weatherId`, `climateInfluences[]`, 派生倍率缓存 |
| 列车 | `carriages[]`, `bodyHp`, `abandonCount`, 四线 tech, `precision?`, `driveIntent`, `driveHoursToday` |
| 世界 | `regionRun`, `heatingEnabled`, `guaranteeFailStreak`, `pressureHistory[2]` |
| 人口 | `members[]`（S1a 可最小：id/hp/job/mood/beds 占用） |
| 元 | `rngState`, `tutorialDone`, `failed?` |

`RegionRun` / `Segment` / `Station` / `Point` 字段对齐 [06 §0](06-region-events.md)。

---

## 4. Intent 目录（表现 → 玩法）

所有 UI 操作只能 `IntentBus.emit(...)`；由 `GameSession` 或 gameplay 服务处理。

### 4.1 S0

| Intent | 载荷 | 效果 |
|---|---|---|
| `NEW_RUN` | `difficultyId?` | 读 balance.start 开局；建教程跨度 |
| `ADVANCE_DAY` | — | 跑日结一步（S0 可简化）后 `dayTotal++` |
| `SET_HEATING` | `enabled: bool` | 写 `heatingEnabled` + 必要时重算温室倍率 |

### 4.2 S1a

| Intent | 载荷 | 效果 |
|---|---|---|
| `SET_DRIVE_INTENT` | `cruise\|slow\|stop` | 写 driveIntent；影响 F04 速度系数 |
| `ENTER_STATION` | `segmentIndex`, `stationIndex` | 打开发现流程 |
| `RESOLVE_OFFER` | `accept: bool` | 修挂或放弃；更新保底 streak |
| `SET_MEMBER_JOB` | `memberId`, `job` | 玩家指派岗位（搜索面板） |
| `ASSIGN_SEARCH` | `memberIds[]`, `pointId` | 开始搜索任务 |
| `RECALL_SEARCH` | `memberIds[]?` | 召回 |
| `END_DAY` | — | 完整日结（02 §8 顺序） |
| `ABANDON_CARRIAGE` | `carId: string` | 停靠遗弃一节（[03 §4.1](03-train.md)）；扣件/油、返 scrap、校验动力与床位 |
| `SELECT_ABANDON_CARRIAGE` | `carId: string` | 遗弃面板选中预览车节（不写其它字段） |
| `OPEN_ABANDON` / `CLOSE_ABANDON` | — | 遗弃面板开关 |
| `DEV_TOGGLE_REGION_FUEL` | — | **仅 debug 构建**：`RegionRun.regionFuelMult` 1.0↔1.3 |

### 4.3 S1b+

| Intent | 期 |
|---|---|
| `PICK_REGION` | S1b |
| `BUY_UPGRADE` | S1b |
| `START_COMBAT_L1` / `CHOOSE_TACTIC` | S1b |
| `SAVE_GAME` / `LOAD_GAME` | S1b |
| `CHOOSE_EVENT_OPTION` | S1b（薄 · `EventOps`） |
| `ENTER_SPUR` / `SKIP_SPUR` | S2 |

### 4.4 GameSession 意图分发（`SessionIntentRouter`）

**接线**：`presentation` → `IntentBus.emit_intent` → `GameSession._on_intent` → `SessionIntentRouter.dispatch`。

**表驱动顺序**（短路与 §4 目录一致，先生命周期再列车再世界）：

| 模块 | 脚本 | 典型 Intent |
|---|---|---|
| Lifecycle | `session_intents_lifecycle.gd` | `NEW_RUN` · `END_DAY`/`ADVANCE_DAY` · `SET_TIME_SPEED` · `TOGGLE_TIME_PAUSE` · `SET_HEATING` · `DEV_TOGGLE_REGION_FUEL`（debug） · `SAVE_GAME`/`LOAD_GAME` |
| Train | `session_intents_train.gd` | `SET_DRIVE_INTENT` · `ASSIGN_SEARCH`/`RECALL_SEARCH` · `OPEN_SEARCH`/`CLOSE_SEARCH` · `ASSIGN_HAUL`/`RECALL_HAUL` · `ENTER_STATION` · `RESOLVE_OFFER` · `ABANDON_CARRIAGE` · `SELECT_ABANDON_CARRIAGE` · `OPEN_ABANDON`/`CLOSE_ABANDON` |
| World | `session_intents_world.gd` | `PICK_REGION` · `CLOSE_REGION_PICK` · `OPEN_TECH`/`CLOSE_TECH` · `BUY_UPGRADE` · `OPEN_COMBAT`/`CLOSE_COMBAT` · `RESOLVE_COMBAT_*` · `CHOOSE_EVENT_OPTION` · `RESOLVE_INCIDENT` |

各域实现 `try_handle(session, intent_name, payload) -> int`：

| 返回值 | 含义 |
|---|---|
| `-1` | 本域未识别，交给下一域 |
| `0` | 已处理；**不**自动 `state_changed`（如 `NEW_RUN` 自备刷新） |
| `1` | 已处理；路由器代发 `GameSession.state_changed` |

新增 Intent：**先**落入上表对应 `match`，**再**在 §4.1–4.3 补一行登记；禁止在 `game_session.gd` 再写巨型 `match`。

实现约定：`session_intent_router.gd` 与 `game_session.gd` 对域模块 **`preload`**；路由器用 `call("try_handle", …)` 调用静态入口，避免全局 `class_name` 未注册时的编译顺序问题。

### 4.5 自动化验收（按需）

2026-11-27 起仓库**不**内置固定 Godot 无头冒烟或 Python runner。需要回归时：按当时 `configVersion` 重写探针；手工清单见 [qa/DEV-functional-checklist.md](../qa/DEV-functional-checklist.md)；文档一致性见 `tools/check_doc_consistency.py`。

---

## 5. 日结顺序（权威引用）

实现必须按 [02 §8](02-resources.md) / [01](01-time-season.md) 钩子，**禁止**自行重排。概要：

1. 延迟事件 `fireOnDay`（−1 / 到期）  
2. F04 燃料（用**已维护**的气候倍率）  
3. 清小时行驶额度相关  
4. `recomputeClimate`（若日界需要）  
5. 扣粮 / 扣水  
6. 供暖扣油  
7. fuel streak / 失败检定  
8. F05 种植 / F32 净水  
9. 工坊 precision / 零件  
10. 归零 / 士气 / pressure 刷（不重抽段事件）

气候 **写入影响因子后必须立刻 recompute**，不得拖到日结（01 §4.3）。

---

## 6. 场景树（S1a）

```
boot.tscn
  └─ 加载 ConfigDb → main_menu 或直进 run

run_main.tscn
  ├─ World (rail_view + train side view)
  ├─ HUD (hud_top：季日、天气、六元、额度、速度)
  ├─ SidePanel (成员/岗位 · S1a 可简)
  ├─ StationPanel (进站时 pause 树或 process_mode)
  ├─ DebugOverlay (dev：configVersion、fuelClimate、streak)
  └─ Systems (Node 挂服务脚本，或纯 Autoload 无子节点)
```

暂停规则：进站 / 事件 / 编队 → 游戏树暂停或 `drive` 冻结；纯巡航可倍速（01 §2）。

---

## 7. 模块职责一览

| 脚本 | 读配置 | 写状态 | 分期 |
|---|---|---|---|
| `config_db` | 全 | — | S0 |
| `calendar` | time.* | day/season/year | S0 |
| `climate_service` | weather + influences | climate 派生 | S0 |
| `inventory_service` | start / caps | 六元 | S0 |
| `day_settle` | fuel/greenhouse/water | 全日结 | S1a |
| `drive_service` | driveHoursPerDayCap, fuel | progressKm, hours | S1a |
| `segment_build` | stations, point_types, regions | segments/points/stations | S0–S1a |
| `station_service` | pools, guaranteeAfter | offers, streak, carriages | S1a |
| `search_service` | point_types | pools, inventory | S1a |
| `region_service` | regions | RegionRun 切换 | S1b |
| `tech_service` | upgrades | tech levels | S1b |
| `event_*` | events/* | flags, delayed, climate | S2 |
| `save_service` | — | 磁盘 | S1b |

---

## 8. 优先级

| 优先级 | 含义 |
|---|---|
| **P0** | 无此不成游戏：配置、会话、时间、驾驶、进站、日结、最小 UI |
| **P1** | 30 日闸：三选一、科技 Lv1、存档、L1 战斗 |
| **P2** | 事件窗、spur、战斗加厚 |
| **P3** | TIPS L6、多语言、埋点全量、异能 |

顺序：**P0 → S1a 切片 → S1b 30 日 → 零 B → P2**。

零 A（数字）→ 冻结 25 → S1a 切片可玩 → 零 B（构建就绪后）→ S1b 30 日包 → S2 事件/L2…

无构建时优先 S1a，**禁止**先解冻数值。

---

## 9. 玩法切片定义

### 9.1 最小可玩（S1a · 支撑零 B）

必须可点出：

1. 时间推进（日/季显示）  
2. 驾驶：加减速 / 停靠意图  
3. 进站 → 发现 → 修复 → 加挂 → 再出发  
4. 派人搜索 / 召回  
5. 日结粮水燃料可见  
6. 供暖开关（T1/T3 提示可后置，L6 暂缓）

**不要求**：L3 战斗、120 事件 UI、异能满轴、多语言齐、L6 TIPS。  
[10 §2.1](10-validation.md)「构建号」以此为准。

### 9.2 阶段一完成定义（S1b · 关 L8）

| # | 交付 |
|---|---|
| 1 | §9.1 切片稳定（无软锁） |
| 2 | 区域三选一（≥3 词条） |
| 3 | 四线科技 Lv1（工坊 + precision） |
| 4 | 战斗至少 L1 |
| 5 | 本地存档（09 最小子集） |
| 6 | data 最小集已在仓库 |
| 7 | 08 §4 提示可后置 |
| 8 | 内部 3 人各满 30 日无阻断 |

data 已有：P0 表 + **P1**（`combat` / `gear` / `abilities` / `archetypes` / `disease` / `items` / `combat-*` / `localization` 最小集）— 见 [`data/P1_README.md`](../data/P1_README.md)。  
S0.2 须加载 manifest 全表；缺文件加载器报键名。

---

## 10. 分期工程验收

### S0 · 工程骨架

| # | 验收 | 过线 |
|---|---|---|
| S0.1 | Autoload 齐；工程可运行 | 启动无报错 |
| S0.2 | S0 表全加载；缺文件报键名 | 删 `weather.json` 后 `ConfigDb` 启动必须报错（手工或临时脚本） |
| S0.3 | 教程跨度第 0 段；dayTotal+1 | 顶栏春日 |
| S0.4 | 开局 = balance.start.* | 改 json 开局变 |
| S0.5 | recompute 后倍率随区域变 | 调试可见 |

### S1a · 最小切片

| # | 验收 | 过线 |
|---|---|---|
| S1a.1 | 驾驶意图；额度来自配置 | 额度满→停靠油耗 |
| S1a.2 | 进站→发现→修挂→出发 | 教程休息车 |
| S1a.3 | guaranteeAfter 配置化保底 | 连 miss 后可修 |
| S1a.4 | 搜索/召回；point_types | 入库可见 |
| S1a.5 | 日结；F04 读 balance | 改 fuel.base 日耗变 |
| S1a.6 | 供暖开关 | 粮/油变化 |
| S1a.7 | 连续 15 游戏日无软锁 | QA 表 |

### S1b · 30 日包（编号与 [MILESTONES §5](MILESTONES.md) 一致）

| # | 验收 | 过线 |
|---|---|---|
| S1b.1 | S1a 稳定无软锁 | 无已知阻断 |
| S1b.2 | 区域三选一 ≥3 词条 | 雪原可感 |
| S1b.3 | 四线科技 Lv1 | `upgrades.json` 真实扣费 |
| S1b.4 | 战斗 L1 | 非跳过即胜 |
| S1b.5 | 本地存档 save 12 | 杀进程不漂 |
| S1b.6 | data P0+P1 | manifest 全表 |
| S1b.7 | 08 §4 提示 | 可后置 |
| S1b.8 | ≥3 人各满 30 日 | 无阻断 |
| S1b.9 | 改 `emptyChance` 可感 | 调参验收 |

### S2 · 事件 + spur

**加载**：\events/_index.json\ → 全卡；抽池 = \sim/event_loader\（季/年 + weight）。

**UI**：\onSegmentBuild\ 抽中后暂停；标题/正文/2–4 选项；禁止无选自动点。

**结算**：选 option → immediate execOp（气候立刻 recompute）→ delay → logLine + 埋点。

| op | 备注 |
|---|---|
| grant_item / mood_delta / flag_set | 即时或延迟 |
| grant_influence | 立刻 recompute |
| clear_influence / loot_halve / weight_mod / spawn_threat | 延迟 |
| recruit_roll | 无空床跳过 |

存档：段 eventId、delayedEvents、eventFlags、climateInfluences；已 built 禁止重抽。

| # | 验收 | 过线 |
|---|---|---|
| S2.1 | Incident + `RESOLVE_INCIDENT` | `tools/stress_sweep.py` OK |
| S2.1b | Legacy 120 卡（可选） | 季/年池（`useLegacyEventCards`） |
| S2.2 | 选项 immediate+delay | 气候即时 |
| S2.3 | spurChance | 跨度 ≤1 |
| S2.4 | 内容加厚 | 按排期 |

### S3 · 灰盒 / 抛光

零 B：[10 §2](10-validation.md)；TIPS 见 [08 §4](08-presentation.md)（若开做）。

---

## 11. 与 sim · 排期 · 风险

| | `sim/` Python | Godot `client/` |
|---|---|---|
| 职责 | 可选日循环对照（`engine.py`） | 玩家运行时唯一权威 |
| 配置 | 读 `data/` | `ConfigDb` 读 `res://data/`（须与仓库同步） |
| 验收 | 按需临时脚本 | 手工清单 + 里程碑录屏 |

| 周 | 焦点 | 退出 |
|---|---|---|
| W1 | S0 | 配置开局 |
| W2–3 | S1a | 切片可录屏 |
| W4 | S1b | 冲 30 日 |

| 风险 | 缓解 |
|---|---|
| 逻辑进 UI | IntentBus |
| Item6 vs 扩张节流 | [OPEN_LOOPS](OPEN_LOOPS.md) **DR1**（已裁定） |
| 过早事件 | 严守 S1a |

---

## 12. 相关文档

| 文档 | 用途 |
|---|---|
| [MILESTONES](MILESTONES.md) | **里程碑 M0–M6 · 验收过线 · 状态** |
| [08](08-presentation.md) | UI · 软规则 / 提示 / HUD |
| [09](09-data-platform.md) | 存档迁移 |
| [10](10-validation.md) | 零 A/B · 冻结 · 灰盒全文 |
| [OPEN_LOOPS](OPEN_LOOPS.md) | 缺口与剩余风险 |
