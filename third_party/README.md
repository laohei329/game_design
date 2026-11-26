# third_party · 外部开源素材

仅作参考与试用；进游戏前核对各包 `LICENSE` / `NOTICE`。

## 发行策略（推荐）

| 阶段 | 本仓库 | 游戏 / 其他 Godot 工程 |
|---|---|---|
| **开发** | `pixelfx-godot/godot` 烘焙工具链 | — |
| **交付** | [`assets/vfx_portable/`](../assets/vfx_portable/README.md) 资源包 | 只拷 `packs/<packId>/`（PNG + JSON + `.res`），**不**拷插件 |

生成命令：[`tools/vfx_export/bake_pack.ps1`](../tools/vfx_export/bake_pack.ps1)。

## 目录

| 目录 | 来源 | 许可 | 用途 |
|---|---|---|---|
| [pixelfx-godot/godot](pixelfx-godot/godot) | [winkidney/pixelfx-godot](https://github.com/winkidney/pixelfx-godot) | MIT | **仅烘焙**：`./pfx sheets … --spriteframes` |
| [godot-weather-2D](godot-weather-2D/) | [pirachute/godot-weather-2D](https://github.com/pirachute/godot-weather-2D) | MIT | 2D 天气（可插件运行，或自行资源化） |

**瘦身**：已删独立 JS `pixelfx/`、vendored `src/`、`godot-particle/`、demo/tests 等。完整上游请 `git clone` 原仓。

商用：MIT 可商用，保留版权声明。字体等例外见各仓 `NOTICE.md`。