class_name GameCalendar
extends RefCounted
## 公历派生：`day_total`（从 1 起）→ 年/季/季内日。
## `advance_day` 在 DaySettle **之后**由 GameSession 调用（进入新的一天索引）。

const SEASONS := ["spring", "summer", "autumn", "winter"]

## day_total → 季节序号 0..3。
##
## 节拍层 Service：日结、换区、段建造时调用；HUD 只读派生乘子。
## @param day_total 从 1 起的总局内日序
## @return 整数结果（计数/下标/容量）。
static func season_index_for_day(day_total: int) -> int:
	var days_per := int(ConfigDb.require("balance.time.daysPerSeason"))
	var seasons_per := int(ConfigDb.require("balance.time.seasonsPerYear"))
	var zero := maxi(0, day_total - 1)
	return (zero / days_per) % seasons_per

## day_total → spring|summer|autumn|winter。
##
## 节拍层 Service：日结、换区、段建造时调用；HUD 只读派生乘子。
## @param day_total 从 1 起的总局内日序
## @return 空串=成功；非空=机器错误码。
static func season_name_for_day(day_total: int) -> String:
	return SEASONS[season_index_for_day(day_total)]

## day_total → 游戏年 1..。
##
## 节拍层 Service：日结、换区、段建造时调用；HUD 只读派生乘子。
## @param day_total 从 1 起的总局内日序
## @return 整数结果（计数/下标/容量）。
static func year_for_day(day_total: int) -> int:
	var days_per := int(ConfigDb.require("balance.time.daysPerSeason"))
	var per_year := int(ConfigDb.require("balance.time.seasonsPerYear"))
	var zero := maxi(0, day_total - 1)
	return zero / (days_per * per_year) + 1

## day_total → 季内日 1..30。
##
## 节拍层 Service：日结、换区、段建造时调用；HUD 只读派生乘子。
## @param day_total 从 1 起的总局内日序
## @return 整数结果（计数/下标/容量）。
static func day_in_season_for_day(day_total: int) -> int:
	var days_per := int(ConfigDb.require("balance.time.daysPerSeason"))
	var zero := maxi(0, day_total - 1)
	return (zero % days_per) + 1

## 写 RunState 四季/年/季日。
##
## 节拍层 Service：日结、换区、段建造时调用；HUD 只读派生乘子。
## @param state 当前局 `RunState`（就地修改字段）
static func sync_calendar_fields(state: RunState) -> void:
	state.year = year_for_day(state.day_total)
	state.season = season_name_for_day(state.day_total)
	state.day_in_season = day_in_season_for_day(state.day_total)

## 日历 +1 并同步季节字段。
##
## 节拍层 Service：日结、换区、段建造时调用；HUD 只读派生乘子。
## @param state 当前局 `RunState`（就地修改字段）
static func advance_day(state: RunState) -> void:
	state.day_total += 1
	sync_calendar_fields(state)
