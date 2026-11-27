# Python 数值沙盒（库）

对齐 **设计 v1.3.33 / 规格 v1.52** · 配置实体见 `data/manifest.json` 的 `configVersion`。

| 文件 | 用途 |
|------|------|
| `engine.py` | 日循环、资源、搜索、区域等简化引擎 |
| `event_loader.py` | 段事件抽卡（`event_draw_rules` + `events/_index`） |
| `point_types.py` | 点位类型 / 区域权重加载 |
| `config_db.py` | manifest 表加载与 `run_validation(stage=…)` |
| `event_ops_sim.py` | `loot_halve` / 段堆清理（对齐 `EventOps`） |
| `run_zero_a.py` | 转发至 [`../tools/run_zero_a.py`](../tools/run_zero_a.py)（阶段零 A @500） |

验收命令见 [`tools/AUTOMATION.md`](../tools/AUTOMATION.md) 与 [`tools/README.md`](../tools/README.md)。