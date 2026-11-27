class_name SearchRules
extends RefCounted
## 搜索配置薄封装，避免 gameplay 散落 `balance.search.*` 字符串。
##
## `cap`：单点单日最多派搜索次数（验收 ZA-7 / §12.7 #3）。
## 工时：`hours_per_task` 任务总长；`hours_progress_per_day` 每游戏日推进量（日钟 tick×day_delta + 日界补差）。


static func cap() -> int:
	return int(ConfigDb.require("balance.search.maxAssignPerPointPerDay"))


## 单次搜索任务总工时（多日累计至 complete）。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @return 浮点结果（量/比率/工时）。
static func hours_per_task() -> float:
	return float(ConfigDb.require("balance.search.hoursPerTask"))


## 每个 END_DAY 为进行中搜索 + 的小时数。
##
## 公开 API：UI 经 `IntentBus` → `GameSession`，勿在 presentation 改 state。
## @return 浮点结果（量/比率/工时）。
static func hours_progress_per_day() -> float:
	return float(ConfigDb.require("balance.search.hoursProgressPerDay"))