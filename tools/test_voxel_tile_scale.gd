extends SceneTree
## V1 Tile Scale: legacy 16 and dense 32 share one normalized block footprint.


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var legacy := _solid_model(16, false)
	var dense := _solid_model(32, true)
	if VoxMesher.voxels_per_block(legacy) != 16:
		errors.append("omitted voxelsPerBlock did not resolve to legacy 16")
	if VoxMesher.voxels_per_block(dense) != 32:
		errors.append("explicit dense model did not resolve to 32")
	if VoxMesher.ember_grid_size(legacy) != Vector3i(16, 16, 16):
		errors.append("legacy semantic grid is not 16 cubed")
	if VoxMesher.ember_grid_size(dense) != Vector3i(32, 32, 32):
		errors.append("dense semantic grid is not 32 cubed")

	for model in [legacy, dense]:
		var density := VoxMesher.voxels_per_block(model)
		var voxel_size := VoxMesher.normalized_voxel_size(model)
		var mesh := VoxMesher.build_from_ember_model(model, voxel_size)
		if mesh.get_surface_count() == 0:
			errors.append("%d density did not produce a mesh" % density)
			continue
		var block_size := mesh.get_aabb().size
		if not block_size.is_equal_approx(Vector3.ONE):
			errors.append("%d density normalized to %s instead of one block" % [density, block_size])
		var prop := EmberVoxelPrefab._make_tree(
			"test_%d" % density,
			model,
			Vector3i(density, density, density),
			voxel_size,
			16.0,
			mesh,
			null,
		)
		var visual := prop.get_node("Mesh") as MeshInstance3D
		if not visual.scale.is_equal_approx(Vector3.ONE * 16.0):
			errors.append("world adapter did not scale %d density to tileSize 16" % density)
		prop.configure_voxel_scale(density, 1.2)
		if not visual.scale.is_equal_approx(Vector3.ONE * 1.2):
			errors.append("battle adapter did not rescale normalized mesh to 1.2")
		if not prop.position.is_equal_approx(Vector3.ZERO):
			errors.append("block adapter changed authored root transform")
		prop.free()

	if not errors.is_empty():
		printerr("FAIL voxel tile scale")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS voxel tile scale")
	print("  legacy: omitted metadata -> 16 vox/block")
	print("  dense: explicit metadata -> 32 vox/block")
	print("  normalized mesh: 1 block; adapters: world 16 / battle 1.2")
	return 0


func _solid_model(density: int, explicit: bool) -> Dictionary:
	var count := density * density * density
	var voxels: Array = []
	voxels.resize(count)
	voxels.fill(1)
	var model := {
		"sizeBlocks": {"x": 1, "y": 1, "z": 1},
		"heightVoxels": density,
		"palette": ["", "#ffffff"],
		"voxels": voxels,
		"physical": false,
	}
	if explicit:
		model["voxelsPerBlock"] = density
	return model
