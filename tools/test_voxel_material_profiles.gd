extends SceneTree
const Profiles = preload("res://scripts/ember_voxel_material_profiles.gd")
const Cache = preload("res://scripts/ember_voxel_projection_cache.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const TreeProvider = preload("res://addons/ember_import/ember_voxel_tree_generator.gd")
const LargeTree = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const Bush = preload("res://addons/ember_import/ember_voxel_bush_generator.gd")
const Rock = preload("res://addons/ember_import/ember_voxel_rock_generator.gd")
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
const Merge = preload("res://addons/ember_import/ember_voxel_merge.gd")

func _init() -> void: _run.call_deferred()

func compare_geometry(a: ArrayMesh, b: ArrayMesh) -> void:
	assert(a.get_surface_count() == b.get_surface_count())
	for surface in a.get_surface_count():
		var aa := a.surface_get_arrays(surface)
		var bb := b.surface_get_arrays(surface)
		for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
			assert(aa[channel] == bb[channel], "material changed geometry or palette")
		assert(a.surface_get_name(surface) == b.surface_get_name(surface))

func _run() -> void:
	var source: EmberVoxelModelResource = Shapes.build("block", Vector3i(8,18,8), 16, Color.BROWN, "material_test", "").source
	source.palette.append(Color.GREEN)
	source.voxels[VoxMesher.cell_index(2,17,2,16,16)] = 2
	source.transparency.resize(source.voxels.size())
	source.transparency[VoxMesher.cell_index(3,17,2,16,16)] = 100
	var before := EmberVoxelPrefab.prepare_resource(source).instantiate()
	var legacy: ArrayMesh = before.get_node("Mesh").mesh
	assert(legacy.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0] == null)
	Profiles.assign(source.material, "bark", {"2": "foliage"})
	assert(source.validation_errors().is_empty())
	var copy := source.duplicate_model()
	copy.material.object_surface.palette["2"] = "ice"
	assert(source.material.object_surface.palette["2"] == "foliage")
	assert(ResourceSaver.save(source,"user://object_material_test.tres") == OK)
	var loaded := ResourceLoader.load("user://object_material_test.tres","",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	assert(loaded.material == source.material)
	var model: Dictionary = loaded.to_definition().model
	var direct := VoxMesher.build_from_ember_model(model, 1.0/16)
	compare_geometry(legacy,direct)
	for surface in direct.get_surface_count():
		var arrays := direct.surface_get_arrays(surface)
		var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
		assert(custom.size() == arrays[Mesh.ARRAY_VERTEX].size()*4)
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			assert(custom[vertex*4] == (3.0 if arrays[Mesh.ARRAY_COLOR][vertex].g > 0.4 else 2.0))
	var cache := Cache.new()
	var cached: ArrayMesh = cache.build(model,1.0/16)
	compare_geometry(direct,cached)
	for surface in direct.get_surface_count(): assert(direct.surface_get_arrays(surface)[Mesh.ARRAY_CUSTOM0] == cached.surface_get_arrays(surface)[Mesh.ARRAY_CUSTOM0])
	cache.build(model,1.0/16); assert(cache.rebuilt == 0)
	Profiles.assign(model.material,"stone")
	cached = cache.build(model,1.0/16); assert(cache.rebuilt > 0)
	assert(cached.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0][0] == 1)
	var region := VoxMesher.build_from_ember_model_region(loaded.to_definition().model,Vector3i.ZERO,loaded.grid_size(),1.0/16)
	compare_geometry(direct,region)
	assert(direct.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0] == region.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0])
	var surface_mesh := EmberVoxelSurfaceMesher.build_region(loaded,Vector3i.ZERO,loaded.grid_size(),1.0/16,false,false)
	assert(surface_mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0] != null)
	var after := EmberVoxelPrefab.prepare_resource(loaded).instantiate()
	assert(before.get_node("Collision/Shape").shape.get_faces() == after.get_node("Collision/Shape").shape.get_faces())
	before.free(); after.free()
	for invalid in [{"version": 2,"default":"stone"}, {"version":1,"default":"typo"}, {"version":1,"default":"ice","palette":{"99":"stone"}}]:
		assert(not Profiles.validation_errors({Profiles.KEY:invalid},3).is_empty())
	for provider in [TreeProvider,LargeTree,Bush]:
		var generated: Dictionary = provider.build({},7,Color.GREEN,{},"test","material_generator")
		assert(not generated.has("error"),str(generated))
		var object: EmberVoxelModelResource = generated.geometry
		assert(object.validation_errors().is_empty())
		var roles := Profiles.palette_parameters(object.material,object.palette.size())
		assert(roles.any(func(v):return v.x == 2) and roles.any(func(v):return v.x == 3))
	for kind in [0,3,4]:
		var object: EmberVoxelModelResource = Rock.build({"generation_version":2,"rock_type":kind,"dimensions":Vector3i(12,16,12)},7,Color.GRAY,{},"test","material_rock").geometry
		assert(object.validation_errors().is_empty())
		assert(Profiles.palette_parameters(object.material,object.palette.size())[1].x == (1 if kind == 0 else kind+1))
	# Equal RGB must not merge different semantic surfaces; source stays detached.
	var bark: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,4,16),16,Color.BROWN,"material_bark","").source
	bark.voxels[0] = 1; Profiles.assign(bark.material,"bark")
	var leaf := bark.duplicate_model(); Profiles.assign(leaf.material,"foliage")
	var inputs: Array[Dictionary] = [{"source":bark,"frame":Transform3D.IDENTITY},{"source":leaf,"frame":Transform3D(Basis.IDENTITY,Vector3(1,0,0))}]
	var merged := Merge.plan(inputs); assert(not merged.has("error"),str(merged))
	var combined: EmberVoxelModelResource = merged.source
	assert(combined.palette.size() == 3 and combined.validation_errors().is_empty())
	assert(Profiles.palette_role(combined.material,1) != Profiles.palette_role(combined.material,2))
	var preset := Stamp.Preset.new(); preset.geometry = leaf; preset.display_name = "leaf"
	var stamp := Stamp.plan(bark,preset,Vector3i(2,0,2),0,0,-1,0,false,0)
	assert(not stamp.has("error"),str(stamp))
	var original := bark.to_definition()
	for key in stamp.properties: bark.set(key,stamp.properties[key])
	assert(bark.validation_errors().is_empty() and Profiles.palette_role(bark.material,2) == "foliage")
	for key in stamp.before: bark.set(key,stamp.before[key])
	assert(bark.to_definition() == original)
	print("test_voxel_material_profiles: PASS (geometry, collision, alpha, cache, roles, save/reopen)")
	quit()
