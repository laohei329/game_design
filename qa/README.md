# QA 证据目录

验收与审计的**现行索引**。历史证据见 [archive/qa-history/](../archive/qa-history/)。

## 现行

| 文件 | 用途 |
|------|------|
| [整体审计报告-第六轮.md](整体审计报告-第六轮.md) | **现行缺陷复核**（2026-11-27） |
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
python tools/check_doc_consistency.py
python tools/smoke_config.py
python tools/stress_sweep.py
python tools/scan_hardcode_gd.py
```

```powershell
$env:GODOT_BIN = "D:\godot\Godot_v4.7.2-stable_win64_console.exe"
powershell -File tools/godot_compile_check.ps1
```

## 权威对照

- [开发计划 §12](../开发计划.md#12-godot-单人实施client) · [MILESTONES](../modules/MILESTONES.md)