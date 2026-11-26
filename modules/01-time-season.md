# 模块：时间 · 季节 · 天气 · 温度

> 所属层：节拍层  
> 依赖：无（系统节拍器）；**气候影响因子**可由区域/事件写入（定居点源延后）  
> 被依赖：资源日耗/F04/F05、列车速度上限、区域导演抽取与事件权重  
> **权威**：日历、天气表、温度合成、气候倍率、影响因子聚合、pressure 以本模块为准；[06](06-region-events.md) 只注册因子与调用抽取。

---

## 1. 设计意图

用**季节循环 + 丰富天气 + 可叠加影响因子 + 逐年加压**替代章节，保持纯无尽。

```
季节（日历 / baseTemp / 权重表）
  + 气候影响因子（地理、事件等）
      → 调制天气权重并抽天气（每区段一次）
      → effectiveTemp = 季节 + 天气 + Σ因子
      → 气候倍率（粮/水/燃料/速度/温室）
      → 日结与驾驶读取
```

禁止：按春夏秋冬再写一套消耗表与气候倍率并行；禁止各系统私自改温度而不走影响因子。

---

## 2. 日历规划（权威）

| 单位 | 游戏日 | 真实时间（1×） | 说明 |
|---|---|---|---|
| 1 日 | 1 | **180 秒** | tick：每 0.1 真实秒推进 `0.1×倍速/180` 日 |
| 1 季 | **30 日** | 90 分钟 | 约 **1 次区域跨度 / 季** → **0.10–0.17 段/日**（中位 ≈0.13）；靠 [03 §6.2](03-train.md) **行驶日额度**对齐，不是按面板时速×24h |
| 1 年 | **120 日**（4×30） | 6 小时 | 「第一年冬天」= 第 91–120 日（春开局） |
| 倍速 | — | **暂停 / 1× / 2× / 4×** | 键位见 [08](08-presentation.md)；1× 下季约 90 / 45 / 22.5 分钟 |

季节序：春 → 夏 → 秋 → 冬 → 年结回春。  
`dayInSeason ∈ [0,29]`（**内部 0-based**）；UI 显示为 `日序+1`（如内部 11 → 「春 12/30」）。`dayTotal` 单调增加。  
开局默认：**第 1 年春 · 第 0 日**（可配置，但文档与验收按此）。

配置键：`time.secondsPerDay=180`，`time.daysPerSeason=30`，`time.seasonsPerYear=4`。改日历必须同步软目标与仿真天数。

### 2.1 游戏小时 ↔ tick（权威换算）

| 单位 | 换算 |
|---|---|
| 1 游戏日 | **24 游戏小时** |
| 1 游戏小时 | `1/24` 日 = **7.5** 真实秒（1×） |
| 本 tick 游戏小时 | `(本 tick 推进的日数) × 24`（供 [03 §6.2](03-train.md) 里程） |
| UI「锁速 5 秒」等 | **真实时间**秒（暂停时冻结）；≈ `5/180` 日 |

搜索/搬运/配制/维修文案中的「游戏小时」一律按本表落到日/tick。禁止另设第二套小时长度。

### 2.2 时间是否合适（设计判定 · 权威）

**总判：合适，但必须把「行驶日额度」说成人话；禁止假装面板时速×24h。**

| 项 | 判定 | 理由 |
|---|---|---|
| 180 秒/日、30 日/季、120 日/年 | **保留** | 对齐 15–25h 完整体验与无尽长尾；改日长必须重算软目标与仿真 |
| 暂停 + 1×/2×/4× | **保留** | 决策停、赶路加速；不强制对齐放逐之城档位数量 |
| 日结批次（粮水油/士气） | **保留** | 殖民地日循环；与连续 tick 驾驶并存合法 |
| `driveHoursPerDayCap=1.0` | **保留（战略阀门）** | 用来锁 **0.13 段/日**；是「今日还能推进多少」，不是物理 24h 巡航 |
| 面板瞬时速度 | **战术钟** | 只服务加减速/刹车/碰撞/召回；**不**等于全日旅行时速 |

**两套钟（必须并存时的读法）**：

1. **日历钟**：日/季/年、倍速、日结——经营与气候。  
2. **行驶日额度**：每日最多折合 `driveHoursPerDayCap` 的有效前进；额度用尽后当日不再加 `progressKm`（细则 [03 §6.2](03-train.md)）。

**倍速引导（表现层须遵守，[08](08-presentation.md)）**：站内操作/事件/战斗 → 暂停或 1×；纯巡航且无车外任务 → 推荐 2×/4×；额度用尽提示后宜停车或改意图，避免空转。

**体验时长口径**：`180s×120日=6h/年` 是 **1× 且几乎不暂停** 的墙上时间上界。对外「15–25 小时完整体验」= **含暂停思考 + 常用 2×/4× 后的玩家日历时间**，约落在 2.5–4 年剧情；禁止写成「必须 1× 连打 18h」。

---

## 3. 运行时状态

| 字段 | 写入时机 | 读取方 |
|---|---|---|
| `year` / `season` / `dayInSeason` / `dayTotal` | tick / 季结 / 年结 | 全系统 |
| `climateInfluences[]` | 区域选定、事件、清除区段时 | 抽天气、温度 |
| `weatherId` | **仅** `onSegmentBuild` 抽一次 | 日结、UI、导演 |
| `effectiveTemp` / `coldIndex` / `heatIndex` | `recomputeClimate()` | 气候倍率、UI |
| `foodClimate` 等五项倍率 | 同上 | 资源、列车 |
| `influenceTemp` / `activeWeightTable` | 同上（调试可序列化） | 断言、埋点 |

`recomputeClimate()` 只读：`season` + `weatherId` + `climateInfluences[]`；**幂等**。

---

## 4. 气候影响因子（对外扩展口）

其它系统**不得**直接改 `effectiveTemp` 或天气权重；一律推入/撤出 `ClimateInfluence`。

### 4.1 结构

```
ClimateInfluence {
  id: string              # 如 region.tundra / event.ashfall_3d
  source: region|event|mod|other   # settlement 源延后，见 archive/settlement-deferred.md
  tempMod: number         # 加到温度合成；单条建议 ∈ [-1, +1]
  weatherBias: { [weatherId]: number }  # 乘到季节权重，缺省 1.0；0 = 本因子禁此天气
  waterMod: number        # 缺省 1.0；乘进 waterClimate
  speedMult: number       # 缺省 1.0；乘进 speedClimate
  pressureAdd: number     # 缺省 0；加进 pressure
  expiresSegment?: int    # 可选；区段计数用尽则移除（事件用）
}
```

### 4.2 聚合（权威）

```
influenceTemp = clamp( Σ tempMod , -1.5, +1.5 )   # 防地理叠爆
w'(id) = seasonWeight(season, year, id) × Π weatherBias[id]   # 各因子连乘
若 w' 全 0 → 回退为未调制季节表
抽天气用 Normalize(w')

effectiveTemp = clamp(seasonBaseTemp + weatherTempMod + influenceTemp, -2, +2)
coldIndex = max(0, −effectiveTemp)
heatIndex = max(0,  effectiveTemp)

waterClimate = waterTemp(heatIndex) × weather.waterMod × Π waterMod
speedClimate = weather.speedClimate × Π speedMult
pressure    = seasonPressure × yearThreat + weatherPressure + Σ pressureAdd
```

燃料/食物/温室仍**只**看 `coldIndex`/`heatIndex`（§8）；地理降温度 → 自然抬冷侧消耗，无需再写平行油耗（雪原 `regionFuelMult=1.3` 见 [06 §1.2](06-region-events.md)，与 `fuelClimate` 叠乘）。
### 4.3 谁写入

| 来源 | 时机 | 例 |
|---|---|---|
| 区域词条 | 三选一确认 / 区段生成 | §4.4 |
| 事件 | 选项结算 | `id=event.*`，可带 `expiresSegment` |
| MOD | 配置 | `source=mod`，标自定义局 |

区段结束或区域切换时：清除 `source=region` 的旧因子，写入新区域因子；`event` 按过期移除。

**写入/移除后必须立即 `recomputeClimate()`（权威）**：

| 时机 | 规则 |
|---|---|
| 事件 `grantInfluence` / `clearInfluence` | 选项结算改完 `climateInfluences[]` 后**立刻**重算（[06 §2.1](06-region-events.md)） |
| `expiresSegment` 到期移除 | 扣减并移除后立刻重算（见下） |
| 区域因子切换 | 清旧写新后立刻重算（通常并入 `onSegmentBuild`） |

禁止「只改数组、等下次 `onDayStart` 再算」——否则当日驾驶 tick / 次日步骤 0 的 F04 会吃旧 `fuelClimate`。  
日结仍可保留「步骤 0 先读小时算 F04 → 步骤 1 再 `recomputeClimate`」：昨日油耗用**昨日已即时维护**的倍率；步骤 1 服务当日粮水。

**`expiresSegment` 扣减（权威）**：每次进入新区段并调用 `onSegmentBuild` **之前**：

```
对 climateInfluences 中带 expiresSegment 的项：
  expiresSegment -= 1
  若 expiresSegment ≤ 0 → 移除该项
若本步有任何移除 → recomputeClimate()
```

不在日结扣；返程回到旧区段**不**回退计数。区段生命周期见 [06 §0](06-region-events.md)。

### 4.4 首发区域 → 因子预设（06 注册）

配置权威：`data/climate_influences.json`（`presets["region.*"]`）；下表为只读摘要，改数须同步 json 与 `regions.climateInfluenceId`。

| 区域 | id | tempMod | weatherBias（乘子，未列=1） | 其它 |
|---|---|---|---|---|
| 雪原 | `region.tundra` | **−0.5** | blizzard×2.0，light_snow×1.5，cold_snap×1.5，heatwave×0，sandstorm×0 | pressureAdd +0.2；区域油耗×1.3 另计 |
| 河谷 | `region.valley` | **−0.25** | rain×1.5，night_rain×1.4，fog×1.3，thunderstorm×1.3，sandstorm×0.5 | — |
| 疫区 | `region.plague` | 0 | fog×2.0，ash_haze×1.5，clear×0.7 | pressureAdd +0.25 |
| 矿区 | `region.mine` | 0 | ash_haze×2.0，sandstorm×1.3，fog×1.2 | — |
| 旧城区 | `region.urban` | **+0.25** | heatwave×1.3，clear×1.1，fog×1.2 | — |
| 军事区 | `region.military` | 0 | ash_haze×1.2 | pressureAdd +0.15 |

---

## 5. 时间钩子

| 钩子 | 调用方 | 动作 |
|---|---|---|
| `onYearStart` | 时间 | `year++`；冬权重切年≥3 表；年压 |
| `onSeasonStart` | 时间 | 切季节字段（§6）、天气权重表（§7.1）、`seasonBaseTemp`；`dayInSeason=0` |
| `onSegmentBuild` | [06](06-region-events.md) | **进入区段时一次**：同步区域因子 → 抽 `weatherId` → `recomputeClimate()` → pressure → 事件/点位（区段生命周期见 06 §0） |
| `onDayStart` | 时间 | 见 [02 §8](02-resources.md)：延迟事件(−1)→F04→清小时→气候→扣粮水→燃料→供暖→fuel streak→F05/F32→工坊→归零/士气→仅刷 pressure（不重抽事件） |
| 驾驶/F04 | 列车·资源 | 只读倍率 |

**开局天气（唯一口径）**：立即生成教程跨度并**进入第 0 段** → 走完整 `onSegmentBuild`（含按季节表×因子抽 `weatherId`），与 [06 §0](06-region-events.md) 一致。  
禁止另置「开局强制 `clear` 且跳过抽取」。引擎冷启动瞬间可短暂空天气，但首帧进入段前必须完成一次抽取。  
天气禁止双抽（每段至多一次 `onSegmentBuild`）。

暂停：计时冻结。里程规则见 [列车](03-train.md)。

---

## 6. 季节（不加消耗表）

| 季节 | 日序（春开局） | `seasonBaseTemp` | 资源点倾向（乘子，权威） | 威胁基调 | `seasonPressure` |
|---|---|---|---|---|---|
| 春 | 1–30 | 0 | 超市/农田/水厂/加油站 ×**1.20** | 疫情、难民 | 1.0 |
| 夏 | 31–60 | **+1** | 水厂 ×**1.40**；其余 1.0 | 掠夺者权重 ×1.30 | 1.2 |
| 秋 | 61–90 | 0 | 上列补给类均 ×**1.30** | 基准 | 0.8 |
| 冬 | 91–120 | **−1** | 加油站 ×**1.40**；其余 1.0 | 尸潮权重 ×1.50 | 1.5 |

点位最终权重 = `06 §3 基权` × `RegionRun.pointTypeWeightMods`（[06 §1.2](06-region-events.md)）× **本表季节乘子**（配置键 `point_types.seasonWeightMods`；**只改抽取权重，不改点位 `remainingYield`**）× 天气 `nodeWeightMods`（× 适用时雷达减免，06 §3）→ 归一化。  
禁止实现另写「冬加油站 ×2 / 夏水 ×1.5」等第二套数；改乘子须改本表并 bump config。
---

## 7. 天气库（丰富；概率随季节 + 因子）

### 7.1 天气定义

| id | 名 | tempMod | waterMod | speedClimate | visibilityMult | weatherPressure | 点位/威胁 | 其它 |
|---|---|---|---|---|---|---|---|---|
| `clear` | 晴朗 | 0 | 1.0 | 1.0 | **1.0** | 0 | — | 基准 |
| `cloudy` | 阴天 | −0.25 | 1.0 | 1.0 | 1.0 | 0.05 | — | 轻阴 |
| `fog` | 浓雾 | −0.25 | 1.0 | 0.95 | **0.55** | 0.2 | — | 视野差 |
| `drizzle` | 毛毛雨 | −0.25 | 1.0 | 0.95 | 0.95 | 0.1 | — | — |
| `rain` | 降雨 | −0.5 | 1.0 | 0.9 | 0.9 | 0.25 | — | — |
| `night_rain` | 夜间暴雨 | −0.5 | 1.0 | **0.8** | **0.70** | 0.4 | 尸潮内容权重 ×1.35 | — |
| `thunderstorm` | 雷暴 | −0.5 | 1.0 | 0.85 | 0.85 | 0.45 | — | — |
| `heatwave` | 热浪 | **+1.0** | 1.1 | 1.0 | 1.0 | 0.35 | 饮水点 ×1.2 | — |
| `dry_wind` | 干热风 | +0.5 | 1.15 | 1.0 | 0.95 | 0.25 | — | — |
| `sandstorm` | 沙尘暴 | +0.5 | **1.2** | 0.95 | **0.60** | 0.3 | — | — |
| `light_snow` | 小雪 | −0.75 | 1.0 | 0.9 | 0.9 | 0.35 | 燃料点 ×1.15 | — |
| `blizzard` | 暴雪 | **−1.0** | 1.0 | **0.85** | **0.50** | 0.6 | 燃料点 ×1.3；尸潮 ×1.25 | — |
| `cold_snap` | 极端寒潮 | **−2.0** | 1.0 | **0.9** | 0.95 | 0.8 | — | 年≥3 冬可抽 |
| `ash_haze` | 灰霾 | 0 | 1.05 | 0.95 | 0.85 | 0.3 | 药品点 ×1.15 | — |

`visibilityMult` 乘进 [03 §7](03-train.md) `effectiveVision`（**不再**乘 ClimateInfluence）。  
点位/威胁列中的乘子 → 写入 `weather.json` 的 `nodeWeightMods`（或内容权重键），由 [06 §3](06-region-events.md) 消费。  
**已废止（纯叙事，不进检定）**：原「搜索受伤↑ / 电力故障事件↑ / 热伤害事件↑ / 病人↑ / 药品点略↑」等无数值句；灰霾药品改为上表 **×1.15**。寒潮对疾病**不**另开 `diseaseMod`（低温触发仍走 [04 §7](04-population.md) 既有「低温」条件 + `coldIndex`）。  
**禁止**天气再挂独立油耗通道。不改发现池车型表。

### 7.2 季节基础权重（归一化前相对值；列和=100）

| id | 春 | 夏 | 秋 | 冬年1–2 | 冬年≥3 |
|---|---|---|---|---|---|
| clear | 18 | 12 | 20 | 12 | 10 |
| cloudy | 18 | 10 | 18 | 14 | 12 |
| fog | 10 | 4 | 10 | 8 | 6 |
| drizzle | 14 | 6 | 12 | 0 | 0 |
| rain | 12 | 10 | 12 | 0 | 0 |
| night_rain | 8 | 14 | 8 | 0 | 0 |
| thunderstorm | 5 | 12 | 4 | 0 | 0 |
| heatwave | 0 | 12 | 0 | 0 | 0 |
| dry_wind | 3 | 8 | 2 | 0 | 0 |
| sandstorm | 8 | 10 | 4 | 0 | 0 |
| light_snow | 2 | 0 | 6 | 28 | 22 |
| blizzard | 0 | 0 | 2 | 32 | 28 |
| cold_snap | 0 | 0 | 0 | 0 | 16 |
| ash_haze | 2 | 2 | 2 | 6 | 6 |

抽前：`w' = 上表 × Π 因子 weatherBias`，再归一化。  
可选寒潮加压（默认关）：年≥3 时 `cold_snap' *= min(1+0.10×(year−3), 2)` 再归一化。

配置：[`data/weather.json`](../data/weather.json) + [`data/climate_influences.json`](../data/climate_influences.json)（区域预设）；sim 经 `point_types.load_weather_*` 加载。

---

## 8. 温度与气候倍率

```
effectiveTemp = clamp(seasonBaseTemp + weatherTempMod + influenceTemp, -2, +2)
```

### 8.1 食物 / 饮水 / 燃料 / 温室 / 速度

与前版同一出口（只认 cold/heat + 天气/因子乘子）：

```
foodClimate:    cold≥2→1.40; ≥1→1.25; ≥0.5→1.10; else 1.0
waterTemp:      heat≥1→1.5; ≥0.5→1.2; else 1.0
waterClimate:   waterTemp × weather.waterMod × Π influence.waterMod
fuelClimate:    cold≥2→1.56; ≥1→1.43; ≥0.5→1.15; else 1.0
greenhouseClimate: cold≥1 ? (供暖中 ? 0.95 : 0.50) : 1.0
speedClimate:   weather.speedClimate × Π influence.speedMult
```

日耗与 F04/F05 见 [02](02-resources.md)；速度上限见 [03](03-train.md)。字段名统一：`greenhouseClimate`（禁止别名 `greenhouse`）；天气速度键统一 `weather.speedClimate`（禁止别名 `weather.speed`）。

### 8.1.1 种植供暖（冬季食物闭环）

```
供暖开销 = greenhouse.heatingFuelPerCarDay × 种植车节数 = 0.30 × n（百分点燃料/日）
生效条件：coldIndex ≥ 1 且 world.heatingEnabled = true
日结位置：[02 §8](02-resources.md) 步骤 3b，在 F05（步骤 4）之前扣
燃料不足（fuel < 0.30×n）→ 当日全部不供暖、不扣燃料 → greenhouseClimate = 0.50
冷侧无种植车 → 无开销
```

- 默认 **关**；入冬首日**强制提示**（暂停一次）「开启供暖：种植产出 0.50→0.95，每节 0.30 燃料/日」，未选择前顶栏按钮高亮。
- 供暖是**玩家取舍**，禁止做成「自动扣到 0」：燃料耗尽会连带 F32=0，不得静默发生。
- 供暖燃料是独立扣项，**不进** F04 日耗率（不得并入牵引/怠速系数）。

### 8.2 采样校验（含因子）

| 场景 | base | weather | infl | temp | 备注 |
|---|---|---|---|---|---|
| 秋·晴·无因子 | 0 | 0 | 0 | 0 | 基准舒适 |
| 夏·热浪·城区 | +1 | +1 | +0.25 | +2（夹） | 极热饮水顶格 |
| 冬·晴·雪原 | −1 | 0 | −0.5 | −1.5 | cold=1.5→food1.25，fuel1.43，绿0.50/0.95 |
| 冬·暴雪·雪原 | −1 | −1 | −0.5 | −2（夹） | cold=2→food1.40，fuel1.56，绿0.50/0.95 |
| 春·雨·河谷 | 0 | −0.5 | −0.25 | −0.75 | cold=0.75→food1.10，fuel1.15 |

改天气或因子后：抽若干 `季节×天气×区域` 手算 cold/heat 与 §8.1 一致即可；不必再维护巨型全组合表。

### 8.3 口径

| 字段 | 用途 |
|---|---|
| `seasonBaseTemp` / `weatherTempMod` / `influenceTemp` | 只合成温度 |
| `foodClimate` / `waterClimate` / `fuelClimate` | 消耗 |
| `speedClimate` / `greenhouseClimate` | 速度 / F05 |
| `climateInfluences[]` | 唯一外挂调制口 |

---

## 9. 压力分

```
yearThreat = 1 + 0.15×(year−1)
pressure = seasonPressure × yearThreat + weatherPressure + Σ pressureAdd
```

高压 `≥2.0` / 低压 `≤1.2` / 其余中压。导演规则见 [06](06-region-events.md)。  
产出年压 `yearProd = 0.95^(year−1)`：**只乘车内可再生产出**——F05、F32（[02 §3](02-resources.md)）。  
**不乘**：工坊 `precision/300`、精炼、搜刮点位中值、事件赠予（零件链另用 precision 门槛加压）。不进 pressure。

---

## 10. 软目标（里程碑，非上限）

熬过第一个冬天（春开局则日 91–120，第一年目标人口 **12–16**）→ **第 2 年夏**车上人口 **≥20**；种植车厢、1000 km、存活第 3 年、10 节车厢。  

种植车配比：前 2 节无重叠惩罚（满效合计 8/日），第 3 节起 `0.90^(n−2)` 递减，**产出饱和**——夏约 **17.2/日（≈19 人）**、冬（供暖 0.95）约 **16.4/日（≈13 人）**，n≈9–10 时到顶。  
据此：12 人冬季约需 8–9 节（≈16/日）即可自给；14 人约 −1.3/日、16 人约 −3.8/日，须靠秋季库存（粮仓 90 起，随货舱扩容）与冬季搜刮补足；20 人夏季同样需搜刮补 ~2/日。净水 ≥2。  

人数与节数**均可继续涨**；20/10 只作节奏锚点与验收中位，不是封顶。  
第一年冬季不按 20 人考核（按 12–16 人）；20 人冬季需约 10 节种植（已到饱和上限，缺口 ≈8/日）+ 秋季库存 + 冬季搜刮 + 燃料线达标，属第 2 年长尾目标，见 [10 §1](10-validation.md) 第 8/10 项。

（原「总人口 30 / 第一个定居点」随定居点玩法延后。）

### 10.1 晶核与科技长尾（稀缺意图）

晶核期望约 **0.10/段** × **0.13 段/日** ≈ **1.56/年**（[02 §3.1](02-resources.md)）。  
**不**靠提高掉率或降低配方成本解决「满配慢」。

| 曲线 | 口径 |
|---|---|
| **15–25h / 约前 2.5–4 年完整体验** | 剧情年序按日历；墙上 `6h/年` 仅 1× 无暂停上界（§2.2）。玩家体验 15–25h（含暂停与倍速）≈ **2.5–4 年**；四线以 **Lv1–3** 为软封顶；异能可觉醒，**不要求** Lv2 满配 |
| **长期 / 约第 5 年+** | Lv4/5（催化药剂+图纸）与异能满级属长尾；可玩上百小时的纵向追求 |
| 验收 | [10 §1](10-validation.md) 第 4 项只考核四线 **Lv1–3** 升级率 |

红线 #7：稀缺靠出现频率；本条把「满配不是短曲线义务」写死。

---

## 11. 闭环自检

1. `daysPerSeason=30`，`seasonsPerYear=4`，年=120；与软目标日序一致。  
2. §2.2：行驶日额度与面板时速分列；15–25h 含暂停/倍速，不以 1× 纯跑表冒充体验。  
3. 额度用尽后前进 tick 油耗速度系数 = 0.3（03/02 一致）。  
4. 季节权重列和=100；调制后若全 0 必须回退。  
5. 温度只经 `base + weather + clamp(Σ因子)`；无第四通道。  
6. 区域/事件只写 `ClimateInfluence`，不写死 `effectiveTemp`。  
7. 每区段天气只抽一次；事件改因子须即时 `recomputeClimate`；日结粮水扣费前有步骤 1 重算。  
8. F04 无平行「天气油耗」；雪原×1.3 仅 `regionFuelMult`。  
9. 06 `pressure` 只用 §9。  
10. 寒潮仅冬年≥3 基础权重 >0；冷侧种植无供暖 0.50 / 供暖 0.95；`foodClimate` 冷侧上限 1.40。
