# 仓库工具（现行）

| 脚本 | 用途 |
|------|------|
| `sync_config_version.py` | 全库 `data/` + `client/data/` JSON 对齐 manifest `configVersion` |
| `check_doc_consistency.py` | Markdown 探针 → `qa/doc-consistency-report.md`（gitignore，本地生成） |
| `run_module_tests.py` | **按模块编排**自动化回归（`--list` / `-m data` / 默认全套件） |
| `smoke_config.py` | 全表 + **`run_validation(s2)`** + 事件卡 op 负向测试 + `stress_sweep` |
| `run_zero_a.py` | 阶段零 A：2 策略 × N 局（默认 N=250）；`--strict` 闸失败 exit 1 |
| `probe_save_migration.py` | 迁移 manifest + JSON 往返 + Godot `SaveMigrationProbe` |
| `AUTOMATION.md` | 第 0/1/2 批自动化清单 |
| `probe_config_paths.py` | `require` 路径审计 |
| `probe_event_weight_mc.py` | 事件权重蒙特卡洛 |
| `probe_long_run_stability.py` | 长局 sim 稳定性 |
| `probe_orphan_data.py` | 孤儿 JSON / 事件索引 |
| `probe_locale_registration.py` | 翻译资源三向一致 |
| `audit_locale_placeholders.py` | 五语占位符 / 长度 |
| `stress_sweep.py` | 合成应力 → incident 触发（阶段 6/7） |
| `scan_hardcode_gd.py` | GDScript 玩法硬编码启发式扫描 |
| `link_client_data.ps1` | `client/data` ↔ 仓库 `data/` junction |
| `audit_locale_keys.py` | `ui.csv` ↔ 代码 key（`--write` → `qa/locale-key-audit.md`，gitignore） |
| `annotate_gdscript_docs.py` | 函数体首行 `##` 上移到签名前 |
| `fill_gdscript_missing_docs.py` | 缺 `##` 的 func 按 `DOCS` 表补一行 |
| `enrich_core_service_docs.py` | README 核心 Service 多行 `##` + `@param` |
| `core_service_paths.py` | enrich 文件清单 |
| `scan_core_service_docs.py` | 报告缺文档 / 过短 `##`（只读） |
| `probe_a6_signoff.py` | A6 签字探针：sim H3/M4R、locale H4、可选 Godot H1/H2（须 `GODOT_BIN`，否则 SKIP 或长等固定路径） |
| `client/scripts/debug/hc_config_probe_runner.gd` | 第八轮配置探针（legacyFiles / events_index）；由 `run_module_tests -m client` 调用 |
| `client/scripts/debug/save_migration_probe_runner.gd` | 迁移 v6→12 / v10→12 / v8 天气；headless 需自建 `ConfigDb` 节点 |
| `godot_compile_check.ps1` | Godot 4.7+ 无头 `--import` + `--quit-after 1`（须 `GODOT_BIN`） |
| `push_github.ps1` | 可选推送辅助 |
| `vfx_export/` | VFX 烘焙（见子目录 README） |

> **说明（2026-11-27）**：`run_all_smoke.ps1` · `run_godot_smoke.ps1` · `run_save_kill_smoke.ps1` · `validate_data_ci.py` · `split_smoke_assertions.py` 已删除；需要 CI/冒烟时按项目现状重做。

已移除（一次性/已完成）：`upgrade_gdscript_placeholder_docs.py` · `prune_gdscript_doc_noise.py`。