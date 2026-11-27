extends Node
## Autoload：启动 LocaleApi.load_all 并同步 TranslationServer。
## 文案用 LocaleApi.tr_key 等；本节点提供 reload_locale / set_locale。


const EDITOR_UI_TRANSLATIONS: PackedStringArray = [
	"res://data/localization/ui.en.translation",
	"res://data/localization/ui.zh.translation",
	"res://data/localization/ui.de.translation",
	"res://data/localization/ui.ru.translation",
	"res://data/localization/ui.es.translation",
]

var _runtime_translations: Array = []


func _ready() -> void:
	var loc: Variant = ProjectSettings.get_setting("game/locale", "zh")
	if str(loc).is_empty():
		loc = ProjectSettings.get_setting("internationalization/locale", "zh")
	LocaleApi.locale_id = str(loc)
	LocaleApi.debug_show_keys = bool(ProjectSettings.get_setting("game/locale_debug_keys", false))
	_load_editor_translation_resources()
	reload_locale()


## 热重载 CSV（含 Mod 覆盖）并重建 TranslationServer。
func reload_locale() -> bool:
	LocaleApi.load_all()
	_push_translation_server()
	return LocaleApi.load_errors.is_empty()


func set_locale(lang: String) -> void:
	LocaleApi.locale_id = lang
	TranslationServer.set_locale(lang)
	ProjectSettings.set_setting("game/locale", lang)
	_push_translation_server()


func _load_editor_translation_resources() -> void:
	for path in EDITOR_UI_TRANSLATIONS:
		if not ResourceLoader.exists(path):
			continue
		var res: Variant = ResourceLoader.load(path)
		if res is Translation:
			TranslationServer.add_translation(res)


func _push_translation_server() -> void:
	for t in _runtime_translations:
		if t is Translation:
			TranslationServer.remove_translation(t)
	_runtime_translations.clear()

	var entries: Dictionary = LocaleApi.entries()
	var langs: PackedStringArray = PackedStringArray(["en", "zh", "de", "ru", "es"])
	for lang in langs:
		var tr_res := Translation.new()
		tr_res.locale = lang
		for key in entries.keys():
			var row: Dictionary = entries[key]
			var msg := str(row.get(lang, "")).strip_edges()
			if msg.is_empty():
				msg = str(row.get("en", "")).strip_edges()
			if msg.is_empty():
				continue
			tr_res.add_message(key, msg)
		TranslationServer.add_translation(tr_res)
		_runtime_translations.append(tr_res)

	TranslationServer.set_locale(LocaleApi.locale_id)