# 可移植 VFX 资源包

**目标**：在**本仓库外**的 Godot 项目里播放特效，**不需要**安装 `pixelfx` 插件。

## 产物形态（每个 `category/name` 一条）

| 文件 | 用途 |
|---|---|
| `*.png` | 精灵表（nearest 过滤） |
| `*.json` | Aseprite 风格 + `meta.pixelfx`（fps、loop、pivot、columns、act） |
| `*.res` | 可选 `SpriteFrames`，Godot `AnimatedSprite2D` 即用 |
| `index.json` | 本包清单（id、帧数、pivot 等） |

## 生成（开发机 · 一次性）

1. 安装 Godot 4.7+，设置环境变量 `GODOT` 指向可执行文件（可选）。
2. 编辑 [`manifest.json`](manifest.json) 里的 `effects[]`（id 格式 `category/name`，可用 `./pfx list` 在工具工程里搜）。
3. 在仓库根目录执行：

```powershell
powershell -File tools/vfx_export/bake_pack.ps1
```

默认写出到 `assets/vfx_portable/packs/<packId>/`。

## 移植到其他项目

1. 复制整个 `packs/<packId>/` 到目标工程，例如 `res://art/vfx/<packId>/`。
2. 使用 `AnimatedSprite2D` + `*.res`，或按 `*.json` 的 `meta.pixelfx.pivot` 对齐锚点导入 `*.png`。
3. **不要**拷贝 `addons/pixelfx`；运行时零代码绘制依赖。

## 与 `third_party/`

- **`third_party/pixelfx-godot/godot`**：仅 **烘焙工具链**（不进发售包）。
- **`godot-weather-2D`**：仍是场景天气插件；若也要「纯资源化」，可同样烘焙或只用 PNG 序列。

## 许可

产物源自 MIT 的 pixelfx 绘制逻辑；分发游戏时保留上游 `NOTICE`（见 `third_party/pixelfx-godot/NOTICE.md`）。