# RF-11 · sim 规则对齐探针

## 命令

```bash
python sim/compare_rules.py
```

已接入 `tools/run_all_smoke.ps1`。

## 覆盖

- `fuelTank`：`engine` 与 `run_time_event_sweep` 的 `FUEL_TANK_*` 与 `data/balance.json` 一致
- `climateColdFoodFuel` / `climateHeatWater`：`engine` 加载表与 balance 一致
- `manifest` 与 `balance.configVersion` 一致

## 未覆盖（见 [RF-11-event-draw-factors.md](RF-11-event-draw-factors.md)）

- `EventDrawContext` 字段级与 Godot `event_draw.gd` 逐项差分
- `food_need` / 未领堆等 sim 简化项