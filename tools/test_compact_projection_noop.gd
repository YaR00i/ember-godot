extends SceneTree

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Extension = preload("res://addons/ember_import/ember_compact_map_extension.gd")
const WorldEditor = preload("res://addons/ember_import/ember_world_editor.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var creation := Creation.new()
	creation.scene_directory = "user://projection_noop/scenes"
	creation.terrain_directory = "user://projection_noop/terrain"
	if not creation.prepare_sections("projection_noop", 1, 1, 8):
		_fail(creation.error)
		return
	var map := EmberMapLoader.new()
	map.hydrate_legacy_regions = false
	map.compact_terrain = creation.source
	root.add_child(map)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if not await _settle(projection):
		_fail("initial terrain did not settle")
		return
	var tile := projection.get_node("TerrainTile_0_0")
	var mesh := (tile.get_node("Ground") as MeshInstance3D).mesh
	map.refresh_visual_surface_projection()
	if projection.pending_tile_count() != 0 or projection.get_node_or_null("TerrainTile_0_0") != tile:
		_fail("unchanged map refresh rebuilt the terrain")
		return
	var draft := creation.source.working_copy()
	projection.open_document(draft)
	if projection.pending_tile_count() != 0 or projection.get_node_or_null("TerrainTile_0_0") != tile:
		_fail("opening an identical editing draft rebuilt the terrain")
		return
	if (tile.get_node("Ground") as MeshInstance3D).mesh != mesh:
		_fail("identical editing draft replaced the terrain mesh")
		return
	var changed := draft.working_copy()
	changed.heights[changed.column_index(100, 100)] += 4
	if not projection.open_document(changed) or projection.pending_tile_count() != 36 or not await _settle(projection):
		_fail("changed draft was not reprojected")
		return
	if not projection.open_document(draft) or not await _settle(projection):
		_fail("original draft did not return after replacement")
		return
	var cells := Creation.SECTION_BLOCKS * 16
	for direction in Extension.DIRECTIONS:
		var expanded := Extension.expanded(draft, direction, Extension.MODE_FLAT)
		if expanded == null or not projection.open_resized_document(expanded, draft, direction, cells):
			_fail("adding section failed: " + direction)
			return
		var moved_key := Vector2i(3 + (cells / 64 if direction == "west" else 0), 3 + (cells / 64 if direction == "north" else 0))
		if projection.get_node_or_null("TerrainTile_%d_%d" % [moved_key.x, moved_key.y]) != projection._tiles.get(moved_key) or projection._tiles.get(moved_key) == null:
			_fail("section growth lost a tile or its name: " + direction)
			return
		var preserved := projection._tiles[moved_key] as Node3D
		var preserved_mesh := (preserved.get_node("Ground") as MeshInstance3D).mesh
		var preserved_shape := (preserved.get_node("GroundPhysics/Shape") as CollisionShape3D).shape
		var expected_mesh := (MeshBuilder.build_tile(expanded, moved_key.x * 64, moved_key.y * 64, 64).terrain as ArrayMesh)
		if not _matches_ground(preserved, expected_mesh):
			_fail("preserved tile moved to the wrong coordinates: " + direction)
			return
		if projection.pending_tile_count() >= ceili(float(expanded.width) / 64.0) * ceili(float(expanded.depth) / 64.0):
			_fail("section growth queued the whole map: " + direction)
			return
		if not await _settle(projection) or projection.document.width != expanded.width or projection.document.depth != expanded.depth or (preserved.get_node("Ground") as MeshInstance3D).mesh != preserved_mesh or (preserved.get_node("GroundPhysics/Shape") as CollisionShape3D).shape != preserved_shape:
			_fail("section growth did not preserve interior geometry: " + direction)
			return
		if not projection.open_resized_document(draft, expanded, direction, cells) or projection.pending_tile_count() >= projection.built_tile_count():
			_fail("section undo queued the whole map: " + direction)
			return
		if not await _settle(projection) or projection.document.width != draft.width or projection.document.depth != draft.depth or projection.get_node_or_null("TerrainTile_3_3") != preserved or preserved.position != Vector3.ZERO:
			_fail("section undo did not restore preserved tiles: " + direction)
			return
	var quick_west := Extension.expanded(draft, "west", Extension.MODE_FLAT)
	if not projection.open_resized_document(quick_west, draft, "west", cells) or not projection.open_resized_document(draft, quick_west, "west", cells) or projection.pending_tile_count() != 6 or not await _settle(projection):
		_fail("undo during an unfinished section build restarted the map")
		return
	var editor := WorldEditor.new()
	root.add_child(editor)
	var entry := {"target": weakref(map), "resource": draft, "compact": true}
	var center_tile := projection.get_node("TerrainTile_3_3")
	var east := Extension.expanded(draft, "east", Extension.MODE_FLAT)
	editor._apply_compact_extension(map, entry, east, Vector2i(48, 24), {}, "east")
	if projection.pending_tile_count() != 42 or projection.get_node_or_null("TerrainTile_3_3") != center_tile:
		_fail("editor Apply rebuilt existing tiles")
		return
	if not await _settle(projection):
		_fail("editor Apply did not settle")
		return
	editor._apply_compact_extension(map, entry, draft, Vector2i(24, 24), {}, "east")
	if projection.pending_tile_count() != 6 or projection.get_node_or_null("TerrainTile_3_3") != center_tile:
		_fail("editor Undo rebuilt existing tiles")
		return
	if not await _settle(projection):
		_fail("editor Undo did not settle")
		return
	editor.free()
	map.free()
	var large := Creation.new()
	large.scene_directory = creation.scene_directory
	large.terrain_directory = creation.terrain_directory
	if not large.prepare_sections("projection_noop_large", 4, 4, 8):
		_fail(large.error)
		return
	var large_map := EmberMapLoader.new()
	large_map.hydrate_legacy_regions = false
	large_map.compact_terrain = large.source
	root.add_child(large_map)
	var large_projection := large_map._visual_surface_projection as EmberTerrainPilotProjection
	var initial_pending := large_projection.pending_tile_count()
	large_map.refresh_visual_surface_projection()
	if large_projection.pending_tile_count() != initial_pending:
		_fail("reopening the large map restarted pending work")
		return
	if not await _settle(large_projection) or large_projection.built_tile_count() != 576:
		_fail("large terrain did not settle")
		return
	var large_interior := large_projection.get_node("TerrainTile_8_8")
	var noop_started := Time.get_ticks_usec()
	large_map.refresh_visual_surface_projection()
	var noop_usec := Time.get_ticks_usec() - noop_started
	if large_projection.pending_tile_count() != 0 or large_projection.get_node("TerrainTile_8_8") != large_interior:
		_fail("opening the large map queued existing tiles")
		return
	var large_draft := large.source.working_copy()
	large_projection.open_document(large_draft)
	var large_east := Extension.expanded(large_draft, "east", Extension.MODE_FLAT)
	var resize_started := Time.get_ticks_usec()
	if not large_projection.open_resized_document(large_east, large_draft, "east", cells) or large_projection.pending_tile_count() != 168 or large_projection.get_node("TerrainTile_8_8") != large_interior:
		_fail("large section queued more than its strip and seam")
		return
	print("COMPACT_PROJECTION_NOOP unchanged_refresh=ok identical_draft=ok four_sides_and_undo=ok editor_apply_undo=ok large_queued=", large_projection.pending_tile_count(), "/", 720, " large_noop_us=", noop_usec, " large_resize_us=", Time.get_ticks_usec() - resize_started)
	quit()


func _settle(projection: EmberTerrainPilotProjection) -> bool:
	var frames := 0
	while projection != null and projection.pending_tile_count() > 0 and frames < 600:
		await process_frame
		frames += 1
	return projection != null and projection.pending_tile_count() == 0


func _matches_ground(tile: Node3D, expected: ArrayMesh) -> bool:
	var actual := (tile.get_node("Ground") as MeshInstance3D).mesh as ArrayMesh
	if actual.get_surface_count() != expected.get_surface_count():
		return false
	if actual.get_surface_count() == 0:
		return true
	var actual_vertices := actual.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var expected_vertices := expected.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if actual_vertices.size() != expected_vertices.size():
		return false
	for i in actual_vertices.size():
		if actual_vertices[i] + tile.position != expected_vertices[i]:
			return false
	return true


func _fail(message: String) -> void:
	push_error("COMPACT_PROJECTION_NOOP " + message)
	quit(1)
