extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+140000
	while not scene.ready_for_foliage21 and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_foliage21,"samples ready")
	if not scene.ready_for_foliage21:quit(1);return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0)
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var cards_hash:=hash(scene.foliage21_cards.mesh.surface_get_arrays(0))
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var tree_material: Material=scene.foliage21_cards.material_override
	var terrain: Resource=scene._projection.document.working_copy()
	var ground_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	scene.set_lighting_preset(1);scene.set_sun_pose(0)
	var camera: Camera3D=scene.follow_camera._cam
	var center: Vector3=scene.smooth_tree.global_position+Vector3(0,3.5,0)
	camera.fov=40;camera.global_position=center+Vector3(2,-0.4,13);camera.look_at(center)
	var old_frame:=await capture("tree-unchanged-before")
	scene.show_leaf_samples()
	if OS.get_cmdline_user_args().has("--quick"):
		for stage in 3:
			scene.set_leaf_sample_stage(stage);await capture("quick-stage-%d"%stage)
	else:
		for preset in 3:
			for pose in 2:
				scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
				for stage in 3:
					scene.set_leaf_sample_stage(stage)
					await capture("samples-%d-%d-stage-%d"%[preset,pose,stage])
		scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_leaf_sample_stage(2)
		for distance in ["near","far"]:
			camera.global_position=scene.leaf_samples.global_position+Vector3(0,0.3,5.8 if distance=="near" else 12)
			camera.look_at(scene.leaf_samples.global_position)
			await capture(distance)
		for i in 5:
			var angle: float=float(i)*0.16
			camera.global_position=scene.leaf_samples.global_position+Vector3(sin(angle)*7.2,0.3,cos(angle)*7.2)
			camera.look_at(scene.leaf_samples.global_position);await capture("angle-%d"%i)
		scene.show_leaf_samples();scene.set_sun_pose(1)
		var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
		var energy:=sun.light_energy;sun.light_energy=0
		var material: ShaderMaterial=scene.leaf_sample_materials[2]
		material.set_shader_parameter("painted_leaf_transmission",0)
		material.set_shader_parameter("painterly_rim_strength",0)
		var dark:=await capture("zero-sun-disabled")
		material.set_shader_parameter("painted_leaf_transmission",0.14)
		material.set_shader_parameter("painterly_rim_strength",0.07)
		check(dark.get_data()==(await capture("zero-sun-enabled")).get_data(),"no added light without sun")
		sun.light_energy=energy
	scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.hide_leaf_samples()
	camera.fov=40;camera.global_position=center+Vector3(2,-0.4,13);camera.look_at(center)
	check(old_frame.get_data()==(await capture("tree-unchanged-after")).get_data(),"old tree returns pixel-exactly")
	check(tree_material==scene.foliage21_cards.material_override,"candidate not applied to tree")
	check(cards_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)) and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"tree geometry UV normals exact")
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text(),"Source exact")
	check(terrain and scene._projection.document.same_terrain_data(terrain) and ground_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"terrain grass paint physics exact")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM unchanged")
	check(scene.leaf_sample_nodes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==12,"one existing curved card")
	check(scene.leaf_sample_nodes[1].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==72,"six existing curved cards in group")
	var atlas: Image=Image.load_from_file(ProjectSettings.globalize_path(scene.SEPARATE_LEAVES_ATLAS))
	var texture: Image=scene.leaf_sample_materials[2].get_shader_parameter("painted_leaf_card_albedo").get_image()
	var alpha_same:=true;var raw:=atlas.get_data();var prepared:=texture.get_data()
	for i in range(3,raw.size(),4):
		if raw[i]!=prepared[i]:alpha_same=false;break
	check(alpha_same and texture.has_mipmaps(),"new alpha silhouette retained with filtered mips")
	scene.show_leaf_samples();scene.get_node("Instructions").show();await capture("controls")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"source_sha256":source_hash,"tree_cards":scene.foliage21_inputs.cards,"sample_cards":[1,6],"pigment_saturation":1.0,"leaf_low":0.24,"transmission":0.14,"rim":0.07,"tree_transfer":"NOT_STARTED","art_acceptance":"OPEN"},"\t"));file.close()
	print("LEAF_PLANE_GROUP_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
