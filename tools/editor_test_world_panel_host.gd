@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"

const ShapeCreation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")

func select_target(target: Node) -> void:
	var selection := EditorInterface.get_selection(); selection.clear(); selection.add_node(target)

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Panel host QA requires isolating stale qa_selection experiments."); get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600,900))
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("qa_host_" + str(OS.get_process_id()),1,1,48),creation.error)
	var path: String = creation.commit(); check(not path.is_empty(),creation.error)
	EditorInterface.get_resource_filesystem().update_file(path); await frames(10); EditorInterface.open_scene_from_path(path)
	deadline = Time.get_ticks_msec() + 30000
	while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != path) and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(15); EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	check(scene != null and scene.scene_file_path == path,"fixture open")
	if not errors.is_empty(): get_tree().quit(1); return
	var world: Node = importer._world_editor
	var map := scene.get_node("Map") as EmberMapLoader; var props := map.get_node("Props") as Node3D
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection; await ready_tiles(projection)
	var shape := ShapeCreation.new(); shape.source_directory = "res://content/voxel_models"; shape.prefab_directory = "user://ember-tests/host-%d" % Time.get_ticks_usec()
	check(shape.prepare("block",Vector3i(12,3,5),16,Color("a86f45"),"HostFixture"),"shape fixture")
	var undo := UndoRedo.new(); var target := shape.commit(scene,props,undo,Vector3(160,58,160)); undo.clear_history(); undo.free()
	check(target != null,"shape commit"); if target == null: get_tree().quit(1); return
	var hash := FileAccess.get_sha256(map.compact_terrain.resource_path); var built := projection.built_tile_count(); var transform := target.transform
	world.enabled.button_pressed = true; await ready_tiles(projection)
	world.edit_region = Rect2i(0,0,24,24); world._open_terrain_generation()
	importer._new_voxel_shape(); world.shape_panel._sizes[0].value += 1
	select_target(target); importer._place_voxel_selection()
	check(world._panel_host.is_active("shape") and world.placement_panel.placement == null,"shape draft lost to placement")
	world.shape_panel.cancel_edit()
	check(world._terrain_workspace.visible,"shape cancel lost terrain page")
	importer._place_voxel_selection(); importer._new_voxel_shape()
	check(world._panel_host.is_active("shape") and world.placement_panel.placement == null,"clean placement did not yield")
	world._close_placement_workspace(); check(world._shape_workspace.visible,"late close hid new page")
	world.shape_panel.cancel_edit()
	select_target(target); importer._scene_assembly_command(4)
	importer._new_voxel_shape(); check(world._panel_host.is_active("duplicate"),"duplicate plan lost to shape")
	world.duplicate_panel.cancel_edit(); check(world._terrain_workspace.visible,"duplicate lost return workspace")
	importer._new_compact_map(); var map_panel: Control = importer._compact_map_panel
	map_panel._height.value += 4; importer._place_voxel_selection()
	check(world._panel_host.is_active("map") and importer._compact_map_panel == map_panel,"new-map settings lost to placement")
	importer._new_compact_map(); check(importer._compact_map_panel == map_panel,"repeat new-map replaced pending panel")
	importer._cancel_compact_map_creation(); check(world._terrain_workspace.visible,"map cancel lost terrain page")
	world._show_workspace(false); world.category.select(1); world._category_changed(1); world.palette.select(1)
	world._open_material_pattern(); var material: Control = world.material_pattern_dialog
	material._finish_sliders.gloss.value += 0.1; select_target(target); importer._scene_assembly_command(4)
	check(world._panel_host.is_active("material") and material.is_dirty(),"material lost to duplicate")
	material.cancel_edit(); check(world._tools_workspace.visible,"material cancel lost tools page")
	world._deactivate(); importer._activate_object_brush(target.model_id)
	check(world._panel_host.is_active("objects") and importer._object_brush.active,"brush route unavailable")
	importer._open_object_brush_settings()
	check(world._panel_host.is_active("objects") and importer._object_brush.active,"repeat settings deactivated brush")
	select_target(target); importer._place_voxel_selection()
	check(world._panel_host.is_active("placement") and not importer._object_brush.active,"brush did not yield to placement")
	world.placement_panel.cancel_edit()
	check(not world._panel_host.any_active() and not importer._world_editor_dock_added,"standalone close retained host")
	check(world.object_parameters.get_parent() == world._object_parameters_parent,"brush controls not restored")
	check(importer._voxel_object_toolbar.visible,"standalone toolbar not restored")
	check(FileAccess.get_sha256(map.compact_terrain.resource_path) == hash and projection.built_tile_count() == built and target.transform == transform,"navigation changed source/mesh/transform")
	print("WORLD_PANEL_HOST_NATIVE ","PASS" if errors.is_empty() else "FAIL"," six-routes/pending/repeat/clean-switch/late-close/return/brush/no-remesh errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
