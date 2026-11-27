# P1 数据包（S1b · 战斗 / 人口 / 本地化）

> 实体 `configVersion` 见 [`manifest.json`](manifest.json) · 对齐 [GODOT_ARCH §9.2](modules/GODOT_ARCH.md)  
> 加载顺序：先 `manifest.json` → 各表；`combat.l1Unit` 权威 **`combat.json`**（`balance.combat` 为 sim 兼容镜像）。

## 本包新增文件

| 文件 | 用途 | 分期 |
|---|---|---|
| `combat.json` | L1/L2 公式常数、占位、非战斗路径 | S1b L1+ |
| `gear.json` | 三类战斗装备数值 | S1b |
| `abilities.json` | 11 异能 hooks | S2/S3（战前页 S1b 可读表） |
| `archetypes.json` | 收留原型、开局四人模板、12 背景 stub | S1b |
| `disease.json` | 病程与传播 | S1b 可读；S2 加厚 |
| `items.json` | 药剂 / 蓝图 / 库存键元数据 | S1b |
| `combat-targets.json` | 敌模板与 `enemyBoost` | S1b L1 |
| `combat-objectives.json` | 16 战斗目标文案键 | S2 表现 |
| `combat-trauma.json` | 创伤标签（行动受限 vs 叙事） | S2 |
| `combat-adaptation.json` | EA 批次三占位 | 禁用 |
| `localization/*.csv` | 岗位 / 战斗 / 异能最小键 | S1b 可只载 zh+en |
| `migrations/manifest.json` | save 2→12 链契约 | S1b 存档 |

## 仍属 P2+ 内容生产（未在本包扩量）

- 成员背景 **200**、遗言 **200**、创伤叙事 **24** 全文（见 [08 §3](modules/08-presentation.md)）  
- 事件卡五语精修  
- `combat-adaptation` 规则实现  
- 客户端 `migrations/*.gd` 实现（见 manifest `runtimeNote`）

## 修改纪律

1. 改战斗/异能/疾病常数 → 对照 `modules/04` / `05`  
2. bump `configVersion` + `python tools/sync_config_version.py`（若动 balance 冻结项须走 [10 §1.1](modules/10-validation.md) 解冻）  
3. 同步 `manifest.json` 的 `files` 键  
4. 提交前：Godot 启动校验 `ConfigDb`；文档 `python tools/check_doc_consistency.py`