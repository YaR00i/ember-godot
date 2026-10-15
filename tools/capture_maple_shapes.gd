extends "res://tools/capture_tree_foliage21_study.gd"
func snapshot() -> Dictionary:
	return {"inputs":scene.birch_inputs,"wood":scene.birch_wood.mesh,"wood_material":scene.birch_wood.material_override,"leaves":scene.birch_leaves.mesh,"painted":scene.birch_painted,"plain":scene.birch_plain,"position":scene.birch_root.position}
func present(data: Dictionary) -> void:
	scene.birch_inputs=data.inputs;scene.birch_wood.mesh=data.wood;scene.birch_wood.material_override=data.wood_material
	scene.birch_leaves.mesh=data.leaves;scene.birch_painted=data.painted;scene.birch_plain=data.plain;scene.birch_root.position=data.position
	scene.set_birch_revision(2)
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_maple_upright_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.species_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false);scene.reset_actors();scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam;camera.fov=scene.follow_camera.fov
	var game:=camera.global_transform;var game_fov:=camera.fov
	var ground:=floor_geometry();var grass:=hash(scene.tuft_visual.multimesh.buffer)
	var terrain: Resource=scene._projection.document.working_copy()
	var upright:=snapshot()
	scene._update_birch(scene.Species.maple());var wide:=snapshot()
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_species_view(1)
	present(wide);var wide_before:=await capture("wide")
	var previous:=Image.load_from_file("C:/Users/novos/Documents/Codex/2026-10-15/ember-maple-species/maple-2.png")
	check(previous.get_data()==wide_before.get_data(),"preserved wide frame exact against previous study")
	present(upright);var upright_before:=await capture("upright")
	scene.species_mode=0;scene.choose_species(3);await capture("upright-bare");scene.species_mode=2;scene.choose_species(3)
	if not OS.get_cmdline_user_args().has("--quick"):
		for preset in [1,0,2]:
			for pose in 2:
				scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
				for view in ["tree","game"]:
					scene.set_species_view(1)
					if view=="game":camera.global_transform=game;camera.fov=game_fov
					present(wide);var before:=await capture("%s-%d-%d-wide"%[view,preset,pose])
					present(upright);await capture("%s-%d-%d-upright"%[view,preset,pose])
					present(wide);check(before.get_data()==(await capture("%s-%d-%d-return"%[view,preset,pose])).get_data(),"wide return exact")
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_species_view(1);present(upright)
	var saved_view:=camera.global_transform;var saved_fov:=camera.fov
	camera.global_position=scene.birch_root.global_position+Vector3(1.4,2.8,3.2);camera.look_at(scene.birch_root.global_position+Vector3(0,3.7,0));camera.fov=45
	await capture("upright-near");camera.global_transform=saved_view;camera.fov=62;await capture("upright-far")
	camera.global_position+=camera.global_basis.x*0.4;await capture("upright-shift")
	camera.global_transform=saved_view;camera.fov=saved_fov
	for pair in [[1,"oak"],[2,"birch"]]:
		scene.choose_species(pair[0]);var image:=await capture(pair[1])
		var path: String="C:/Users/novos/Documents/Codex/2026-10-15/"+("ember-maple-species/species-1.png" if pair[0]==1 else "ember-birch-species/birch-2.png")
		check(image.get_data()==Image.load_from_file(path).get_data(),"accepted reference exact "+pair[1])
	scene.set_birch_revision(2)
	var panel=scene.birch_recipe_panel
	check(panel.recipe.parameters.crown_shape==1 and panel.controls.size()==5,"upright recipe and five fields")
	panel.controls.crown_shape.select(0);panel.controls.crown_shape.item_selected.emit(0)
	check(panel.recipe.parameters.crown_shape==0 and panel.creation==null,"draft form callback no rebuild")
	panel.undo_parameters();check(panel.recipe.parameters.crown_shape==1,"native shape Undo")
	panel.redo_parameters();panel.prepare();check(scene.birch_inputs.parameters.crown_shape==0,"native preview selects wide form")
	check(wide_before.get_data()==(await capture("wide-from-editor")).get_data(),"editor wide matches preserved wide")
	panel.discard();check(scene.birch_inputs.parameters.crown_shape==1,"discard returns upright initial form")
	check(upright_before.get_data()==(await capture("upright-discard")).get_data(),"upright discard frame exact")
	var builds: int=scene.birch_density_builds
	scene.birch_sliders.density.drag_started.emit();scene.birch_sliders.density.value=30
	check(scene.birch_density_builds==builds,"no per-drag build")
	scene.birch_sliders.density.drag_ended.emit(true);check(scene.birch_density_builds==builds+1,"one release derived leaves")
	await capture("upright-density30");scene.reset_birch_settings()
	check(upright_before.get_data()==(await capture("upright-reset")).get_data(),"reset upright look exact")
	check(terrain.same_terrain_data(scene._projection.document) and ground==floor_geometry() and grass==hash(scene.tuft_visual.multimesh.buffer),"ground paint grass physical surface retained")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM4cm retained")
	scene.get_node("Instructions").show();scene.birch_tabs.current_tab=0;await capture("controls-shape")
	for control: Control in panel.controls.values():check(control.get_global_rect().end.x<=1600 and control.get_global_rect().end.y<900,"shape fields fit")
	scene.birch_tabs.current_tab=1;await capture("controls-leaves")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"wide_source_sha256":wide.inputs.source.voxels.hex_encode().sha256_text(),"upright_source_sha256":upright.inputs.source.voxels.hex_encode().sha256_text(),"same_cards":wide.inputs.leaves.cards==upright.inputs.leaves.cards,"art_upright":"OPEN","wide_saved_as_variation":true,"quick":OS.get_cmdline_user_args().has("--quick")},"\t"));file.close()
	print("MAPLE_SHAPES_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
