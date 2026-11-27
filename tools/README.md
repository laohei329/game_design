# 仓库工具（现行）

| 脚本 | 用途 |
|------|------|
| `sync_config_version.py` | 全库 `data/` + `client/data/` JSON 对齐 manifest `configVersion` |
| `check_doc_consistency.py` | Markdown 死链、过期脚本引用、权威头 `configVersion` 落后 → `qa/doc-consistency-report.md` |
| `smoke_config.py` | 最小回归：`ConfigDb.load_all` + `event_ops_sim` + `stress_sweep` |
| `stress_sweep.py` | 合成应力 → incident 触发（阶段 6/7） |
| `scan_hardcode_gd.py` | GDScript 玩法硬编码启发式扫描 |
| `link_client_data.ps1` | `client/data` ↔ 仓库 `data/` junction |
| `audit_locale_keys.py` | `ui.csv` ↔ `LocaleApi.tr_*` 引用（`--write` → `qa/locale-key-audit.md`） |
| `annotate_gdscript_docs.py` | 函数体首行 `##` 上移到签名前 |
| `fill_gdscript_missing_docs.py` | 缺 `##` 的 func 按 `DOCS` 表补一行 |
| `enrich_core_service_docs.py` | README 核心 Service 多行 `##` + `@param` |
| `core_service_paths.py` | enrich 文件清单 |
| `scan_core_service_docs.py` | 报告缺文档 / 过短 `##`（只读） |
| `godot_compile_check.ps1` | Godot 4.7+ 无头 `--import` + `--quit-after 1`（须 `GODOT_BIN`） |
| `push_github.ps1` | 可选推送辅助 |
| `vfx_export/` | VFX 烘焙（见子目录 README） |

> **说明（2026-11-27）**：`run_all_smoke.ps1` · `run_godot_smoke.ps1` · `run_save_kill_smoke.ps1` · `validate_data_ci.py` · `split_smoke_assertions.py` 已删除；需要 CI/冒烟时按项目现状重做。

已移除（一次性/已完成）：`upgrade_gdscript_placeholder_docs.py` · `prune_gdscript_doc_noise.py`。