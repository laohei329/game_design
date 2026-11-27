# 事件卡 → 自发 Incident 迁移

> **目标**：几乎不写选项型事件卡；段/日/进站后果由 **应力快照 + incident 类型 + SystemEffects** 产生。  
> **权威**：[`architecture.md`](../architecture.md) 红线 #14 · 本文件为执行路线图。  
> **状态**：阶段 7 已切默认自发路径（`useLegacyEventCards` **false**）；30 日手签见 [qa/DEV-incident-30d-signoff.md](../qa/DEV-incident-30d-signoff.md)。

## 阶段 0 · 落档

- [x] `architecture.md` 红线 #14  
- [x] `balance.featureFlags`  
- [x] `OPEN_LOOPS` L10 / DR8  
- [ ] `06-region-events.md` §2.1 全文改写到 incident（随阶段 5 下线卡库时闭合）  
- [x] `MILESTONES` M5 / `10-validation` / `GODOT_ARCH` S2.1 → incident + stress_sweep  

## 阶段 1 · 数据与存档

- [x] `data/incidents.json` · `data/stress.json` · `manifest`  
- [x] `Segment.pending_incidents[]` 读写（`save_schema` / `segment.gd`）

## 阶段 2 · Effect 内核

- [x] `SystemEffects.apply_effects` → 委托 `EventOps.apply_op`

## 阶段 3 · Director

- [x] `IncidentDirector.on_segment_build`（legacy 开关分流）  
- [x] 首版：**silent** incident 段建成即结算；**modal** 类型入队待阶段 4 UI  

## 阶段 4 · UI / Intent

- [x] `IncidentService` · `incident_modal` 场景 · `RESOLVE_INCIDENT`  
- [x] 读档 `IncidentService.sync_after_load`  
- [x] `ui.csv`：`incident.recruit_segment.*` · `incident.modal.*`  
- [ ] 与 legacy 事件弹窗优先级/互斥全量手测  

## 阶段 5 · Legacy 收口与权重迁移

- [x] `incidents.json` 扩至 8 类（粮/水/油/掠夺/守卫/低压/段收留/日结收留）  
- [x] 段建成 **silent 可叠乘** + **modal 加权 1 个**  
- [x] `onDayEnd` · `day_settle` 与 `MemberRoster.try_day_end_recruit` 分流  
- [x] `event_draw_rules` 语义对齐（supply 0.4/0.35、raid +0.25、低油 +0.25）  
- [x] `EventCatalog`：`loadLegacyEventCatalog` + legacy 关时不读单卡  
- [x] `data/events/LEGACY.md` · `06` §2 迁移注记  
- [x] 归档索引 `archive/events-legacy/README.md`（运行目录仍为 `data/events/`）

## 阶段 6 · 验收与扫掠

- [x] `tools/stress_sweep.py`（合成快照 + 单调性断言）  
- [x] `manifest` 注明 incident 主叙事 · `events_index` legacy  
- [x] MILESTONES / 10 / GODOT_ARCH / 09 口径更新  
- [x] `smoke_config` 串联 `stress_sweep.py`  

## 阶段 7

- [x] 全引擎默认 `useLegacyEventCards=false` · `loadLegacyEventCatalog=false`
- [x] `events_index` 迁至 `manifest.legacyFiles`（Godot `files` 不载；Python `config_db` 仍载）
- [x] `smoke_config` 断言自发开关 + `legacyFiles` 索引可达
- [ ] 30 日 incident-only 手签（[DEV-incident-30d-signoff.md](../qa/DEV-incident-30d-signoff.md)）

## 开关

| 键 | 默认 | 含义 |
|---|---|---|
| `balance.featureFlags.useLegacyEventCards` | `false` | `true` = 现 `EventDraw` + 120 卡（对照/旧档） |
| `balance.featureFlags.useIncidentDirector` | `true` | `false` 时即使 legacy 关闭也不跑 Director（调试） |
| `balance.featureFlags.loadLegacyEventCatalog` | `false` | `true` 可在 legacy 关时仍读卡库（工具/对照） |

**自发路径**：`useLegacyEventCards=false` 且 `useIncidentDirector=true`。

关闭 legacy：将 `balance.featureFlags.useLegacyEventCards` 设为 `false`（Godot 重启加载 ConfigDb）。