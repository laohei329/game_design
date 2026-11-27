# GDScript 目录导读

> 分层细则：[modules/GODOT_ARCH.md](../../modules/GODOT_ARCH.md) · 意图列表：开发计划 §12.9

## 读代码推荐阅读顺序

1. `app/intent_bus.gd` → `app/game_session.gd`（所有玩法入口）
2. `domain/run_state.gd`（局内有哪些字段）
3. `economy/day_settle.gd`（结束一天算什么）
4. 按需读 `gameplay/*_service.gd`（进站/搜索/驾驶等单主题）

## 依赖规则（写新代码时遵守）

| 层级 | 目录 | 允许做什么 |
|------|------|------------|
| 表现 | `presentation/` | 读 `GameSession.state`，发 `IntentBus` |
| 应用 | `app/` | 接 Intent，调 Service，发 `state_changed` |
| 玩法 | `gameplay/` | 改 `RunState`，读 `ConfigDb` |
| 经济/节拍 | `economy/` `rhythm/` | 日结、油耗、日历、气候 |
| 领域 | `domain/` | 纯数据结构，无场景、无磁盘 |
| 数据 | `data/` | 配置、存档、RNG、遥测 |

**禁止**：`presentation` 直接改库存；玩法里硬编码 balance 常数（用 `ConfigDb.require`）；**禁止**脚本内 `*_ZH` 文案表（用 `LocaleDb` + `data/localization/*.csv`）。

玩家可见字符串：**`LocaleApi.tr_key`** / `tr_code` / `trf` / `from_locale_block`（`class_name` 的 `static func` 必须用 LocaleApi，勿调 Autoload 实例方法）。热重载：`LocaleDb.reload_locale()`。键表见 `ui.csv`。

Service 内每个 `func` / `static func` 上方应有 `##` 说明（Godot 悬停文档）。

文档注释维护（见 [tools/README.md](../../tools/README.md)）：

- `python tools/annotate_gdscript_docs.py` — 函数体首行 `##` 上移到签名前。
- `python tools/fill_gdscript_missing_docs.py` — 缺 `##` 的 func 按 `DOCS` 表补一行。
- `python tools/enrich_core_service_docs.py` — 核心 Service 多行 `##`（清单 `core_service_paths.py`）。

函数文档建议：首行摘要 → 空 `##` → 前置/副作用 → `@param` / `@return`。

## Autoload（project.godot）

`ConfigDb` · `LocaleDb` · `RngService` · `TelemetryService` · `SaveService` · `IntentBus` · `GameSession`

## 子目录

| 目录 | 职责 |
|------|------|
| `boot.gd` | 可选启动：校验配置后进 `run_main` |
| `data/migrations/` | 读档补丁；版本链与 09 文档对齐 |

## 核心 Service 速查（读代码时对照）

| 脚本 | 负责什么 |
|------|----------|
| `gameplay/region_service.gd` | RegionRun、段末三选一、段/点生成 |
| `gameplay/drive_service.gd` | 驾驶意图、日里程、段末回调 |
| `gameplay/station_service.gd` | 进站要约、保底 streak、挂车 |
| `gameplay/search_service.gd` | 搜索任务、cap、产出进堆 |
| `gameplay/haul_service.gd` | 杂工：堆 → 库存 |
| `gameplay/loot_pile_service.gd` | 点位临时堆读写、存档扁平化 |
| `gameplay/train_service.gd` | 遗弃、床位、人口计数 |
| `gameplay/inventory_service.gd` | 库存上限与 add |
| `economy/day_settle.gd` | END_DAY 数值链 02 §8 |
| `economy/fuel_f04.gd` | 日油耗百分比 |
| `data/save_schema.gd` | RunState ↔ JSON save 12 |
| `gameplay/combat_l1.gd` | L1 检定、非战路径、编队 |
| `gameplay/segment_build.gd` | NEW_RUN 教程 RegionRun 入口 |
| `gameplay/station_defer_service.gd` | 进站搁置/遗弃 HUD 提示码 |
| `gameplay/tech_service.gd` | 四线科技 BUY_UPGRADE |
| `rhythm/calendar.gd` | day_total → 年/季/季内日 |
| `rhythm/climate_service.gd` | 气候乘子 recompute |
| `rhythm/weather_draw.gd` | 段天气掷取与换区影响 |
| `content/event_catalog.gd` | 事件 JSON 懒加载 |
| `data/save_service.gd` | 槽位读写 Autoload |
| `data/config_db.gd` | manifest 配置加载 |
| `app/intent_bus.gd` | UI→Intent 派发 |
| `presentation/combat_panel.gd` | 遭遇 UI 与战斗 Intent |

核心脚本文档批量加厚：`python tools/enrich_core_service_docs.py`（清单见 `tools/core_service_paths.py`）。