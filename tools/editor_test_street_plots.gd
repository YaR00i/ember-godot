@tool
extends "res://tools/editor_test_terrain_plan.gd"
## Native road/plot authoring gate on a disposable flat map.


func _run() -> void:
	var evidence := OS.get_environment("EMBER_STREET_EVIDENCE")
	if evidence.is_empty() or not ProjectSettings.globalize_path("res://").contains("ember-entry-"):
		return
	await frames(30)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null:
		check(false, "world editor plugin is available")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec() + 120000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline:
		await frames(1)
	var fixture := Creation.new()
	fixture.scene_directory = SCENE.get_base_dir()
	fixture.terrain_directory = "res://qa_generation/terrains"
	var id := "street_plots_" + str(OS.get_process_id())
	check(fixture.prepare_sections(id, 2, 2, 12), fixture.error)
	var path := fixture.commit()
	if path.is_empty():
		check(false, fixture.error)
		get_tree().quit(1)
		return
	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	var scene := EditorInterface.get_edited_scene_root()
	deadline = Time.get_ticks_msec() + 20000
	while (scene == null or scene.scene_file_path != path) and Time.get_ticks_msec() < deadline:
		await frames(1)
		scene = EditorInterface.get_edited_scene_root()
	if scene == null or scene.scene_file_path != path:
		check(false, "the street fixture opens")
		get_tree().quit(1)
		return
	await frames(20)
	var map := scene.get_node("Map") as EmberMapLoader
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	world.scene_changed(scene)
	world.category.select(0)
	world._category_changed(0)
	await ready_tiles(map._visual_surface_projection)
	EditorInterface.set_main_screen_editor("3D")
	_camera = Camera3D.new()
	EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.position = Vector3(384, 960, 360)
	_camera.look_at(Vector3(384, 12, 360), Vector3.FORWARD)
	_camera.far = 3000
	_camera.make_current()
	world._plan_button.pressed.emit()
	await frames(6)
	check_dry_footprints()
	await check_street_workflow(world, map, scene, path, evidence)
	print("STREET_PLOTS ", JSON.stringify({"pass": errors.is_empty(), "errors": errors}))
	get_tree().quit(0 if errors.is_empty() else 1)


func street_click(world: Node, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = _camera.unproject_position(world._plan_handle_world(point))
	world.forward_input(_camera, event)


func street_key(world: Node, key: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = key
	world.forward_input(_camera, event)


func check_dry_footprints() -> void:
	var edge := Terrain.Sections.CELLS
	var source := Terrain.new()
	source.schema_version = Terrain.SECTION_SCHEMA_VERSION
	source.width = edge + 2
	source.depth = 2
	for x in 2:
		var section := Terrain.new()
		section.width = edge if x == 0 else 2
		section.depth = 2
		section.heights.resize(section.width * section.depth)
		section.heights.fill(12)
		section.water_levels.resize(section.heights.size())
		source.sections[Vector2i(x, 0)] = section
	var bounds := Rect2i(edge - 1, 0, 2, 2)
	check(Terrain.Sections.is_dry_rectangle(source, bounds), "a dry footprint can straddle terrain sections")
	source.sections[Vector2i(1, 0)].water_levels[0] = 13
	check(not Terrain.Sections.is_dry_rectangle(source, bounds), "one wet column rejects a footprint even on a section seam")
	source.sections.erase(Vector2i(1, 0))
	check(not Terrain.Sections.is_dry_rectangle(source, bounds), "an unloaded terrain section does not supply dry ground")


func check_street_workflow(world: Node, map: EmberMapLoader, scene: Node, path: String, evidence: String) -> void:
	var panel: Control = world._plan_panel
	var terrain: Terrain = world.sessions.open_map(map, scene).resource
	var reserved := Rect2i(5, 25, 8, 8)
	panel._add_menu.get_popup().id_pressed.emit(panel.ADD_ACTIONS.find("add_plot"))
	select_rect(world, reserved)
	panel._buttons.add_road.pressed.emit()
	for point in [Vector2(4, 19), Vector2(16, 19), Vector2(29, 23), Vector2(43, 25)]:
		street_click(world, point)
	street_key(world, KEY_ENTER)
	var before: Resource = Plan.read(map)
	check(before != null and before.regions.size() == 2 and before.regions[-1].get("kind") == "road", "draw a road through the existing line tool")
	if before == null or before.regions.size() != 2 or before.regions[-1].get("kind") != "road":
		return
	var road: Dictionary = before.regions[-1]
	var road_id: String = road.id
	world._select_plan_region(road_id)
	check(panel._buttons.street_panel.visible, "road parameters expose the street plot action")
	panel._buttons.street_panel.pressed.emit()
	panel._buttons.street_width.value = 6
	panel._buttons.street_depth.value = 8
	panel._buttons.street_gap.value = 1
	panel._buttons.street_setback.value = 1
	panel._buttons.street_side.select(1)
	panel._buttons.street_preview.pressed.emit()
	var left: Array[Dictionary] = world._street_preview.get("lots", [] as Array[Dictionary])
	check(left.size() >= 2 and Plan.Influence.plan_anchor(left[0]).y < 19, "left-side preview follows the drawn road direction")
	street_key(world, KEY_ESCAPE)
	check(world._street_preview.is_empty() and Plan.same(Plan.read(map), before), "Escape removes only the preview")
	panel._buttons.street_side.select(0)
	var started := Time.get_ticks_usec()
	panel._buttons.street_preview.pressed.emit()
	var preview_us := Time.get_ticks_usec() - started
	var proposed: Array[Dictionary] = world._street_preview.get("lots", [] as Array[Dictionary])
	check(proposed.size() >= 2 and Plan.Influence.plan_anchor(proposed[0]).y > 19, "right-side preview proposes separate lots")
	if proposed.size() < 2:
		return
	check(Plan.Influence.plan_anchor(proposed[-1]).y > Plan.Influence.plan_anchor(proposed[0]).y, "the layout follows the bend of the existing road")
	check(Plan.same(Plan.read(map), before) and world.sessions.open_map(map, scene).resource == terrain,
		"preview only changes the editor overlay")
	for lot in proposed:
		check(Geometry2D.intersect_polygons(Plan.Influence.plan_controls(lot),
			Plan.Influence.rectangle_points(Rect2(reserved))).is_empty(), "the pre-existing construction plot stays clear")
	street_click(world, Plan.Influence.plan_anchor(proposed[0]))
	check(world._street_preview.excluded.has(0), "click a lot on the map to exclude it")
	await frames(8)
	await RenderingServer.frame_post_draw
	check(EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(evidence.path_join("street-plots-preview.png")) == OK,
		"capture the confirmed and excluded lot contours")
	panel._buttons.street_apply.pressed.emit()
	var added: Resource = Plan.read(map)
	check(added.regions.size() == before.regions.size() + proposed.size() - 1, "confirm only included lots")
	if added.regions.size() <= before.regions.size():
		return
	var new_id: String = added.regions[before.regions.size()].id
	for index in range(before.regions.size(), added.regions.size()):
		var lot: Dictionary = added.regions[index]
		var preview := proposed[index - before.regions.size() + 1]
		check(lot.kind == "construction" and lot.parameters.is_empty() and lot.plot_frame == preview.plot_frame and lot.plot_size_m == preview.plot_size_m,
			"each ordinary construction lot uses the exact preview frame and size")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	check(Plan.same(Plan.read(map), before), "undo removes the whole batch")
	history.redo()
	check(Plan.same(Plan.read(map), added), "redo restores the exact lot ids and geometry")
	world._select_plan_region(new_id)
	panel._buttons.bounds.pressed.emit()
	var lot: Dictionary = added.regions[added.index_of(new_id)]
	var resized := Plan.Influence.plan_edit(lot, 2, lot.plot_frame.basis_xform(Vector2(-1, -1)), false)
	check(world.commit_plan_shape(map, new_id, resized).is_empty(), "resize a lot along the local grid")
	var edited: Resource = Plan.read(map)
	check(edited.regions[edited.index_of(new_id)].plot_size_m == resized.plot_size_m, "resize stores the exact local size")
	check(world.save_all(), world.sessions.error)
	var reopened := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved: Resource = Plan.read(reopened.get_node("Map"))
	check(Plan.same(edited, saved) and reopened.get_node("Map").compact_terrain.same_terrain_data(terrain), "reopen plots without a terrain change")
	reopened.free()
	world._select_plan_region(new_id)
	panel._buttons.delete.pressed.emit()
	world.sessions.discard(scene)
	check(Plan.same(Plan.read(map), saved), "discard restores the saved street plots")
	print("STREET_PREVIEW ", JSON.stringify({"preview_ms": preview_us / 1000.0, "lots": proposed.size()}))
