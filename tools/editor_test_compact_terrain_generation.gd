@tool
extends EditorPlugin
## Disposable Forward+ editor fixture. Never enable in the author's project.

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const SCENE := "res://qa_generation/scenes/generation_native.tscn"
var errors: Array[String] = []
var _camera: Camera3D


func _enter_tree() -> void:
	_run.call_deferred()


func frames(count: int) -> void:
	for i in count: await get_tree().process_frame


func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL generator native: ", message)


func ready_tiles(projection: EmberTerrainPilotProjection) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while projection.pending_tile_count() > 0 and Time.get_ticks_msec() < deadline: await frames(1)
	check(projection.pending_tile_count() == 0, "tile timeout")


func ready_dialog(dialog: ConfirmationDialog) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while dialog.get_ok_button().disabled and Time.get_ticks_msec() < deadline: await frames(1)
	check(not dialog.get_ok_button().disabled, "preview timeout: " + dialog._status.text)


func capture(name: String, dialog: ConfirmationDialog = null) -> void:
	await frames(5)
	await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://qa_generation/" + name + ".png")
	if dialog != null and dialog.visible: dialog.get_texture().get_image().save_png("res://qa_generation/dialog.png")


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"):
		printerr("FAIL generator native: disposable project required"); return
	if "--dialog-regression" in OS.get_cmdline_user_args():
		await _dialog_regression()
		return
	print("GENERATOR_NATIVE start")
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false, "importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete, "editor preparation timeout")
	for path in [SCENE, "res://qa_generation/terrains/generation_native.res"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var creation := Creation.new()
	creation.scene_directory = SCENE.get_base_dir()
	creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("generation_native", 2, 2, 12), creation.error)
	check(not creation.commit().is_empty(), creation.error)
	EditorInterface.open_scene_from_path(SCENE)
	EditorInterface.reload_scene_from_path(SCENE)
	await frames(20)
	EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	var map := scene.get_node("Map") as EmberMapLoader
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection)
	_camera = Camera3D.new()
	EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.position = Vector3(1100, 1150, 1300)
	_camera.look_at_from_position(_camera.position, Vector3(384, 65, 384))
	_camera.far = 8000
	_camera.make_current()
	world.edit_region = Rect2i(0, 0, 48, 48)
	world._open_terrain_generation()
	var dialog: ConfirmationDialog = world._generation_dialog
	check(dialog.visible and world._generation_context.area == world.edit_region, "existing selection not used")
	var original_hash := FileAccess.get_sha256(map.compact_terrain.resource_path)
	dialog._preview_button.pressed.emit()
	await ready_dialog(dialog)
	check(world._generation_context.candidate.height_limit > 128, "height range not raised")
	check(world.sessions.dirty_count(scene) == 0, "preview dirtied source")
	await capture("hills", dialog)
	dialog.hide()
	await frames(3)
	check(world._generation_preview == null and world._generation_job == null, "cancel left pending preview")
	check(FileAccess.get_sha256(map.compact_terrain.resource_path) == original_hash, "preview changed saved file")
	world._open_terrain_generation()
	dialog._profile.select(2)
	dialog._profile.item_selected.emit(2)
	dialog._preview_button.pressed.emit()
	await ready_dialog(dialog)
	await capture("eroded", dialog)
	var candidate: Terrain = world._generation_context.candidate
	var preview := world._generation_preview as Node3D
	var mesh := preview.get_node("PreviewTile_6_6").get_child(0, true) as MeshInstance3D
	var points: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	dialog.get_ok_button().pressed.emit()
	check(not dialog.visible, "successful native confirmation did not close the dialog")
	dialog.hide()
	await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map, scene)
	check(draft.resource == candidate and world.sessions.dirty_count(scene) == 1, "Apply regenerated or lost candidate")
	var ground := projection._tiles[Vector2i(6, 6)].get_node("Ground") as MeshInstance3D
	check(ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == points, "preview/Apply geometry mismatch")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	await ready_tiles(projection)
	check(draft.resource.height_limit == 128 and draft.resource.column_value("heights", 0) == 12, "native Undo")
	history.redo()
	await ready_tiles(projection)
	check(draft.resource.same_terrain_data(candidate), "native Redo")
	# Preserve the original entry marker below the raised hill. Real F6 must
	# resolve its height from terrain, rather than rely on a QA-only reposition.
	check(map.get_node("Regions/PlayerStart").position.y < projection.floor_surface_sample(Vector3(384, 1000, 384)).position.y, "fixture entry was not below generated land")
	var playback := Node.new()
	playback.name = "GenerationPlaybackCheck"
	playback.set_script(load("res://tools/test_compact_terrain_generation_playback.gd"))
	scene.add_child(playback)
	playback.owner = scene
	check(world.sessions.save_all(scene), world.sessions.error)
	var packed := ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := packed.instantiate()
	check(reopened.get_node("Map").compact_terrain.same_terrain_data(candidate), "native Save/Reopen")
	reopened.free()
	var entry: Dictionary = world.sessions.open_map(map, scene)
	world._apply_generated_terrain(map, entry, creation.source.sectioned_copy())
	world.sessions.discard(scene)
	check(entry.resource.same_terrain_data(candidate) and world.sessions.dirty_count(scene) == 0, "native Discard")
	await ready_tiles(projection)
	await capture("applied")
	_camera.queue_free()
	print("GENERATOR_NATIVE ", "PASS" if errors.is_empty() else "FAIL", " selection/cancel/preview-parity/height-range/Undo-Redo/Save-Reopen/Discard errors=", errors)
	var result_path := "res://qa_generation/play_result.json"
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
	print("GENERATOR_F6 ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)


func _dialog_regression() -> void:
	await frames(20)
	var source_job := Creation.new()
	check(source_job.prepare_sections("dialog_bounds_fixture", 2, 2, 12), source_job.error)
	var probe_map := EmberMapLoader.new()
	probe_map.authored_size_blocks = Vector2i(72, 48)
	probe_map.compact_terrain = source_job.source
	var probe_world := preload("res://addons/ember_import/ember_world_editor.gd").new()
	probe_world.map = probe_map
	probe_world.entry = {"compact": true, "resource": source_job.source}
	probe_world._open_terrain_generation()
	check(probe_world._generation_context.area == Rect2i(0, 0, 48, 48), "default area follows scene metadata instead of actual terrain")
	probe_world._generation_dialog.hide()
	probe_world._generation_dialog.queue_free()
	probe_world.free()
	probe_map.free()
	var dialog := preload("res://addons/ember_import/ember_compact_terrain_generation_dialog.gd").new()
	EditorInterface.get_base_control().add_child(dialog)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for dimensions in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		DisplayServer.window_set_size(dimensions)
		await frames(10)
		dialog.open_for(Rect2i(0, 0, 48, 48))
		await frames(15)
		print("GENERATOR_DIALOG_PROBE opened=", dialog.size, " host=", EditorInterface.get_base_control().size, " scale=", EditorInterface.get_editor_scale())
		dialog.set_pending("Область выходит за границу карты.")
		await frames(15)
		var host := EditorInterface.get_base_control().size
		check(dialog.size.y <= mini(800, int(host.y * 0.85)), "dialog exceeds bounded editor height: " + str(dialog.size))
		check(dialog.size.x <= int(host.x * 0.9), "dialog exceeds editor width")
		check(dialog._preview_button.position.y + dialog._preview_button.size.y < dialog.size.y, "preview outside dialog")
		await RenderingServer.frame_post_draw
		dialog.get_texture().get_image().save_png("res://qa_generation/dialog_%dx%d.png" % [dimensions.x, dimensions.y])
		dialog.hide()
	dialog.queue_free()
	# Audit the neighbouring authoring windows without applying any operation.
	var map_dialog := preload("res://addons/ember_import/ember_compact_map_dialog.gd").new()
	EditorInterface.get_base_control().add_child(map_dialog)
	map_dialog.open_for()
	await frames(15)
	print("GENERATOR_NEIGHBOUR_AUDIT map=", map_dialog.size, " minimum=", map_dialog.get_contents_minimum_size())
	map_dialog.hide()
	map_dialog.queue_free()
	var section_dialog := preload("res://addons/ember_import/ember_compact_map_extension_dialog.gd").new()
	EditorInterface.get_base_control().add_child(section_dialog)
	var section_map := EmberMapLoader.new()
	section_map.authored_size_blocks = Vector2i(48, 48)
	section_dialog.open_for(section_map)
	await frames(15)
	print("GENERATOR_NEIGHBOUR_AUDIT section=", section_dialog.size, " minimum=", section_dialog.get_contents_minimum_size())
	section_dialog.hide()
	section_dialog.queue_free()
	section_map.free()
	print("GENERATOR_DIALOG_REGRESSION ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
