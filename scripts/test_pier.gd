extends "res://scripts/fan_town.gd"
## Native, non-story exploration fixture. Geometry belongs to test_pier.tscn.

const STORAGE_ROOT := "user://ember-test-pier-v2"


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var progress := _progress()
	if progress != null:
		# Tests can supply a unique fixture namespace before entering the tree.
		var isolated_root := str(progress.get_meta("test_pier_storage_root", STORAGE_ROOT))
		if progress.storage_root != isolated_root:
			progress.storage_root = isolated_root
			progress.legacy_storage_root = isolated_root.path_join("legacy-unused")
			progress.combat_party_locked = false
			progress.set_world_context("test_pier", null, 16.0)
			progress.reset_new_game()
			progress.load_latest_available()
		# Reload after a pause-menu load retains the selected slot's pending spawn.
		progress.set_active_hero_ids(["protagonist", "mira"], false)
	super._ready()


func _exit_tree() -> void:
	# A selected slot already owns the pending position. Do not capture the outgoing
	# player on pause-menu reload and replace that position with the old one.
	var progress := _progress()
	if progress != null and progress._restore_pending:
		return
	super._exit_tree()


func _play_text() -> String:
	return "ПРИЧАЛ · тестовая локация\nWASD — идти · Tab — герой · I — сумка · T — строй · Esc — меню · RMB — камера"
