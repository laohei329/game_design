# 自动化回归（按优先级）

## 第 0 批 · 应立即跑

| 命令 | 作用 |
|---|---|
| `python tools/smoke_config.py` | 全表 + **s2** + 事件卡篡改负向 |
| `python tools/run_zero_a.py --runs 250` | 零 A（2×250）；`--strict` 作闸 |
| `python tools/probe_save_migration.py` | manifest v2→12 + Godot 迁移探针 |
| `python tools/run_module_tests.py -m client` | HcConfigProbe |

## 第 1 批 · 已接入

| 命令 | 作用 |
|---|---|
| `python tools/scan_hardcode_gd.py` | 启发式硬编码（含 `sim/engine.py` 顶栏） |
| `python tools/probe_config_paths.py` | `require` 路径 vs manifest / `balance.stations` 镜像 |
| `python tools/audit_locale_placeholders.py` | 五语列、`{n}` 占位符、长度异常 |
| `python tools/probe_event_weight_mc.py` | 事件权重蒙特卡洛 + 情境对比 |
| `python tools/probe_long_run_stability.py` | 30–240 日 × 多种子稳定性上界 |
| `python tools/probe_locale_registration.py` | CSV / `.translation` / `project.godot` 三向一致 |

推荐：`python tools/run_module_tests.py`（`data` / `events` / `sim` / `locale` / `hardcode` / `docs` 已编入）

## 第 2 批 · 已接入

| 命令 | 作用 |
|---|---|
| `python tools/check_doc_consistency.py` | 死链、已删脚本、configVersion 头、裸「壳」字 |
| `python tools/probe_orphan_data.py` | 顶层 data JSON、`events` index ↔ 磁盘、`event_hooks_registry.json` |
| `python tools/audit_locale_keys.py` | 代码键 ↔ CSV（`-m locale`） |

Godot headless 见第 0 批。