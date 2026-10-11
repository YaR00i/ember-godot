@tool
extends "res://tools/editor_test_compact_section_selection.gd"
## Runtime cadence must stay outside the real native editor/brush path.
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const WATER_SCENE := "res://scenes/compact_material_light_study.tscn"

func water_ready(scene: Node) -> void:
	var controller: Node = scene.get_node("PlanarReflection")
	var projection: EmberTerrainPilotProjection = scene.get_node("Map")._visual_surface_projection
	var deadline := Time.get_ticks_msec() + 180000
	await frames(3)
	while Time.get_ticks_msec() < deadline:
		if controller._prepared and controller._water_regions.ready and projection.pending_tile_count() == 0 and controller._field_revision == projection.column_revision(): break
		await frames(1)
	check(controller._prepared and projection.pending_tile_count() == 0, "editor field preparation timed out")
	controller._water_regions.set_runtime_activity(true, PackedVector2Array([Vector2(10000, 10000)]))
	controller._refresh_sea_swash()
	check(not controller._water_regions._runtime_activity, "runtime activity leaked into native editor")
	check(projection.pending_runtime_lod_count() == 0, "editor created LOD jobs")
	check(projection._geometry_cache == null and projection._geometry_keys.is_empty(), "editor entered runtime geometry cache")
	check(projection.profile_snapshot().get("runtime_lod_array_readbacks", 0) == 0, "editor extracted runtime LOD arrays")
	check(projection._geometry_snapshot == null and projection._geometry_prepared.is_empty() and projection._geometry_requests.is_empty(), "editor prepared runtime geometry snapshots")
	check(projection.profile_snapshot().get("geometry_prepare_jobs", 0) == 0, "editor scheduled runtime geometry reads")
	for entry in controller._water_regions.regions.values():
		check(entry.sea._border_records.is_empty() and not entry.sea._border_uploaded, "editor prepared runtime boundary buffers")
		for key in ["object_shapes", "object_shape_meta", "object_shape_count", "reaction_samples", "reaction_details", "reaction_count"]:
			check(entry.water.get_shader_parameter(key) == controller._material.get_shader_parameter(key),
				"editor rebind left a stale water parameter: " + key)

func _run() -> void:
	if ProjectSettings.get_setting("application/config/name") != "Ember River Preview QA": printerr("Disposable native QA only."); return
	var importer := get_parent().get_node("EmberImportPlugin")
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	EditorInterface.open_scene_from_path(WATER_SCENE)
	EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	await water_ready(scene)
	var map: EmberMapLoader = scene.get_node("Map")
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	await frames(3)
	var entry: Dictionary = world.sessions.open_map(map, scene)
	var index: int = entry.resource.column_index(400, 900)
	var before: int = entry.resource.column_value("heights", index)
	var brush := Brush.new(); brush.configure(entry, get_undo_redo(), scene)
	check(brush.begin("raise", 0.0625, 2, 2, 0, 16, 0, 9, 0), "native brush start")
	brush.stamp(Vector2i(400, 900)); brush.end()
	await water_ready(scene)
	check(entry.resource.column_value("heights", index) > before, "brush did not apply")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await water_ready(scene)
	check(entry.resource.column_value("heights", index) == before, "native Undo")
	history.redo(); await water_ready(scene)
	world.sessions.discard(scene); await water_ready(scene)
	check(world.sessions.dirty_count(scene) == 0, "Discard failed")
	var playback := Node.new(); playback.name = "WaterActivityPlayback"
	playback.set_script(load("res://tools/test_compact_water_activity_playback.gd"))
	scene.add_child(playback); playback.owner = scene
	# A previous fixture may still be open in QA's restored tabs. Saving over
	# that tab can disturb Godot's scene index during reload; use a fresh fixture.
	var saved_scene := "res://qa_selection/scenes/water_activity_" + str(Time.get_ticks_usec()) + ".tscn"
	EditorInterface.save_scene_as(saved_scene)
	await frames(5)
	check(FileAccess.file_exists(saved_scene), "QA Save")
	var previous_scene_id := scene.get_instance_id()
	EditorInterface.reload_scene_from_path(saved_scene)
	await frames(3)
	scene = EditorInterface.get_edited_scene_root()
	check(scene.get_instance_id() != previous_scene_id, "QA Reopen must replace the scene root")
	await water_ready(scene)
	await capture("activity_editor")
	var result_path := "res://qa_selection/activity_play_result.json"
	if FileAccess.file_exists(result_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
	EditorInterface.play_current_scene()
	deadline = Time.get_ticks_msec() + 180000
	while not FileAccess.file_exists(result_path) and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(result_path), "F6 result missing")
	if FileAccess.file_exists(result_path):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path))
		check(result.get("ok", false), "F6 actual player/camera/frozen clock: " + str(result))
	EditorInterface.stop_playing_scene(); await frames(5)
	print("WATER_ACTIVITY_EDITOR ", "PASS" if errors.is_empty() else "FAIL", " brush/Undo/Redo/Discard/Save/Reopen/F6 errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
