# Godot 客户端（S0 → S1a）

**开发计划（本人写代码）**：[开发计划.md §12](../开发计划.md#12-godot-单人实施client)  
里程碑验收：[modules/MILESTONES.md](../modules/MILESTONES.md) · 分层细则：[modules/GODOT_ARCH.md](../modules/GODOT_ARCH.md)

## 数据目录

Godot 需 `res://data/` 与仓库 `data/` 一致：

```powershell
# 自 game_design 根目录（推荐 junction，改 data 即时生效）
cmd /c mklink /J client\data ..\data
```

无 junction 时可将 `data/` **复制**到 `client/data/`。

## 启动

1. Godot 4.x → 打开 `client/project.godot`
2. 运行主场景 `scenes/boot.tscn`（F5）
3. 配置校验（CI）：`python sim/validate_config_db.py`

## S0/S1a 已实现骨架

| 组件 | 脚本 |
|---|---|
| ConfigDb | `scripts/data/config_db.gd` |
| IntentBus + GameSession | `scripts/app/` |
| 进站 defer 阈值 | `scripts/gameplay/station_defer_service.gd` |
| 遗弃车厢 | `scripts/gameplay/train_service.gd` |
| 搜索次数（Item7 草案） | `scripts/gameplay/search_service.gd` |
| 遥测 | `scripts/data/telemetry_service.gd` |
| 存档缺省 | `scripts/data/save_service.gd` |

玩法日结 / 完整 F04 仍在迭代；本包优先 **Intent 接线 + 配置只读 + 遥测 + 存档缺省**。