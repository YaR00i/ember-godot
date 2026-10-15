extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_spruce_shape_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.species_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false);scene.reset_actors();scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam;camera.fov=scene.follow_camera.fov
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_species_view(1)
	var ground:=floor_geometry();var grass:=hash(scene.tuft_visual.multimesh.buffer)
	var terrain: Resource=scene._projection.document.working_copy()
	for view in [1,2,3]:
		scene.set_species_view(view)
		for mode in [0,1,2]:scene.set_shape_mode(mode);await capture("view-%d-mode-%d"%[view,mode])
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_2;scene._unhandled_input(key)
	check(scene.shape_mode==1 and not scene.shape_volumes.visible,"keyboard2 shows bare scaffold")
	key.keycode=KEY_3;scene._unhandled_input(key)
	check(scene.shape_mode==2 and scene.shape_volumes.visible,"keyboard3 restores crown")
	scene.set_species_view(1);scene.set_shape_mode(0)
	check((await capture("rejected-return")).get_data()==Image.load_from_file("C:/Users/novos/Documents/Codex/2026-10-15/ember-birch-species/species-4.png").get_data(),"legacy spruce reference exact")
	for row in [[0,"ember-savanna-tip-cover/tree-1.png"],[1,"ember-bark-species/tree-1-1-painted.png"],[2,"ember-birch-species/birch-2.png"],[3,"ember-maple-shapes/upright.png"]]:
		scene.choose_species(row[0]);var picture:=await capture("accepted-%d"%row[0])
		check(picture.get_data()==Image.load_from_file("C:/Users/novos/Documents/Codex/2026-10-15/"+row[1]).get_data(),"accepted species exact "+str(row[0]))
	scene.set_shape_mode(2)
	var shape_before:=await capture("shape-baseline")
	var panel=scene.birch_recipe_panel
	panel.controls.main_branch_count.value=9;check(panel.creation==null,"native draft does not rebuild")
	panel.undo_parameters();check(panel.recipe.parameters.main_branch_count==7,"native Undo")
	panel.redo_parameters();panel.prepare();check(scene.birch_inputs.parameters.main_branch_count==9,"native preview regenerates nine whorls")
	await capture("tiers9")
	panel.discard();check(scene.birch_inputs.parameters.main_branch_count==7,"native discard restores seven whorls")
	check(shape_before.get_data()==(await capture("shape-discard")).get_data(),"shape after preview/discard frame exact")
	camera.global_position=scene.smooth_tree.global_position+Vector3(5,9,10)
	camera.look_at(scene.smooth_tree.global_position+Vector3(0,3.8,0));camera.fov=43
	await capture("shape-above")
	scene.set_species_view(1)
	if not OS.get_cmdline_user_args().has("--quick"):
		for preset in [1,0,2]:
			for pose in [1,0]:
				scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
				scene.set_species_view(1)
				await capture("light-%d-%d"%[preset,pose])
				camera.global_transform=game_transform;camera.fov=game_fov
				await capture("game-%d-%d"%[preset,pose])
	scene.set_lighting_preset(1);scene.set_sun_pose(1)
	for seed in [31,197]:
		scene._update_birch(scene.Species.spruce(seed));scene.set_shape_mode(2);scene.set_species_view(1);await capture("seed-%d"%seed)
	scene._update_birch(scene.birch_baseline)
	check(terrain.same_terrain_data(scene._projection.document) and ground==floor_geometry() and grass==hash(scene.tuft_visual.multimesh.buffer),"ground/paint/grass/physics exact")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM preserved")
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_species_view(1);scene.get_node("Instructions").show();await capture("controls")
	for control: Control in panel.controls.values():
		check(control.is_visible_in_tree() and control.get_global_rect().end.x<=1600 and control.get_global_rect().end.y<900,"all six shape controls fit the window")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"source_sha256":scene.birch_inputs.source.voxels.hex_encode().sha256_text(),"branches":scene.birch_inputs.layout.size(),"groups":scene.birch_inputs.structure.groups.size(),"art":"silhouette OPEN; no final needle artwork","quick":OS.get_cmdline_user_args().has("--quick")},"\t"));file.close()
	print("SPRUCE_SHAPE_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
