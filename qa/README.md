# QA 证据目录

验收与审计的**现行索引**。命名：`qa/<主题>.md` 或 `DEV-<主题>-<日期>.md`。

## 现行（维护）

| 文件 | 用途 |
|------|------|
| [整体审计报告-第六轮.md](整体审计报告-第六轮.md) | **现行缺陷复核**（2026-11-27）：4 高 / 13 中 / 4 低，含可复现证据 |
| [整体审计报告-第五轮.md](整体审计报告-第五轮.md) | 全面审计（2026-11-27，部分状态已被第六轮推翻） |
| [整体审计报告-第四轮.md](整体审计报告-第四轮.md) | 第四轮 + §8 落地表（历史基线） |
| [DEV-hardcode-audit-2026-11-27.md](DEV-hardcode-audit-2026-11-27.md) | 硬编码专项（H/U1 已闭 · §2 多轮 R1–R7） |
| [../modules/06-incident-migration.md](../modules/06-incident-migration.md) | 事件卡 → Incident 迁移 |
| `python tools/stress_sweep.py` | 阶段 6 应力触发扫掠 |
| [RF-11.md](RF-11.md) | 客户端 / sim 对照（合并 RF-11） |
| [DEV-functional-checklist.md](DEV-functional-checklist.md) | 功能勾选手工清单 |
| [DEV-day-clock-manual-2026-11-26.md](DEV-day-clock-manual-2026-11-26.md) | 日钟 / 户外工时手工 5 步 |
| [doc-consistency-report.md](doc-consistency-report.md) | `tools/check_doc_consistency.py` 输出 |
| [locale-key-audit.md](locale-key-audit.md) | `audit_locale_keys.py` 生成 |

## 历史

[archive/qa-history/](../archive/qa-history/)：冒烟证据、代码审计 R1–R3、已删 runner 相关 md。

## 权威对照

- 勾选与进度：[开发计划 §12](../开发计划.md#12-godot-单人实施client)、§14
- 里程碑：[MILESTONES](../modules/MILESTONES.md)

## 文档一致性

```bash
python tools/check_doc_consistency.py
python tools/smoke_config.py
python tools/stress_sweep.py
python tools/scan_hardcode_gd.py
```

Godot 编译（本机须 4.7+ 且在 `PATH` 或设 `GODOT_BIN`）：

```powershell
powershell -File tools/godot_compile_check.ps1
```

无头冒烟/CI **已移除**（2026-11-27）；Godot 侧旧 QA 冒烟目录已删。勿引用归档里的旧 runner 字面量。