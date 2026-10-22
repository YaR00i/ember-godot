extends SceneTree
## Republish the derived prefab of the accepted rock group so its mesh carries form
## normals. Source, palette and geometry are unchanged; only derived files are rewritten.
## Argument after "--": directory holding before-files/ (pre-change derived mesh).
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL ", message)
func run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	var id := "vox_painted_rock_group"
	var before: ArrayMesh = ResourceLoader.load(output.path_join("before-files/vox_painted_rock_group_block.res"), "", ResourceLoader.CACHE_MODE_IGNORE)
	check(before != null, "pre-change mesh readable")
	var before_arrays := before.surface_get_arrays(0)
	var source: EmberVoxelModelResource = load("res://content/voxel_models/vox_painted_rock_group.tres")
	var voxels_before := source.voxels.duplicate(); var parts_before := source.voxel_part_ids.duplicate()
	var packed := EmberVoxelPrefab.ensure_saved(id, 16.0, {}, true)
	check(packed != null, "prefab republished")
	var prop := packed.instantiate()
	var mesh := (prop.get_node("Mesh") as MeshInstance3D).mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	check(mesh.has_meta("solid_form_contract"), "mesh carries form contract")
	check(arrays[Mesh.ARRAY_CUSTOM0] != null and arrays[Mesh.ARRAY_CUSTOM0].size() == arrays[Mesh.ARRAY_VERTEX].size() * 4, "CUSTOM0 form normals present")
	check(arrays[Mesh.ARRAY_CUSTOM1] != null and arrays[Mesh.ARRAY_CUSTOM1].size() == arrays[Mesh.ARRAY_VERTEX].size() * 4, "CUSTOM1 convex-edge frame present")
	check(arrays[Mesh.ARRAY_CUSTOM2] != null and arrays[Mesh.ARRAY_CUSTOM3] != null, "CUSTOM2/3 neighbour normals present")
	var vertex_after: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]; var vertex_before: PackedVector3Array = before_arrays[Mesh.ARRAY_VERTEX]
	check(vertex_after.size() == vertex_before.size(), "same vertex count")
	var worst := 0.0
	for i in mini(vertex_after.size(), vertex_before.size()): worst = maxf(worst, vertex_after[i].distance_to(vertex_before[i]))
	check(worst == 0.0, "vertex positions bit-identical to previous derived mesh")
	var normal_after: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]; var normal_before: PackedVector3Array = before_arrays[Mesh.ARRAY_NORMAL]
	var worst_normal := 0.0
	for i in mini(normal_after.size(), normal_before.size()): worst_normal = maxf(worst_normal, normal_after[i].distance_to(normal_before[i]))
	check(worst_normal < 0.01, "facet normals unchanged")
	check(arrays[Mesh.ARRAY_COLOR] == before_arrays[Mesh.ARRAY_COLOR] and arrays[Mesh.ARRAY_TEX_UV] == before_arrays[Mesh.ARRAY_TEX_UV] and arrays[Mesh.ARRAY_TEX_UV2] == before_arrays[Mesh.ARRAY_TEX_UV2], "paint slots unchanged")
	check(source.voxels == voxels_before and source.voxel_part_ids == parts_before, "Source occupancy and parts unchanged")
	check(source.validation_errors().is_empty(), "Source validates")
	print("ROCK_FORM_PUBLISH signature ", EmberVoxelPrefab.source_signature(id))
	print("ROCK_FORM_PUBLISH ", "PASS" if errors.is_empty() else errors)
	prop.free()
	quit(0 if errors.is_empty() else 1)
