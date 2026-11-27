# 清理候选清单（只读扫描，2026-11-27）

**⚠️ 此操作非常危险，可能导致不可逆的数据丢失！**

> **本轮只做只读扫描与登记**：没有删除、移动、重命名或改写任何已有文件；只新增本清单。  
> 只有在你明确回复「确认清理某一组」后，我才会执行；执行前会先备份，并优先使用回收站而不是永久删除。  
> 范围：`C:\Users\Administrator\Desktop\game_design`，不触碰 `third_party/`、`.git/`、`assets/vfx_portable/` 与系统目录。

## 执行记录（2026-11-27，用户确认 A + C）

- 备份：`archive/cleanup-backup-2026-11-27/` 已保存下列三份文件的逐文件副本，SHA-256 校验通过：
  - `qa/locale-key-audit.md`
  - `qa/doc-consistency-report.md`
  - `qa/CONFIG_TABLE_WIRING.md`
- A 组：两份生成报告已移入 Windows 回收站；随后已重跑 `python tools/audit_locale_keys.py --write` 与 `python tools/check_doc_consistency.py` 重新生成，最终 `doc consistency: 0 issue(s)`。
- C 组：`qa/CONFIG_TABLE_WIRING.md` 已移入 Windows 回收站；`qa/README.md` 对应索引行已移除。
- B 组（2026-11-27 晚）：已 `git rm` 25 个非 UI `.translation`（abilities/combat/events_*）；保留 `ui.*.translation` 与 `*.csv.import`。

### 执行记录（2026-11-27 晚 · 代码/文档收口）

- `client/scripts/qa/` + `client/scenes/qa/`：无头冒烟脚本/场景已从 Git 移除；`SoftLockProbe` 在 `scripts/debug/`。
- 文档：`开发计划.md` §12 现行闸改为 `smoke_config` / `stress_sweep`；`qa/DEV-functional-checklist.md` §F；`tools/README.md`；新增 `tools/godot_compile_check.ps1`。
- 回归：`check_doc_consistency` + `smoke_config` + `stress_sweep` + `scan_hardcode_gd`（见下方命令）。

---

## 0. 已经完成的清理（无需再操作）

扫描期间仓库已被并行过程清理过一轮；以下是当前实际状态，仅作记录，不再执行删除。

### 0.1 已删除的测试脚本 / 无头冒烟设施

以下文件在工作树中已不存在（`git ls-files --deleted` 确认）：

```text
client/scenes/qa/headless_save_kill.tscn
client/scenes/qa/headless_smoke.tscn
client/scripts/qa/headless_save_kill.gd
client/scripts/qa/headless_save_kill.gd.uid
client/scripts/qa/headless_smoke.gd
client/scripts/qa/headless_smoke.gd.uid
client/scripts/qa/smoke_assertions.gd
client/scripts/qa/smoke_assertions.gd.uid
client/scripts/qa/smoke_assertions_core.gd
client/scripts/qa/smoke_assertions_core.gd.uid
client/scripts/qa/smoke_assertions_events.gd
client/scripts/qa/smoke_assertions_events.gd.uid
client/scripts/qa/smoke_assertions_helpers.gd
client/scripts/qa/smoke_assertions_helpers.gd.uid
client/scripts/qa/smoke_assertions_outdoor.gd
client/scripts/qa/smoke_assertions_outdoor.gd.uid
client/scripts/qa/smoke_assertions_world.gd
client/scripts/qa/smoke_assertions_world.gd.uid
client/scripts/qa/soft_lock_probe.gd
client/scripts/qa/soft_lock_probe.gd.uid
sim/run_time_event_sweep.py
sim/run_zero_a.py
sim/validate_config_db.py
tools/run_all_smoke.ps1
tools/run_godot_smoke.ps1
tools/run_save_kill_smoke.ps1
tools/split_smoke_assertions.py
tools/validate_data_ci.py
```

**风险提示**：这些脚本已删；`开发计划.md` §8 已改为 `tools/smoke_config.py` 等现行命令。`check_doc_consistency.py` 当前 **0 issue**；`qa/doc-consistency-report.md` 为本地快照（可重跑覆盖）。

### 0.2 已归档的过期文档

以下文件已从 `qa/` 移入 `archive/qa-history/`，并已有归档索引 `archive/qa-history/README.md`：

```text
archive/qa-history/DEV-M1-M2-smoke-2026-11-26.md
archive/qa-history/DEV-M3-04-combat-l1.md
archive/qa-history/DEV-S1a7-soft-lock.md
archive/qa-history/DEV-S2-01-event-modal.md
archive/qa-history/DEV-S2-02-event-ops.md
archive/qa-history/DEV-code-quality-2026-11-26.md
archive/qa-history/DEV-code-audit-2026-11-26.md
archive/qa-history/DEV-code-audit-2026-11-26-r2.md
archive/qa-history/代码模块审计报告.md
archive/qa-history/代码模块审计报告-第二轮.md
archive/qa-history/代码模块审计报告-第三轮.md
archive/qa-history/DEV-RF-11-parity.md
archive/qa-history/README.md
```

**建议保留**：这些是历史证据，`qa/README.md` 与归档索引均指向它们。再删会丢失审计链；不建议永久删除。

---

## 1. 可执行清理候选（需你明确确认）

### A 组 · 生成的 QA 报告（低风险，删后需立刻重跑）

| 路径 | 再生命令 | 风险 | 置信度 |
|---|---|---|---|
| `C:\Users\Administrator\Desktop\game_design\qa\locale-key-audit.md` | `python tools/audit_locale_keys.py --write` | 删除后 `qa/README.md:16` 与 `tools/README.md:8` 的链接暂时失效；重跑即恢复 | 高 |
| `C:\Users\Administrator\Desktop\game_design\qa\doc-consistency-report.md` | `python tools/check_doc_consistency.py` | 删除后 `qa/README.md:15` 链接暂时失效；重跑即恢复。报告为快照，重跑后以最新 0 issue 覆盖 | 高 |

**建议**：这两份文件本质是快照，删除收益很低；更稳妥的做法是覆盖重跑。若你确认清理，我会在备份后移入回收站，然后立即重跑生成，保证索引不悬空。

### B 组 · 非界面本地化生成物（中风险，可删但需 Godot 重导入）

以下 25 个文件是 Godot 从 CSV 导入生成的翻译资源，**未被 `client/project.godot:43` 注册**；运行时 `LocaleDb.reload_locale()` 会从 CSV 重建 TranslationServer，因此运行影响低，但编辑器产物会丢失，直到再次用 Godot 打开 `client/` 工程重导入：

```text
C:\Users\Administrator\Desktop\game_design\data\localization\abilities.en.translation
C:\Users\Administrator\Desktop\game_design\data\localization\abilities.zh.translation
C:\Users\Administrator\Desktop\game_design\data\localization\abilities.de.translation
C:\Users\Administrator\Desktop\game_design\data\localization\abilities.ru.translation
C:\Users\Administrator\Desktop\game_design\data\localization\abilities.es.translation
C:\Users\Administrator\Desktop\game_design\data\localization\combat.en.translation
C:\Users\Administrator\Desktop\game_design\data\localization\combat.zh.translation
C:\Users\Administrator\Desktop\game_design\data\localization\combat.de.translation
C:\Users\Administrator\Desktop\game_design\data\localization\combat.ru.translation
C:\Users\Administrator\Desktop\game_design\data\localization\combat.es.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_general.en.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_general.zh.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_general.de.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_general.ru.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_general.es.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_season.en.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_season.zh.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_season.de.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_season.ru.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_season.es.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_year.en.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_year.zh.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_year.de.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_year.ru.translation
C:\Users\Administrator\Desktop\game_design\data\localization\events_year.es.translation
```

**不要删除**：`ui.en/zh/de/ru/es.translation`（5 个），它们被 `project.godot` 注册为冷启动资源。  
**不要删除**：6 个 `*.csv.import`，它们保存 Godot 导入设置；重导入会重建，但删掉会导致编辑器反复重导入。

### C 组 · 过期文档（中风险，建议更新而非删除）

| 路径 | 问题 | 风险 | 建议 |
|---|---|---|---|
| ~~`qa/CONFIG_TABLE_WIRING.md`~~ | **已删**（C 组 2026-11-27 清理）；接线见 `data/P1_README.md` 与 `config_db` 表清单 | — | 勿再列为现存候选 |

---

## 2. 明确不建议删除的文件

- `archive/qa-history/**`：已归档且有索引，删掉会断审计链。
- `archive/settlement-deferred.md`：被 `architecture.md`、`modules/01-time-season.md`、`modules/04-population.md` 引用。
- `data/events/gen_event_stubs.py`：已用 `manifest_config_version()` 动态写卡（第四轮 OA-H3 已闭）；仍是 120 卡重建脚本，不能删除。
- `qa/RF-11.md`、`qa/DEV-hardcode-audit-2026-11-27.md`、`qa/整体审计报告-第四轮.md`：现行审计入口。
- `sim/config_db.py`、`sim/engine.py`、`sim/event_loader.py`、`sim/point_types.py`：模拟器核心，仍被引用。
- `tools/sync_config_version.py`、`tools/check_doc_consistency.py`、`tools/audit_locale_keys.py` 等：现行工具链。
- `client/data/**`：`data/` 的 junction，不是副本。

---

## 3. 若你确认清理，执行纪律

1. 先在 `archive/cleanup-backup-2026-11-27/` 建立逐文件备份，确认备份成功。
2. 每批最多 10 个文件；每批后校验。
3. 使用 Windows 回收站机制，不使用 `rm` / `del /F` 永久删除。
4. A 组删除后立即重跑生成命令并修复索引链接。
5. B 组删除后提示你用 Godot 打开 `client/` 一次以重导入；不删 `ui.*` 与 `*.csv.import`。
6. C 组若确认删除，同时更新 `qa/README.md` 与 `qa/doc-consistency-report.md`。

**请回复要清理的组**：例如「确认清理 A」「确认清理 B」「确认清理 A+B+C」，或「先不删，只修文档」。未收到明确确认前，我不会改动任何文件。
