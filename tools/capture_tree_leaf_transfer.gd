extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+140000
	while not scene.ready_for_foliage21 and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_foliage21,"ready")
	if not scene.ready_for_foliage21:quit(1);return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam
	# Explicitly update the real follow-camera once after resetting the actors.
	scene.follow_camera._process(1.0)
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_network_view(1)
	var old_frame:=await capture("old-before" if OS.get_cmdline_user_args().has("--before") else "old-default")
	if OS.get_cmdline_user_args().has("--before"):
		print("TREE_LEAF_TRANSFER PASS");quit(0);return
	check(old_frame.get_data()==Image.load_from_file(output.path_join("old-before.png")).get_data(),"old default tree exact before/after controller")
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var cards_hash:=hash(scene.foliage21_cards.mesh.surface_get_arrays(0))
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var bark: Material=scene.parametric_wood.material_override
	var terrain: Resource=scene._projection.document.working_copy()
	var ground_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var sample_hash:=hash(scene.leaf_sample_materials[2].get_shader_parameter("painted_leaf_card_albedo").get_image().get_data())
	for key in ["painted_leaf_card_albedo","painted_leaf_saturation","painterly_grass_low","painterly_grass_shadow_fill","painted_leaf_transmission","painterly_rim_strength"]:
		check(scene.tree_leaf_trial_material.get_shader_parameter(key)==scene.leaf_sample_materials[2].get_shader_parameter(key),"candidate uses sample material "+key)
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	var sun_initial: Array=[sun.shadow_bias,sun.shadow_normal_bias,sun.light_angular_distance,sun.shadow_enabled]
	var center: Vector3=scene.smooth_tree.global_position+Vector3(0,3.5,0)
	var offset:=Vector3(2,-0.4,13)
	for preset in 3:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for mode in ["old","new100","new40","new35"]:
				apply_mode(mode)
				camera.fov=40;camera.global_position=center+offset;camera.look_at(center)
				await capture("tree-%d-%d-%s"%[preset,pose,mode])
				camera.global_transform=game_transform;camera.fov=game_fov
				await capture("game-%d-%d-%s"%[preset,pose,mode])
	scene.set_lighting_preset(1);scene.set_sun_pose(0)
	for view in ["near","far","side","back"]:
		var position: Vector3=offset*0.72 if view=="near" else (offset*1.7 if view=="far" else (Vector3(-13,-0.4,2) if view=="side" else Vector3(-2,-0.4,-13)))
		camera.fov=40;camera.global_position=center+position;camera.look_at(center)
		for mode in ["old","new40","new35"]:
			apply_mode(mode);await capture("view-%s-%s"%[view,mode])
	apply_mode("new40")
	for i in 8:
		var angle:=i*0.12
		camera.global_position=center+Vector3(sin(angle)*13,0.4,cos(angle)*13);camera.look_at(center)
		await capture("motion-%d"%i)
	# Identical alpha/geometry must cast the identical world shadow at100/40/35.
	# A QA-only overhead view isolates the actual map receiver from the canopy.
	camera.global_position=center+Vector3(14,16,18);camera.look_at(scene.smooth_tree.global_position)
	for mode in ["new100","new40","new35"]:
		apply_mode(mode);await capture("ground-%s"%mode)
	# Finite sun energy controls all additional light. No emission is introduced.
	scene.set_network_view(1);var energy:=sun.light_energy;sun.light_energy=0
	apply_mode("new100");var zero:=await capture("zero-before")
	apply_mode("new40");check(zero.get_data()==(await capture("zero-after")).get_data(),"no independent emission")
	sun.light_energy=energy
	# Traverse the public controls and return to the saved original material.
	scene.show_leaf_samples();scene.set_leaf_sample_shadow_strength(0.35)
	scene.show_tree_leaf_trial(0.4)
	check(not scene.leaf_samples.visible and not scene.leaf_sample_panel.visible and scene.tree_leaf_trial_panel.visible,"sample to tree preview controls")
	check(scene.tree_leaf_trial_material.get_shader_parameter("painted_leaf_shadow_strength")==0.4,"requested40 independent of sample35")
	check(scene.tree_leaf_trial_strength==0.4 and scene.material_revision==5,"trial40 routed")
	scene.get_node("Instructions").show();await capture("controls");scene.get_node("Instructions").hide()
	scene.set_material_revision(3);scene.set_network_view(1)
	check(not scene.tree_leaf_trial_panel.visible and scene.optics_panel.visible,"return panel old controls")
	check(old_frame.get_data()==(await capture("old-return")).get_data(),"old tree returns exact")
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text(),"Source exact")
	check(cards_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)) and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"cards wood UV normals exact")
	check(bark==scene.parametric_wood.material_override,"bark owner/material exact")
	check(scene._projection.document.same_terrain_data(terrain) and ground_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"paint floor physics grass exact")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM exact")
	check(sample_hash==hash(scene.leaf_sample_materials[2].get_shader_parameter("painted_leaf_card_albedo").get_image().get_data()),"texture exact")
	check(sun_initial==[sun.shadow_bias,sun.shadow_normal_bias,sun.light_angular_distance,sun.shadow_enabled],"light controls exact")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"source_sha256":source_hash,"cards":scene.foliage21_inputs.cards,"triangles":scene.foliage21_inputs.triangles,"strength":0.4,"scope":"LAB_material_only","art_acceptance":"OPEN","game_camera_transform":str(game_transform)},"\t"));file.close()
	print("TREE_LEAF_TRANSFER ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)

func apply_mode(mode: String) -> void:
	if mode=="old":scene.set_material_revision(3)
	else:
		scene.set_tree_leaf_trial_strength(1.0 if mode=="new100" else (0.4 if mode=="new40" else 0.35))
