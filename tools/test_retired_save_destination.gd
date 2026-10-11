extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Transition = preload("res://scripts/ember_map_transition.gd")
var _directory := ""
var _setup: Dictionary
var _sources: Array[PackedScene] = []
var _errors: Array[String] = []

func _init() -> void:
	_directory = "user://ember-tests/retired-save-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_setup = Fixture.prepare(self, _directory)
	_run.call_deferred()

func _check(ok: bool, message: String) -> bool:
	if not ok: _errors.append(message)
	return ok

func _run() -> void:
	var current_id := "retirement_current_fixture"
	for id in [Transition.DEFAULT_MAP_ID, "fan_town", current_id]:
		var source := Fixture.save_map(id, _directory)
		if not _check(source != null, "native map fixture failed"):
			quit(1)
			return
		_sources.append(source)
	var default_path := Transition.scene_path(Transition.DEFAULT_MAP_ID)
	ProjectSettings.set_setting("application/run/main_scene", default_path)
	var source_state := EmberExploreState.new()
	source_state.storage_root = _directory.path_join("save-v2")
	source_state.legacy_storage_root = _directory.path_join("save-v1")
	source_state.persistence_enabled = true
	source_state.restore_enabled = true
	source_state.reset_new_game()
	source_state.inventory = {"coin": 77, "herb": 3, "retired_item": 250}
	source_state.flags = {"old_story_done": true}
	source_state.opened_chests = ["retired/chest"]
	source_state.active_hero_ids.assign(["mira", "orik"])
	var marker := Node3D.new()
	marker.position = Vector3(9000, 40, -7000)
	var saved_hash := ""
	for id in Transition.RETIRED_MAP_IDS + ["missing_save_fixture"]:
		source_state.set_world_context(id, marker, 16)
		_check(source_state.save_slot(0), "old save fixture failed")
		saved_hash = FileAccess.get_sha256(source_state.save_path(0))
		var loaded := EmberExploreState.new()
		loaded.storage_root = source_state.storage_root
		loaded.restore_enabled = true
		_check(loaded.load_slot(0), "old save could not be parsed")
		_check(loaded.resume_scene_path() == default_path and loaded.inventory == source_state.inventory and loaded.flags == source_state.flags and loaded.opened_chests == source_state.opened_chests and loaded.active_hero_ids == source_state.active_hero_ids, "retired save lost destination/progress: " + str(id))
		var adopted := EmberExploreState.new()
		adopted.restore_enabled = true
		adopted.adopt_loaded_save(loaded)
		_check(adopted.has_pending_spawn_restore() and adopted.consume_saved_spawn(Transition.DEFAULT_MAP_ID, 16) == null and not adopted.has_pending_spawn_restore(), "retired coordinates or pending state survived adoption")
		_check(FileAccess.get_sha256(source_state.save_path(0)) == saved_hash, "loading rewrote original v2 save")
		adopted.free()
		loaded.free()
	# Normal destinations retain their saved coordinates.
	source_state.set_world_context(current_id, marker, 16)
	source_state.save_slot(1)
	var normal := EmberExploreState.new()
	normal.storage_root = source_state.storage_root
	normal.restore_enabled = true
	normal.load_slot(1)
	_check(normal.consume_saved_spawn(current_id, 16) == marker.position, "native saved position changed")
	normal.free()
	# V1 conversion keeps original source/backup, then resolves the location in memory.
	var legacy_path := source_state.legacy_save_path(2)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(legacy_path.get_base_dir()))
	var legacy := {"version": 1, "packId": EmberExploreState.PACK_ID, "slot": 2, "mapId": "fan_town", "x": 9000, "y": -7000, "hp": 20, "maxHp": 40, "inventory": {"coin": 12, "retired_item": 250}}
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var legacy_hash := FileAccess.get_sha256(legacy_path)
	var v1 := EmberExploreState.new()
	v1.storage_root = source_state.storage_root
	v1.legacy_storage_root = source_state.legacy_storage_root
	v1.restore_enabled = true
	_check(v1.load_slot(2) and v1.resume_scene_path() == default_path and v1.consume_saved_spawn(Transition.DEFAULT_MAP_ID, 16) == null, "v1 relocation applied converted old coordinates")
	_check(v1.inventory.get("retired_item") == 250 and FileAccess.get_sha256(legacy_path) == legacy_hash and FileAccess.get_sha256(v1.migration_backup_path(2)) == legacy_hash, "v1 progress/source/backup changed")
	v1.free()
	if not _errors.is_empty():
		marker.free()
		source_state.free()
		printerr("FAIL retired save destination: ", "; ".join(_errors))
		quit(1)
		return
	# Real pause menu: old save changes scene to default and uses native entry.
	source_state.set_world_context("fan_town", marker, 16)
	source_state.save_slot(0)
	saved_hash = FileAccess.get_sha256(source_state.save_path(0))
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	progress.persistence_enabled = true
	progress.restore_enabled = true
	change_scene_to_file(Transition.scene_path(current_id))
	await process_frame
	await process_frame
	var menu := current_scene.get("_pause_ui") as EmberExplorePauseMenu
	menu.open_menu()
	menu._load_game(0)
	await process_frame
	await process_frame
	_check(current_scene.scene_file_path == default_path and progress.inventory.get("retired_item") == 250 and not progress.has_pending_spawn_restore(), "real menu did not relocate retired save")
	var player := current_scene.get("_player") as EmberPlayer
	var map := current_scene.get_node("Map") as EmberMapLoader
	var entry := map.spawn_world()
	_check(is_equal_approx(player.global_position.x, entry.x) and is_equal_approx(player.global_position.z, entry.z), "real relocation did not use native entry")
	_check(FileAccess.get_sha256(source_state.save_path(0)) == saved_hash, "menu load rewrote original old slot")
	# No available fallback: pause/menu/live inventory/slot/pending remain unchanged.
	_sources[0].take_over_path(_directory.path_join("unregistered_default.tscn"))
	progress.active_slot = 1
	var before := progress.inventory.duplicate(true)
	menu = current_scene.get("_pause_ui") as EmberExplorePauseMenu
	menu.open_menu()
	menu._load_game(0)
	_check(progress.inventory == before and progress.active_slot == 1 and not progress.has_pending_spawn_restore() and paused and menu.is_open(), "failed destination partially changed live state or closed menu")
	_sources[0].take_over_path(default_path)
	paused = false
	progress.persistence_enabled = false
	current_scene.free()
	marker.free()
	source_state.free()
	if not _errors.is_empty():
		printerr("FAIL retired save destination: ", "; ".join(_errors))
		quit(1)
		return
	print("PASS retired save destination; seven cities/missing map -> native entry, v1/v2/progress/backup, normal coordinates, atomic menu refusal")
	quit(0)
