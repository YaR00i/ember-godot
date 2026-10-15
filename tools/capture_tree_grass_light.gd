extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var baseline_only:=OS.get_cmdline_user_args().has("--before")
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+140000
	while not scene.ready_for_foliage21 and Time.get_ticks_msec()<deadline:await process_frame
	if not scene.ready_for_foliage21:printerr("FAIL ready");quit(1);return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0);scene.show_tree_leaf_trial(0.4)
	var camera: Camera3D=scene.follow_camera._cam
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	var mesh: ArrayMesh=scene.foliage21_cards.mesh
	var mesh_hash:=hash(mesh.surface_get_arrays(0))
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var ground_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var terrain: Resource=scene._projection.document.working_copy()
	var recipe_hash:=hash(scene.parameter_panel.recipe.parameters)
	if OS.get_cmdline_user_args().has("--controls"):
		scene.set_network_view(1);scene.set_lighting_preset(1);scene.set_sun_pose(0)
		scene.set_tree_leaf_shared_light(true)
		check(scene.foliage21_cards.material_override==scene.tree_leaf_shared_material,"B selected")
		scene.set_tree_leaf_form_depth(scene.tree_leaf_form_depth)
		check(not scene.tree_leaf_shared_light and scene.foliage21_cards.material_override==scene.tree_leaf_trial_material,"A form control exits B even for same value")
		scene.set_tree_leaf_shared_light(true);scene.set_tree_leaf_trial_strength(0.4)
		check(not scene.tree_leaf_shared_light,"A shadow control exits B")
		scene.set_tree_leaf_shared_light(true);scene.get_node("Instructions").show();await capture("controls")
		print("TREE_GRASS_LIGHT ","PASS controls" if errors.is_empty() else errors)
		quit(0 if errors.is_empty() else 1);return
	for preset in [1,0,2]:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			scene.set_network_view(1)
			if not baseline_only:scene.set_tree_leaf_shared_light(false)
			var a:=await capture("tree-%d-%d-%s"%[preset,pose,"original" if baseline_only else "before"])
			if baseline_only:continue
			check(a.get_data()==Image.load_from_file(output.path_join("tree-%d-%d-original.png"%[preset,pose])).get_data(),"A exact before edits")
			scene.set_tree_leaf_shared_light(true)
			var b:=await capture("tree-%d-%d-after"%[preset,pose])
			check(a.get_data()!=b.get_data(),"B changes foliage")
			check(a.get_region(Rect2i(0,700,1600,200)).get_data()==b.get_region(Rect2i(0,700,1600,200)).get_data(),"ground shadow grass unchanged")
			scene.set_tree_leaf_shared_light(false)
			check(a.get_data()==(await capture("tree-%d-%d-return"%[preset,pose])).get_data(),"A return exact")
			camera.global_transform=game_transform;camera.fov=game_fov
			await capture("game-%d-%d-before"%[preset,pose])
			scene.set_tree_leaf_shared_light(true);await capture("game-%d-%d-after"%[preset,pose])
	if baseline_only:print("TREE_GRASS_LIGHT PASS original");quit();return
	# Existing shadow mask, shape and source are retained throughout comparison.
	check(mesh==scene.foliage21_cards.mesh and mesh_hash==hash(mesh.surface_get_arrays(0)),"mesh identity and all arrays exact")
	check(scene.tree_leaf_density_percent==45 and scene.tree_leaf_density_inputs.cards==885,"45 percent885 cards retained")
	check(scene.tree_leaf_shared_material.get_shader_parameter("painted_leaf_card_albedo")==scene.tree_leaf_trial_material.get_shader_parameter("painted_leaf_card_albedo"),"same alpha atlas")
	check(scene.tree_leaf_shared_material.get_shader_parameter("painted_leaf_shadow_strength")==0.4,"receiving response unchanged")
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text() and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"Source wood exact")
	check(scene._projection.document.same_terrain_data(terrain) and ground_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer) and recipe_hash==hash(scene.parameter_panel.recipe.parameters),"terrain paint floor grass Recipe exact")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM4cm retained")
	scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_network_view(1)
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(3.5,4,0.2)
	blocker.mesh=box;blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;scene.add_child(blocker)
	blocker.global_transform=Transform3D(sun.global_basis,scene.smooth_tree.global_position+Vector3(0,4.3,0)+sun.global_basis.z*5)
	blocker.hide();var clear:=await capture("external-clear")
	blocker.show();check(clear.get_data()!=(await capture("external-blocked")).get_data(),"external shadow still affects B")
	blocker.queue_free();await frames()
	var energy:=sun.light_energy;sun.light_energy=0
	var zero:=await capture("zero-light")
	scene.tree_leaf_shared_material.set_shader_parameter("painted_leaf_transmission",0.0)
	scene.tree_leaf_shared_material.set_shader_parameter("painterly_rim_strength",0.0)
	check(zero.get_data()==(await capture("zero-light-effects-off")).get_data(),"rim transmission no emission")
	sun.light_energy=energy
	scene.tree_leaf_shared_material.set_shader_parameter("painted_leaf_transmission",0.06)
	scene.tree_leaf_shared_material.set_shader_parameter("painterly_rim_strength",0.05)
	scene.get_node("Instructions").show();await capture("controls")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"density":45,"cards":885,"source_sha256":source_hash,"art_acceptance":"OPEN"},"\t"));file.close()
	print("TREE_GRASS_LIGHT ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
