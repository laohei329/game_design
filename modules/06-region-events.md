# 模块：区域 · 事件

> 所属层：内容层 + 玩法层  
> 依赖：时间/气候（[01](01-time-season.md)）、列车雷达  
> 被依赖：发现池调制、资源点构成  
> **天气表、温度、气候倍率、影响因子数值、pressure 权威在 01**；本模块注册区域因子并调用抽取。  
> **区段生命周期、车站规模、收留触发**以本模块为准。

---

## 0. 区段生命周期（权威）

一条**区域跨度 RegionRun** 含 `segmentCount` 个**区段 Segment**（`segmentCount ∈ [3,5]`，三选一确认时掷定）。区段是行驶与内容的基本锚。  
（此处段数**不要**与装甲车数 `armorCars`/旧简写 N 混淆；跨度≠区段，见 [architecture §8.1](../architecture.md)。）

```
RegionRun {                 # 区域跨度 = 一次三选一后的整段行程
  regionId, tag             # 当前词条
  segmentCount              # 本跨度区段数 ∈[3,5]；文内勿再单写 N 指装甲
  segmentIndex = 0..count-1
  segments[]                # 各区段快照
  regionFuelMult            # F04 区域油耗系数；缺省 1.0；雪原 1.3；跨度开始写入
  pointTypeWeightMods{}     # 点位 type→乘子；跨度开始按 §1.2 写入；缺省键=1.0
}
# 世界级（非段内）：
world.pressureHistory[2]    # 最近两次建成段的 pressureClass；跨跨度保留；存档

Segment {                   # 区段
  id, lengthKm              # 基线 40–60，配置 stations.segmentLength*
  progressKm                # 0 → lengthKm；返程可减少并跨段（03 §6.2）
  stations[]                # 0–2 站；车站 size=small|medium|large（≠车厢 size）
                            # + nonePool/empty；每站车厢要约 offer?（≠事件选项）
  points[]                  # Point{id,type,remainingYield,depleted}（02 §7）
  eventId?                  # 本段主事件（可空）
  built: bool               # 是否已 onSegmentBuild（≠「车厢已建造」）
  segmentFuelSurcharge?     # 绕行成功附加，驶离本段清零（05 §6.3）
  raidWeightDelta?          # 谈判买路等写入；缺省 0；驶离本段清零（05 §6.3）
  pressureClass?            # 本段建成时写入；「连续两高压」读 world.pressureHistory
}
```

| 阶段 | 何时 | 动作 |
|---|---|---|
| **跨度开始** | 三选一确认 | 写区域因子；掷 `segmentCount`；写入 `regionFuelMult` + `pointTypeWeightMods`（§1.2）；生成 `segments[]` 骨架；`segmentIndex=0`；**清除上一跨度各站车厢要约** |
| **进入区段** | 首次驶入该段（`built=false`） | `expiresSegment` 扣减（[01 §4.3](01-time-season.md)）→ `onSegmentBuild`（§3）→ `built=true` |
| **读档恢复** | 读档落到已 `built=true` 的段 | **禁止**再跑 `onSegmentBuild` / 再扣 `expiresSegment`；只恢复存档中的天气、因子、点位、事件与 `progressKm` |
| **段内行驶** | `progressKm` 随 [03 §6.2](03-train.md) 增减 | 遇站可进站；搜索/战斗挂本段 `points`；返程可减进度并**跨段回退** `segmentIndex`，不撤 `built` |
| **返程越界** | 返程扣穿 `progressKm=0` 且 `segmentIndex>0` | `segmentIndex--`，`progressKm=新段 lengthKm`，余量继续扣；不重跑 build；第 0 段夹 0 并 STOPPED（权威式在 03 §6.2） |
| **区段结束** | `progressKm ≥ lengthKm` 且方向前进 | `segmentIndex++`；若仍有下一段 → 进入区段；否则 → **跨度结束** |
| **跨度结束** | 末段走完 | 触发下一轮三选一（§1）；清除 `source=region` 旧因子；**清除全部车站车厢要约**（lootPiles 临时堆保留） |

锚点约定：

- **天气单抽 / 事件抽取 / 车站已插入**：全部在「进入区段」的 `onSegmentBuild`（或跨度开始预生成车站列表，进入时只抽天气事件）。  
- **返程**：不重新 `onSegmentBuild`；不回退 `expiresSegment`；临时堆仍挂原点位；可跨段回到本跨度内已 `built` 段。  
- **车厢要约 vs 临时堆**：`offer` 随 **RegionRun 结束**清除；`lootPiles` 不因离段/离跨度删除（[04 §5.4](04-population.md)）。  
- 开局：生成**教程跨度**（§0.1）并进入第 0 段 → **完整** `onSegmentBuild`；与 [01 §5](01-time-season.md) 同一口径，禁止开局写死 `clear`。

### 0.1 教程跨度（首小时钩子 · 强制站）

开局固定生成，不掷普通车站概率：

| 项 | 规则 |
|---|---|
| `segmentCount` | **3**；词条默认旧城（可配置 `stations.tutorialRegion=urban`） |
| 第 0 段车站 | **恰好 1 座**有池站：`size=small`，`none_pool=false`，**跳过**空站 0.10 / 无池 0.08 |
| 站位 | `progressKm` 目标 ≈ `lengthKm × 0.50`（段长取 50 时约 25 km） |
| 可达日 | 按 [03 §6.2](03-train.md) `driveHoursPerDayCap=1.0`、开局约 6.7 km/日 → 站在 25 km 时约 **dayTotal 3–5** 首次进站 |
| 发现 | 首次进该站 → [03 §5](03-train.md) 强制 **受损休息车厢**（`living`，修复 1 零件） |
| 点位保底 | 第 **0** 段 `onSegmentBuild` 的 `points[]` **至少含 1×`supermarket` + 1×`water_plant`**（配置 `stations.tutorialForcePointTypes`）；其余点位仍按 §3 抽取。对齐 [02 §10](02-resources.md) 首周粮水缓冲。 |
| 第 1–2 段 | 恢复 §1.1 普通车站概率 |

禁止把首小时钩子做成「碰运气遇到站」。

### 0.2 世界拓扑（权威 · 非开放大地图 / 非关卡）

**定稿：程序化走廊（procedural corridor），不是开放随机大地图，也不是章节关卡。**

| 模式 | 本产品 | 理由 |
|---|---|---|
| 章节关卡（关1→关2） | **不做** | 与「纯无尽 / 无通关门槛」冲突（[architecture §1](../architecture.md)） |
| 开放随机大地图（自由漫游节点/2D 沙盒） | **不做** | 冲淡铁轨身份；行驶日额度、停靠油、雪原油压、秋储节奏难控；事件难锚 |
| **走廊 + 三选一 + 段生成** | **首发唯一** | 逻辑分段锚内容；表现可连续铁轨；油/粮/验收可调 |

**逻辑 vs 表现**：

- **逻辑**：`RegionRun` → `Segment[]` → `stations[]` / `points[]`（本模块 §0）。  
- **表现**：[08](08-presentation.md) 侧视连续铁轨与远景；**禁止**把 Segment 画成互不衔接的小地图拼盘；**禁止** UI 暗示「选关进入」。  
- 随机感靠：三选一情报不全、同词条段内变异（§1.3）、可选短分岔（§1.4），**不**靠开放地图自由度。

改拓扑（开放图 / 关卡制）须另开设计并重跑 [10](10-validation.md) 油粮与节奏验收；禁止实现静默换成大地图。

---

## 1. 区域三选一

每跨度结束触发，必须三选一（不可拒绝、不可重抽）。

流程：暂停 → 每选项 2 条模糊线索 → 若 `effectiveVision≥3`（[03 §7](03-train.md)）再 **+1** 条 → 确认 → §0 跨度开始（`segmentCount ∈ [3,5]`）。禁止写死「有雷达车就 +1」而忽略是否在岗/能见度。

| 词条 | 资源倾向（叙事） | 威胁 | 车厢发现倾向 | 气候因子（写入 01） |
|---|---|---|---|---|
| 疫区 | 药品/试剂 ×2.5 | 疫情、尸群 | 医疗 | `region.plague` |
| 雪原 | 燃料 ×2.0 | 低温、油耗 ×1.3 | 动力 | `region.tundra` |
| 矿区 | 零件/废料 ×2.2 | 塌方 | 装甲、工坊 | `region.mine` |
| 旧城区 | 食物/织物 ×1.8 | 掠夺者 | 休息、货舱、净水 | `region.urban` |
| 河谷 | 饮水/种子 ×2.2 | 洪水 | 种植、净水 | `region.valley` |
| 军事区 | 装备/晶核/废料 ×2.0；图纸点 | 变异体、武装 | 动力、装甲 | `region.military` |

雪原「油耗 ×1.3」→ 写入 `RegionRun.regionFuelMult=1.3`（其它词条 **1.0**）；与 `fuelClimate`、`region.*.tempMod` **分列**；总乘数上限 3.0（[02 §4](02-resources.md)）。  
因子数值见 [01 §4.4](01-time-season.md)。资源倾向的**可执行映射**见 §1.2（禁止只留叙事乘子）。

**秋储 / 冬雪原节奏（策划 · 零 A 沉淀）**：

| 窗口 | 意图 |
|---|---|
| 夏末→秋 | 三选一提高雪原价值；玩家应开始囤油/粮 |
| 秋中后～冬 | 雪原可在**资源池未空**时多留榨油；**池空必须进入下一段**（禁止空转吃 ×1.3） |
| 冬 | 「三选一必含雪原」类保底成立；入冬前罐不满视为操作失误而非数值坑 |
| 年2 春→夏 | 与生活线对齐：床位冲 ≥20，再收人（收留基率不改，见 [04](04-population.md)/§2.2） |

详细探针与零 B 纪律见 [10 §2](10-validation.md) · [08 §4](08-presentation.md)。

### 1.1 车站插入与规模

每区段插入车站数：

```
p0=0.35, p1=0.45, p2=0.20 → 站数 ∈ {0,1,2}
```

每站规模权重（再 × 区域车厢发现倾向；军事区 `large` ×1.4）：

| size | 权重 | 发现池（[03 §5](03-train.md)） |
|---|---|---|
| `small` | 0.50 | 小型池 |
| `medium` | 0.35 | 中型池 |
| `large` | 0.15 | 大型池 |

**有池车站**：`size ∈ {small,medium,large}` 且本站发现检定未判定为「空站」（空站概率基线 0.10，计入「进站无可获得车厢」）。  
**无池车站**：站数生成后仍可能标 `none_pool`（权重 0.08，与规模抽独立）——可进站搜刮点位/事件，但**不提供车厢发现池**。  
保底「下一**有池**车站必出」：只对 `none_pool=false` 的站生效（[03 §5](03-train.md)）。

军事区额外：每跨度至多 1 个「首领营」或「大型军械库」点（§2 点位），可掉 `blueprints`（[02 §2.3](02-resources.md)）。

### 1.2 区域 → 点位权重（`pointTypeWeightMods` · 权威）

跨度开始按词条写入；未列 type = **1.0**。与 [02 §7](02-resources.md) type 键对齐。

| 词条 | regionFuelMult | pointTypeWeightMods（节选） |
|---|---:|---|
| 疫区 | 1.0 | `hospital`×2.5，`lab`×2.5 |
| 雪原 | **1.3** | `gas_station`×2.0 |
| 矿区 | 1.0 | `factory`×2.2，`scrapyard`×2.2 |
| 旧城区 | 1.0 | `supermarket`×1.8，`residential`×1.8 |
| 河谷 | 1.0 | `water_plant`×2.2，`farm`×2.2 |
| 军事区 | 1.0 | `military_depot`×2.0，`scrapyard`×2.0；`armory_boss` 每跨度至多 1（不进普通权重池） |

配置：`regions.json` 每词条须含 `regionFuelMult` + `pointTypeWeightMods`。

### 1.3 段内变异（同词条去重复感）

在**不改词条、不拆走廊**前提下，于 `onSegmentBuild` / 跨度预生成时拉开段差异：

| 维度 | 规则 | 备注 |
|---|---|---|
| `lengthKm` | 已在 `stations.segmentLength*`（基线 40–60）；实现须真正采样，禁止恒中值 | 影响进站日序 |
| 站数 / 站位 | §1.1；站在段内 `progressKm` 均匀抖动 ±15%（夹进 (0.15,0.85)×length） | 教程第 0 段除外 |
| 点位组合 | §3 抽 3–4 点；**禁止**连续两段点位 type 多重集完全相同（可重抽至多 2 次） | 降「复制粘贴段」感 |
| 空站 / 无池 | 空站 0.10、无池 0.08 必须生效 | 发现饥荒靠保底，不靠假繁荣 |
| 死轨装饰 | 表现层可生成不可进的废弃侧线/塌桥远景 | **不**进 `stations[]`，不耗额度 |

禁止用「加大开放地图」替代本表。

### 1.4 短分岔（可选 · 仍汇回主跨度）

每 **RegionRun** 至多 **1** 条短分岔（`spur`），用于局部路线选择，**不是**开放支线网。

```
Spur {
  hostSegmentIndex      # 挂在本跨度某一主段
  lengthKm              # 12–24（短于主段）
  progressKm
  stations[]            # 0–1 站；大型池权重 ×0.5
  points[]              # 1–2 点；权重仍走 §1.2 × 季节
  rejoinsMain: true     # 走完或中途折返 → 回到 host 段原 progress 附近
}
```

| 规则 | 口径 |
|---|---|
| 出现率 | 跨度开始：`effectiveSpurChance = stations.spurChance × regions[tag].spurChanceMult`（缺省 mult **1.0**；基线 **0.35** 见 `stations.json`）；雷达 `effectiveVision≥3` 时三选一线索可暗示「前方有岔」 |
| 进入 | 驶近 host 段分岔标牌 → 暂停二选一：「主线继续」/「驶入短分岔」；不可拒绝提示，但可选主线 |
| 油耗 | 分岔内仍走 F04；可选写入本段 `segmentFuelSurcharge` **+0.05～0.10**（驶离分岔清零），表示绕行代价 |
| 行驶额度 | 分岔前进**计入** `driveHoursToday`；与主线同一额度池 |
| 返程 | 可在分岔内返程回汇合点；**不**另开 RegionRun |
| 禁止 | 分岔再分岔；分岔跨跨度；分岔当开放地图节点图；分岔逃避冬季（季节不因进岔重置） |

军事/矿区 `spurChanceMult` **1.25**（`regions.json`）；其余词条缺省 **1.0**。

---

## 2. 事件卡与收留

### 2.1 事件硬规则

- 2–4 个选项；禁止纯奖励  
- 每张至少一处延迟后果（flag + 天数）；`op`/`args` 见 [09 §3](09-data-platform.md)  
- 例：`weight_mod` + `args:{ eventTag:"raid", delta:+0.2 }` → 改本段事件权重缓存；`spawn_threat` + `args:{ threatTemplateId:"horde_small" }`  
- 必填：`weightEventId`、`yieldScale`（默认 1.0）  
- 可附带 `grantInfluence` / `clearInfluence`（结构见 01 §4.1）  
- **气候闭环**：选项结算若写入或移除任何 `ClimateInfluence` → **立即** `recomputeClimate()`（[01 §4.3](01-time-season.md)）；禁止拖到日结  
- 首发量：120 条（通用 60 + 季节 40 + 年份 20；收留类约 24）；目录 [`data/events/_index.json`](../data/events/_index.json) · 零 A sweep 经 `sim/event_loader.py` 加权抽取

### 2.2 收留触发（可执行）

目标期望：有空床时约 **0.15–0.17 人/日**。  
**行驶节奏权威**：[01 §2](01-time-season.md) → **0.10–0.17 段/日**（中位 **0.13**）；禁止再用 0.5 段/日校准。

| 来源 | 规则 | 中位贡献（人/日） |
|---|---|---|
| **收留事件** | `recruit` 标签；进入区段抽事件时：有空床基率使**期望成功 0.70 人/段**（食物不足人口×2 时成功期望 ×1.3，封顶 1.2 人/段）；选项成功 → 1 人（15% 为 2） | 0.13×0.70 ≈ **0.09** |
| **进站邂逅** | 每次进站：基率 `0.12`；过道 ×0.35；成功 → 1 人。期望约 0.9 站/段 | 0.13×0.9×0.12 ≈ **0.014** |
| **日结补抽** | 当日**尚未成功收留**（下方定义）且有空床：`0.05` → 「路边求收容」 | **0.05** |
| **合计** | — | ≈ **0.15–0.16**（落在目标带） |

**「当日尚未成功收留」**：本 `dayTotal` 内，收留事件 / 进站邂逅 / 日结补抽**均未成功加入新成员**。任一来源成功 → 写 `world.lastRecruitSuccessDay = dayTotal`，当日不再日结补抽。  
判定：`lastRecruitSuccessDay == dayTotal` → 已成功。字段须存档（[09](09-data-platform.md)）。  
行驶节奏与 [03 §6.2](03-train.md) `driveHoursPerDayCap` 对齐；改权重须用 **0.13 段/日** 重算。生成：`archetypes.json`（[04](04-population.md)）。

### 2.3 段事件抽取权重（配置权威）

数值表：[`data/event_draw_rules.json`](../data/event_draw_rules.json)（`configVersion` 与 manifest 对齐）。  
实现：`sim/event_loader.py` · `EventDrawContext` · `draw_event_id()`；客户端 `event_draw.gd` 须同参。

| 输入 | 作用 |
|---|---|
| 粮 / 水 vs `foodNeedPerCapita` / `waterNeedPerCapita` | `supply` 标签 **+supplyFoodBoost** / **+supplyWaterBoost** |
| 床位 vs 人口 | `recruit` **×recruitBedsFullMult** / **×recruitHasBedsMult**；粮紧且有空床 **×recruitLowFoodMult** |
| `segment.raidWeightDelta` | 仅 `raidDeltaTags`（默认 `raid`）**+delta** |
| 段内未搬空临时堆 | 掠夺类 **+unclaimedLootRaidBoost** |
| `guard` 在岗 | 掠夺类 **×guardOnDutyRaidMult** |
| `pharmacist` 在岗且词条=疫区 | 配置内 `pharmacistOnDutyTagBoost` |
| `forced_low_content`（连续两高压） | 低压标签 **+tagBoost**；`raid`/`weather` **×suppressTagMult** |
| 燃料 < `lowFuelSupplyBoost.fuelFillBelow` | 配置 tags（默认 `supply`）**+tagBoost** |
| 同跨度最近 `weightEventId` 重复 | **×noRepeatWeightEventId.weightMult**（窗口见配置） |
| 与上一段主标签相同 | **×tagRepeatPenalty.lastPrimaryTagMult** |

**不放回规则**：同一 `RegionRun` 内，最近 **N** 段（默认 2）已抽过的 `weightEventId` 仅降权，不硬排除。  
**禁止**：日结重算本表；禁止在 `onDayStart` 重抽段事件（红线 #2）。

文案（R3）：[`data/localization/events_*.csv`](../data/localization/README.md) + `sync_event_locale.py --bucket`；钩子参考 [`event_hooks_registry.json`](../data/events/event_hooks_registry.json)（只读，不跑脚本）。

点位类型扩展（军事）：

| 点位 | 主产出 | 中值 | 区域 |
|---|---|---|---|
| 大型军械库 / 首领营 | `blueprints`（四线之一布尔）+ 少量 parts/装备 | 图纸 1 条（未拥有线优先） | 仅军事；每跨度 ≤1 |

权威表仍以 [02 §7.1](02-resources.md) 为准；本行是军事区补充节点。

---

## 3. 节奏导演（`onSegmentBuild`）

仅在 **§0 进入区段** 时调用一次。

```
# 0) 同步地理因子
移除 climateInfluences 中 source=region 的旧项
按当前区域词条 Push(01 §4.4 对应因子)
# expiresSegment 已在进入前按 01 §4.3 扣减并清理

# 1) 天气（本区段唯一一次）
weights = 01.季节表 × Π 因子.weatherBias → 归一化
weatherId = WeightedDraw(weights)
world.weatherId = weatherId
01.recomputeClimate()

# 2) 压力（顺序锁死）
# 2a) 读历史：连续两高压 = pressureHistory[0]==high AND pressureHistory[1]==high
#     （不足 2 条记录 → 视为否；跨跨度历史仍有效）
# 2b) 调用 01 §9 得本段 pressure → 映射 pressureClass → 写入本 Segment
# 2c) 追加历史：pressureHistory := [pressureHistory[1], 本段 pressureClass]
#     （队头丢掉最旧；首段只有 1 条时用占位 null 不算「两高压」）

# 3) 内容与事件（写入本段事件权重缓存；日结禁止重抽，红线 #2）
若步骤 2a 为真 → 强制低压内容（在写入本段 class 之前已判定）
若食物 < 人口×2 → 补给事件权重 +0.4；收留权重见 §2.2
若有药剂师在岗 → 疫情 +0.2；若有守卫 → 掠夺者可和平
若区段内存在未搬临时堆 → 掠夺者/扫荡类事件权重 +0.25（夺走见 04 §5.4）
再加本段 raidWeightDelta（谈判买路等，缺省 0；仅掠夺/扫荡类）
抽取：3–4 资源点 + 1 事件（可与预生成点位合并去重）
# 延迟 op=weight_mod：改的是「本段事件权重缓存」，不是 onDayStart 重抽

# 4) 点位权重微调
w = 基权(下表) × RegionRun.pointTypeWeightMods[type] × 季节乘子(01§6) × 天气 nodeWeightMods
若点位属尸潮/搜索险内容且天气 ∈ {night_rain,blizzard,fog}：
  w *= max(0.60, 1 − 0.08×雷达科技等级)    # 03 §7；空岗雷达科技仍计等级减免
归一化后抽点
```

**点位类型基础权重（权威基线；type 键与 [02 §7.1](02-resources.md) / `data/point_types.json` 一致）**：

| type 键 | 基权重 |
|---|---:|
| `supermarket` / `farm` / `water_plant` / `gas_station` | 1.0 |
| `factory` / `scrapyard` | 0.8 |
| `hospital` / `lab` | 0.6 |
| `residential` | 0.7 |
| `military_depot` | 0.4（非军事区权重 **×0**，不进池） |
| `armory_boss` | 每跨度至多 1，不进普通权重池 |

改此表须同步验收燃料/食物供给假设；禁止实现私自另写一套权重。

禁止在本模块重写天气权重、温度公式或 `fuelClimate`。  
pressure 公式权威在 [01 §9](01-time-season.md)，此处只调用结果。  
**禁止**在 `onDayStart` 重抽本段事件/点位或重算事件抽取权重（日结只可读 pressure 显示值，见 [02 §8](02-resources.md) 步骤 8）。
