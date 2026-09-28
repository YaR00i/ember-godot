extends SceneTree

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Extension = preload("res://addons/ember_import/ember_compact_map_extension.gd")
const ExtensionDialog = preload("res://addons/ember_import/ember_compact_map_extension_dialog.gd")
const WorldEditor = preload("res://addons/ember_import/ember_world_editor.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const DRAFT := "user://compact_extension_test.res"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var creation := Creation.new()
	creation.scene_directory = "user://compact_extension_test/scenes"
	creation.terrain_directory = "user://compact_extension_test/terrain"
	assert(creation.prepare_sections("section_fixture", 1, 1, 8), creation.error)
	assert(creation.blocks == Vector2i(24, 24))
	assert(not creation.prepare_sections("section_fixture", 5, 1, 8))
	assert(creation.prepare_sections("section_fixture", 1, 1, 8), creation.error)
	var source: TerrainResource = creation.source
	var west := source.column_index(0, 12)
	var east := source.column_index(source.width - 1, 12)
	source.heights[west] = 12
	source.top_materials[west] = 3
	source.water_levels[west] = 16
	source.water_materials[west] = 5
	source.column_material_overrides[west] = {2: 3}
	source.heights[east] = 20
	source.top_materials[east] = 4
	assert(source.validation_errors().is_empty())
	var cells := Creation.SECTION_BLOCKS * TerrainResource.CELLS_PER_BLOCK
	for direction in Extension.DIRECTIONS:
		var next: TerrainResource = Extension.expanded(source, direction)
		assert(next != null and next.validation_errors().is_empty())
		assert(next.width == source.width + (cells if direction in ["west", "east"] else 0))
		assert(next.depth == source.depth + (cells if direction in ["north", "south"] else 0))
		var dx := cells if direction == "west" else 0
		var dz := cells if direction == "north" else 0
		for point in [Vector2i(0, 12), Vector2i(source.width - 1, 12), Vector2i(42, 86)]:
			var old_index := source.column_index(point.x, point.y)
			var new_index := next.column_index(point.x + dx, point.y + dz)
			assert(next.heights[new_index] == source.heights[old_index])
			assert(next.top_materials[new_index] == source.top_materials[old_index])
			assert(next.water_levels[new_index] == source.water_levels[old_index])
			assert(next.water_materials[new_index] == source.water_materials[old_index])
		assert(next.column_material_overrides[next.column_index(dx, 12 + dz)] == {2: 3})
		if direction == "west":
			assert(next.heights[next.column_index(0, 12)] == 12)
			assert(next.water_levels[next.column_index(0, 12)] == 16)
		if direction == "east":
			assert(next.heights[next.column_index(next.width - 1, 12)] == 20)
		assert(ResourceSaver.save(next, DRAFT) == OK)
		var reopened := ResourceLoader.load(DRAFT, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
		assert(reopened != null and reopened.validation_errors().is_empty())
		assert(reopened.heights == next.heights and reopened.water_levels == next.water_levels)
		var flat: TerrainResource = Extension.expanded(source, direction, Extension.MODE_FLAT)
		assert(flat != null and flat.validation_errors().is_empty())
		var seam_x := cells - 1 if direction == "west" else source.width if direction == "east" else 12
		var far_x := 0 if direction == "west" else flat.width - 1 if direction == "east" else 12
		var seam_z := cells - 1 if direction == "north" else source.depth if direction == "south" else 12
		var far_z := 0 if direction == "north" else flat.depth - 1 if direction == "south" else 12
		var old_edge_x := 0 if direction == "west" else source.width - 1 if direction == "east" else 12
		var old_edge_z := 0 if direction == "north" else source.depth - 1 if direction == "south" else 12
		var old_edge_index := source.column_index(old_edge_x, old_edge_z)
		var seam_index := flat.column_index(seam_x, seam_z)
		var far_index := flat.column_index(far_x, far_z)
		assert(flat.heights[seam_index] == source.heights[old_edge_index])
		assert(flat.top_materials[seam_index] == source.top_materials[old_edge_index])
		assert(flat.water_levels[seam_index] == source.water_levels[old_edge_index])
		assert(flat.heights[far_index] == 8)
		assert(flat.water_levels[far_index] == 0)
		assert(flat.column_material_overrides.size() <= next.column_material_overrides.size())
	var wet_edge := source.working_copy()
	for z in wet_edge.depth:
		var wet_index := wet_edge.column_index(0, z)
		wet_edge.water_levels[wet_index] = 16
		wet_edge.water_materials[wet_index] = 5
	var wet_flat: TerrainResource = Extension.expanded(wet_edge, "west", Extension.MODE_FLAT)
	assert(wet_flat != null and wet_flat.validation_errors().is_empty())
	assert(wet_flat.water_levels[wet_flat.column_index(0, 12)] == 16)
	assert(wet_flat.water_materials[wet_flat.column_index(0, 12)] == 5)
	var scene := Node3D.new()
	root.add_child(scene)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.authored_size_blocks = Vector2i(24, 24)
	scene.add_child(map)
	for name in ["Terrain", "Props", "Regions"]:
		var group := Node3D.new()
		group.name = name
		map.add_child(group)
	var editor := WorldEditor.new()
	root.add_child(editor)
	var dialog := ExtensionDialog.new()
	root.add_child(dialog)
	var requested := [""]
	var preview_requested := [""]
	dialog.requested.connect(func(direction: String, mode: String): requested[0] = direction + ":" + mode)
	dialog.preview_requested.connect(func(direction: String, mode: String): preview_requested[0] = direction + ":" + mode)
	dialog._direction.select(1)
	dialog._request_preview()
	assert(preview_requested[0] == "west:flat" and dialog.get_ok_button().disabled)
	dialog.show_preview_ready()
	assert(not dialog.get_ok_button().disabled)
	dialog._submit()
	assert(requested[0] == "west:flat")
	dialog._mode.select(1)
	dialog._submit()
	assert(requested[0] == "west:continue")
	dialog.queue_free()
	var draft := {"target": weakref(map), "resource": source, "compact": true}
	var grown: TerrainResource = Extension.expanded(source, "west")
	var original_positions := {"Terrain": Vector3.ZERO, "Props": Vector3.ZERO, "Regions": Vector3.ZERO}
	var shifted_positions := {}
	for name in original_positions:
		shifted_positions[name] = Extension.scene_shift("west", map.imported_tile_size)
	var undo := UndoRedo.new()
	undo.create_action("Expand compact map")
	undo.add_do_method(Callable(editor, "_apply_compact_extension").bind(map, draft, grown, Vector2i(48, 24), shifted_positions))
	undo.add_undo_method(Callable(editor, "_apply_compact_extension").bind(map, draft, source, Vector2i(24, 24), original_positions))
	undo.commit_action()
	assert(draft.resource == grown and map.authored_size_blocks == Vector2i(48, 24))
	assert((map.get_node("Props") as Node3D).position.x == 384.0)
	undo.undo()
	assert(draft.resource == source and map.authored_size_blocks == Vector2i(24, 24))
	assert((map.get_node("Props") as Node3D).position == Vector3.ZERO)
	undo.redo()
	assert(draft.resource == grown and map.authored_size_blocks == Vector2i(48, 24))
	var large_creation := Creation.new()
	large_creation.scene_directory = creation.scene_directory
	large_creation.terrain_directory = creation.terrain_directory
	assert(large_creation.prepare_sections("large_growth_fixture", 4, 4, 8))
	var growth_started := Time.get_ticks_msec()
	var large_grown: TerrainResource = Extension.expanded(large_creation.source, "east")
	var growth_ms := Time.get_ticks_msec() - growth_started
	assert(large_grown != null and large_grown.width == 1920 and large_grown.depth == 1536)
	assert(Extension.expanded(large_grown, "east") == null)
	large_grown = null
	large_creation.source = null
	var save_creation := Creation.new()
	save_creation.scene_directory = creation.scene_directory
	save_creation.terrain_directory = creation.terrain_directory
	for path in [save_creation.scene_directory.path_join("extended_saved.tscn"), save_creation.terrain_directory.path_join("extended_saved.res")]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	assert(save_creation.prepare_sections("extended_saved", 1, 1, 8), save_creation.error)
	assert(not save_creation.commit().is_empty(), save_creation.error)
	var packed := ResourceLoader.load(save_creation.scene_path(), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var saved_scene := packed.instantiate()
	var saved_map := saved_scene.get_node("Map") as EmberMapLoader
	var history := UndoRedo.new()
	var sessions := Sessions.new()
	sessions.configure(history, func() -> int:
		var updated := PackedScene.new()
		var pack_error := updated.pack(saved_scene)
		return ResourceSaver.save(updated, save_creation.scene_path()) if pack_error == OK else pack_error
	)
	editor.sessions = sessions
	var saved_entry := sessions.open_map(saved_map, saved_scene)
	assert(not saved_entry.is_empty(), sessions.error)
	var saved_grown: TerrainResource = Extension.expanded(saved_entry.resource, "north")
	var group_positions := {}
	for name in ["Terrain", "Props", "Regions"]:
		group_positions[name] = Extension.scene_shift("north", saved_map.imported_tile_size)
	editor._apply_compact_extension(saved_map, saved_entry, saved_grown, Vector2i(24, 48), group_positions)
	assert(sessions.save_all(saved_scene), sessions.error)
	var reopened_scene := ResourceLoader.load(save_creation.scene_path(), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened_root := reopened_scene.instantiate()
	var reopened_map := reopened_root.get_node("Map") as EmberMapLoader
	assert(reopened_map.authored_size_blocks == Vector2i(24, 48))
	assert(reopened_map.compact_terrain.depth == 768)
	assert((reopened_map.get_node("Regions") as Node3D).position.z == 384.0)
	reopened_root.free()
	sessions.discard(saved_scene)
	saved_scene.free()
	history.clear_history()
	history.free()
	for path in [save_creation.scene_path(), save_creation.terrain_path()]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	undo.clear_history()
	undo.free()
	editor.queue_free()
	scene.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DRAFT))
	print("COMPACT_MAP_EXTENSION directions=4 edge_height_material_water=ok save_reopen=ok undo_redo=ok large_growth_ms=", growth_ms)
	quit()
