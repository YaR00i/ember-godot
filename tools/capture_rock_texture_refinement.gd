extends "res://tools/capture_rock_material_looks.gd"
## Material-only A/B. Retain the previous pigment and all existing geometry.
const Recipe=preload("res://scripts/prototypes/ember_natural_rock_recipe.gd")
var control: Array[ShaderMaterial]=[]
var candidate: Array[ShaderMaterial]=[]

func select_materials(revision: int,look: int,nodes: Array[MeshInstance3D]) -> void:
	study_materials=control if revision==0 else candidate
	apply_look(nodes,look)

func protected_scene() -> int:
	var values: Array=[scene._projection.document.to_dict() if scene._projection.document.has_method("to_dict") else hash(scene._projection.document.heights),floor_geometry(),scene.tuft_visual.multimesh.buffer]
	for visual in [scene.smooth_visual,scene.faceted_visual,scene.voxel_visual]:
		values.append(visual.mesh.get_faces())
		for surface in visual.mesh.get_surface_count():
			var material: ShaderMaterial=visual.mesh.surface_get_material(surface)
			if material!=null:values.append(material.get_shader_parameter("painted_leaf_card_albedo"))
	return hash(values)

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var guard:=protected_scene()
	scene.rock_maps=Recipe.maps(256,0)
	prepare_materials();control=study_materials.duplicate()
	var previous_height: PackedByteArray=scene.rock_maps.height.get_data()
	for look in 3:
		var image: Image=Image.load_from_file(output.path_join("colour-%d.png"%look))
		image.save_png(output.path_join("baseline-colour-%d.png"%look))
	scene.rock_maps=Recipe.maps()
	check(previous_height==scene.rock_maps.height.get_data(),"entire master height and mips unchanged")
	study_materials=[]
	var result:=await super.capture_looks(source,clouds,nodes)
	candidate=study_materials.duplicate()
	var camera: Camera3D=scene.follow_camera._cam
	var game_pose:=camera.global_transform;var game_fov:=camera.fov
	scene.set_rock_view(1)
	var close_pose:=camera.global_transform;var close_fov:=camera.fov
	var records: Array=[]
	for view in 2:
		camera.global_transform=game_pose if view==0 else close_pose
		camera.fov=game_fov if view==0 else close_fov
		for preset in 3:
			for light in 2:
				scene.set_lighting_preset(preset);scene.set_sun_pose(light)
				for look in 3:
					for revision in 2:
						select_materials(revision,look,nodes)
						var name:="view-%d-preset-%d-light-%d-look-%d-rev-%d"%[view,preset,light,look,revision]
						await capture(name)
						if revision==1:
							records.append({"view":view,"preset":preset,"light":light,"look":look})
	# Short deterministic camera sweeps: shared poses for A/B, every preset/look.
	for preset in 3:
		scene.set_lighting_preset(preset);scene.set_sun_pose(0)
		for look in 3:
			for revision in 2:
				select_materials(revision,look,nodes)
				for frame in 10:
					camera.global_transform=game_pose;camera.fov=game_fov
					camera.global_position+=game_pose.basis.x*((frame/9.0-0.5)*0.65)
					await capture("motion-%d-%d-%d-%02d"%[preset,look,revision,frame])
	camera.global_transform=game_pose;camera.fov=game_fov
	scene.set_lighting_preset(1);scene.set_sun_pose(1);select_materials(1,0,nodes)
	var first:=await capture("candidate-return-start")
	select_materials(0,2,nodes);await frames();select_materials(1,0,nodes)
	check(first.get_data()==(await capture("candidate-return-end")).get_data(),"candidate returns exactly after A/B and look switch")
	check(protected_scene()==guard,"terrain, collision, grass and tree geometry/textures preserved")
	result["refinement"]={"matrix":records,"motion_frames":180,"views":["game","close"],"control_revision":0,"candidate_revision":1,"master_height_unchanged":true,"context":"fixed ordinary environment; other materials and geometry are controls, not a completed three-world conversion"}
	return result
