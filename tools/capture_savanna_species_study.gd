extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_savanna_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	while not scene.species_ready:await process_frame
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam
	camera.fov=scene.follow_camera.fov
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	var ground:=floor_geometry();var grass:=hash(scene.tuft_visual.multimesh.buffer)
	var terrain: Resource=scene._projection.document.working_copy()
	var oak_source: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var oak_wood:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var oak_leaves:=hash(scene.foliage21_cards.mesh.surface_get_arrays(0))
	var oak_material=scene.parametric_wood.material_override
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_species_view(1)
	scene.choose_species(1);var oak_before:=await capture("oak-C-before")
	for kind in 5:
		scene.choose_species(kind);var species_frame:=await capture("species-%d"%kind)
		if kind==2:
			var accepted:=Image.load_from_file("C:/Users/novos/Documents/Codex/2026-10-15/ember-birch-species/birch-2.png")
			check(accepted.get_data()==species_frame.get_data(),"accepted birch reference exact")
		if kind==3:
			var accepted_maple:=Image.load_from_file("C:/Users/novos/Documents/Codex/2026-10-15/ember-maple-shapes/upright.png")
			check(accepted_maple.get_data()==species_frame.get_data(),"accepted upright maple frame exact")
		if kind==1:
			scene.choose_species(4);scene.species_roots[4].hide();scene.species_roots[1].show()
			await capture("source-oak17")
	for revision in 3:
		scene.set_birch_revision(revision);await capture("savanna-%d"%revision)
	scene.species_mode=0;scene.set_birch_revision(2);await capture("savanna-bare")
	scene.species_mode=2;scene.set_birch_revision(2)
	var start:=camera.global_transform;var start_fov:=camera.fov
	camera.global_position=scene.birch_root.global_position+Vector3(1.4,2.8,2.8)
	camera.look_at(scene.birch_root.global_position+Vector3(0,3.2,0));camera.fov=45
	await capture("savanna-near")
	camera.global_transform=start;camera.fov=62;await capture("savanna-far")
	camera.global_position+=camera.global_basis.x*0.4;await capture("savanna-camera-shift")
	if not OS.get_cmdline_user_args().has("--quick"):
		for preset in [1,0,2]:
			for pose in 2:
				scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
				for view in ["tree","game"]:
					scene.set_species_view(1)
					if view=="game":camera.global_transform=game_transform;camera.fov=game_fov
					scene.set_birch_revision(0);var before:=await capture("%s-%d-%d-old"%[view,preset,pose])
					for revision in [1,2]:
						scene.set_birch_revision(revision);await capture("%s-%d-%d-new%d"%[view,preset,pose,revision])
					scene.set_birch_revision(0);var returned:=await capture("%s-%d-%d-return"%[view,preset,pose])
					check(before.get_data()==returned.get_data(),"old savanna return exact "+view)
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_species_view(1);scene.choose_species(1)
	check(oak_before.get_data()==(await capture("oak-C-return")).get_data(),"accepted oak C frame exact")
	check(scene.parametric_wood.material_override==oak_material and oak_wood==hash(scene.parametric_wood.mesh.surface_get_arrays(0)) and oak_leaves==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)),"oak material/shape/B exact")
	check(oak_source==scene.parametric_inputs.source.voxels.hex_encode().sha256_text(),"oak Source exact")
	check(terrain.same_terrain_data(scene._projection.document) and ground==floor_geometry() and grass==hash(scene.tuft_visual.multimesh.buffer),"ground/grass/paint/physics preserved")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"ground POM preserved")
	check(scene.oak_bark_variant==2,"accepted oak C default")
	scene.set_birch_revision(2);scene.get_node("Instructions").show();await capture("controls")
	check(scene.species_panel.get_global_rect().end.x<=1600,"species controls fit")
	check(scene.birch_recipe_panel.controls.size()==4,"four shared branch controls")
	for control: Control in scene.birch_recipe_panel.controls.values():
		check(control.is_visible_in_tree() and control.get_global_rect().size.y>20 and control.get_global_rect().end.x<=1600 and control.get_global_rect().end.y<=900,"visible branch input fits")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"savanna_branches":scene.birch_inputs.layout.size(),"savanna_cards":scene.birch_inputs.leaves.cards,"source_sha256":scene.birch_inputs.source.voxels.hex_encode().sha256_text(),"oak_sha256":oak_source,"art_acceptance":"OPEN","quick":OS.get_cmdline_user_args().has("--quick")},"\t"));file.close()
	print("SAVANNA_SPECIES_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
