extends SceneTree

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Dialog = preload("res://addons/ember_import/ember_compact_map_dialog.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const BrushMath = preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const WorldEditor = preload("res://addons/ember_import/ember_world_editor.gd")
const DIRECTORY := "user://compact_map_creation_test"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var plugin_script := load("res://addons/ember_import/plugin.gd") as Script
	assert(plugin_script != null and plugin_script.can_instantiate())
	_clean_fixture()
	var creation := Creation.new()
	creation.scene_directory = DIRECTORY.path_join("scenes")
	creation.terrain_directory = DIRECTORY.path_join("world_terrains")
	assert(not creation.prepare("../bad", 8, 10, 12))
	assert(not creation.prepare("flat_test", 0, 10, 12))
	assert(not creation.prepare("flat_test", 8, 10, 13))
	assert(creation.prepare("flat_test", 8, 10, 12), creation.error)
	assert(BrushMath.edit_profile("coarse").cell_stride == TerrainResource.CELLS_PER_BLOCK / 2)
	var preview: TerrainResource = creation.source
	assert(preview.width == 128 and preview.depth == 160)
	assert(preview.validation_errors().is_empty())
	assert(preview.heights[0] == 12 and preview.top_materials[0] == 2)
	assert(preview.base_materials[0] == 1 and preview.cap_depths[0] == 3)
	assert(preview.water_levels[0] == 0)
	var path := creation.commit()
	assert(not path.is_empty(), creation.error)
	assert(FileAccess.file_exists(path) and FileAccess.file_exists(creation.terrain_path()))
	assert(FileAccess.get_file_as_string(path).contains(creation.terrain_path()))
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert(packed != null)
	var scene := packed.instantiate()
	var saved_map := scene.get_node("Map") as EmberMapLoader
	assert(saved_map != null and saved_map.map_id == "flat_test")
	assert(saved_map.hydrate_legacy_regions == false)
	assert(saved_map.visual_surface == null and saved_map.compact_terrain != null)
	assert(saved_map.authored_size_blocks == Vector2i(8, 10))
	assert(saved_map.compact_terrain.resource_path == creation.terrain_path())
	assert(saved_map.compact_terrain.heights == preview.heights)
	assert(saved_map.get_node_or_null("Regions/PlayerStart") != null)
	assert(scene.get_node_or_null("CanvasLayer/Gate") != null)
	var scene_hash := FileAccess.get_sha256(path)
	var duplicate := Creation.new()
	duplicate.scene_directory = creation.scene_directory
	duplicate.terrain_directory = creation.terrain_directory
	assert(not duplicate.prepare("flat_test", 8, 10, 12))
	assert(FileAccess.get_sha256(path) == scene_hash)
	var large_creation := Creation.new()
	large_creation.scene_directory = creation.scene_directory
	large_creation.terrain_directory = creation.terrain_directory
	var preview_started := Time.get_ticks_msec()
	assert(large_creation.prepare("flat_large", 96, 96, 8), large_creation.error)
	var large_preview_ms := Time.get_ticks_msec() - preview_started
	assert(large_creation.source.width == 1536 and large_creation.source.depth == 1536)
	large_creation.source = null
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.creation.scene_directory = creation.scene_directory
	dialog.creation.terrain_directory = creation.terrain_directory
	dialog._id_field.text = "flat_ui_test"
	dialog._prepare()
	assert(not dialog.get_ok_button().disabled and dialog._swatch.visible)
	dialog._height.value = 16
	await process_frame
	assert(dialog.get_ok_button().disabled)
	dialog.free()
	scene.set_script(null)
	root.add_child(scene)
	assert(scene.scene_file_path == path)
	var map := saved_map
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	assert(projection != null)
	while projection.pending_tile_count() > 0:
		await process_frame
	var floor_sample := map.surface_floor_sample(Vector3(64.5, 0, 80.5))
	assert(floor_sample.solid and is_equal_approx(floor_sample.position.y, 12.0))
	await physics_frame
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(64.5, 100, 80.5), Vector3(64.5, -10, 80.5))
	var hit := root.world_3d.direct_space_state.intersect_ray(ray)
	assert(not hit.is_empty() and is_equal_approx(hit.position.y, 12.0))
	var editor_history := UndoRedo.new()
	var editor := WorldEditor.new()
	scene.add_child(editor)
	editor.configure(null, editor_history)
	editor.build_toolbar()
	editor.build_sidebar()
	editor.scene = scene
	editor.map = map
	editor._target_changed(0)
	assert(editor._compact_active() and editor._mode() == "raise")
	assert(editor._terrain_diagnostics_button.visible and editor._terrain_diagnostics_button.text.contains("производительность"))
	assert(not editor.create_ground_button.visible and not editor.open_canvas_button.visible)
	assert(is_equal_approx(editor.radius_slider.min_value,editor.radius.min_value))
	assert(editor.terrain_edit_scale.visible and editor.terrain_edit_scale.selected == 0)
	assert(editor.terrain_height_step.visible and editor.terrain_height_step.selected == 0)
	assert(editor.brush_shape.visible and editor.brush_shape.selected == 0)
	assert(is_equal_approx(editor.radius.min_value,0.5))
	editor.terrain_edit_scale.select(1)
	editor._refresh_brush_scale_settings()
	editor._tool_changed()
	assert(is_equal_approx(editor.radius.min_value,0.125))
	assert(editor.terrain_height_step.visible)
	editor.terrain_edit_scale.select(2)
	editor.brush_shape.select(1)
	editor._refresh_brush_scale_settings()
	editor._tool_changed()
	assert(is_equal_approx(editor.radius.min_value,0.0625))
	assert(not editor.terrain_height_step.visible)
	editor.terrain_edit_scale.select(0)
	editor.brush_shape.select(0)
	editor._refresh_brush_scale_settings()
	editor._tool_changed()
	editor._category_changed(1)
	assert(editor.terrain_edit_scale.visible and editor.brush_shape.visible and is_equal_approx(editor.radius.min_value,0.5))
	assert(not editor.terrain_height_step.visible)
	editor._category_changed(2)
	assert(editor.terrain_edit_scale.visible and editor.brush_shape.visible and is_equal_approx(editor.radius.min_value,0.5))
	assert(not editor.terrain_height_step.visible)
	editor._category_changed(0)
	assert(editor.terrain_height_step.visible)
	editor.terrain_edit_scale.select(2)
	editor.brush_shape.select(1)
	editor.scene_changed(scene)
	assert(editor.terrain_edit_scale.selected == 0 and editor.brush_shape.selected == 0)
	editor._target_changed(0)
	var stuck_button := InputEventMouseButton.new()
	stuck_button.button_index = MOUSE_BUTTON_RIGHT
	stuck_button.button_mask = MOUSE_BUTTON_MASK_RIGHT
	stuck_button.pressed = true
	Input.parse_input_event(stuck_button)
	Input.flush_buffered_events()
	assert(Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_RIGHT != 0)
	var undo_key := InputEventKey.new()
	undo_key.keycode = KEY_Z
	undo_key.ctrl_pressed = true
	undo_key.pressed = true
	assert(editor._forward_compact(undo_key) == EditorPlugin.AFTER_GUI_INPUT_PASS)
	assert(Input.get_mouse_button_mask() & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE) == 0)
	editor.sessions.discard(scene)
	editor.toolbar.free()
	editor.sidebar.free()
	editor.inspector_panel.free()
	editor.queue_free()
	await process_frame
	editor_history.clear_history()
	editor_history.free()
	var undo := UndoRedo.new()
	var sessions := Sessions.new()
	sessions.configure(undo, func() -> int: return OK)
	var entry := sessions.open_map(map, scene)
	assert(not entry.is_empty() and entry.get("compact", false))
	var brush := Brush.new()
	brush.configure(entry, undo, map)
	var index: int = entry.resource.column_index(64, 80)
	var original: int = entry.resource.heights[index]
	assert(brush.begin("raise", 0.0625, 2, 2, 0, 16, 0, 1, 0))
	brush.stamp(Vector2i(64, 80))
	brush.end()
	assert(entry.resource.heights[index] > original)
	undo.undo()
	assert(entry.resource.heights[index] == original)
	undo.redo()
	assert(entry.resource.heights[index] > original)
	assert(sessions.save_all(scene), sessions.error)
	var saved := ResourceLoader.load(creation.terrain_path(), "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	assert(saved.heights[index] > original)
	sessions.discard(scene)
	undo.clear_history()
	undo.free()
	scene.queue_free()
	await process_frame
	_clean_fixture()
	print("COMPACT_MAP_CREATION preview=apply duplicate_guard=ok scene=ok native_3d_route=ok collision=ok undo_redo=ok save_reopen=ok large_preview_ms=", large_preview_ms)
	quit()


func _clean_fixture() -> void:
	for path in [DIRECTORY.path_join("scenes/flat_test.tscn"), DIRECTORY.path_join("world_terrains/flat_test.res")]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for directory in [DIRECTORY.path_join("scenes"), DIRECTORY.path_join("world_terrains"), DIRECTORY]:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
