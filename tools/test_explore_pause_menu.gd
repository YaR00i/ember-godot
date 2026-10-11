extends SceneTree
## Real pause/save/load/delete UI on saved native maps; only test-owned user://
## files. No retired city, map JSON or authored voxel asset is required.

const Fixture = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
var _directory := ""
var _main_id := ""
var _main_path := ""
var _other_path := ""
var _sources: Array[PackedScene] = []
var _setup: Dictionary = {}


func _init() -> void:
	root.size = Vector2i(1280, 720)
	_directory = "user://ember-tests/pause-menu-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_setup = Fixture.prepare(self, _directory)
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var errors: Array[String] = []
	await _run(errors)
	paused = false
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if progress != null: progress.persistence_enabled = false
	if current_scene != null: current_scene.free()
	if not errors.is_empty():
		printerr("FAIL explore pause menu")
		for error in errors: printerr(" - ", error)
		quit(1)
		return
	print("PASS explore pause menu")
	print("  native fixtures; real menu/slot buttons, modal blocker and pause/resume")
	print("  three slots + autosave metadata; same-map reload and cross-map saved position")
	print("  delete confirmation is target-specific and expires; recovery bytes preserved")
	quit(0)


func _run(errors: Array[String]) -> void:
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if progress == null or _setup.error != OK or not _setup.progress_isolated:
		errors.append("fixture/progress isolation failed")
		return
	_main_id = "pause_fixture_%d" % OS.get_process_id()
	var other_id := "pause_other_%d" % OS.get_process_id()
	for id in [_main_id, other_id]:
		var source := Fixture.save_map(id, _directory)
		if source == null:
			errors.append("could not save/reopen native pause fixture")
			return
		_sources.append(source)
	_main_path = EmberMapTransition.scene_path(_main_id)
	_other_path = EmberMapTransition.scene_path(other_id)
	var scene_hashes := {}
	for id in [_main_id, other_id]: scene_hashes[id] = FileAccess.get_sha256(_directory.path_join(id + ".tscn"))
	progress.reset_new_game()
	progress.persistence_enabled = true
	progress.restore_enabled = true
	if change_scene_to_file(_main_path) != OK:
		errors.append("could not start native exploration fixture")
		return
	if not await _wait_scene(_main_path, 0, errors): return
	var nodes := _controls(errors)
	if nodes.is_empty(): return
	var menu := nodes.menu as EmberExplorePauseMenu
	var inventory := nodes.inventory as EmberInventoryUi
	var player := nodes.player as EmberPlayer
	var map := current_scene.get_node("Map") as EmberMapLoader
	if map.hydrate_legacy_regions or FileAccess.file_exists(EmberPack.map_path(_main_id)):
		errors.append("native pause fixture unexpectedly uses map JSON")
	if player.pause_ui != menu or menu.progress_state != progress:
		errors.append("Player/menu do not share the real exploration/save owners")
	inventory.toggle()
	_press("ExploreMenuButton")
	if menu.is_open() or paused:
		errors.append("pause menu opened over active inventory")
	inventory.close()
	_press("ExploreMenuButton")
	if not menu.is_open() or not (nodes.overlay as ColorRect).visible or not paused:
		errors.append("exploration menu did not pause the SceneTree")
	await process_frame
	if root.gui_get_focus_owner() != _button("ExplorePauseResume"):
		errors.append("pause menu did not focus Resume")

	var save_hashes := {}
	for slot in EmberExploreState.MANUAL_SLOT_COUNT:
		player.global_position = _slot_position(slot)
		progress.flags = {"pause_slot": slot}
		progress.inventory["herb"] = slot + 1
		_press("ExploreSaveSlot%d" % (slot + 1))
		var feedback := nodes.feedback as Label
		if not feedback.text.contains("сохранена") or not bool(progress.slot_metadata(slot).get("exists", false)):
			errors.append("slot %d save button did not save/report success" % (slot + 1))
		if _button("ExploreLoadSlot%d" % (slot + 1)).disabled or _button("ExploreDeleteSlot%d" % (slot + 1)).disabled:
			errors.append("saved slot %d did not become loadable/deletable" % (slot + 1))
		save_hashes[slot] = FileAccess.get_sha256(progress.save_path(slot))
	progress.flags = {"pause_slot": "autosave"}
	progress.inventory["herb"] = 9
	if not progress.save_autosave(): errors.append("could not create isolated autosave")
	var autosave_hash := FileAccess.get_sha256(progress.autosave_path())
	_press("ExplorePauseResume")
	if menu.is_open() or paused: errors.append("Resume button did not resume the SceneTree")
	_press("ExploreMenuButton")
	await process_frame
	if _button("ExploreDeleteAutosave").disabled or not bool(progress.autosave_metadata().get("exists", false)):
		errors.append("separate autosave metadata did not refresh")
	for slot in EmberExploreState.MANUAL_SLOT_COUNT:
		var label := current_scene.find_child("ExploreSaveSlot%dLabel" % (slot + 1), true, false) as Label
		if not label.text.contains(_main_id): errors.append("slot metadata did not show its saved native map")

	# Same-map load must reload the scene while releasing the pause state.
	progress.flags = {"pause_slot": "changed"}
	progress.inventory["herb"] = 77
	player.global_position = Vector3(12, 5, 12)
	var previous := current_scene.get_instance_id()
	_press("ExploreLoadSlot1")
	if not await _wait_scene(_main_path, previous, errors): return
	_assert_loaded(progress, 0, errors)
	if FileAccess.get_sha256(progress.autosave_path()) != autosave_hash:
		errors.append("same-map UI load overwrote autosave")
	# A second native map exercises the different-scene branch of the same UI.
	previous = current_scene.get_instance_id()
	if change_scene_to_file(_other_path) != OK:
		errors.append("could not open second native map")
		return
	if not await _wait_scene(_other_path, previous, errors): return
	# Ordinary travel still autosaves the departure scene. Preserve that newer
	# autosave through the following cross-map UI load rather than suppressing it.
	if FileAccess.get_sha256(progress.autosave_path()) == autosave_hash:
		errors.append("ordinary native map departure did not autosave")
	autosave_hash = FileAccess.get_sha256(progress.autosave_path())
	nodes = _controls(errors)
	if nodes.is_empty(): return
	progress.flags = {"pause_slot": "other_map"}
	progress.inventory["herb"] = 88
	_press("ExploreMenuButton")
	await process_frame
	previous = current_scene.get_instance_id()
	_press("ExploreLoadSlot3")
	if not await _wait_scene(_main_path, previous, errors): return
	_assert_loaded(progress, 2, errors)
	_press("ExploreMenuButton")
	await process_frame
	previous = current_scene.get_instance_id()
	_press("ExploreLoadSlot2")
	if not await _wait_scene(_main_path, previous, errors): return
	_assert_loaded(progress, 1, errors)
	for slot in save_hashes:
		if FileAccess.get_sha256(progress.save_path(slot)) != save_hashes[slot]:
			errors.append("UI loading changed saved slot bytes")
	if FileAccess.get_sha256(progress.autosave_path()) != autosave_hash:
		errors.append("manual UI loading overwrote autosave")

	nodes = _controls(errors)
	if nodes.is_empty(): return
	menu = nodes.menu as EmberExplorePauseMenu
	_press("ExploreMenuButton")
	_press("ExploreDeleteSlot1")
	if not (nodes.feedback as Label).text.contains("ещё раз") or not bool(progress.slot_metadata(0).get("exists", false)):
		errors.append("first manual delete did not arm confirmation without deleting")
	_press("ExploreDeleteSlot2")
	_press("ExploreDeleteSlot1")
	if not bool(progress.slot_metadata(0).get("exists", false)) or not bool(progress.slot_metadata(1).get("exists", false)):
		errors.append("confirmation leaked across manual slots")
	_press("ExploreDeleteSlot1")
	if bool(progress.slot_metadata(0).get("exists", false)) or not _button("ExploreLoadSlot1").disabled:
		errors.append("confirmed manual delete left the slot loadable")
	if not (nodes.feedback as Label).text.contains("резервная копия"):
		errors.append("confirmed manual delete did not explain recovery archive")
	_press("ExploreDeleteAutosave")
	if not bool(progress.autosave_metadata().get("exists", false)):
		errors.append("first autosave delete removed it without confirmation")
	menu.set("_armed_delete_until_ms", Time.get_ticks_msec() - 1)
	_press("ExploreDeleteAutosave")
	if not bool(progress.autosave_metadata().get("exists", false)):
		errors.append("expired confirmation still deleted autosave")
	_press("ExploreDeleteAutosave")
	if bool(progress.autosave_metadata().get("exists", false)) or not _button("ExploreDeleteAutosave").disabled:
		errors.append("confirmed autosave delete did not refresh its metadata")
	for slot in [1, 2]:
		if FileAccess.get_sha256(progress.save_path(slot)) != save_hashes[slot]:
			errors.append("deleting one slot/autosave changed another slot")
	var archived_hashes: Array[String] = []
	var archive_dir := progress.storage_root.path_join(EmberExploreState.PACK_ID).path_join("deleted_saves")
	for name in DirAccess.get_files_at(archive_dir): archived_hashes.append(FileAccess.get_sha256(archive_dir.path_join(name)))
	if save_hashes[0] not in archived_hashes or autosave_hash not in archived_hashes:
		errors.append("UI deletion did not preserve exact recovery bytes")
	_press("ExplorePauseResume")
	if menu.is_open() or paused: errors.append("menu did not resume after save operations")
	for id in scene_hashes:
		if FileAccess.get_sha256(_directory.path_join(id + ".tscn")) != scene_hashes[id]:
			errors.append("runtime changed a saved native map fixture")


func _controls(errors: Array[String]) -> Dictionary:
	if current_scene == null:
		errors.append("native exploration scene is missing")
		return {}
	var names: Array[String] = ["ExploreMenuButton", "ExplorePauseOverlay", "ExplorePauseFeedback", "ExplorePauseResume", "ExploreAutosaveLabel", "ExploreDeleteAutosave"]
	for slot in EmberExploreState.MANUAL_SLOT_COUNT:
		for prefix in ["ExploreSaveSlot%dLabel", "ExploreSaveSlot%d", "ExploreLoadSlot%d", "ExploreDeleteSlot%d"]:
			names.append(prefix % (slot + 1))
	var missing := false
	for name in names:
		if current_scene.find_child(name, true, false) == null:
			errors.append("pause menu lost " + name)
			missing = true
	var player := current_scene.get_node_or_null("Player") as EmberPlayer
	var menu := current_scene.get_node_or_null("CanvasLayer/ExplorePauseUI") as EmberExplorePauseMenu
	var inventory := current_scene.get_node_or_null("CanvasLayer/InventoryUI") as EmberInventoryUi
	if missing or player == null or menu == null or inventory == null:
		errors.append("native exploration lost Player/PauseUI/InventoryUI wiring")
		return {}
	return {"player": player, "menu": menu, "inventory": inventory, "overlay": current_scene.find_child("ExplorePauseOverlay", true, false), "feedback": current_scene.find_child("ExplorePauseFeedback", true, false)}


func _assert_loaded(progress: EmberExploreState, slot: int, errors: Array[String]) -> void:
	var nodes := _controls(errors)
	if nodes.is_empty(): return
	var player := nodes.player as EmberPlayer
	var expected := _slot_position(slot)
	if current_scene.scene_file_path != _main_path or paused or (nodes.menu as EmberExplorePauseMenu).is_open():
		errors.append("UI load did not restore its native scene and release pause")
	if progress.flags.get("pause_slot") != slot or int(progress.inventory.get("herb", 0)) != slot + 1:
		errors.append("UI load did not restore slot %d flags/inventory" % (slot + 1))
	if not Vector2(player.global_position.x, player.global_position.z).is_equal_approx(Vector2(expected.x, expected.z)):
		errors.append("UI load did not restore slot %d saved position" % (slot + 1))


func _wait_scene(path: String, previous_id: int, errors: Array[String]) -> bool:
	for frame in 12:
		await process_frame
		if current_scene != null and current_scene.get_instance_id() != previous_id and current_scene.scene_file_path == path:
			await process_frame
			return true
	errors.append("native UI scene handoff timed out: " + path)
	return false


func _slot_position(slot: int) -> Vector3:
	return Vector3(24.25 + slot * 2, 5, 37.5 + slot)


func _button(name: String) -> Button:
	return current_scene.find_child(name, true, false) as Button


func _press(name: String) -> void:
	_button(name).pressed.emit()
