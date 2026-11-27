# 仓库工具（现行）

| 脚本 | 用途 |
|------|------|
| `run_all_smoke.ps1` | 无头冒烟 + save_kill（主回归） |
| `run_godot_smoke.ps1` / `run_save_kill_smoke.ps1` | 单套件 |
| `validate_data_ci.py` | manifest / 表 / 战斗模板 id |
| `link_client_data.ps1` | `client/data` ↔ 仓库 `data/` junction |
| `audit_locale_keys.py` | `ui.csv` ↔ `LocaleApi.tr_*` 引用（`--write` → `qa/locale-key-audit.md`） |
| `annotate_gdscript_docs.py` | 函数体首行 `##` 上移到签名前 |
| `fill_gdscript_missing_docs.py` | 缺 `##` 的 func 按 `DOCS` 表补一行 |
| `enrich_core_service_docs.py` | README 核心 Service 多行 `##` + `@param` |
| `core_service_paths.py` | enrich 文件清单 |
| `scan_core_service_docs.py` | 报告缺文档 / 过短 `##`（只读） |
| `push_github.ps1` | 可选推送辅助 |
| `vfx_export/` | VFX 烘焙（见子目录 README） |

已移除（一次性/已完成）：`upgrade_gdscript_placeholder_docs.py` · `prune_gdscript_doc_noise.py`。