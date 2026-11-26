# VFX 导出 · 可移植资源包

把 pixelfx **代码特效**烘焙成 PNG / JSON / SpriteFrames，供 `assets/vfx_portable/` 及其他 Godot 工程使用。

| 脚本 | 作用 |
|---|---|
| [`bake_pack.ps1`](bake_pack.ps1) | 读 `assets/vfx_portable/manifest.json`，调用 `pfx sheets --spriteframes` |

依赖：`third_party/pixelfx-godot/godot` + 本机 Godot 4.7+。