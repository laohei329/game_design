# 事件卡与维护脚本

120 张卡 · 权威 JSON 在本目录；五语文案权威 CSV 见 [`../localization/`](../localization/README.md)。

| 脚本 | 用途 |
|---|---|
| [`sync_event_locale.py`](sync_event_locale.py) | **日常**：`--bucket general\|season\|year` · `export` / `import` / `pipeline` |
| [`gen_event_stubs.py`](gen_event_stubs.py) | **仅灾难重建**：重生 120 卡骨架；**禁止**在已有译文的卡上全量覆盖（见 localization README） |

设计钩子变体（只读参考）：[`event_hooks_registry.json`](event_hooks_registry.json)（R3；不再单独跑脚本，改文案走 CSV）。