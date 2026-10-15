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
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.show_tree_leaf_trial(0.4)
	var before:=OS.get_cmdline_user_args().has("--before")
	var initial:=await capture("before100" if before else "default100")
	if before:print("TREE_LEAF_DENSITY PASS");quit(0);return
	check(initial.get_data()==Image.load_from_file(output.path_join("before100.png")).get_data(),"100 density exact before controller changes")
	var full_mesh: ArrayMesh=scene.foliage21_inputs.mesh
	var full_hash:=hash(full_mesh.surface_get_arrays(0))
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var material: ShaderMaterial=scene.foliage21_cards.material_override
	var bark: ShaderMaterial=scene.parametric_wood.material_override
	var ground_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var terrain: Resource=scene._projection.document.working_copy()
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	var light_controls: Array=[sun.shadow_bias,sun.shadow_normal_bias,sun.light_angular_distance,sun.shadow_enabled]
	var counts: Array=[]
	var center: Vector3=scene.smooth_tree.global_position+Vector3(0,3.5,0)
	for preset in 3:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for percent in [100,75,60,45]:
				scene.set_tree_leaf_density(percent)
				if preset==0 and pose==0:counts.append({"percent":percent,"puffs":scene.tree_leaf_density_inputs.get("puffs",scene.Branching.crown_puff_count(scene.foliage21_inputs)),"cards":scene.tree_leaf_density_inputs.cards})
				scene.set_network_view(1);await capture("tree-%d-%d-density-%d"%[preset,pose,percent])
				camera.global_transform=game_transform;camera.fov=game_fov
				await capture("game-%d-%d-density-%d"%[preset,pose,percent])
	scene.set_lighting_preset(1);scene.set_sun_pose(0)
	for view in ["near","far","side","back"]:
		var offset:=Vector3(2,-0.4,13)*(0.72 if view=="near" else 1.7) if view in ["near","far"] else (Vector3(-13,-0.4,2) if view=="side" else Vector3(-2,-0.4,-13))
		camera.fov=40;camera.global_position=center+offset;camera.look_at(center)
		for percent in [100,75,60,45]:
			scene.set_tree_leaf_density(percent);await capture("view-%s-density-%d"%[view,percent])
	scene.set_tree_leaf_density(60)
	for i in 8:
		camera.global_position=center+Vector3(sin(i*0.12)*13,0.4,cos(i*0.12)*13);camera.look_at(center)
		await capture("motion-%d"%i)
	# Slider drag is label-only until release, then exactly one cached derivation.
	scene.set_tree_leaf_density(100);var builds: int=scene.tree_leaf_density_builds
	scene.tree_leaf_density_slider.drag_started.emit()
	scene.tree_leaf_density_slider.value=75;scene.tree_leaf_density_slider.value=60
	check(scene.foliage21_cards.mesh==full_mesh and scene.tree_leaf_density_builds==builds,"drag keeps committed full mesh without rebuild")
	scene.tree_leaf_density_slider.drag_ended.emit(true)
	check(scene.tree_leaf_density_percent==60 and scene.foliage21_cards.mesh==scene.tree_leaf_density_inputs.mesh,"release applies60")
	var reduced: ArrayMesh=scene.foliage21_cards.mesh
	scene.set_tree_leaf_density(100);scene.set_tree_leaf_density(60)
	check(scene.foliage21_cards.mesh==reduced,"density cached exact mesh reused")
	scene.set_material_revision(3)
	check(scene.foliage21_cards.mesh==full_mesh,"historical material always full geometry")
	scene.set_material_revision(5)
	check(scene.foliage21_cards.mesh==reduced,"trial density retained on return")
	scene.set_tree_leaf_density(0);check(not scene.foliage21_cards.visible,"zero hides leaf cards")
	scene.set_tree_leaf_density(60);scene.set_network_view(1)
	scene.get_node("Instructions").show();await capture("controls");scene.get_node("Instructions").hide()
	scene.set_tree_leaf_density(100);scene.set_network_view(1)
	check(initial.get_data()==(await capture("return100")).get_data(),"100 restores exact previous image")
	check(scene.foliage21_cards.mesh==full_mesh and hash(full_mesh.surface_get_arrays(0))==full_hash,"full authored buffers retained exact")
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text() and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"Source wood exact")
	check(material==scene.foliage21_cards.material_override and bark==scene.parametric_wood.material_override,"material light and bark exact")
	check(scene._projection.document.same_terrain_data(terrain) and ground_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"terrain paint floor physics grass exact")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM exact")
	check(light_controls==[sun.shadow_bias,sun.shadow_normal_bias,sun.light_angular_distance,sun.shadow_enabled],"world light controls exact")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"source_sha256":source_hash,"counts":counts,"builds":scene.tree_leaf_density_builds,"last_build_ms":scene.tree_leaf_density_build_ms,"art_acceptance":"OPEN","scope":"LAB derived whole-puff thinning"},"\t"));file.close()
	print("TREE_LEAF_DENSITY ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
