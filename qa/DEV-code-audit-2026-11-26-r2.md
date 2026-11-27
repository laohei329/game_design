# Godot 客户端 · 续审 R2（2026-11-26）

> **基线**：`powershell tools/run_all_smoke.ps1` → **PASS**（含 save_kill · 日钟 · 事件 op）。  
> **触发**：P2 `SessionIntentRouter` / 冒烟分文件 / P3 `InventoryService.remove` 全链对齐后复核。  
> **主文档**：[DEV-code-audit-2026-11-26.md](DEV-code-audit-2026-11-26.md)（本节修正其中过时项）。

---

## 1. 架构 · Intent（已变更）

| 项 | R2 结论 |
|---|---|
| 分发 | `IntentBus` → `GameSession._on_intent` → `SessionIntentRouter.dispatch`（Lifecycle → Train → World） |
| 文档 | [GODOT_ARCH.md §4.4](../modules/GODOT_ARCH.md) |
| UI 违规写 state | **未发现**（`presentation/*` 仅 `emit_intent` + 读 `GameSession.state`） |
| 未接线 | 仍 `push_warning("unhandled intent …")`；**grep 已接线 Intent ⊆ 三域 `match`** |

**Intent 覆盖核对**（`emit_intent` vs 路由器）：

| Intent | 路由 | 备注 |
|---|---|---|
| 全线 HUD/面板/冒烟 | 三域 | 与 §12.9 一致 |
| `CLOSE_REGION_PICK` | World | **无 UI 发射**；`RegionService.pick_region` 内关面板 — 留作测试/未来取消流 |

**可维护性 P2**

| 项 | 说明 |
|---|---|
| ~~`session_intents_train` → `_search_err_zh`~~ | **已关**：`SearchService.localize_err` |
| `SessionIntentRouter` | 须 `preload` + `call("try_handle")`（避免 `class_name` 注册顺序问题） |

---

## 2. 库存单入口 M2 复核

| 检查 | 结果 |
|---|---|
| `state.* -=` 六元 | **0** 处（玩法层） |
| `InventoryService.remove` | day_settle · population · tech · train · station · combat · event_ops |
| 初始化/读档 `=` | `game_session._new_run` · `save_schema.from_save_dict` — 合理 |
| 搜索产出 | **设计例外**：`SearchService` → `LootPileService.add`（非直接上车库存） |
| 搬运上车 | `HaulService` → `InventoryService.add`（待 grep 确认仍一致） |

**遗留 P3**：`SaveSchema` 段/成员序列化长函数重复注释块（见 [DEV-code-quality](DEV-code-quality-2026-11-26.md) §3）。

---

## 3. 冒烟布局

| 文件 | 职责 |
|---|---|
| `smoke_assertions.gd` | 门面；`headless_smoke` **仅**引用此类名 |
| `smoke_assertions_{core,world,outdoor,events,helpers}.gd` | 主题断言 |
| `tools/split_smoke_assertions.py` | 可选再拆分 |

子模块经 `preload` 共用 `SmokeAssertionsHelpers`（Intent 驱动与搜索复位）。cap 测仍 **直连** `SearchService.assign_search`（有意，见 code-quality §2）。

---

## 4. §8 主审计勘误（过时 → 现行）

| 原 §8 项 | R2 |
|---|---|
| `lastRecruitSuccessDay` 未入盘 | **已入盘** `world.lastRecruitSuccessDay` + 冒烟 `errors_recruit_morale_save` |
| 空 `lootPiles[]` 不清堆 | **已修**：`apply_world_list` 先 `_clear_all_piles`，空数组 = 清场 |
| `fuel_cap()` 硬编码 60 | **部分表化**：读 `balance.fuelTank`；缺省 fallback 仍在代码 |
| `GameSession` 巨型 `match` | **已拆** SessionIntentRouter |
| 库存扣减多入口 | **M1–M2 已收敛**（含 station 接车 parts） |
| 对外 `ClimateService.recompute` | **0** 调用方；仅 `refresh` / 内部 `recompute` |

**仍有效（未在本轮改代码）**

| 级 | 项 |
|---|---|
| P1 | `drive_service.travel_speed_kmh` 走廊速度常量 |
| P1 | `event_draw` 相对 sim 的加权上下文缺口 |
| P2 | §8.1 士气/车身/轻伤阈值硬编码族 |
| P2 | `raid_weight_delta` ↔ `eventTagWeights.raid` 双轨（有镜像逻辑，09 正文仍缺） |
| P3 | 卡牌未触达 op（`loyalty_delta` 等） |
| P3 | `client/data` vs 仓库 `data/` CI 镜像（`validate_data_ci` 已扫威胁模板，非全量 diff） |

---

## 5. 规模

| 指标 | R2 |
|---|---|
| `client/scripts/**/*.gd` | ≈ **62** 运行时 + QA（原稿 ≈55，+Intent 三域 + 冒烟 5 片） |
| Autoload | 不变（ConfigDb · LocaleDb · Rng · Telemetry · Save · IntentBus · GameSession） |

---

## 6. 建议执行顺序（续）

1. ~~09 §3.0.1 · 走廊速度 · localize_err · SaveSchema~~ — **2026-11-26 续审已落地**。  
2. ~~§8.1 人口阈值 / fuel_cap~~ — **`PopulationRules` + `balance.population.*`**（2026-11-26）。  
3. **日岗 + mood**：`assign_daily_jobs` · `MemberMorale.settle_daily_moods`（`_step_7b` 先跑成员环再 offset；表 `moodDaily*`）。

---

## 7. 修订链

| 文档 | 动作 |
|---|---|
| `DEV-code-audit-2026-11-26.md` | §2/§8.2/§8.3 脚注指向本节勘误 |
| `OPEN_LOOPS.md` §5.11 | 登记 R2 可关/仍开项 |
| `GODOT_ARCH.md` | §4.4–4.5 已写（上轮） |