# Python 数值沙盒（库）

对齐 **设计 v1.3.33 / 规格 v1.52** · 配置实体见 `data/manifest.json` 的 `configVersion`。

本目录保留 **可被脚本 import 的模拟逻辑**，不附带固定验收 runner：

| 文件 | 用途 |
|------|------|
| `engine.py` | 日循环、资源、搜索、区域等简化引擎 |
| `event_loader.py` | 段事件抽卡（`event_draw_rules` + `events/_index`） |
| `point_types.py` | 点位类型 / 区域权重加载 |
| `config_db.py` | 与 Godot 类似的 manifest 表加载探针（供临时脚本用） |
| `event_ops_sim.py` | `loot_halve` / 段堆清理（对齐 `EventOps`） |

> **说明（2026-11-27）**：原 `run_zero_a.py` · `run_time_event_sweep.py` · `validate_config_db.py` · `compare_rules.py` 及 Godot `scripts/qa/*`、`tools/*smoke*` / `validate_data_ci.py` 已移除。需要回归时按当时 `configVersion` 与 `GODOT_ARCH` / `开发计划 §12` 重新编写测试，勿假设旧路径仍存在。

未闭环：[OPEN_LOOPS](../modules/OPEN_LOOPS.md) · 手算/灰盒：[10](../modules/10-validation.md)