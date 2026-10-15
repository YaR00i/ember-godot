extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+140000
	while not scene.ready_for_foliage21 and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_foliage21,"ready")
	if not scene.ready_for_foliage21:quit(1);return
	check(scene.tree_leaf_density_percent==45,"requested45 starting density")
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	scene.show_tree_leaf_trial(0.4);scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_network_view(1)
	var baseline:=await capture("baseline45")
	var baseline_mesh: ArrayMesh=scene.foliage21_cards.mesh
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var full_hash:=hash(scene.foliage21_inputs.mesh.surface_get_arrays(0))
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var ground_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var terrain: Resource=scene._projection.document.working_copy()
	var recipe_hash:=hash(scene.parameter_panel.recipe.parameters)
	var selected: int=scene.tree_leaf_group_ids[-1]
	scene.set_tree_leaf_group(selected)
	var counts: Dictionary={}
	for preset in 3:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for mode in ["base","local50","soft","local50-soft"]:
				set_mode(mode,selected)
				if preset==0 and pose==0:counts[mode]=scene.tree_leaf_density_inputs.cards
				scene.set_network_view(1);await capture("tree-%d-%d-%s"%[preset,pose,mode])
				camera.global_transform=game_transform;camera.fov=game_fov;await capture("game-%d-%d-%s"%[preset,pose,mode])
	scene.set_lighting_preset(1);scene.set_sun_pose(0)
	var center: Vector3=scene.smooth_tree.global_position+Vector3(0,3.5,0)
	for view in ["near","far","side","back"]:
		var offset:=Vector3(2,-0.4,13)*(0.72 if view=="near" else 1.7) if view in ["near","far"] else (Vector3(-13,-0.4,2) if view=="side" else Vector3(-2,-0.4,-13))
		camera.global_position=center+offset;camera.fov=40;camera.look_at(center)
		for mode in ["base","local50-soft"]:set_mode(mode,selected);await capture("view-%s-%s"%[view,mode])
	for i in 8:
		camera.global_position=center+Vector3(sin(i*0.12)*13,0.4,cos(i*0.12)*13);camera.look_at(center);await capture("motion-%d"%i)
	# Local drag keeps committed geometry, applies once at release, then Undo/Redo
	# uses the existing generator panel history without touching its Recipe data.
	set_mode("base",selected);scene.set_network_view(1)
	var builds: int=scene.tree_leaf_density_builds
	scene.tree_leaf_local_slider.drag_started.emit();scene.tree_leaf_local_slider.value=65;scene.tree_leaf_local_slider.value=35
	check(scene.foliage21_cards.mesh==baseline_mesh and scene.tree_leaf_density_builds==builds,"local drag leaves committed mesh intact")
	scene.tree_leaf_local_slider.drag_ended.emit(true)
	check(scene.tree_leaf_local_percent[selected]==35 and scene.tree_leaf_density_builds==builds+1,"release derives once")
	var edited_mesh: ArrayMesh=scene.foliage21_cards.mesh
	scene.parameter_panel.undo_parameters();check(scene.foliage21_cards.mesh==baseline_mesh,"undo local exact cached base")
	scene.parameter_panel.redo_parameters();check(scene.foliage21_cards.mesh==edited_mesh,"redo local exact cached edited mesh")
	scene.set_tree_leaf_form_depth(60);check(is_equal_approx(scene.tree_leaf_trial_material.get_shader_parameter("painterly_grass_low"),0.544),"depth60 existing low uniform")
	scene.reset_tree_leaf_local();check(scene.tree_leaf_local_percent.is_empty() and scene.tree_leaf_form_depth==100,"reset local and form")
	scene.parameter_panel.undo_parameters();check(scene.tree_leaf_local_percent[selected]==35 and scene.tree_leaf_form_depth==60,"undo reset restores both settings")
	set_mode("local50-soft",selected);scene.get_node("Instructions").show()
	check(scene.tree_leaf_selection.visible,"chosen part marker visible with UI")
	await capture("controls")
	scene.get_node("Instructions").hide();check(not scene.tree_leaf_selection.visible,"F1 hides selection marker")
	set_mode("base",selected);scene.set_tree_leaf_group(-1);scene.set_network_view(1)
	check(baseline.get_data()==(await capture("controls-return")).get_data(),"control-only return exact45 frame")
	scene.set_tree_leaf_group(selected);set_mode("local50-soft",selected)
	# The new depth parameter must retain the real external shadow response.
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(3.5,4,0.2)
	blocker.mesh=box;blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;scene.add_child(blocker)
	blocker.global_transform=Transform3D(sun.global_basis,scene.smooth_tree.global_position+Vector3(0,4.3,0)+sun.global_basis.z*5)
	for depth in [100,60,25]:
		scene.set_tree_leaf_form_depth(depth);blocker.hide();await capture("external-clear-%d"%depth)
		blocker.show();await capture("external-blocked-%d"%depth)
	blocker.queue_free();await frames()
	set_mode("base",selected);scene.set_tree_leaf_group(-1);scene.set_network_view(1)
	await capture("baseline-return")
	check(scene.foliage21_cards.mesh==baseline_mesh and is_equal_approx(scene.tree_leaf_trial_material.get_shader_parameter("painterly_grass_low"),0.24),"neutral controls restore exact mesh and original light parameter")
	var energy:=sun.light_energy;sun.light_energy=0;var zero:=await capture("zero-depth100")
	scene.set_tree_leaf_form_depth(25);check(zero.get_data()==(await capture("zero-depth25")).get_data(),"depth creates no emission")
	sun.light_energy=energy;scene.set_tree_leaf_form_depth(100)
	scene.set_material_revision(3);await capture("old-material-return")
	check(scene.foliage21_cards.mesh==scene.foliage21_inputs.mesh,"old material retains full crown")
	check(hash(scene.parameter_panel.recipe.parameters)==recipe_hash,"LAB edits never change Recipe parameters")
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text() and full_hash==hash(scene.foliage21_inputs.mesh.surface_get_arrays(0)) and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"Source full geometry wood exact")
	check(scene._projection.document.same_terrain_data(terrain) and ground_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"terrain paint physical floor grass exact")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM retained")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"source_sha256":source_hash,"group_id":selected,"groups":scene.tree_leaf_group_ids.size(),"counts":counts,"density":45,"received_shadow_strength":0.4,"form_low":[0.24,0.544,0.81],"builds":scene.tree_leaf_density_builds,"last_build_ms":scene.tree_leaf_density_build_ms,"art_acceptance":"OPEN","scope":"LAB transient controls"},"\t"));file.close()
	print("TREE_LEAF_LOCAL ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)

func set_mode(mode: String,owner: int) -> void:
	scene.set_tree_leaf_local_percent(owner,50 if mode in ["local50","local50-soft"] else 100)
	scene.set_tree_leaf_form_depth(60 if mode in ["soft","local50-soft"] else 100)
