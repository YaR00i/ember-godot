@tool
extends EditorPlugin
## Native Forward+ fixture; enable only in the guarded disposable QA checkout.

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const SCENE := "res://qa_selection/scenes/selection_native.tscn"
var errors: Array[String] = []
var _camera: Camera3D

func _enter_tree() -> void:
	_run.call_deferred()

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL selection native: ", message)

func ready_tiles(projection: EmberTerrainPilotProjection) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while projection.pending_tile_count() > 0 and Time.get_ticks_msec() < deadline: await frames(1)
	check(projection.pending_tile_count() == 0, "tile timeout")

func ready_dialog(dialog: Control) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while dialog.get_apply_button().disabled and Time.get_ticks_msec() < deadline: await frames(1)
	check(not dialog.get_apply_button().disabled, "preview timeout: " + dialog._status.text)

func capture(name: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://qa_selection/" + name + ".png")
	var world: Node = get_parent().get_node("EmberImportPlugin")._world_editor
	if is_instance_valid(world._generation_panel) and world._generation_panel.visible:
		world._generation_panel.get_viewport().get_texture().get_image().save_png("res://qa_selection/" + name + "_dialog.png")

func drag(world: Node, start: Vector2i, finish: Vector2i) -> void:
	var projection: Node3D = world.map._visual_surface_projection
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = _camera.unproject_position(projection.to_global(Vector3(start.x * 384 + 192, 12, start.y * 384 + 192)))
	world.forward_input(_camera, press)
	var move := InputEventMouseMotion.new()
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	move.position = _camera.unproject_position(projection.to_global(Vector3(finish.x * 384 + 192, 12, finish.y * 384 + 192)))
	world.forward_input(_camera, move)
	press.position = move.position
	press.pressed = false
	world.forward_input(_camera, press)

func key(world: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	world.forward_input(_camera, event)

func _run() -> void:
	if ProjectSettings.get_setting("application/config/name") != "Ember River Preview QA":
		printerr("Selection QA is forbidden in the author checkout."); return
	await frames(35)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false, "importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete, "preparation timeout")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa_selection"))
	for path in [SCENE, "res://qa_selection/terrains/selection_native.res"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var creation := Creation.new()
	creation.scene_directory = SCENE.get_base_dir()
	creation.terrain_directory = "res://qa_selection/terrains"
	check(creation.prepare_sections("selection_native", 2, 2, 12), creation.error)
	check(not creation.commit().is_empty(), creation.error)
	EditorInterface.open_scene_from_path(SCENE)
	EditorInterface.reload_scene_from_path(SCENE)
	await frames(20)
	EditorInterface.set_main_screen_editor("3D")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var scene := EditorInterface.get_edited_scene_root()
	var map := scene.get_node("Map") as EmberMapLoader
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection)
	_camera = Camera3D.new()
	EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.position = Vector3(1500, 1800, 1600)
	_camera.look_at_from_position(_camera.position, Vector3(250, 30, 250))
	_camera.far = 8000
	_camera.make_current()
	var original_hash := FileAccess.get_sha256(map.compact_terrain.resource_path)
	var start_position: Vector3 = map.get_node("Regions/PlayerStart").global_position
	if "--section-budget-regression" in OS.get_cmdline_user_args():
		await _verify_section_budget(world, importer, map, scene)
		print("SECTION_BUDGET ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
		get_tree().quit(0 if errors.is_empty() else 1)
		return
	importer._extend_compact_map()
	check(world._section_mode and world._section_controls.visible and not is_instance_valid(importer._compact_extension_dialog), "+ Section opened old numeric menu")
	drag(world, Vector2i.ZERO, Vector2i.ZERO)
	check(world._section_next.disabled, "occupied area was accepted")
	key(world, KEY_ENTER)
	check(world._section_mode, "occupied Enter opened parameters")
	drag(world, Vector2i(1, 0), Vector2i(2, 1))
	check(world._section_rect == Rect2i(1, 0, 2, 2) and not world._section_next.disabled, "mixed drag selection")
	await capture("selection")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await frames(10)
	check(world._section_controls.global_position.x + world._section_controls.size.x <= EditorInterface.get_base_control().size.x, "selection actions leave the small window")
	await capture("selection_small")
	world._section_next.pressed.emit()
	var dialog: Control = world._generation_panel
	check(dialog.visible and dialog._back_button.visible and world._generation_context.addition, "parameters not connected to selection")
	check(world.inspector_panel.is_ancestor_of(dialog) and dialog.get_combined_minimum_size().x <= world.inspector_panel.size.x, "parameters outside dock or horizontal overflow")
	await capture("parameters_small")
	dialog._back_button.pressed.emit()
	await frames(3)
	check(world._section_mode and world._section_rect == Rect2i(1, 0, 2, 2), "Back lost selection")
	var orbit := InputEventMouseMotion.new()
	orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(world.forward_input(_camera, orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS, "camera blocked")
	key(world, KEY_ESCAPE)
	check(not world._section_mode and not world._section_controls.visible and world.sessions.dirty_count(scene) == 0, "Escape dirtied map")
	importer._extend_compact_map()
	drag(world, Vector2i(-1, -1), Vector2i.ZERO)
	check(world._section_rect == Rect2i(-1, -1, 2, 2), "negative address selection")
	key(world, KEY_ENTER)
	dialog = world._generation_panel
	dialog._preview_button.pressed.emit()
	await ready_dialog(dialog)
	check(world._generation_context.selection.keys.size() == 3, "preview changed occupied sections")
	check(world.sessions.dirty_count(scene) == 0 and map.get_node("Regions/PlayerStart").global_position.is_equal_approx(start_position), "preview mutated draft or moved objects")
	await capture("preview")
	# Native Ctrl+S packs the scene while this popup is still open. Temporary
	# coordinate compensation must be cleared before Godot serializes it.
	EditorInterface.save_scene()
	await frames(5)
	var clean_saved := (load(SCENE) as PackedScene).instantiate()
	check(clean_saved.get_node("Map").position == Vector3.ZERO, "native Save packed temporary preview origin")
	clean_saved.free()
	check(world._generation_preview == null and dialog.get_apply_button().disabled, "Save did not invalidate preview")
	dialog._preview_button.pressed.emit()
	await ready_dialog(dialog)
	world.save_all()
	await frames(5)
	clean_saved = (load(SCENE) as PackedScene).instantiate()
	check(clean_saved.get_node("Map").position == Vector3.ZERO, "toolbar Save packed temporary preview origin")
	clean_saved.free()
	check(world._generation_preview == null and dialog.get_apply_button().disabled, "toolbar Save left preview")
	dialog.hide()
	await frames(3)
	check(map.position == Vector3.ZERO and world._generation_preview == null, "cancel retained origin shift")
	check(FileAccess.get_sha256(map.compact_terrain.resource_path) == original_hash, "preview published source")
	importer._extend_compact_map()
	drag(world, Vector2i(-1, -1), Vector2i.ZERO)
	key(world, KEY_ENTER)
	dialog._preview_button.pressed.emit()
	await ready_dialog(dialog)
	if "--confirm-button-regression" not in OS.get_cmdline_user_args():
		# A rejected candidate must keep the real dialog open with a visible
		# explanation, rather than silently behaving like Cancel.
		var stale_version: Terrain = world._generation_context.version.duplicate(false)
		stale_version.width += 16
		world._generation_context.version = stale_version
		dialog.get_apply_button().pressed.emit()
		check(dialog.visible and dialog.get_apply_button().disabled and dialog._status.text.contains("изменилась"), "rejected confirmation hid the reason")
		check(world.sessions.open_map(map, scene).resource.sections.size() == 4, "rejected confirmation changed terrain")
		dialog._preview_button.pressed.emit()
		await ready_dialog(dialog)
	var candidate: Terrain = world._generation_context.candidate
	var preview_tile := world._generation_preview.get_node("PreviewTile_1_1").get_child(0, true) as MeshInstance3D
	var points: PackedVector3Array = preview_tile.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var shown_position := preview_tile.global_position
	dialog.get_apply_button().pressed.emit()
	check(not dialog.visible, "successful confirmation left dialog open")
	dialog.hide()
	if "--confirm-button-regression" in OS.get_cmdline_user_args():
		await frames(3)
		var result_draft: Dictionary = world.sessions.open_map(map, scene)
		check(result_draft.resource == candidate and result_draft.resource.sections.size() == 7, "native confirmation discarded new sections")
		print("SECTION_CONFIRM_BUTTON ", "PASS" if errors.is_empty() else "FAIL", " expected=7 actual=", result_draft.resource.sections.size(), " errors=", errors)
		get_tree().quit(0 if errors.is_empty() else 1)
		return
	await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map, scene)
	check(draft.resource == candidate and candidate.sections.size() == 7, "Apply recomputed or lost candidate")
	check(world.edit_region == Rect2i(0, 0, 48, 48) and world.clip.button_pressed, "new area not selected for editing")
	check(map.get_node("Regions/PlayerStart").global_position.is_equal_approx(start_position), "Apply moved original object")
	var ground := projection._tiles[Vector2i(1, 1)].get_node("Ground") as MeshInstance3D
	check(ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == points and ground.global_position == shown_position, "preview/Apply parity")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	await ready_tiles(projection)
	check(draft.resource.sections.size() == 4 and map.position == Vector3.ZERO and map.authored_size_blocks == Vector2i(48, 48), "single native Undo")
	history.redo()
	await ready_tiles(projection)
	check(draft.resource == candidate and map.authored_size_blocks == Vector2i(72, 72), "native Redo")
	world.sessions.discard(scene)
	await ready_tiles(projection)
	check(draft.resource.sections.size() == 4 and map.position == Vector3.ZERO, "Discard")
	# Apply a fresh version after Discard, then use the real native save route.
	importer._extend_compact_map()
	drag(world, Vector2i(-1, -1), Vector2i.ZERO)
	key(world, KEY_ENTER)
	dialog._preview_button.pressed.emit()
	await ready_dialog(dialog)
	dialog.get_apply_button().pressed.emit()
	dialog.hide()
	await ready_tiles(projection)
	var playback := Node.new()
	playback.name = "SelectionPlaybackCheck"
	playback.set_script(load("res://tools/test_compact_section_selection_playback.gd"))
	scene.add_child(playback)
	playback.owner = scene

	world.save_all()
	deadline = Time.get_ticks_msec() + 60000
	while not world.sessions.pending_native_save.is_empty() and Time.get_ticks_msec() < deadline: await frames(1)
	check(world.sessions.dirty_count(scene) == 0, "native Save did not finish")
	EditorInterface.reload_scene_from_path(SCENE)
	await frames(20)
	map = EditorInterface.get_edited_scene_root().get_node("Map")
	await ready_tiles(map._visual_surface_projection)
	check(map.compact_terrain.sections.size() == 7 and map.position == Vector3(-384, 0, -384), "Save/Reopen lost terrain or origin")
	check(map.get_node("Regions/PlayerStart").global_position.is_equal_approx(start_position), "Reopen moved entry")
	await capture("applied")
	_camera.queue_free()
	print("SECTION_SELECTION_NATIVE ", "PASS" if errors.is_empty() else "FAIL", " input/occupied/multiple/back/Escape/camera/preview/cancel/world-space/parity/single-Undo-Redo/Discard/Save-Reopen errors=", errors)
	var result_path := "res://qa_selection/play_result.json"
	if FileAccess.file_exists(result_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
	EditorInterface.play_current_scene()
	deadline = Time.get_ticks_msec() + 60000
	while not FileAccess.file_exists(result_path) and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(result_path), "F6 result missing")
	if FileAccess.file_exists(result_path):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path))
		check(result.get("ok", false), "F6: " + str(result))
	EditorInterface.stop_playing_scene()
	await frames(5)
	print("SECTION_SELECTION_F6 ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)

func _verify_section_budget(world: Node, importer: Node, map: EmberMapLoader, scene: Node) -> void:
	# Repeat + Section without leaving edit mode after the first successful Apply.
	importer._extend_compact_map()
	drag(world, Vector2i(2, 0), Vector2i(2, 0))
	world._section_next.pressed.emit()
	var dialog: Control = world._generation_panel
	check(dialog.visible, "first addition did not open parameters")
	dialog._preview_button.pressed.emit()
	await ready_dialog(dialog)
	dialog.get_apply_button().pressed.emit()
	await ready_tiles(map._visual_surface_projection)
	check(world.enabled.button_pressed and not dialog.visible, "Apply left edit mode or kept parameters")
	importer._extend_compact_map()
	drag(world, Vector2i(3, 0), Vector2i(3, 0))
	world._section_next.pressed.emit()
	check(dialog.visible, "second addition without exiting edit mode did not open parameters")
	dialog.hide()
	# Exercise the real water study owner/gate without preparing animated fields.
	var water := preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd").new()
	scene.add_child(water)
	water.set_process(false)
	var source: Terrain = world.entry.resource
	var count := source.sections.size()
	var file_hash := FileAccess.get_sha256(world.entry.path)
	importer._extend_compact_map()
	drag(world, Vector2i(4, 0), Vector2i(7, 3))
	world._section_next.pressed.emit()
	check(dialog.visible, "regional water still rejected the 192x96 envelope")
	check(not world._section_mode, "Next kept selection instead of opening parameters")
	check(world.entry.resource == source and source.sections.size() == count and FileAccess.get_sha256(world.entry.path) == file_hash, "Next changed existing terrain or saved file")
	await capture("section_budget")
	dialog.hide()
	water.free()
	# Closing the parameters also permits another selection.
	drag(world, Vector2i(3, 0), Vector2i(3, 0))
	world._section_next.pressed.emit()
	check(dialog.visible, "dismissed rejection broke subsequent addition")
	dialog.hide()
