# QA 证据目录

验收与审计的**现行索引**。历史证据见 [archive/qa-history/](../archive/qa-history/)。

## 现行

| 文件 | 用途 |
|------|------|
| [整体审计报告-第六轮.md](整体审计报告-第六轮.md) | 第六轮缺陷复核（2026-11-27） |
| [一致性与逻辑检查-2026-11-27.md](一致性与逻辑检查-2026-11-27.md) | 第七轮一致性与逻辑检查（2026-11-27） |
| [硬编码与加载审计报告-2026-11-27.md](硬编码与加载审计报告-2026-11-27.md) | 第八轮硬编码 / 参数配置 / 加载链审计（2026-11-27） |
| [自动化审计执行报告-2026-11-27.md](自动化审计执行报告-2026-11-27.md) | **现行自动化审计执行**（第九轮，2026-11-27） |
| [DEV-a6-batch0-signoff.md](DEV-a6-batch0-signoff.md) | 第六轮 H1–H4 自动探针签字 |
| [DEV-hardcode-audit-2026-11-27.md](DEV-hardcode-audit-2026-11-27.md) | 硬编码专项（U2 · R1–R7） |
| [DEV-incident-30d-signoff.md](DEV-incident-30d-signoff.md) | Incident-only 30 日手签 |
| [DEV-functional-checklist.md](DEV-functional-checklist.md) | 功能手工清单 |
| [DEV-day-clock-manual-2026-11-26.md](DEV-day-clock-manual-2026-11-26.md) | 日钟 / 户外工时 5 步 |
| [RF-11.md](RF-11.md) | 客户端 / sim 对照 |
| [../modules/06-incident-migration.md](../modules/06-incident-migration.md) | 事件卡 → Incident |
| （本地生成） | `check_doc_consistency.py` → `qa/doc-consistency-report.md` |
| （本地生成） | `audit_locale_keys.py --write` → `qa/locale-key-audit.md` |

## 回归命令

```bash
# 推荐：按模块一次性跑（见 python tools/run_module_tests.py --list）
python tools/run_module_tests.py

# 第 0 批（单独重跑）
python tools/smoke_config.py
python tools/run_zero_a.py --runs 250
python tools/probe_save_migration.py
python tools/probe_config_paths.py
python tools/probe_event_weight_mc.py
python tools/probe_long_run_stability.py
python tools/audit_locale_placeholders.py
python tools/probe_orphan_data.py

# 单模块
python tools/run_module_tests.py -m data -m locale -m client

python tools/check_doc_consistency.py
python tools/stress_sweep.py
python tools/scan_hardcode_gd.py
python tools/probe_a6_signoff.py
```

```powershell
$env:GODOT_BIN = "D:\godot\Godot_v4.7.2-stable_win64_console.exe"
powershell -File tools/godot_compile_check.ps1
```

## 权威对照

- [开发计划 §12](../开发计划.md#12-godot-单人实施client) · [MILESTONES](../modules/MILESTONES.md)