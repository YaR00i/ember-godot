extends "res://tools/capture_tree_foliage21_study.gd"
const Profiles=preload("res://scripts/ember_voxel_material_profiles.gd")
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	while not scene.ready_for_foliage21:await process_frame
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.show_tree_leaf_trial(0.4);scene.set_tree_leaf_shared_light(true);scene.set_tree_rim(true)
	var source: EmberVoxelModelResource=scene.parametric_inputs.source
	source.material=Profiles.with_rim(source.material,"bark",true,0.45)
	source.material=Profiles.with_rim(source.material,"foliage",true,0.18)
	scene.apply_tree_material_rim(source)
	if OS.get_cmdline_user_args().has("--controls-only"):
		scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_network_view(1)
		scene.set_oak_bark_variant(2);scene.get_node("Instructions").show()
		await capture("controls")
		check(scene.oak_bark_choice.get_global_rect().end.x<=1600,"bark selector fits viewport")
		print("OAK_BARK_CONTROLS PASS" if errors.is_empty() else "FAIL controls")
		quit(0 if errors.is_empty() else 1);return
	var wood_parameters:={}
	for property in scene.parametric_wood.material_override.get_property_list():
		if str(property.name).begins_with("shader_parameter/") and property.name!="shader_parameter/painted_bark_albedo":
			wood_parameters[property.name]=scene.parametric_wood.material_override.get(property.name)
	var camera: Camera3D=scene.follow_camera._cam
	scene.set_comparison(0);camera.fov=scene.follow_camera.fov
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	var leaf_material: ShaderMaterial=scene.foliage21_cards.material_override
	var leaf_parameters:={}
	for property in leaf_material.get_property_list():
		if str(property.name).begins_with("shader_parameter/"):leaf_parameters[property.name]=leaf_material.get(property.name)
	var leaf_hash:=hash(scene.foliage21_cards.mesh.surface_get_arrays(0))
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var ground:=floor_geometry();var grass:=hash(scene.tuft_visual.multimesh.buffer)
	var terrain: Resource=scene._projection.document.working_copy()
	var material_id: int=scene.parametric_wood.material_override.get_instance_id()
	for preset in [1,0,2]:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for view in ["tree","game"]:
				scene.set_network_view(1)
				if view=="game":camera.global_transform=game_transform;camera.fov=game_fov
				scene.set_oak_bark_trial(false);var before:=await capture("%s-%d-%d-before"%[view,preset,pose])
				for revision in [1,2]:
					scene.set_oak_bark_variant(revision)
					var painted:=await capture("%s-%d-%d-%s"%[view,preset,pose,"painted-v1" if revision==1 else "painted"])
					check(before.get_data()!=painted.get_data(),"new bark visible "+view)
				scene.set_oak_bark_trial(false);var returned:=await capture("%s-%d-%d-return"%[view,preset,pose])
				check(before.get_data()==returned.get_data(),"return to old bark exact")
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_network_view(1)
	var start:=camera.global_transform;var fov:=camera.fov
	for variant in [0,1,2]:
		camera.global_transform=start;camera.fov=fov
		for shot in ["near","far","motion"]:
			if shot=="near":
				camera.global_position=scene.parametric_wood.global_position+Vector3(3.1,2.6,4.2)
				camera.look_at(scene.parametric_wood.global_position+Vector3(0,3,0));camera.fov=40
			elif shot=="far":camera.global_transform=start;camera.fov=62
			else:camera.global_position+=camera.global_basis.x*0.4
			scene.set_oak_bark_variant(variant);await capture("%s-%s"%[shot,["before","painted-v1","painted"][variant]])
	check(leaf_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)) and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"wood and leaves arrays exact")
	check(scene.foliage21_cards.material_override==leaf_material and scene.parametric_wood.material_override.get_instance_id()==material_id,"same material instances")
	for key in leaf_parameters:check(leaf_material.get(key)==leaf_parameters[key],"leaf B parameter preserved "+key)
	for key in wood_parameters:check(scene.parametric_wood.material_override.get(key)==wood_parameters[key],"wood light/projection parameter preserved "+key)
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text(),"Source exact")
	check(terrain.same_terrain_data(scene._projection.document) and ground==floor_geometry() and grass==hash(scene.tuft_visual.multimesh.buffer),"paint grass physics exact")
	check(scene.tree_leaf_density_percent==45 and scene.tree_leaf_density_inputs.cards==885,"density 45%885 cards")
	check(scene.tree_rim_enabled and scene.tree_rim_wood_strength==0.45 and scene.tree_rim_leaf_strength==0.18,"accepted rim preserved")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM retained")
	camera.global_transform=start;camera.fov=fov
	scene.oak_bark_choice.item_selected.emit(0);check(not scene.oak_bark_trial,"old bark callback")
	scene.oak_bark_choice.item_selected.emit(1);check(scene.oak_bark_variant==1,"first bark callback")
	scene.oak_bark_choice.item_selected.emit(2);check(scene.oak_bark_variant==2,"calm bark callback")
	scene.get_node("Instructions").show();await capture("controls")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"source_sha256":source_hash,"cards":885,"art_acceptance":"OPEN","leaf_B_preserved":true,"shape_preserved":true},"\t"));file.close()
	print("OAK_BARK_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
