extends SceneTree

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Extension = preload("res://addons/ember_import/ember_compact_map_extension.gd")
const Preview = preload("res://addons/ember_import/ember_compact_map_extension_preview.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var creation := Creation.new()
	creation.scene_directory = "user://preview_fixture/scenes"
	creation.terrain_directory = "user://preview_fixture/terrain"
	assert(creation.prepare_sections("preview_fixture", 1, 1, 8), creation.error)
	var map := EmberMapLoader.new()
	map.compact_terrain = creation.source
	map.authored_size_blocks = Vector2i(24, 24)
	for group_name in ["Props", "Regions"]:
		var group := Node3D.new()
		group.name = group_name
		map.add_child(group)
	root.add_child(map)
	await process_frame
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	assert(projection != null)
	for direction in ["east", "west", "south", "north"]:
		var candidate := Extension.expanded(creation.source, direction, Extension.MODE_FLAT)
		var preview := Preview.new()
		map.add_child(preview)
		assert(preview.show_candidate(map, creation.source, candidate, direction))
		var expected_shift := Extension.scene_shift(direction, map.imported_tile_size)
		assert(projection.position == expected_shift)
		assert((map.get_node("Props") as Node3D).position == expected_shift)
		var frames := 0
		while preview._pending.size() > 0 and frames < 300:
			await process_frame
			frames += 1
		assert(preview._pending.is_empty(), "Preview tiles did not finish: %s" % direction)
		assert(preview.get_child_count(true) > 1)
		preview.clear_preview()
		assert(projection.position == Vector3.ZERO)
		assert((map.get_node("Props") as Node3D).position == Vector3.ZERO)
		assert(projection._editor_hidden_edge_keys.is_empty())
		preview.free()
	map.free()
	var large := Creation.new()
	large.scene_directory = creation.scene_directory
	large.terrain_directory = creation.terrain_directory
	assert(large.prepare_sections("large_preview_fixture", 4, 4, 8), large.error)
	var large_map := EmberMapLoader.new()
	large_map.compact_terrain = large.source
	large_map.authored_size_blocks = Vector2i(96, 96)
	root.add_child(large_map)
	await process_frame
	var large_candidate := Extension.expanded(large.source, "east", Extension.MODE_FLAT)
	var large_preview := Preview.new()
	large_map.add_child(large_preview)
	var started := Time.get_ticks_msec()
	assert(large_preview.show_candidate(large_map, large.source, large_candidate, "east"))
	var large_frames := 0
	while large_preview._pending.size() > 0 and large_frames < 1000:
		await process_frame
		large_frames += 1
	assert(large_preview._pending.is_empty())
	assert(large_preview.get_child_count(true) == 169) # 168 changed tiles + boundary.
	var large_preview_ms := Time.get_ticks_msec() - started
	large_preview.clear_preview()
	large_map.free()
	print("COMPACT_EXTENSION_PREVIEW four_sides=ok cancel_restores_scene=ok large_preview_ms=", large_preview_ms)
	quit()
