extends SceneTree
const Cache = preload("res://scripts/ember_voxel_projection_cache.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
var errors: Array[String] = []
func _init() -> void:
	_run.call_deferred()
func compare(source: EmberVoxelModelResource, cache: RefCounted) -> void:
	var model: Dictionary = source.to_definition().model
	var expected := VoxMesher.build_from_ember_model(model,1.0/source.normalized_density())
	var actual: ArrayMesh = cache.build(model,1.0/source.normalized_density())
	if expected.get_surface_count() == 0:
		assert(actual.get_surface_count() == 0)
	else:
		Parity._compare_meshes(expected,actual,errors,[])
	# Exposed meshes must never alias the private reusable pieces.
	actual.clear_surfaces()
func _run() -> void:
	var cache := Cache.new()
	var source: EmberVoxelModelResource = Shapes.build("block",Vector3i(64,32,64),16,Color.BROWN,"cache","").source
	compare(source,cache)
	assert(cache.rebuilt == 4)
	compare(source,cache)
	assert(cache.rebuilt == 0 and cache.reused == 4)
	source.voxels[VoxMesher.cell_index(2,8,2,64,64)] = 0
	compare(source,cache)
	assert(cache.rebuilt == 2 and cache.reused == 2)
	source.transparency.resize(source.voxels.size())
	source.transparency[VoxMesher.cell_index(2,16,2,64,64)] = 120
	compare(source,cache)
	source.transparency[VoxMesher.cell_index(2,16,2,64,64)] = 0
	compare(source,cache)
	assert(cache.rebuilt == 2)
	source.palette[1] = Color(0.1234,0.6789,0.3123)
	compare(source,cache)
	assert(cache.rebuilt == 4)
	var plain := EmberVoxelPrefab.prepare_resource(source).instantiate()
	var cached := EmberVoxelPrefab.prepare_resource(source,cache).instantiate()
	assert(plain.get_node("Collision/Shape").shape.get_faces() == cached.get_node("Collision/Shape").shape.get_faces())
	plain.free()
	cached.free()
	source = Shapes.build("sphere",Vector3i(32,32,32),32,Color.RED,"cache","").source
	compare(source,cache)
	source.voxels.fill(0)
	compare(source,cache)
	print("test_voxel_projection_cache: ","PASS" if errors.is_empty() else "FAIL", " ",errors)
	quit(0 if errors.is_empty() else 1)
