# QA 证据目录

验收与审计材料的**现行索引**。命名：`qa/<主题>-<短名>.md` 或 `qa/DEV-<里程碑>-<序号>-<短名>.md`（见 [开发计划 §14.7](../开发计划.md)）。

## 现行文档（2026-11-26）

| 文件 | 用途 |
|------|------|
| [DEV-code-audit-2026-11-26.md](DEV-code-audit-2026-11-26.md) | **代码层审计**（冒烟基线 + §8 硬编码/存档/逻辑） |
| [DEV-code-audit-2026-11-26-r2.md](DEV-code-audit-2026-11-26-r2.md) | **续审 R2**（IntentRouter · M2 库存 · 冒烟布局 · §8 勘误） |
| [DEV-code-quality-2026-11-26.md](DEV-code-quality-2026-11-26.md) | 冗余/重复代码审计 + 本批清理 |
| [代码模块审计报告.md](代码模块审计报告.md) | 结合设计/规划文档的分模块代码审计（28 项：高 6 / 中 16 / 低 6） |
| [locale-key-audit.md](locale-key-audit.md) | `audit_locale_keys.py` 生成（可再跑覆盖） |
| [CONFIG_TABLE_WIRING.md](CONFIG_TABLE_WIRING.md) | manifest ↔ Service 接线清单 |
| [DEV-S2-01-event-modal.md](DEV-S2-01-event-modal.md) | 事件弹窗冒烟证据 |
| [DEV-S2-02-event-ops.md](DEV-S2-02-event-ops.md) | EventOps / 延迟 / snapshot 证据 |
| [DEV-functional-checklist.md](DEV-functional-checklist.md) | 功能勾选手工清单 |
| [DEV-M1-M2-smoke-2026-11-26.md](DEV-M1-M2-smoke-2026-11-26.md) | 无头冒烟证据（§12.7） |
| [DEV-day-clock-manual-2026-11-26.md](DEV-day-clock-manual-2026-11-26.md) | 日钟 / 户外工时 / 搜索不关表 · 手工 5 步 |
| [DEV-S1a7-soft-lock.md](DEV-S1a7-soft-lock.md) | 软锁人工 8 步 |
| [DEV-M3-04-combat-l1.md](DEV-M3-04-combat-l1.md) | L1 战斗冒烟与人工 |

## 权威对照

- 勾选与进度：**[开发计划 §12](../开发计划.md#12-godot-单人实施client)**、**§14**
- 里程碑：**[MILESTONES](../modules/MILESTONES.md)**

## 回归命令

```powershell
powershell tools/run_all_smoke.ps1
python tools/validate_data_ci.py
```