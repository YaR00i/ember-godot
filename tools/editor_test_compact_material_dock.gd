@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const Pattern = preload("res://scripts/ember_compact_terrain_pattern.gd")

func cell_point(grid: Control, cell: Vector2i) -> Vector2:
	var side := minf(grid.size.x, grid.size.y) / 16.0
	return (grid.size - Vector2.ONE * side * 16.0) / 2.0 + (Vector2(cell) + Vector2(0.5, 0.5)) * side

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Material dock QA requires isolating stale qa_selection experiments."); get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false, "importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete, "preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600, 900))
	var prefix := "qa_mat_" + str(OS.get_process_id())
	var a := prefix + "_a"; var b := prefix + "_b"; var c := prefix + "_c"
	for id in [a, b]: check(ResourceSaver.save(Materials.load_compact_terrain_pattern("grass").duplicate(true), Materials.variant_path(id)) == OK, "fixture pattern save")
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections(prefix, 1, 1, 48), creation.error)
	var path: String = creation.commit(); check(not path.is_empty(), creation.error)
	EditorInterface.get_resource_filesystem().update_file(path); await frames(10)
	EditorInterface.open_scene_from_path(path)
	deadline = Time.get_ticks_msec() + 30000
	while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != path) and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(15); EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	check(scene != null and scene.scene_file_path == path, "fixture scene open")
	if not errors.is_empty(): get_tree().quit(1); return
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true; world.category.select(1); world._category_changed(1)
	var map := scene.get_node("Map") as EmberMapLoader
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection)
	check(world.set_compact_surface_material(2, "grass", a), "assign first fixture")
	check(world.set_compact_surface_material(3, "grass", b), "assign second fixture")
	world.palette.select(1); world._refresh_palette_swatch()
	var draft: Dictionary = world.sessions.open_map(map, scene)
	var before: Terrain = draft.resource.working_copy()
	var mesh_count: int = projection.built_tile_count()
	var terrain_hash := FileAccess.get_sha256(map.compact_terrain.resource_path)
	var a_hash := FileAccess.get_sha256(Materials.variant_path(a))
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(620, 740, 720), Vector3(192, 48, 192)); _camera.far = 8000; _camera.make_current()
	world.material_pattern_button.pressed.emit(); await frames(10)
	var editor: Control = world.material_pattern_dialog
	check(world._material_mode and editor.is_visible_in_tree() and world.inspector_panel.is_ancestor_of(editor.parameters_panel), "split material layout did not open")
	check(editor._id == a and not world.sidebar.visible, "wrong material or crowded viewport")
	check(editor._canvas_scroll.size.y >= 256 and editor._canvas_scroll.get_global_rect().encloses(editor._grid.get_global_rect()), "grid clipped in default bottom panel")
	var host := EditorInterface.get_base_control().get_global_rect()
	check(host.encloses(editor.get_global_rect()) and host.encloses(editor.parameters_panel.get_global_rect()), "panels outside editor")
	editor._parameter_scroll.scroll_vertical = 10000; await frames(6)
	check(editor.parameters_panel.get_global_rect().encloses(editor._save_button.get_global_rect()), "Save outside pinned footer")
	editor._parameter_scroll.scroll_vertical = 0
	var original: PackedByteArray = editor._draft.pixels.duplicate()
	editor._grid.current_tone = (int(original[0]) + 1) % 3
	var down := InputEventMouseButton.new(); down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.position = cell_point(editor._grid, Vector2i.ZERO)
	editor._grid._gui_input(down)
	var move := InputEventMouseMotion.new(); move.button_mask = MOUSE_BUTTON_MASK_LEFT; move.position = cell_point(editor._grid, Vector2i(1, 0)); editor._grid._gui_input(move)
	down.pressed = false; down.position = move.position; editor._grid._gui_input(down)
	check(editor._draft.pixels[0] != original[0] and editor.is_dirty(), "native drag did not paint")
	editor._grid.grab_focus()
	var key := InputEventKey.new(); key.pressed = true; key.ctrl_pressed = true; key.keycode = KEY_Z
	Input.parse_input_event(key); await frames(4)
	check(editor._draft.pixels == original, "focused Ctrl+Z did not undo entire stroke")
	key.keycode = KEY_Y; Input.parse_input_event(key); await frames(4)
	check(editor.is_dirty(), "focused Ctrl+Y did not redo")
	var orbit := InputEventMouseMotion.new(); orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(importer._forward_3d_gui_input(_camera, orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS, "material editor blocked camera")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	check(importer._forward_3d_gui_input(_camera, click) == EditorPlugin.AFTER_GUI_INPUT_PASS and not world._compact_brush.active(), "viewport click painted terrain")
	importer._new_compact_map()
	check(importer._compact_map_panel == null and world._material_mode and editor.is_dirty(), "new-map command discarded material draft")
	importer.hide_bottom_panel(); await frames(5)
	check(editor.is_dirty(), "collapse lost material draft")
	importer.make_bottom_panel_item_visible(editor); await frames(5)
	check(editor.open_variant(b, "grass") and editor._switch_box.visible and editor._id == a, "dirty material switch lost draft")
	editor._resolve_variant_switch(false)
	check(editor._id == b and FileAccess.get_sha256(Materials.variant_path(a)) == a_hash, "discard-switch wrote previous material")
	editor._finish_sliders.gloss.value = 0.65
	check(editor.open_variant(a, "grass"), "switch back request")
	editor._resolve_variant_switch(true)
	check(editor._id == a and is_equal_approx(Materials.load_compact_terrain_variant(b).gloss, 0.65), "save-switch failed")
	editor._select_face(1); editor._set_pixels(editor._draft.pixels.duplicate(), true)
	editor._file_import = false; editor._on_file_selected("user://qa-material-dock-side.png")
	check(FileAccess.file_exists("user://qa-material-dock-side.png"), "side PNG export")
	editor._file_import = true; editor._on_file_selected("user://qa-material-dock-side.png")
	editor._finish_sliders.gloss.value = 0.45
	editor._finish_sliders.micro_relief.value = 0.23
	editor.undo_edit(); check(is_zero_approx(editor._draft.micro_relief),"detail Undo")
	editor.redo_edit(); check(is_equal_approx(editor._draft.micro_relief,0.23),"detail Redo")
	editor._finish_sliders.micro_size_m.value = 0.14
	editor._finish_sliders.micro_roughness.value = 0.26
	await capture("material_dock", editor)
	editor._save_button.pressed.emit(); await frames(6)
	check(not world._material_mode and world.sidebar.visible and not importer._material_pattern_bottom_button.visible, "Save did not restore tools")
	var saved := Materials.load_compact_terrain_variant(a)
	check(saved.side_pixels.size() == 256 and is_equal_approx(saved.gloss, 0.45), "side/finish Save-Reopen")
	check(is_equal_approx(saved.micro_relief,0.23) and is_equal_approx(saved.micro_size_m,0.14) and is_equal_approx(saved.micro_roughness,0.26),"detail Save-Reopen")
	check(draft.resource.same_terrain_data(before) and FileAccess.get_sha256(map.compact_terrain.resource_path) == terrain_hash and projection.built_tile_count() == mesh_count, "material editing changed/remeshed/saved terrain")
	world._open_material_pattern(); editor._finish_sliders.gloss.value = 0.75
	editor.cancel_edit(); world._open_material_pattern()
	check(is_equal_approx(editor._draft.gloss, 0.45), "Cancel-Reopen lost saved baseline")
	world.palette.select(2) # A different selected slot must not redirect the file editor.
	editor._show_new_variant(); editor._name_input.text = c; editor._create_variant(); await frames(5)
	check(Materials.load_compact_terrain_variant(c) != null and draft.resource.material_id_for_palette(2) == c, "new variant not assigned to original slot")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); check(draft.resource.material_id_for_palette(2) == a, "variant slot Undo")
	history.redo(); check(draft.resource.material_id_for_palette(2) == c, "variant slot Redo")
	check(world.sessions.save_all(scene), world.sessions.error)
	var reopened := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_terrain.material_id_for_palette(2) == c, "scene Save-Reopen assigned variant")
	reopened.free()
	world._open_material_pattern(); editor._finish_sliders.sheen.value = 0.5
	world.sessions.discard(scene); await ready_tiles(projection)
	check(world._material_mode and editor.is_dirty(), "terrain Discard lost independent material draft")
	var other := Creation.new(); other.scene_directory = creation.scene_directory; other.terrain_directory = creation.terrain_directory
	check(other.prepare_sections(prefix + "_other", 1, 1, 48), other.error)
	var other_path: String = other.commit(); EditorInterface.get_resource_filesystem().update_file(other_path); await frames(10)
	EditorInterface.open_scene_from_path(other_path)
	deadline = Time.get_ticks_msec() + 30000
	while (world.scene == null or world.scene.scene_file_path != other_path) and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(10)
	check(world.scene.scene_file_path == other_path and world._material_mode and editor.is_dirty() and editor.parameters_panel.is_visible_in_tree(), "scene switch lost independent material draft")
	var other_ids: PackedStringArray = world.entry.resource.palette_material_ids.duplicate()
	editor._show_new_variant(); editor._name_input.text = c + "_detached"; editor._create_variant(); await frames(5)
	check(Materials.load_compact_terrain_variant(c + "_detached") != null and world.entry.resource.palette_material_ids == other_ids, "detached editor assigned to wrong map")
	_camera.queue_free()
	print("COMPACT_MATERIAL_DOCK_NATIVE ", "PASS" if errors.is_empty() else "FAIL", " layout/drag/keyboard/PNG/switch/save/cancel/collapse/guards/variant/Undo-Redo/Save-Reopen/Discard/scene-switch/original-slot/no-remesh errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
