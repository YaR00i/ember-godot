extends SceneTree
const Profiles = preload("res://scripts/ember_voxel_material_profiles.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var source: EmberVoxelModelResource = Shapes.build("block",Vector3i(8,8,8),16,Color("8fcace"),"optics_test","").source
	Profiles.assign(source.material,"ice")
	var before := EmberVoxelPrefab.prepare_resource(source).instantiate()
	var mesh: Mesh = before.get_node("Mesh").mesh
	var definition := source.to_definition()
	source.material.object_surface.optics = {"enabled":true,"ior":1.31,"refraction_strength":0.035,"thickness_m":0.5}
	assert(source.validation_errors().is_empty())
	var copy := source.duplicate_model(); copy.material.object_surface.optics.ior = 1.6
	assert(source.material.object_surface.optics.ior == 1.31)
	assert(ResourceSaver.save(source,"user://optics_source_test.tres") == OK)
	var loaded := ResourceLoader.load("user://optics_source_test.tres","",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	assert(loaded.material == source.material and loaded.voxels == source.voxels)
	var after := EmberVoxelPrefab.prepare_resource(loaded).instantiate()
	var optics_mesh: Mesh = after.get_node("Mesh").mesh
	assert(optics_mesh.get_surface_count() == mesh.get_surface_count())
	for surface in mesh.get_surface_count():
		for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_INDEX,Mesh.ARRAY_CUSTOM0]:
			assert(mesh.surface_get_arrays(surface)[channel] == optics_mesh.surface_get_arrays(surface)[channel])
	assert(before.get_node("Collision/Shape").shape.get_faces() == after.get_node("Collision/Shape").shape.get_faces())
	var mat: ShaderMaterial = optics_mesh.surface_get_material(0)
	assert(mat.shader.code.contains("ember_surface_optics") and mat.get_shader_parameter("optics_ior") == 1.31)
	assert(not mesh.surface_get_material(0).shader.code.contains("ember_surface_optics"))
	for bad in [{"enabled":1},{"ior":0.5},{"clarity":2},{"thickness_m":0},{"refraction_strength":NAN},{"body_opacity":"high"},{"cloud_strength":2},{"cloud_scale":0},{"cloud_seed":NAN},{"cloud_light":"badcolor"},{"finish":1},{"finish":"unknown"},{"surface_detail":1},{"crack_width":0},{"bubble_scale":100},{"absorption_strength":INF}]:
		var material := {Profiles.KEY:{"version":1,"default":"glass","palette":{},"optics":bad}}
		assert(not Profiles.validation_errors(material,2).is_empty(),str(bad))
	for finish in Profiles.FINISH_PROFILES:
		var material := {Profiles.KEY:{"version":1,"default":"ice" if finish.begins_with("ice") else "crystal","palette":{},"optics":{"enabled":true,"finish":finish}}}
		assert(Profiles.validation_errors(material,2).is_empty())
		var resolved := Profiles.optics_parameters(material)
		assert(resolved.clarity > 0.98 and resolved.cloud_blur < 0.2 and resolved.cloud_opacity < 0.2)
		var profile_mat := EmberVoxelPrefab.refractive_material(material)
		assert(profile_mat.get_shader_parameter("optics_surface_roughness") == resolved.surface_roughness)
	# Existing assembly owner preserves compatible optics and rejects silent loss.
	var other := loaded.duplicate_model()
	var merger = preload("res://addons/ember_import/ember_voxel_merge.gd")
	var inputs: Array[Dictionary] = [{"source":loaded,"frame":Transform3D.IDENTITY},{"source":other,"frame":Transform3D(Basis.IDENTITY,Vector3(1,0,0))}]
	var merged: Dictionary = merger.plan(inputs); assert(not merged.has("error"),str(merged))
	assert(merged.source.validation_errors().is_empty() and Profiles.optics_parameters(merged.source.material) == Profiles.optics_parameters(loaded.material))
	other.material.object_surface.optics.ior = 1.7
	assert(merger.plan(inputs).has("error"))
	var stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
	var preset = stamp.Preset.new(); preset.geometry = other
	assert(stamp.plan(loaded,preset,Vector3i.ZERO,0,0,-1,0,false,0).has("error"))
	var provider = preload("res://addons/ember_import/ember_voxel_rock_generator.gd")
	var settings := {"generation_version":2,"rock_type":3,"dimensions":Vector3i(12,16,12)}
	var generated: EmberVoxelModelResource = provider.build(settings,7,Color.GRAY,{},"test").geometry
	assert(Profiles.optics_parameters(generated.material).enabled)
	generated.material.object_surface.optics.refraction_strength = 0.05
	generated.material.object_surface.optics.cloud_strength = 0.35
	generated.material.object_surface.optics.cloud_light = "eeccff"
	generated.material.object_surface.optics.enabled = false
	var regenerated: EmberVoxelModelResource = provider.build(settings,7,Color.GRAY,generated.material,"test").geometry
	assert(regenerated.material.object_surface.optics == generated.material.object_surface.optics)
	assert(regenerated.validation_errors().is_empty() and regenerated.voxels == generated.voxels)
	before.free(); after.free()
	var scene := (load("res://scenes/object_material_study.tscn") as PackedScene).instantiate(); root.add_child(scene); await process_frame
	var visual: Mesh = scene.get_node("Sample3/Mesh").mesh
	var original: Dictionary = scene.sample_sources[3].to_definition()
	var undo := UndoRedo.new()
	undo.create_action("optics strength"); undo.add_do_property(scene,"refraction_scale",0.0); undo.add_undo_property(scene,"refraction_scale",1.0); undo.commit_action(); await process_frame
	assert(visual.surface_get_material(0).get_shader_parameter("optics_refraction_strength") == 0)
	undo.undo(); await process_frame; assert(visual.surface_get_material(0).get_shader_parameter("optics_refraction_strength") > 0)
	undo.redo(); await process_frame; scene.optics_enabled = false; scene.clarity = 0.8; scene.body_scale = 0.6; scene.apply_settings()
	assert(not visual.surface_get_material(0).shader.code.contains("ember_surface_optics"))
	assert(scene.sample_sources[3].to_definition() == original and scene.get_node("Sample3/Mesh").mesh == visual)
	scene.cloud_strength = 0.0; scene.apply_settings()
	var optical: ShaderMaterial = visual.get_meta("ember_optics_materials")[0]
	assert(optical.get_shader_parameter("optics_cloud_strength") == 0)
	undo.create_action("cloud"); undo.add_do_property(scene,"cloud_strength",0.5); undo.add_undo_property(scene,"cloud_strength",0.0); undo.commit_action(); await process_frame
	assert(optical.get_shader_parameter("optics_cloud_strength") > 0)
	undo.undo(); await process_frame; assert(optical.get_shader_parameter("optics_cloud_strength") == 0)
	undo.redo(); await process_frame
	undo.create_action("ice finish"); undo.add_do_property(scene,"ice_finish",0); undo.add_undo_property(scene,"ice_finish",1); undo.commit_action(); await process_frame
	assert(scene.get_node("Sample4/Mesh").mesh.get_meta("ember_optics_materials")[0].get_shader_parameter("optics_surface_roughness") < 0.1)
	undo.undo(); await process_frame; assert(scene.ice_finish == 1)
	undo.redo(); await process_frame; scene.crystal_finish = 0; scene.probe_kind = 1
	assert(scene.get_node("Sample4/Mesh").mesh.get_meta("ember_optics_materials")[0].get_shader_parameter("optics_crack_strength") < 0.1)
	scene.cloud_scale = 1.7; scene.cloud_seed = 19; scene.crystal_cloud_light = Color("ddbbff"); scene.apply_settings()
	assert(scene.sample_sources[3].to_definition() == original and scene.get_node("Sample3/Mesh").mesh == visual)
	var packed := PackedScene.new(); assert(packed.pack(scene) == OK); assert(ResourceSaver.save(packed,"user://optics_scene_test.tscn") == OK)
	var reopened := (ResourceLoader.load("user://optics_scene_test.tscn","",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate(); root.add_child(reopened); await process_frame
	assert(reopened.ice_finish == 0 and reopened.crystal_finish == 0 and reopened.probe_kind == 1 and reopened.neutral_light)
	assert(reopened.cloud_strength == 0.5 and reopened.cloud_scale == 1.7 and reopened.cloud_seed == 19 and reopened.crystal_cloud_light == Color("ddbbff"))
	assert(not reopened.optics_enabled and reopened.refraction_scale == 0 and reopened.clarity == 0.8 and reopened.body_scale == 0.6)
	reopened.optics_enabled = true; reopened.refraction_scale = 1; reopened.apply_settings()
	assert(reopened.get_node("Sample3/Mesh").mesh.surface_get_material(0).shader.code.contains("ember_surface_optics"))
	assert(reopened.get_node("Sample3/Mesh").mesh.surface_get_material(0).get_shader_parameter("optics_cloud_light") == Color("ddbbff"))
	assert(is_equal_approx(reopened.get_node("Sample3/Mesh").mesh.surface_get_material(0).get_shader_parameter("optics_refraction_strength"),0.026))
	undo.clear_history(); undo.free(); reopened.free(); scene.free()
	print("test_voxel_optics: PASS validation/source/geometry/collision/toggle/one Undo/save-off-reopen-enable/no remesh")
	quit()
