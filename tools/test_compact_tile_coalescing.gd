extends SceneTree

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := TerrainResource.new()
	source.width = 128
	source.depth = 128
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.GREEN])
	var count := source.width * source.depth
	source.heights.resize(count)
	source.heights.fill(8)
	source.top_materials.resize(count)
	source.top_materials.fill(2)
	source.base_materials.resize(count)
	source.base_materials.fill(1)
	source.cap_depths.resize(count)
	source.cap_depths.fill(3)
	source.water_levels.resize(count)
	source.water_materials.resize(count)
	var projection := EmberTerrainPilotProjection.new()
	projection.source = source
	projection._repeat_edit_build_interval_us = 250000
	root.add_child(projection)
	while projection.pending_tile_count() > 0:
		await process_frame
	projection.begin_live_brush()
	var index := source.column_index(32, 32)
	var indices := PackedInt32Array([index])
	var tops := PackedByteArray([2])
	var waters := PackedInt32Array([0])
	var water_colors := PackedByteArray([0])
	var before := int(projection.profile_snapshot().tile_builds)
	projection.apply_columns(indices, PackedInt32Array([12]), tops, waters, water_colors)
	await process_frame
	var first := int(projection.profile_snapshot().tile_builds)
	if first != before + 1:
		_fail("first edit was not visible on the next frame")
		return
	for height in [16, 20, 24]:
		projection.apply_columns(indices, PackedInt32Array([height]), tops, waters, water_colors)
		await process_frame
	var repeated := int(projection.profile_snapshot().tile_builds) - first
	if repeated > 1:
		_fail("same tile rebuilt on every successive frame: %d" % repeated)
		return
	var pending_profile := projection.profile_snapshot()
	if int(pending_profile.coalesced_tile_requests) < 1 or int(pending_profile.deferred_repeat_builds) < 1:
		_fail("repeated edits were not merged while the tile waited")
		return
	projection.end_live_brush()
	var timeout := Time.get_ticks_msec() + 1000
	while projection.pending_tile_count() > 0 and Time.get_ticks_msec() < timeout:
		await process_frame
	if projection.pending_tile_count() > 0:
		_fail("final edit did not settle")
		return
	var tile := projection.get_node("TerrainTile_0_0")
	var actual_mesh := (tile.get_node("Ground") as MeshInstance3D).mesh as ArrayMesh
	var expected_mesh := MeshBuilder.build_tile(projection.document, 0, 0, 64).terrain as ArrayMesh
	if actual_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != expected_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		_fail("settled ground mesh differs from document")
		return
	var shape := (tile.get_node("GroundPhysics/Shape") as CollisionShape3D).shape as ConcavePolygonShape3D
	if shape.get_faces() != MeshBuilder.build_tile(projection.document, 0, 0, 64).collision_faces:
		_fail("settled collision differs from document")
		return
	print("COMPACT_TILE_COALESCING first=", first - before, " successive_rebuilds=", repeated, " final_mesh_and_collision=ok")
	projection.free()
	quit()


func _fail(message: String) -> void:
	push_error("COMPACT_TILE_COALESCING " + message)
	quit(1)
