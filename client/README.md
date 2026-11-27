# Godot 客户端（S0 → S1a）

**代码怎么读**：[scripts/README.md](scripts/README.md)（从 IntentBus / GameSession 入手）

**开发计划（本人写代码）**：[开发计划.md §12](../开发计划.md#12-godot-单人实施client)  
里程碑验收：[modules/MILESTONES.md](../modules/MILESTONES.md) · 分层细则：[modules/GODOT_ARCH.md](../modules/GODOT_ARCH.md)  
**代码审计**：[qa/整体审计报告-第四轮.md](../qa/整体审计报告-第四轮.md)

## 数据目录

Godot 需 `res://data/` 与仓库 `data/` 一致：

```powershell
# 自 game_design 根目录（推荐 junction，改 data 即时生效）
cmd /c mklink /J client\data ..\data
```

无 junction 时可将 `data/` **复制**到 `client/data/`。

配置回归（仓库根）：

```bash
python tools/smoke_config.py
```

无头编译快检（须安装 Godot 4.7+ 并设 `GODOT_BIN`）：

```powershell
$env:GODOT_BIN = "C:\path\to\Godot_v4.x.exe"
powershell -File tools/godot_compile_check.ps1
```

## 启动

1. Godot **4.7+** → 打开 `client/project.godot`
2. **F5** 主场景 `scenes/run_main.tscn`（`boot.tscn` 仅配置校验后跳转）
3. **F3** 调试覆盖层；功能清单见 [qa/DEV-functional-checklist.md](../qa/DEV-functional-checklist.md)

## S1a 已落地（摘要）

| 组件 | 脚本 |
|---|---|
| ConfigDb | `scripts/data/config_db.gd` |
| IntentBus + GameSession | `scripts/app/` |
| 驾驶 / 进站 / 搜索 / 遗弃 | `scripts/gameplay/*_service.gd` |
| 日结 F04 / 人口日耗 | `economy/day_settle.gd` · `balance.population.*` |
| 界面 | `scenes/run_main.tscn` · `ui/hud_top` · station/search/abandon |
| 区域三选一 | `region_service.gd` · `ui/region_pick.tscn` · `PICK_REGION` |
| 四线科技 Lv1 | `tech_service.gd` · `ui/tech_panel.tscn` · 停靠「科技」· `BUY_UPGRADE` |
| 日结 6–8 薄 | `day_settle.gd` · `RunState.precision` / `morale_offset` |
| L1 战斗 | `combat_l1.gd` · `combat_panel.tscn` · 停靠「遭遇」 |
| S2 段事件 | `event_modal` · `EventOps` · `content/event_*` |
| 文案 | `LocaleApi` + `ui.csv`（Autoload `LocaleDb`） |

S1b+ 仍缺：**L2 战斗会话**；详情见 [开发计划 §12](../开发计划.md#12-godot-单人实施client)。
