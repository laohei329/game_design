# 本地化 CSV

首发五语列：`en` · `zh` · `de` · `ru` · `es`（与 [08 §1](modules/08-presentation.md) 一致）。

| 文件 | 用途 | 写入方 |
|---|---|---|
| `ui.csv` | 岗位 / 战斗入口 / HUD / 面板模板句 | 手改；运行时由 Autoload `LocaleDb` 加载 |

**Mod / 调试**

- 覆盖键：把同格式 CSV 放进 `user://mods/locale/`，启动时合并（后文件覆盖）。
- 语言：`project.godot` → `[game] locale` = `zh|en|de|ru|es`（与 `[internationalization] locale` 同步由 `LocaleDb.set_locale`）。
- 查键：`locale_debug_keys=true` 时 UI 显示 `[key]` 便于对表。

**Godot TranslationServer / csv_translation**

1. `ui.csv` 使用首列 `key`，后续列 `en,zh,de,ru,es`（与 `ui.csv.import` 的 `csv_translation` 一致）。
2. 在 Godot 编辑器中打开 `client/` 工程一次，会生成 `ui.*.translation` 并写入 `project.godot` `[internationalization] translations`（已预置路径）。
3. 运行时 `LocaleDb.reload_locale()` **总是**根据合并后的 CSV（含 Mod）重建 `Translation` 并 `TranslationServer.add_translation`；编辑器产物可作无 Mod 时的冷启动补充。
4. 代码中取词：**`LocaleApi.tr_key("hud.btn.search")`**（`class_name` 的 `static func` 必须用 `LocaleApi`，勿写 `LocaleDb.xxx`）；内部走 `TranslationServer.translate`。场景节点也可设 `text = "hud.btn.search"` + `auto_translate = true`（本工程暂用手动 `_sync` 赋值）。
5. 热重载：`LocaleDb.reload_locale()`（改 CSV / Mod 后）。

**HUD 键（节选）**：`hud.btn.end_day` · `hud.btn.heating` · `hud.btn.enter_station` · `hud.btn.search` · `hud.btn.abandon` · `hud.btn.tech` · `hud.btn.combat_dev`；驾驶用既有 `drive.forward|reverse|stop`。

**事件弹窗**：壳 `event.modal.chrome` + 模板 `event.modal.title`（`{0}` 壳、`{1}` 卡标题）；正文/选项仍读事件 JSON。
| `combat.csv` | 战斗目标、异能名 | 手改 |
| `abilities.csv` | 药剂与异能短述 | 手改 |
| **`events_general.csv`** | **通用事件 gen_001–060** | **管线** `--bucket general` |
| **`events_season.csv`** | **季节事件 spr/sum/aut/win 各10** | **管线** `--bucket season` |
| **`events_year.csv`** | **年份事件 yr_001–020** | **管线** `--bucket year` |

## 通用事件管线

```bash
# 通用 60 / 季节 40 / 年份 20（推荐首次各跑一遍）
python data/events/sync_event_locale.py --bucket general pipeline
python data/events/sync_event_locale.py --bucket season pipeline
python data/events/sync_event_locale.py --bucket year pipeline

# 日常：改 CSV 后写回卡片
python data/events/sync_event_locale.py --bucket season import

# 改卡内 zh/en 后刷新表（会覆盖 CSV，先备份）
python data/events/sync_event_locale.py --bucket general export
python data/events/sync_event_locale.py --bucket season seed
```

### 键名

| 键 | 含义 |
|---|---|
| `event.gen_012.title` | 标题五语 |
| `event.gen_012.body` | 正文五语 |
| `event.gen_012.logLine` | 日志句五语 |
| `event.gen_012.opt.shelter` | 选项 `shelter` 按钮文案 |

JSON 内仍为 `title` / `body` / `logLine` / `options[].label` 对象；`import` 写入五种语言键。

### 分工

- **译员**：只改 `events_general.csv`（或 CAT 导出同列）。
- **策划**：改单卡机制仍直接改 `gen_*.json` 的 `options` / `op`；然后 `export` 同步键表。
- **禁止**：用 `gen_event_stubs.py` 全量重生覆盖已译 CSV（R3）。

120 张事件五语 CSV 与 JSON 已齐；新卡先 `export` → 译 CSV → `import`。