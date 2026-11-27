# A6 第 0 批验收签字（2026-11-27）

> 自动探针：`python tools/probe_a6_signoff.py`  
> Godot 子探针：`client/scripts/debug/a6_probe_runner.gd`（契约镜像，无 ConfigDb 依赖）

## 结果摘要

| ID | 探针 | 结果 |
|---|---|---|
| A6-H1 | Godot `A6Batch0Probe` | OK（返程 progress=length、第 0 段 stop） |
| A6-H2 | Godot `A6Batch0Probe` | OK（orphan_loot_piles 保留堆） |
| A6-H3 | Python sim | OK（day1 nodes=4；首站 day 5；tutorial_done） |
| A6-H4 | `audit_locale_keys.py` | OK（静态键缺行 0） |

## 2026-11-27 实跑日志

```text
python tools/probe_a6_signoff.py
  → probe_a6_signoff: OK

python tools/smoke_config.py
  → smoke_config: OK

powershell -File tools/godot_compile_check.ps1
  → godot_compile_check: OK
```

## 人工说明

- H1/H2 探针验证与 `region_service.gd` / `drive_service.gd` / `loot_pile_service.gd` **同契约**的镜像逻辑；全链路仍依赖编辑器内 F3 `SoftLockProbe` 做运行时巡检。
- H3 教程车挂定时以 seed 42 为准；换种子若首站 >8 日需另记。

签字：**自动探针绿 · 2026-11-27**