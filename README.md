# 末日列车：生存序列 — 文档

> 版本：设计 v1.3.33 / 规格 v1.52 / configVersion **30**（十项闸 config25）/ version.save 12  
> 结构：总架构 → 玩法模块 → 工程附件

## 怎么读

| 顺序 | 文件 | 读什么 |
|---|---|---|
| 1 | [architecture.md](architecture.md) | 定位、分层、依赖、红线；§8.1 缩写 |
| 2 | [modules/](modules/) 01–10 | 规则与公式（08 含提示/HUD；10 含冻结/手算/灰盒） |
| 3 | [MILESTONES](modules/MILESTONES.md) | **里程碑 · 验收**（M0–M6 · **M-D Demo · M-EA**） |
| 4 | [GODOT_ARCH](modules/GODOT_ARCH.md) | 客户端分层 · Intent · S0–S3 细项 |
| 5 | [OPEN_LOOPS](modules/OPEN_LOOPS.md) | 缺口与剩余风险 |
| 6 | [sim/](sim/) | Python 数值沙盒库（无固定 runner） |
| — | [client/](client/) | Godot 4 工程；实施勾选 **[开发计划 §12](开发计划.md#12-godot-单人实施client)** · 验收 **[qa/](qa/README.md)** · 工具 **[tools/README.md](tools/README.md)** |
| — | [assets/vfx_portable/](assets/vfx_portable/) | 可移植 VFX 资源包（烘焙产出，可拷到其他 Godot 工程） |
| 7 | [archive/VERSION.md](archive/VERSION.md) | 版本沿革 |

## 核心玩法模块（01–10）

| 模块 | 内容 |
|---|---|
| [01 时间·季节·天气·温度](modules/01-time-season.md) | 日历、天气、气候消耗 |
| [02 资源](modules/02-resources.md) | 六元、日结、转换 |
| [03 列车](modules/03-train.md) | 车厢模板与设备、发现、驾驶、科技 |
| [04 人口](modules/04-population.md) | 岗位、任务、异能、疾病 |
| [05 战斗](modules/05-combat.md) | 编队、L1–L3 |
| [06 区域与事件](modules/06-region-events.md) | 区段、三选一、收留 |
| [07 结局·元进度](modules/07-endings-meta.md) | 失败、收藏 |
| [08 表现与内容](modules/08-presentation.md) | UI、音效、模板、**玩家软规则/提示/HUD** |
| [09 数据与存档](modules/09-data-platform.md) | 配置、迁移、埋点 |
| [10 验收](modules/10-validation.md) | 零 A/B、**冻结、手算、灰盒包**、制作阶段 |
| [MILESTONES](modules/MILESTONES.md) | **里程碑 M0–M6 · 验收过线 · 当前状态** |

## 工程附件

| 文档 | 用途 |
|---|---|
| [开发计划](开发计划.md) | **项目排期 + Godot 单人实施 §12**（服务/界面/勾选） |
| [MILESTONES](modules/MILESTONES.md) | **排期与验收索引** |
| [GODOT_ARCH](modules/GODOT_ARCH.md) | **Godot/GDScript** · 分层 · S0–S3 |
| [整体审计报告（第六轮）](qa/整体审计报告-第六轮.md) | 第六轮缺陷复核 |
| [一致性与逻辑检查（第七轮）](qa/一致性与逻辑检查-2026-11-27.md) | 第七轮一致性与逻辑检查 |
| [硬编码与加载审计（第八轮）](qa/硬编码与加载审计报告-2026-11-27.md) | 第八轮硬编码 / 配置 / 加载审计 |
| [自动化审计执行（第九轮）](qa/自动化审计执行报告-2026-11-27.md) | **现行**自动化审计执行 |
| [OPEN_LOOPS](modules/OPEN_LOOPS.md) | L 缺口 · 剩余风险 |
| [data/](data/) | 配置权威 |

## 按角色

- **主策**：architecture → **MILESTONES** → 10 → OPEN_LOOPS  
- **程序**：architecture → **MILESTONES** → GODOT_ARCH → 09 → 08  
- **数值**：02、03、05、10  
- **文案**：08、06、events 卡  
- **QA**：**MILESTONES** + 10 + GODOT_ARCH §10  

## 修改纪律

1. 只改对应模块正文  
2. 同步配置键与验收  
3. 触碰红线/分层 → architecture  
4. **冻结期内**（config **25**）不随意改乘子/开局/验收阈；须改时走 [10 §1.1](modules/10-validation.md) 解冻流程并按当时现状重做数值验收  
