class_name GameCalendar
extends RefCounted

const SEASONS := ["spring", "summer", "autumn", "winter"]


static func season_index_for_day(day_total: int) -> int:
	var days_per := int(ConfigDb.require("balance.time.daysPerSeason"))
	if days_per <= 0:
		days_per = 30
	var zero := maxi(0, day_total - 1)
	return (zero / days_per) % 4


static func season_name_for_day(day_total: int) -> String:
	return SEASONS[season_index_for_day(day_total)]


static func year_for_day(day_total: int) -> int:
	var days_per := int(ConfigDb.require("balance.time.daysPerSeason"))
	var per_year := int(ConfigDb.require("balance.time.seasonsPerYear"))
	if days_per <= 0:
		days_per = 30
	if per_year <= 0:
		per_year = 4
	var zero := maxi(0, day_total - 1)
	return zero / (days_per * per_year) + 1


static func day_in_season_for_day(day_total: int) -> int:
	var days_per := int(ConfigDb.require("balance.time.daysPerSeason"))
	if days_per <= 0:
		days_per = 30
	var zero := maxi(0, day_total - 1)
	return (zero % days_per) + 1


static func sync_calendar_fields(state: RunState) -> void:
	state.year = year_for_day(state.day_total)
	state.season = season_name_for_day(state.day_total)
	state.day_in_season = day_in_season_for_day(state.day_total)


static func advance_day(state: RunState) -> void:
	state.day_total += 1
	sync_calendar_fields(state)