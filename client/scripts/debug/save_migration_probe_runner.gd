extends SceneTree
## Headless：`ConfigDb` 挂到 `/root` 后跑 `SaveMigrationProbe`（`--script` 不加载 Autoload）。

const _ConfigDb = preload("res://scripts/data/config_db.gd")
const _Probe = preload("res://scripts/debug/save_migration_probe.gd")


func _init() -> void:
	var db: Node = _ConfigDb.new()
	db.name = "ConfigDb"
	if not db.load_all():
		print(JSON.stringify({"ok": false, "lines": db.load_errors}))
		quit(1)
		return
	var existing := root.get_node_or_null("ConfigDb")
	if existing != null and existing != db:
		root.remove_child(existing)
	if db.get_parent() == null:
		root.add_child(db)
	var r: Dictionary = _Probe.run_all(db)
	for ln in r.get("lines", []):
		print(ln)
	print(JSON.stringify(r))
	quit(0 if r.get("ok", false) else 1)