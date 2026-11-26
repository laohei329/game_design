# 模块：资源

> 所属层：经济层  
> 依赖：时间·气候（日耗倍率）、列车（油耗/槽位/设备）、人口（粮水）  
> 被依赖：战斗、科技、事件、设备制造、结局判定  
> **权威**：库存字段、日结顺序、产出/消耗公式、转换规则以本模块为准。  
> **公式代号**：F04=日燃料消耗；F05=种植日产；F32=净水日产；F39=饥渴/脱水 hp 日扣。总表见 [architecture §8.1](../architecture.md)。

---

## 1. 设计意图

稀缺靠**前进 + 有限补给点**，不靠商店互转（红线 #7）。  
资源分三层：**核心六元**（顶栏）→ **材料四元**（工艺输入）→ **道具**（有上限的专用物）。  
材料→核心只允许**有损系统转换**（耗时/耗工位/损耗率），禁止 1:1 兑换台。

```
补给点/事件
        ↓
   入库（受上限）
        ↓
  ┌─ 日结刚性：粮/水/燃料 ──→ 归零后果 / 失败
  ├─ 触发消耗：药/零件、药剂、战斗装备耐久
  └─ 工艺：废料→零件、试剂→药品、晶核+试剂→药剂、种子→种植
```

---

## 2. 资源总表

### 2.1 核心六元（顶栏；不可互转）

| id | 名 | 日耗/触发 | 主要来源 | 主要去向 |
|---|---|---|---|---|
| `food` | 食物 | `车上人口 × 0.9 × foodClimate` | 超市、种植车厢（F05 日产） | 日结 |
| `water` | 饮水 | `车上人口 × 0.8 × waterClimate` | 水厂、净水车厢（F32 日产） | 日结 |
| `fuel` | 燃料 | F04 日耗（% 点） | 加油站 | 行驶；净水 F32 需燃料>0；造零件附加 |
| `parts` | 零件 | 无刚性日耗 | 工厂、残骸、**废料精炼**、工坊产出 | 修车/车厢/科技/设备 |
| `medicine` | 药品 | 治疗触发 | 医院、试剂配制 | 治疗；科技 Lv2；**配药剂辅料** |
| `crystal` | 晶核 | 无刚性日耗 | 军事仓库 + 隐藏事件 | **仅作药剂材料**（§5.4）；禁止直接吞服/直接付科技 |

气候倍率权威：[01 §8](01-time-season.md)。

### 2.2 材料四元（工艺层）

| id | 名 | 刚性日耗 | 主要来源 | 转换出口（唯一） |
|---|---|---|---|---|
| `scrap` | 废料 | 无 | 残骸、矿区点、拆舱 | 工坊精炼 → `parts`（§5.1） |
| `seed` | 种子 | 无 | 农田点、河谷事件、旧温室 | 维持种植架；无种时 F05×0.5（§3） |
| `chem` | 试剂 | 无 | 医院、实验室点、疫区 | → `medicine`（§5.2）；→ 药剂（§5.4） |
| `cloth` | 织物 | 无 | 旧城民宅、货列 | 床铺/包扎（§5.3） |

**禁止**：废料当零件；试剂当药喝；织物当食物；**晶核直接当科技费或异能费**。

### 2.3 道具：药剂 · 装备 · 图纸

| id | 名 | 上限 | 来源 | 消耗 |
|---|---|---|---|---|
| `potion.awaken` | **觉醒药剂** | **无上限** | 药剂师配制（§5.4） | 饮用 → 觉醒异能（[04 §8](04-population.md)）；在世觉醒者仍 ≤3 |
| `potion.upgrade` | **升级药剂** | 5 | 同上 | 饮用 → 强化已有异能 |
| `potion.catalyst` | **催化药剂** | 10 | 同上 | 发动异能；科技 Lv3+（替代原「直接扣晶核」） |
| `gear.ranged` / `melee` / `defense` | 战斗装备 | 各类 10 | 军事仓库等 | 编队挂载 |
| `blueprints` | 图纸 | **四线布尔解锁**（不叠数量） | 军事区「大型军械库/首领营」（[06 §2](06-region-events.md)；§7.1） | 解锁该线 Lv4/Lv5 **资格**；升级时**不消耗** |
| `equip` 实体 | 未装车设备 | 列表 | 搜刮/制造 | 装入车厢槽 |

**分类口径（权威在战斗模块，库存只计数）**：

| 类 | 例 | 战斗职责 |
|---|---|---|
| 远程 | 步枪、弩、自制火枪 | 抬输出；克群 |
| 近战 | 砍刀、刺矛、工兵铲 | 抬输出；压敌方伤 |
| 单兵防御 | 防弹衣、盾牌、防毒面罩 | 降低该成员分摊伤害 |

旧字段 `weaponKits`：**废止**；迁移时 `ranged += kits`，`melee += ⌊kits/2⌋`，`defense += ⌊kits/3⌋`（见存档迁移）。  
顶栏可显示三色小计数或「装备」汇总入口，不必三格常驻。

---

## 3. 产出公式（F05 种植日产 / F32 净水日产）

日结只调用下列两式；禁止「车数 × 常数」简化。

**F05 · 种植日产**（`function=greenhouse`；UI 称种植车厢）

```
重叠惩罚 = 0.90^max(0, 同 function 车厢数 − 2)
种子系数 = (种子库存 ≥ 种植架台数) ? 1.0 : 0.5
  # 台数 = Σ 已装 grow_rack 占用的「架位」（dual 计 2）
  # 有意：阈值门槛按「每架 ≥1 粒库存」算满种；日耗 0.05/架只在满种时扣（见下）

单车 30 日理论 = 120 × (efficiency/100) × 重叠惩罚
                × greenhouseClimate × 0.95^(年份−1) × 种子系数
                # 120 = 满效 4/日 × 30；不乘车上人口（人口压力靠加车消化）

单车当日产出 = 单车 30 日理论 / 30
全日种植产出 = Σ 各种植车当日产出   → 入 food
```

- `greenhouseClimate`：冷侧无供暖 **0.50** / 供暖中 **0.95**，否则 1.0（[01 §8.1.1](01-time-season.md)）  
- **不乘车上人口**：单车产出固定（满效 4/日），人口压力靠加车消化。结合 `0.90^(n−2)` 的饱和上限，见 [01 §10](01-time-season.md) 的 12/14/16 人配比结论。  
- 供暖开销 `0.30 × 种植车数` 百分点燃料/日，在日结**步骤 3b** 扣；燃料不足则整日不供暖、不扣燃料（§8）  
- 式中已含 `0.95^(年份−1)` = `yearProd`（[01 §9](01-time-season.md)）  
- 满仓：**停止累积**  
- 需 1 名 `grower` 在岗；无人 → 0  
- 在岗 `grower` 有 `farming` 专长 → 该车当日产出再 ×1.10（[04 §4.5](04-population.md)）  
- 种子系数用 0.5 时**不扣**种子；系数为 1.0 时每日再扣 `0.05 × 架位数`（可配置 `greenhouse.seedConsumePerRackDay=0.05`，见 [09 §1](09-data-platform.md)），扣到 0 则次日变 0.5  

**F32 · 净水日产**（`function=water`）

```
单车基础 = advanced ? 15 : 10
重叠惩罚 = 0.90^max(0, 同 function=water 车厢数 − 2)   # 与 F05 同构，按净水车计数
单车当日 = 单车基础 × (efficiency/100) × 重叠惩罚 × yearProd
全日净水 = Σ → 入 water
```

- `yearProd = 0.95^(年份−1)`（与 F05 同；**不**乘工坊 precision/300）  
- **燃料 = 0** → 该车当日 0（与「无燃料强制停车」闭环）  
- 需 1 名 `purifier` 在岗；无人 → 0；不随气候变倍率  
- `advanced=true` 时 efficiency 可达 150  

**纸面校验**：2 节 efficiency=100 种植、20 人、cold=0、有种、第 1 年 → 每车日产 4，合计 8。2 节普通净水 → 日产 20；夏晴 20 人饮水 `20×0.8×1.5=24`，日缺口 4，须搜索补水。

### 3.1 晶核期望（可复算）

```
每区段晶核期望 ≡ 0.10（权威总和，含军事仓 + 隐藏事件）

军事仓全局期望/段 =
  P(本段属军事区) × E[本段军事仓点数] × E[对该点搜索次数] × 0.10
基线校准（可改配置但须重算隐藏项）：
  P(军事)≈1/6；E[点数]≈0.5；E[搜索]≈1.2 → 军事仓 ≈ 0.01
隐藏事件期望/段 = 0.10 − 军事仓全局期望   # 上例 ≈ 0.09
```

军事仓库：仅军事区；每次对该点**完成搜索** 10% 掉 1 晶核。  
`balance.crystalHiddenChance` = 隐藏期望折算到「每段一次隐藏检定」的概率；改任一项须保持段期望和为 0.10。

### 3.2 工坊造零件（与精炼分列）

**聚合单位（权威）**：按**在岗 crafter 工位**计，不是按车厢全局一次。

```
每节 workshop：工位上限 = min(2, 该节在岗 crafter 数)
每个在岗工位当日互斥二选一：造零件 或 精炼（面板按工位勾选；默认同节同模式）

造零件（每工位）：
  日产 parts += precision / 300          # 不乘 yearProd；多工位各自加一份
精炼（每工位）：见 §5.1（每工位每日至多 1 批 scrap3→parts1）

当日任一工位造零件 → 额外燃料 +0.5%/日（只加一次，不按工位叠）
precision 日变：若≥1 工位造零件 → +1；否则若≥1 工位精炼 → 0；否则空转 −1
  # 全车共用一条 precision；多工坊不叠 +1/−1
```

**`workshopSlotDay`（验收/手算用）**：当日计入造零件或精炼的有效工位·日；每名在岗且未因改装/兼搜互斥的 `crafter` 选该模式 → +1.0。用于冬季劳力手算（[10](10-validation.md)）；**不**另改上列「造零件 +0.5% 只加一次」燃料规则。

精炼 ≠ 岗位。车体维修一 / 失护检修 / **出车搜索**占用的 crafter **当日不计入**上列在岗工位（[03 §4](03-train.md)/[04 §4.3](04-population.md)）。

---

## 4. 燃料日耗 F04

```
# 下式 = 「当前状态折合的全日耗油率」（%/日）；tick 积分时 × 本 tick 日长
燃料日耗率(%/日) = (3 + Σ每节油耗增量百分点)
            × 牵引效率
            × min(速度系数 × fuelClimate × regionFuelMult × (1+segmentFuelSurcharge), 3.0)

# Σ油耗增量：功能车/装甲按 [03 §2](03-train.md)；第 2+ 节动力各 +0.5；首节动力不进 Σ（已含常数 3）
牵引效率 = max(0.40, 1 − 0.08×min(动力车数,3) − 0.08×动力科技等级)

fuelClimate（权威与 01 §8 同一表）:
  coldIndex ≥ 2 → 1.56
  coldIndex ≥ 1 → 1.43
  coldIndex ≥ 0.5 → 1.15
  else → 1.00

regionFuelMult = RegionRun.regionFuelMult   # 跨度开始写入；缺省 1.0；雪原 1.3（06 §1）
```

速度系数：停车/额度用尽 0.3 / 低速 0.8 / 巡航 1.0 / 高速 1.3。  
`segmentFuelSurcharge` 缺省 0（绕行成功写入，见 [05 §6.3](05-combat.md)）；与 `regionFuelMult`、`fuelClimate` 一并进上式 `min(..., 3.0)`。  
起始 1 动力+休息+货舱全日巡航对照约 `(3+1.0+1.0)×0.92`——非日结默认。  
**禁止**再乘季节燃料系数或天气独立油耗；禁止供暖并入本式（走步骤 3b）。

**日结算（与行驶日额度对齐）**：在 `onDayStart` 用**昨日**积分：

```
# tick 积分（权威）：每个 tick 取该 tick 的速度系数
# 若当日 travelBudgetExhausted 且 driveIntent=forward → 本 tick 速度系数 = 0.3
# （与 03 §6.2 一致；禁止额度用尽后仍按巡航/高速计油）
fuelDay% = Σ_tick ( 燃料日耗率(%/日) × 本 tick 日长 )
```

无 tick 积分时的等价简化（须与上式同结果）：

```
前进小时 = min(driveHoursToday_昨日, driveHoursPerDayCap)   # 有效推进小时
返程小时 = reverseHoursToday_昨日
停靠小时 = max(0, 24 − 前进小时 − 返程小时)               # 含「额度用尽后的前进空转」
速度系数_日 = (前进小时 × 巡航档系数 + 返程小时 × 0.8 + 停靠小时 × 0.3) / 24
```

前进默认「巡航 1.0」、返程默认「低速 0.8」（若昨日有效前进 tick 多为高速/其它档，按**未用尽额度前**的实际档加权）。  
禁止：全日按面板档 ×1.0；禁止把返程并进停车 0.3；禁止额度用尽后的前进 tick 仍用巡航系数。

**供暖为独立扣项**（§8 步骤 3b），不进 F04 日耗率；禁止并入牵引效率或怠速系数，否则冷侧会被重复惩罚。

---

## 5. 有损转换（材料出口）

### 5.1 废料 → 零件

```
须对应工位有 crafter 在岗；该工位选「精炼」：
  每工位每日至多 1 批：消耗 scrap 3 → 产出 parts 1
  precision 规则见 §3.2（精炼不单独 ±precision）
  不单独触发燃料附加（仅造零件工位触发一次 +0.5%）
  与同工位「造零件」互斥
精炼不是独立岗位（[04 §4](04-population.md)）
```

### 5.2 试剂 → 药品

```
停靠 + 医疗车厢 + job=pharmacist：
  消耗 chem 2 → medicine 1，耗时 2 游戏小时（= 2/24 日，见 01 §2.1）
无医疗台 / 无人 → 不可制
```

### 5.3 织物

```
制作床铺设备 bunk：cloth 2 + parts 1
战斗/疾病「简易包扎」：cloth 1 → 临时减伤或延缓恶化（04），不替代 medicine
```

### 5.4 晶核 → 药剂（药剂师；唯一晶核出口）

须：**医疗车厢** + `job=pharmacist` + 停靠（与治疗/制药品同一岗，不互斥）。  
有 `pharmacy` 专长 → 配制时长 ×0.75（[04 §4.5](04-population.md)）。

| 产物 | 配方 | 耗时 | 备注 |
|---|---|---|---|
| `potion.awaken` 觉醒药剂 ×1 | crystal 1 + chem 2 + medicine 1 | 4 游戏小时 | 第 2 年起可配；年 1 配方锁 |
| `potion.upgrade` 升级药剂 ×1 | crystal 1 + chem 1 + medicine 1 | 3 游戏小时 | **可预囤**；饮用时校验：已觉醒 + `proficiency≥60` + Lv1（[04 §8.1](04-population.md)） |
| `potion.catalyst` 催化药剂 ×2 | crystal 1 + chem 1 | 2 游戏小时 | 异能发动 / 科技 Lv3+ |

```
禁止：库存界面「右键晶核使用」
禁止：科技升级 UI 直接扣 crystal（只认 potion.catalyst）
禁止：战斗声明异能时扣 crystal（只认 potion.catalyst，数量见 04 §8.3）
```

溢出：`upgrade`/`catalyst` 达上限则该次配制取消并退材料；**`awaken` 无上限**，不受本条约束。

---

## 6. 库存上限

生活科技倍率 `lifeMult = 1 + 0.10 × 生活科技等级`（晶核、药剂、装备、图纸除外）。

| 资源 | 基础 | 每节 cargo `size` 增量 | 科技 |
|---|---|---|---|
| food / water | 60 | `size×10` | ×lifeMult |
| parts | 20 | `round(size×10/3)` | ×lifeMult |
| medicine | 15 | `round(size×5/3)` | ×lifeMult |
| crystal | 5 | 0 | **硬上限 5**（原料）；列车满则**留在临时堆/点上**，禁止静默销毁 |
| fuel | 100% | `size×6` 百分点 | — |
| scrap | 30 | `size×8` | ×lifeMult |
| seed | 20 | `size×4` | ×lifeMult |
| chem | 15 | `round(size×5/3)` | ×lifeMult |
| cloth | 20 | `size×5` | ×lifeMult |
| potion.awaken | — | — | **无上限**（在世觉醒者仍 ≤3；晶核硬上限 5 仍限制配制节奏） |
| potion.upgrade | — | — | **硬上限 5** |
| potion.catalyst | — | — | **硬上限 10** |
| gear.ranged / melee / defense | — | — | **各类硬上限 10** |

开局货舱 size=3、科技 0：food/water 上限 **90**；parts 30；fuel 118%。  
休息车槽若改装 `cargo_rack`（储物架，`slotCost=1`）：该节对 food/water 额外 `+8` 上限（拆床换储的代价）；**不**改 `templateId`。  
满仓：搜索溢出不装（留堆）；F05/F32 **停止累积**；精炼/配制若产出溢出则取消该次转换。

燃料上限**禁止**旧口径「+20%/货舱」。

---

## 7. 补给点

**权威 type 键（禁止并行缩写）**：`Segment.points[].type`、`regions.json` 的 `pointTypeWeightMods`、掉落与存档一律用 [§7.1](#71-点位类型与单次中值配置-regions-可覆盖) 的 **type 键**（如 `gas_station`，**禁止**再写 `fuel` / `food` 等库存简称）。配置总表：`data/point_types.json`（含 `baseWeight`、中值、`inventoryPrimary`）。  
**零 A 冒烟收窄**：`simYield` 列仅供 `sim/` 入库简化；正式客户端应按 `inventoryPrimary` 与 §7.1 多产出结算。

```
Point {
  id, type                  # type 对齐下表 / 06 基权键
  remainingYield            # 初值 = 该类型中值 × 2.5；搜索扣减
  depleted: bool            # remainingYield≤0
}
```

- 点位本体挂在 `Segment.points[]` 并存档（[09](09-data-platform.md)）；**临时堆** `lootPiles[]` 是已搜出未搬物资，与 `remainingYield` 分列  
- **搜索/搬运派人**权威在 [04 §5](04-population.md)：点名可派人 → 扣 `remainingYield` → 点位临时堆 → `labor` 搬运入库（无搜刮员岗位）  
- 临时堆**不超时蒸发**；仅杂工搬走或被掠夺者等单位夺走（04 §5.4）  
- 重复搜索：受伤概率 +0.05/次（上限 0.95）；有 `scavenge` 专长者该权重 ×0.8；伤员不可再派  
- **点位权重合成（权威）**：`06 §3 基权` × `RegionRun.pointTypeWeightMods[type]`（[06 §1.2](06-region-events.md)）× `01` 季节乘子 × 天气 `nodeWeightMods` ×（适用时）雷达威胁减免 → 归一化  
- 区段耗尽后只能前进；未搬临时堆仍留在原点，可返程 

### 7.1 点位类型与单次中值（配置 `regions` 可覆盖）

| 点位 | type 键 | 主产出 | 中值 | simYield（零 A） | 区域倾向（06 §1.2） |
|---|---|---|---:|---|---|
| 废弃超市 | `supermarket` | food | 8 | food | 旧城食物类 |
| 农田/种子库 | `farm` | seed (+ 少食) | seed 4 / food 2 | seed | 河谷种子类 |
| 水厂 | `water_plant` | water | 11 | water | 河谷饮水类 |
| 加油站 | `gas_station` | fuel | 30% | fuel | 雪原燃料类 |
| 机械厂 | `factory` | parts | 3.5 | parts | 矿区零件类 |
| 残骸堆 | `scrapyard` | scrap | 6 | parts | 矿区/军事废料类 |
| 医院 | `hospital` | medicine + chem | med 3 / chem 2 | med | 疫区药品类 |
| 实验室 | `lab` | chem | 4 | med | 疫区试剂类 |
| 民宅货列 | `residential` | cloth + food | cloth 5 / food 3 | mixed | 旧城织物类 |
| 军事仓库 | `military_depot` | parts + 战斗装备 + 晶核检定 | parts 1.5；装备各 0–1；10% crystal | parts | 军事装备类 |
| 大型军械库 / 首领营 | `armory_boss` | `blueprints` + 少 parts/装备 | 未拥有线图纸 1；parts 1 | — | 仅军事；每跨度 ≤1 |

---

## 8. 日结闭环（顺序锁死）

与 [01](01-time-season.md) 对齐：

```
onDayStart:
  -1. 到期 `delayedEvents` 结算（改因子则立刻 `recomputeClimate`，见 [01 §4.3](01-time-season.md)/[09](09-data-platform.md)）
  0. 用当前 driveHoursToday / reverseHoursToday（尚未清零 = 昨日累计）结算 F04（§4）；再二者 = 0
  1. recomputeClimate()
  2. 扣 food / water（车上人口 × 气候）
     → 当日标志 foodWentZero / waterWentZero = (扣后该资源 == 0)
     → 若 foodWentZero：foodZeroStreak++；否则 foodZeroStreak = 0
     → 若 waterWentZero：waterZeroStreak++；否则 waterZeroStreak = 0
  3. 应用步骤 0 算出的燃料扣减（此处**暂不**改 fuelZeroStreak）
  3b. 种植供暖（coldIndex≥1 且 world.heatingEnabled）：扣 0.30×种植车数 燃料
     → fuel 不足则本次不扣、全部按未供暖结算（[01 §8.1.1](01-time-season.md)）
  3c. 燃料 streak（权威时点）：步骤 3+3b **全部扣完并 clamp 后**
     → 若 fuel==0：fuelZeroStreak++；否则 fuelZeroStreak = 0
  4. F05 种植 → food（种子规则；greenhouseClimate 读步骤 3b 结果）
  5. F32 净水 → water（燃料已为 0 则跳过产出）
  6. 工坊日结算（造零件 XOR 精炼；precision 涨跌）
  7. 归零后果判定（§9）——粮水用步骤 2；燃料用步骤 3c；**不看**产后库存
  7b. 集体士气（[04 §9](04-population.md)：9.1 mood → 9.2 offset → 9.3 集体士气/streak）
  8. 刷新 pressure **显示/缓存值**（只读 [01 §9](01-time-season.md)）；收留日结补抽（[06 §2.2](06-region-events.md)）
     # 禁止：日结重算事件权重或重抽事件/点位（权重与抽取仅 onSegmentBuild，见 06 §3；红线 #2）
  8b. 车体抛锚计数（[03 §6.3](03-train.md)）：bodyHp≥30 → breakdownCounter=0；
      bodyHp<30 且 counter≥3 → 抛锚 2h 并清零；否则 bodyHp<30 → counter+=1
```

步骤 0 必须在清零前进/返程小时 **之前**读昨日累计（[03 §6.2](03-train.md)）。  
步骤 0 的 F04 使用**当前已维护**的 `fuelClimate`（事件改因子须已即时重算，见 [01 §4.3](01-time-season.md)）；步骤 1 的重算服务当日粮水/UI。

扣费后所有核心库存 **clamp 到 [0, 该资源上限]**，再判 `*WentZero` / `fuel==0`（禁止出现负库存）。

**禁止**：先产出再扣导致「当日凭空撑过」；禁止日结外再扣一笔同口径粮水。

**缺口计数口径（权威）**：

| 字段 | 类型 | 规则 |
|---|---|---|
| `foodWentZero` / `waterWentZero` | 当日布尔 | 扣费后、产出前判定；产后回正**不**改当日标志 |
| `foodZeroStreak` / `waterZeroStreak` / `fuelZeroStreak` | 存档连续日（[09](09-data-platform.md)） | 当日对应缺口为真则 +1，否则归 0；产回库存**不**清当日已计 |

`foodZeroStreak` 或 `waterZeroStreak` ≥ 3 → **本步起** F39（饥渴/脱水全体 hp 日扣）生效（与燃料失败同口径：连续第 3 个缺口日结点当日触发，不另延一日）。疾病触发同此计数（[04 §7](04-population.md)）。

---

## 9. 归零与缺货后果

| 情况 | 后果 |
|---|---|
| 粮/水缺（当日 `*WentZero`） | 士气 offset −13 / −16（`moraleOffset` 下限 **−60**，见 [04 §9.2](04-population.md)） |
| `foodZeroStreak` 或 `waterZeroStreak` ≥ 3 | 全体 hp −20/日（步骤 7 当日起）= **F39**；死因饥饿/脱水 |
| 燃料 = 0（当日） | 强制停车；F32=0；种植供暖不可用（greenhouseClimate=0.50） |
| `fuelZeroStreak` ≥ 3 | 失败（[07](07-endings-meta.md) 优先 3） |
| 零件 = 0 | 无法维修/升级/装设备；不直接失败 |
| 药品 = 0 | 只能织物包扎或硬抗；疫情风险↑ |
| 晶核 = 0 | 无法再配新药剂（已有药剂仍可用） |
| 催化药剂 = 0 | 异能无法发动；科技 Lv3+ 锁 |
| 种子 = 0 | 种植 F05×0.5 |
| 废料/试剂/织物 = 0 | 对应转换不可用 |

---

## 10. 起始条件（校验）

| 项 | 值 |
|---|---|
| 编组 | 动力 size3 + **休息** size2 + 货舱 size3 |
| 人口 | 4（床位 4）；编制见 [04 §4.3.1](04-population.md)：1 动力看护 + 1 守卫 + 2 杂工 |
| food / water | 20 / **24** |
| fuel | 88% |
| parts / medicine | 6 / 4 |
| scrap / seed / chem / cloth | 2 / 1 / 0 / 1 |
| gear 三类 / crystal / 药剂 | 0 / 0 / 0 |

粮：基准气候约 **5.5 日**（`20/(4×0.9)`）。水：**24** 起点——基准约 7.5 日；极端饮水天气（如 sandstorm 使 `waterClimate≈1.44`）仍 ≥**5 日**（`24/(4×0.8×1.44)≈5.2`），覆盖教程站 day 3–5。  
燃料按 §4、以 `time.driveHoursPerDayCap` 加权（无返程）约 **1.51%/日**，88% ≈ **58 日**。首段教程跨度强制 **超市 + 水厂** 点位（[06 §0.1](06-region-events.md)）；仍需停靠搜索，不能仅靠车上库存撑过前期。
起始速度上限见 [03](03-train.md)（动力模板 → 80 km/h）。

---

## 11. 闭环自检（改表必跑）

1. 顶栏只显示核心六元；材料在库存/工坊页；道具独立。  
2. 无「资源兑换所」；仅有 §5 有损转换。  
3. 日结顺序 = §8；与 01 钩子一致。  
4. F04 气候只走 `fuelClimate`；雪原×1.3 仅区域字段。  
5. F05 满仓停积；无种 ×0.5；冷侧无供暖 0.50 / 供暖 0.95，供暖燃料走步骤 3b。  
6. F32 与燃料=0 联动。  
7. 工坊日：造零件 XOR 精炼。  
8. 晶核区段期望和恒为 0.10；晶核唯一出口是 §5.4 药剂。  
9. 异能/Lv3+ 科技只扣 `potion.catalyst`（及觉醒/升级药剂），不扣 raw crystal。  
10. 开局货舱 size3 上限与 §6 公式手算一致。  
11. 01 季节点位倾向、06 区域词条，须能映射到 §7.1 点位（改点位类型同步两边）。  
12. 不引用定居点回流（该系统延后）。
