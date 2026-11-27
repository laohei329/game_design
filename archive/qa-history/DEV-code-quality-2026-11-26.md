# 代码质量审计 · 冗余与重复（2026-11-26）

> 范围：`client/scripts/**/*.gd`（S1b 玩法层）  
> 自动化：`powershell tools/run_all_smoke.ps1`（改后须 PASS）

## 1. 已清理（本提交）

| 项 | 处理 |
|---|---|
| 空 `SearchService`/`HaulService.reset_day_counters` | 删除函数与 `GameSession` 调用 |
| 户外 `tick`/`on_end_day` 前导 | 收敛到 `GameClock.begin_outdoor_work_tick` / `outdoor_end_day_hours` |
| `PopulationConsumption._food_applied` 包装 | 直读 `_food_applied_today` |
| `DaySettle._clamp_resource` | 产出改 `InventoryService.add`；燃油单次 `clamp_resource` |
| `SaveService.write_state` | 去掉与 `to_save_dict` 重复的 `breakdownStopHoursRemaining` |
| `EventOps` | 删除 19 处重复文件头注释，保留类顶一条 |
| `END_DAY` Intent | 去掉与 `_advance_one_day` 重复的 `state_changed` |
| 注释 | `tech_service`/`fuel_f04` 气候文案 → `refresh` |

## 2. 保留重复（有意）

| 项 | 原因 |
|---|---|
| `SearchService` / `HaulService` `_advance_hours` | 任务结构不同，合并收益低 |
| 冒烟 `on_end_day` 直连 | `GameClock` 切片单测，不走完整日界 |
| cap 测 `assign_search` 直连 | 需要机器错误码，非 Intent |
| `enrich_core_service_docs.py` 生成重复 doc | 工具链；非运行时 |

## 3. 后续可选（未做）

| 优先级 | 项 |
|---|---|

**已做（2026-11-26）**：`SessionIntentRouter` + 冒烟分片；`parts`/`medicine` `InventoryService.remove`；`Segment.from_dict`；`SearchService.localize_err`；`EventDraw` 对齐 sim 加权上下文；`balance.travel.*` 走廊速度 `require`。

**已做（续审清债）**：`SaveSchema` 段反序列化迁至 `Segment.from_dict`；序列化辅助重复 doc 块删除。

## 4. 度量（粗）

| 指标 | 约值 |
|---|---|
| GDScript 文件 | ~55 |
| 删除空函数/重复注释行 | ~25 行 |
| 户外 tick 重复逻辑 | −12 行（search+haul） |