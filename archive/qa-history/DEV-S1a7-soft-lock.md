# DEV-S1a.7 — 软锁自检联调（§12.7）

在 Godot 运行 `run_main`，F3 查看 `§12.7` / `SoftLockProbe` 输出（`client/scripts/debug/soft_lock_probe.gd`）。

## 手工步骤

1. **结束一天 ×5**：粮水油件均 ≥ 0；F3 `OK 库存非负`。
2. **保底**：非教程站连续 **暂不挂** ×4 → 第 5 次进站出现「保底要约」；`guaranteeFailStreak` 在拒 4 次后 ≥4。
3. **搜索 cap**：同一点 **派人搜索** ×4 → 第 4 次 `ASSIGN_SEARCH: cap_exceeded`。
4. **末节动力**：**遗弃** → 选 `car_pwr` → 文案「最后一节动力不可遗弃」；确认灰显。
5. **遗弃货舱**：停靠 → **遗弃** `car_cgo` → 件 −1、废料 +、油略降、`driveHoursToday` +0.5；`carriage_abandon` 写入 `user://telemetry.jsonl`。
6. **搜索→堆→搬**：搜索结束一天 → 面板「待搬 food」→ 粮水**当日仍低**；再结束一天或同日电量内 → 粮水上升、`haul_complete` 埋点；满仓时堆上仍有余量。
7. **点名搜索**：搜索面板勾选 1–4 人（★搜刮 置顶）→ **开始搜索**；未勾选应 warning。
8. **存档堆**：搜索产生临时堆后 F3 **存档 0** → **读档 0** → 搜索面板「待搬」仍在；F3 `lootPiles=` 与存前一致。

## 内存探测（F3）

- `probe=PASS`：非负库存 + 末节动力拦截正确。
- `probe=CHECK`：按各行 FAIL 排查。

## S1b 后加项

- 杀进程读档不漂（SaveService v12）。