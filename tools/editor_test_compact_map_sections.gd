@tool
extends EditorPlugin
## Enable only in a disposable Forward+ checkout/cache, never in the author's project.

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const SCENE := "res://qa_sections/scenes/addressed_native.tscn"
var errors: Array[String] = []
var _qa_camera: Camera3D


func _enter_tree() -> void:
	print("ADDRESSED_NATIVE start")
	_run.call_deferred()


func frames(count: int) -> void:
	for i in count: await get_tree().process_frame


func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL addressed native: ", message)


func ready_tiles(projection: EmberTerrainPilotProjection) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while projection.pending_tile_count() > 0 and Time.get_ticks_msec() < deadline: await frames(1)
	check(projection.pending_tile_count() == 0, "tile queue timeout")
	check(projection.pending_runtime_lod_count() == 0 and not projection._mesh_lod_thread.is_started(), "editor started gameplay LOD preparation")
	check(int(projection.profile_snapshot().ground_lod_jobs) == 0, "editor built gameplay LODs")
	check(int(projection.profile_snapshot().water_lod_jobs) == 0, "editor built water LODs")
	check(projection._geometry_cache == null and int(projection.profile_snapshot().geometry_cache_hits) == 0 and int(projection.profile_snapshot().geometry_cache_misses) == 0, "editor entered gameplay geometry cache")
	for tile: Node3D in projection._tiles.values():
		check(tile.get_node("Ground").lod_bias == 1.0, "editor ground inherited gameplay LOD bias")
		var water: ArrayMesh = tile.get_node("Water").mesh
		check(water.get_surface_count() == 0 or water.surface_get_array_index_len(0) == 0, "editor indexed gameplay water")


func ready_dialog(dialog: ConfirmationDialog) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while dialog.get_ok_button().disabled and Time.get_ticks_msec() < deadline: await frames(1)
	check(not dialog.get_ok_button().disabled, "preview timeout: " + dialog._status.text)


func capture(name: String) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://qa_sections/" + name + ".png")
	var dialog := EditorInterface.get_base_control().find_children("*", "ConfirmationDialog", true, false)
	for window: ConfirmationDialog in dialog:
		if window.visible and window.title == "Расширить компактную карту":
			window.get_texture().get_image().save_png("res://qa_sections/dialog.png")


func _run() -> void:
	var path := ProjectSettings.globalize_path("res://")
	if not (path.contains("ember-sections-native-") or path.contains("ember-river-preview-")):
		printerr("FAIL addressed native: disposable project required")
		return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false, "importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete, "editor preparation timeout")
	var creation := Creation.new()
	creation.scene_directory = SCENE.get_base_dir()
	creation.terrain_directory = "res://qa_sections/terrains"
	if FileAccess.file_exists(SCENE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCENE))
		DirAccess.remove_absolute(ProjectSettings.globalize_path("res://qa_sections/terrains/addressed_native.res"))
	if not FileAccess.file_exists(SCENE):
		check(creation.prepare_sections("addressed_native", 2, 2, 12), creation.error)
		for z in 64:
			for x in creation.source.width:
				var i := creation.source.column_index(x, z)
				creation.source.water_levels[i] = 16
				creation.source.water_materials[i] = 5
		check(not creation.commit().is_empty(), creation.error)
	EditorInterface.open_scene_from_path(SCENE)
	EditorInterface.reload_scene_from_path(SCENE)
	print("ADDRESSED_NATIVE fixture open")
	await frames(20)
	print("ADDRESSED_NATIVE scene settled")
	EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	var map := scene.get_node("Map") as EmberMapLoader
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	print("ADDRESSED_NATIVE tiles pending=", projection.pending_tile_count(), " map_blocks=", map.authored_size_blocks, " source=", Vector2i(map.compact_terrain.width, map.compact_terrain.depth))
	await ready_tiles(projection)
	print("ADDRESSED_NATIVE initial tiles ready")
	_qa_camera = Camera3D.new()
	EditorInterface.get_editor_viewport_3d(0).add_child(_qa_camera)
	_qa_camera.position = Vector3(1500, 1350, 1600)
	_qa_camera.look_at_from_position(_qa_camera.position, Vector3(600, 12, 380))
	_qa_camera.far = 8000
	_qa_camera.make_current()
	var original_hash := FileAccess.get_sha256(map.compact_terrain.resource_path)
	var retained := projection._tiles[Vector2i.ZERO] as Node3D
	importer._extend_compact_map_by_address()
	print("ADDRESSED_NATIVE dialog opened")
	var dialog: ConfirmationDialog = importer._compact_extension_dialog
	# An old scene footprint must offer an explicit, undoable metadata repair.
	map.authored_size_blocks = Vector2i(72, 48)
	dialog._request_preview()
	check(dialog._repair_button.visible and dialog.get_ok_button().disabled, "extent mismatch has no repair action")
	dialog._repair_button.pressed.emit()
	await ready_dialog(dialog)
	check(map.authored_size_blocks == Vector2i(48, 48), "extent repair used scene metadata instead of terrain")
	var repair_history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	repair_history.undo()
	check(map.authored_size_blocks == Vector2i(72, 48), "extent repair native Undo")
	repair_history.redo()
	check(map.authored_size_blocks == Vector2i(48, 48), "extent repair native Redo")
	await ready_dialog(dialog)
	check(dialog.section_index() == 0 and dialog.section_address().x < 0, "default single-edge selection")
	check(world._compact_extension_candidate.after.sections.size() == 5, "preview filled the whole edge")
	check(map.compact_terrain.sections.size() == 4, "preview changed saved source")
	await capture("preview")
	dialog.canceled.emit()
	await frames(3)
	check(world._compact_extension_preview == null and (retained as Node3D).visible, "cancel did not restore live terrain")
	check(FileAccess.get_sha256(map.compact_terrain.resource_path) == original_hash, "preview rewrote the source file")
	importer._extend_compact_map_by_address()
	dialog = importer._compact_extension_dialog
	await ready_dialog(dialog)
	var preview := world._compact_extension_preview as Node3D
	var preview_ground := preview.get_node("PreviewTile_12_2").get_child(0, true) as MeshInstance3D
	var preview_points: PackedVector3Array = preview_ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	dialog._submit()
	await frames(3)
	await ready_tiles(projection)
	check(world.sessions.dirty_count(scene) == 1 and projection.document.sections.size() == 5, "Apply is not a single scene draft")
	check(projection._tiles[Vector2i.ZERO] == retained, "Apply rebuilt an untouched interior tile")
	check(projection.built_tile_count() == 180, "missing-address tiles were created")
	var ground := projection._tiles[Vector2i(12, 2)].get_node("Ground") as MeshInstance3D
	check(ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == preview_points, "preview geometry differs from Apply")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	await ready_tiles(projection)
	check(projection.document.sections.size() == 4 and map.authored_size_blocks == Vector2i(48, 48), "native extension Undo")
	history.redo()
	await ready_tiles(projection)
	check(projection.document.sections.size() == 5, "native extension Redo")
	# West/north growth uses the existing scene shift, then reverses it on Undo.
	var old_start: Vector3 = map.get_node("Regions/PlayerStart").position
	check(world.extend_compact_map("west", "continue", 1) == "", "west partial extension")
	await ready_tiles(projection)
	check(projection.document.sections.size() == 6 and map.get_node("Regions").position.x == 384, "west section or scene anchor shift")
	history.undo()
	await ready_tiles(projection)
	check(projection.document.sections.size() == 5 and map.get_node("Regions").position.x == 0, "west Undo shift")
	check(map.get_node("Regions/PlayerStart").position == old_start, "west Undo changed start")
	importer._extend_compact_map_by_address()
	dialog = importer._compact_extension_dialog
	dialog._coverage.select(2)
	dialog._address_x.set_value_no_signal(2)
	dialog._address_z.set_value_no_signal(1)
	dialog._request_preview()
	await ready_dialog(dialog)
	check(dialog.section_address() == Vector2i(2, 1), "address selection")
	dialog._submit()
	await frames(3)
	await ready_tiles(projection)
	check(projection.document.sections.size() == 6 and projection.floor_surface_sample(Vector3(800, 30, 500)).solid, "fill an empty address")
	history.undo()
	await ready_tiles(projection)
	check(projection.document.sections.size() == 5 and not projection.floor_surface_sample(Vector3(800, 30, 500)).solid, "address Undo")
	var entry: Dictionary = world.sessions.open_map(map, scene)
	var brush := Brush.new()
	brush.configure(entry, get_undo_redo(), scene)
	check(brush.begin("raise", 1, 4, 2, 0, 16, 1, 9, 0, -99999, "coarse"), "seam brush start")
	brush.stamp(Vector2i(766, 200))
	brush.stamp(Vector2i(770, 200))
	brush.end()
	var index: int = entry.resource.column_index(772, 200)
	check(entry.resource.column_value("heights", index) > 12, "seam brush did not cross sections")
	history.undo()
	check(entry.resource.column_value("heights", index) == 12, "native brush Undo")
	history.redo()
	await ready_tiles(projection)
	check(entry.resource.column_value("heights", index) > 12, "native brush Redo")
	map.get_node("Regions/PlayerStart").position = Vector3(720, 20, 208)
	var playback := Node.new()
	playback.name = "SectionsPlaybackCheck"
	playback.set_script(load("res://tools/test_compact_map_sections_playback.gd"))
	playback.geometry_cache_directory = "user://ember-tests/native-geometry-cache-" + str(Time.get_ticks_usec())
	scene.add_child(playback)
	playback.owner = scene
	# Save through the real world/session and scene owner, then discard a draft.
	check(world.sessions.save_all(scene), world.sessions.error)
	check(map.compact_terrain.sections.size() == 5 and world.sessions.dirty_count(scene) == 0, "native Save baseline")
	var packed := ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := packed.instantiate()
	var saved: Terrain = reopened.get_node("Map").compact_terrain
	check(saved.sections.size() == 5 and saved.column_value("heights", index) > 12, "native saved scene/resource reopen")
	reopened.free()
	var next: Dictionary = world.sessions.open_map(map, scene)
	var saved_blocks := map.authored_size_blocks
	var saved_regions: Vector3 = map.get_node("Regions").position
	check(world.extend_compact_map("north", "flat", 0) == "", "discard resize fixture")
	world.sessions.discard(scene)
	check(map.authored_size_blocks == saved_blocks and map.get_node("Regions").position == saved_regions, "Discard left resized scene/group anchors")
	brush.configure(next, get_undo_redo(), scene)
	check(brush.begin("raise", 0.0625, 2, 2, 0, 16, 0, 9, 0), "discard brush start")
	brush.stamp(Vector2i(772, 200)); brush.end()
	world.sessions.discard(scene)
	check(world.sessions.dirty_count(scene) == 0 and projection.document.column_value("heights", index) == saved.column_value("heights", index), "native Discard")
	await ready_tiles(projection)
	await capture("applied")
	_qa_camera.queue_free()
	print("ADDRESSED_NATIVE ", "PASS" if errors.is_empty() else "FAIL", " preview/cancel/apply-parity/partial-edge/west-shift/Undo-Redo/seam-brush/Save-Reopen/Discard errors=", errors)
	var result_path := "res://qa_sections/play_result.json"
	for pass_index in 2:
		if FileAccess.file_exists(result_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
		EditorInterface.play_current_scene()
		deadline = Time.get_ticks_msec() + 60000
		while not FileAccess.file_exists(result_path) and Time.get_ticks_msec() < deadline: await frames(1)
		check(FileAccess.file_exists(result_path), "F6 playback result missing")
		if FileAccess.file_exists(result_path):
			var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path))
			check(result.get("ok", false), "F6 walk: " + str(result))
			check(int(result.get("geometry_cache_failures", -1)) == 0, "F6 cache I/O failed")
			if pass_index == 0: check(int(result.get("geometry_cache_misses", 0)) > 0, "cold F6 did not fill cache")
			else: check(int(result.get("geometry_cache_hits", 0)) > 0 and int(result.get("geometry_cache_misses", -1)) == 0, "warm F6 rebuilt geometry")
			print("ADDRESSED_CACHE_F6 ", "cold" if pass_index == 0 else "warm", " ", result)
		EditorInterface.stop_playing_scene()
		await frames(15)
	print("ADDRESSED_F6 ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
