extends SceneTree
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var scene := (load("res://scenes/object_material_study.tscn") as PackedScene).instantiate()
	assert(scene.sample_sources.size() == 6)
	for index in scene.sample_sources.size():
		var source: EmberVoxelModelResource = scene.sample_sources[index]
		assert(source.validation_errors().is_empty())
		var actual := scene.get_node("Sample"+str(index)+"/Mesh").mesh as ArrayMesh
		var expected := VoxMesher.build_from_ember_model(source.to_definition().model,1.0/source.normalized_density())
		assert(actual.get_surface_count() == expected.get_surface_count())
		for surface in actual.get_surface_count():
			var aa := actual.surface_get_arrays(surface); var bb := expected.surface_get_arrays(surface)
			for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_INDEX,Mesh.ARRAY_CUSTOM0]: assert(aa[channel] == bb[channel])
			assert(actual.surface_get_material(surface) is ShaderMaterial)
		assert(scene.get_node("Sample"+str(index)+"/Collision/Shape").shape != null)
	scene.free()
	print("test_object_material_study_export: PASS baked mesh/custom stream/collision/source/ShaderMaterial")
	quit()
