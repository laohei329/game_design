# Legacy 事件卡（归档索引）

> **运行时路径未搬迁**：Godot 仍从 `data/events/`（`res://data/events/`）加载；本目录仅作 **审计/迁出记录**，避免误增新卡。

| 项 | 位置 |
|---|---|
| 索引 | [`data/events/_index.json`](../../data/events/_index.json) |
| 单卡 | `data/events/{general,season,year}/` |
| 五语 CSV | `data/localization/events_*.csv` |
| 说明 | [`data/events/LEGACY.md`](../../data/events/LEGACY.md) |
| 自发替代 | [`data/incidents.json`](../../data/incidents.json) · [`modules/06-incident-migration.md`](../../modules/06-incident-migration.md) |

**规则**：冻结新卡（红线 #14）；`events_index` 在 `manifest.legacyFiles`；运行时默认不读卡库。