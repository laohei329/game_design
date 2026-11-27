# DEV · 日钟与户外工时 · 手工验收（2026-11-26）

**权威**：[01 §2.3](../modules/01-time-season.md) · [04 §5](../modules/04-population.md) · `SmokeAssertions.errors_outdoor_day_clock_p0_a`

**自动**：`powershell tools/run_all_smoke.ps1`（含 forward 全日 / 无日钟 / 停 0.5+行 0.5 / haul forward）

## 手工场景（约 3 分钟）

| # | 操作 | 期望 |
|---|------|------|
| A | 新局 → **停靠** → 打开搜索 → 派人搜索 → **不关面板** | 搜索/搬运 `ProgressBar` 随时间上涨；HUD 饥渴行变化；**不**因开搜索而全停表 |
| B | 切 **前进** · 倍速 2× | 户外进度条停涨；饥渴涨幅慢于停靠（`metabolismMult.forward`） |
| C | 再切 **停靠** 数十秒 | 进度条续涨；乘员饥渴涨快 |
| D | **P** 暂停 · 再 **P** | 日钟与进度冻住/恢复 |
| E | 决策弹窗（F3 无关）进站或战斗 | 全停表；关窗后恢复 |

## 回归命令

```powershell
powershell tools/run_all_smoke.ps1
```