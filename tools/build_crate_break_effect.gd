extends SceneTree
## Derived asset only; never edits the canonical voxel source.
const SOURCE := "res://content/voxel_models/quest_carry_crate.tres"
const OUTPUT := "res://prefabs/items/quest_crate_break.scn"
func _init() -> void:
	var source := load(SOURCE) as EmberVoxelModelResource
	if source == null or not source.validation_errors().is_empty(): quit(1); return
	var root_node := preload("res://scripts/ember_world_break_effect.gd").new()
	root_node.name = "CrateFragments"
	root_node.set_meta("voxel_source", SOURCE)
	root_node.set_meta("voxel_source_sha256", FileAccess.get_sha256(SOURCE))
	var size := source.grid_size()
	var center := size / 2
	for part in 8:
		var model: Dictionary = source.to_definition().model
		var voxels := source.voxels.duplicate()
		for y in size.y:
			for z in size.z:
				for x in size.x:
					var octant := (1 if x >= center.x else 0) + (2 if y >= center.y else 0) + (4 if z >= center.z else 0)
					if octant != part: voxels[VoxMesher.cell_index(x, y, z, size.x, size.z)] = 0
		model["voxels"] = voxels
		var mesh := VoxMesher.build_from_ember_model(model, 1.0 / source.voxels_per_block)
		EmberVoxelPrefab._apply_visual_materials(mesh, model.get("material", {}))
		var visual := MeshInstance3D.new(); visual.name = "Fragment%d" % part
		visual.mesh = mesh; visual.position = Vector3(-0.5, 0, -0.5)
		root_node.add_child(visual); visual.owner = root_node
	var packed := PackedScene.new()
	var error := packed.pack(root_node)
	if error == OK: error = ResourceSaver.save(packed, OUTPUT)
	root_node.free()
	print("PASS baked 8 voxel fragments: " + OUTPUT if error == OK else "FAIL crate fragment bake")
	quit(0 if error == OK else 1)
