extends SceneTree
## Isolated pilot gate. The authored beach and its existing Surface are read only.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const PilotProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const INPUT := "res://content/terrain_pilot/beach_region.res"
const DRAFT := "user://ember_terrain_pilot_test.res"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_msec()
	var compact := ResourceLoader.load(INPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	var load_ms := Time.get_ticks_msec() - started
	if compact == null or not compact.validation_errors().is_empty():
		_fail("compact source missing or invalid")
		return
	if compact.source_sha256 != FileAccess.get_sha256(compact.source_path):
		_fail("pilot source no longer matches the copied beach")
		return
	var projection := PilotProjection.new()
	projection.source = compact
	root.add_child(projection)
	if not await _settle(projection):
		_fail("initial tile projection timed out")
		return
	var expected_tiles := ceili(float(compact.width) / PilotProjection.TILE_SIZE) * ceili(float(compact.depth) / PilotProjection.TILE_SIZE)
	if projection.built_tile_count() != expected_tiles:
		_fail("wrong initial tile count")
		return
	var first_tile_ms := projection.first_tile_ms
	var all_tiles_ms := projection.all_tiles_ms
	var index := compact.column_index(200, 200)
	var original := compact.heights[index]
	await physics_frame
	await physics_frame
	await process_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(200.5, 100, 200.5), Vector3(200.5, -40, 200.5))
	var hit := root.world_3d.direct_space_state.intersect_ray(ray)
	if hit.is_empty() or absf(float(hit.position.y) - float(compact.origin_y + original)) > 0.02:
		var tile := projection.get_node("TerrainTile_3_3")
		var shape := (tile.get_node("GroundPhysics/Shape") as CollisionShape3D).shape as ConcavePolygonShape3D
		_fail("terrain collision differs from visible height: hit=%s expected=%s shape_faces=%s layer=%s ground_surfaces=%s" % [str(hit), str(compact.origin_y + original), str(shape.get_faces().size()), str((tile.get_node("GroundPhysics") as StaticBody3D).collision_layer), str((tile.get_node("Ground") as MeshInstance3D).mesh.get_surface_count())])
		return
	var changed := PackedInt32Array([original + 2])
	var indices := PackedInt32Array([index])
	var edited_tile := Vector2i(200 / PilotProjection.TILE_SIZE, 200 / PilotProjection.TILE_SIZE)
	var grid_revision_before := projection.tile_revision(edited_tile)
	projection.apply_heights(indices, changed)
	if not await _settle(projection) or projection.document.heights[index] != original + 2 or projection.tile_revision(edited_tile) <= grid_revision_before:
		_fail("edited tile did not settle")
		return
	var grid_revision_after := projection.tile_revision(edited_tile)
	projection.apply_columns(indices, changed, PackedByteArray([projection.document.top_materials[index]]), PackedInt32Array([projection.document.water_levels[index] + 1]), PackedByteArray([1]))
	if projection.tile_revision(edited_tile) != grid_revision_after:
		_fail("water-only edit invalidated ground hover grid")
		return
	projection.apply_heights(indices, PackedInt32Array([original]))
	if not await _settle(projection) or projection.document.heights[index] != original:
		_fail("undo patch did not restore height")
		return
	projection.apply_heights(indices, changed)
	if not await _settle(projection):
		_fail("redo patch did not settle")
		return
	if projection.save_document(DRAFT) != OK:
		_fail("pilot save failed")
		return
	if not projection.reopen_document(DRAFT) or not await _settle(projection):
		_fail("pilot reopen failed")
		return
	if projection.document.heights[index] != original + 2:
		_fail("saved height did not reopen")
		return
	if projection.document.column_material_overrides != compact.column_material_overrides:
		_fail("sparse material overrides did not survive save/reopen")
		return
	var edge := compact.column_index(63, 200)
	var left_mesh: Mesh = (projection.get_node("TerrainTile_0_3/Ground") as MeshInstance3D).mesh
	var right_mesh: Mesh = (projection.get_node("TerrainTile_1_3/Ground") as MeshInstance3D).mesh
	projection.apply_heights(PackedInt32Array([edge]), PackedInt32Array([compact.heights[edge] + 1]))
	if not await _settle(projection) or left_mesh == (projection.get_node("TerrainTile_0_3/Ground") as MeshInstance3D).mesh or right_mesh == (projection.get_node("TerrainTile_1_3/Ground") as MeshInstance3D).mesh:
		_fail("tile-boundary edit did not rebuild both sides")
		return
	var wide := _repeat_2x2(compact)
	var wide_projection := PilotProjection.new()
	wide_projection.source = wide
	root.add_child(wide_projection)
	if not await _settle(wide_projection):
		_fail("four-times-area projection timed out")
		return
	print("TERRAIN_PILOT load_ms=", load_ms, " first_tile_ms=", first_tile_ms, " all_tiles_ms=", all_tiles_ms, " tiles=", expected_tiles, " four_times_first_tile_ms=", wide_projection.first_tile_ms, " four_times_all_tiles_ms=", wide_projection.all_tiles_ms, " four_times_tiles=", wide_projection.built_tile_count(), " source_bytes=", FileAccess.open(INPUT, FileAccess.READ).get_length(), " save_reopen=ok edit_restore=ok collision=ok")
	wide_projection.free()
	projection.free()
	quit()


func _settle(projection: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while projection.pending_tile_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	return projection.pending_tile_count() == 0


func _fail(reason: String) -> void:
	printerr("FAIL terrain pilot: ", reason)
	quit(1)


func _repeat_2x2(source: TerrainResource) -> TerrainResource:
	var repeated := TerrainResource.new()
	repeated.width = source.width * 2
	repeated.depth = source.depth * 2
	repeated.height_limit = source.height_limit
	repeated.origin_y = source.origin_y
	repeated.palette = source.palette.duplicate()
	var count := repeated.width * repeated.depth
	repeated.heights.resize(count)
	repeated.top_materials.resize(count)
	repeated.base_materials.resize(count)
	repeated.cap_depths.resize(count)
	repeated.water_levels.resize(count)
	repeated.water_materials.resize(count)
	for z in repeated.depth:
		for x in repeated.width:
			var to_index := repeated.column_index(x, z)
			var from_index := source.column_index(x % source.width, z % source.depth)
			repeated.heights[to_index] = source.heights[from_index]
			repeated.top_materials[to_index] = source.top_materials[from_index]
			repeated.base_materials[to_index] = source.base_materials[from_index]
			repeated.cap_depths[to_index] = source.cap_depths[from_index]
			repeated.water_levels[to_index] = source.water_levels[from_index]
			repeated.water_materials[to_index] = source.water_materials[from_index]
			if source.column_material_overrides.has(from_index):
				repeated.column_material_overrides[to_index] = (source.column_material_overrides[from_index] as Dictionary).duplicate(true)
	return repeated
