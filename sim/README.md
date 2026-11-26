# 阶段零 A — 数值模拟器

对齐 **设计 v1.3.33 / 规格 v1.52** · [`data/balance.json`](../data/balance.json) config **25**。  
`engine` / `sweep` 数据：`weather.json` · `regions.json` · `climate_influences.json` · `stations.json` · `balance.seasonPressure`（经 `point_types`）。  
`sweep` 事件：`data/events/_index.json` + 120 卡 · `sim/event_loader.py`（按季/年池加权抽取）。  
未闭环：[OPEN_LOOPS](../modules/OPEN_LOOPS.md) · 验收/手算/灰盒：[10](../modules/10-validation.md)

```bash
python sim/validate_config_db.py          # manifest 全表 + require 路径（默认 stage=s1b）
python sim/validate_config_db.py --stage s2   # 含 120 事件卡
python data/events/sync_event_locale.py --bucket general pipeline
python data/events/sync_event_locale.py --bucket season pipeline
python data/events/sync_event_locale.py --bucket year pipeline
python sim/run_zero_a.py --runs 500
```

段事件权重权威：`data/event_draw_rules.json` · 实现 `sim/event_loader.py`（`EventDrawContext` / `draw_event_id`）。

## 结论（AUDIT K · config **25** · 2026-11-26 · `--runs 500`）

| 策略 | ≥120 日 | pop≥20 | 燃料失败 | 死因峰值 | Item6 |
|---|---|---|---|---|---|
| 保守 | **46%** | **23%** | **71%** | **68%** | — |
| 扩张 | **48%** | **32%** | **69%** | **63%** | **PASS**（config25 阈） |

历史 config24：存活 75%/72%，pop20 55%/56%，燃料失败 38%/40%。

Runner 另打：peak_cars / hung / **acquire** drought≥8 与含 `ai_skip` 对照（第 5/6 项）。第 9/10 见 [10 §1.2](../modules/10-validation.md)。

```bash
python sim/run_time_event_sweep.py   # 可选；报告默认写出 sim/TIME_EVENT_SWEEP.md
```
