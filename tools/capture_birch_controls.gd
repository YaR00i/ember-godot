extends "res://tools/capture_tree_foliage21_study.gd"
func control_scene_path() -> String:return "res://scenes/compact_tree_species_study.tscn"
func control_reference_path() -> String:return "C:/Users/novos/Documents/Codex/2026-10-15/ember-birch-species/birch-2.png"
func control_card_count() -> int:return 388
func control_marker() -> String:return "BIRCH_CONTROLS"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load(control_scene_path()).instantiate();root.add_child(scene);current_scene=scene
	while not scene.species_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false);scene.reset_actors()
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_species_view(1);scene.set_birch_revision(2)
	var baseline:=await capture("accepted")
	var old:=Image.load_from_file(control_reference_path())
	check(old.get_data()==baseline.get_data(),"accepted birch initial frame exact")
	var oak_hash:=hash(scene.foliage21_cards.mesh.surface_get_arrays(0));var wood_hash:=hash(scene.birch_wood.mesh.surface_get_arrays(0))
	var source: String=scene.birch_inputs.source.voxels.hex_encode().sha256_text()
	var ground:=floor_geometry();var grass:=hash(scene.tuft_visual.multimesh.buffer)
	var terrain: Resource=scene._projection.document.working_copy()
	var leaf_hash:=hash(scene.birch_leaves.mesh.surface_get_arrays(0))
	var builds: int=scene.birch_density_builds
	var slider: HSlider=scene.birch_sliders.density
	slider.drag_started.emit();slider.value=45;slider.value=30
	check(scene.birch_density_builds==builds and scene.birch_inputs.leaves.cards==control_card_count(),"no per-drag leaf rebuild")
	slider.drag_ended.emit(true)
	check(scene.birch_density_builds==builds+1 and scene.birch_inputs.leaves.cards<control_card_count(),"one release rebuilds derived leaves once")
	await capture("density30")
	scene.birch_recipe_panel.undo_parameters();check(scene.birch_inputs.leaves.cards==control_card_count() and scene.birch_density_builds==builds+1,"Undo cache exact")
	scene.birch_recipe_panel.redo_parameters();check(scene.birch_inputs.leaves.cards<control_card_count(),"Redo density")
	scene.birch_recipe_panel.undo_parameters()
	var ids: Array=scene.birch_crown_groups.keys();ids.sort();var owner: int=ids[0]
	scene.birch_parts.select(1);scene.birch_parts.item_selected.emit(1)
	scene.birch_sliders.local.value=25
	check(scene.birch_selected_part==owner and scene.birch_settings["part:%d"%owner]==25,"local part callback")
	var remaining: Dictionary={}
	for entry: Dictionary in scene.birch_inputs.leaves.roots:remaining[entry.original_card]=true
	var original: Dictionary=scene.Branching.thin_crown_cards(scene.birch_inputs.full_leaves,0.60)
	var arrays: Array=scene.birch_inputs.full_leaves.mesh.surface_get_arrays(0)
	for entry: Dictionary in original.roots:
		var full_root: Dictionary=scene.birch_inputs.full_leaves.roots[entry.original_card]
		var part:=int(arrays[Mesh.ARRAY_CUSTOM1][(full_root.vertex-7)*4+3])
		if part!=owner:check(remaining.has(entry.original_card),"local edit leaves other parts exact")
	await capture("local25")
	scene.birch_recipe_panel.undo_parameters();check(scene.birch_inputs.leaves.cards==control_card_count(),"local Undo exact")
	builds=scene.birch_density_builds
	scene.birch_sliders.depth.value=30;scene.birch_sliders.receive.value=20
	check(scene.birch_density_builds==builds and scene.birch_painted.get_shader_parameter("painted_leaf_shadow_strength")==0.20,"light uniforms no geometry rebuild")
	scene.birch_sliders.leaf_rim.value=35;scene.birch_sliders.wood_rim.value=20
	scene.birch_rim_toggle.button_pressed=false;scene.birch_rim_toggle.button_pressed=true
	await capture("light-trial")
	scene.reset_birch_settings()
	check(hash(scene.birch_leaves.mesh.surface_get_arrays(0))==leaf_hash,"reset original leaf buffers")
	check(baseline.get_data()==(await capture("reset")).get_data(),"reset accepted frame exact")
	scene.birch_recipe_panel.undo_parameters();check(scene.birch_settings.depth==30,"reset Undo")
	scene.birch_recipe_panel.redo_parameters();check(scene.birch_settings.depth==100,"reset Redo")
	for preset in [1,0,2]:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			var before:=await capture("%d-%d-before"%[preset,pose])
			scene.set_birch_setting("density",35);scene.set_birch_setting("receive",20);await capture("%d-%d-trial"%[preset,pose])
			scene.reset_birch_settings();check(before.get_data()==(await capture("%d-%d-return"%[preset,pose])).get_data(),"preset return exact")
	scene.set_birch_setting("part:%d"%owner,25);scene.reset_birch_settings()
	scene._update_birch(scene.trial_inputs())
	scene.birch_recipe_panel.undo_parameters()
	check(not scene.birch_settings.has("part:%d"%owner) and scene.birch_inputs.leaves.cards==control_card_count(),"old reset Undo cannot cut parts of new scaffold")
	scene.birch_recipe_panel.undo_parameters();scene.birch_recipe_panel.redo_parameters()
	check(scene.birch_inputs.leaves.cards==control_card_count(),"obsolete local history never changes new scaffold")
	scene.birch_recipe_panel.redo_parameters()
	check(oak_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)) and wood_hash==hash(scene.birch_wood.mesh.surface_get_arrays(0)),"oak and wood unchanged")
	check(source==scene.birch_inputs.source.voxels.hex_encode().sha256_text() and ground==floor_geometry() and grass==hash(scene.tuft_visual.multimesh.buffer) and terrain.same_terrain_data(scene._projection.document),"Source paint grass floor exact")
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.get_node("Instructions").show()
	scene.birch_tabs.current_tab=1;await capture("controls-leaves")
	for control: Control in scene.birch_sliders.values():
		check(control.is_visible_in_tree() and control.get_global_rect().end.x<=1600 and control.get_global_rect().end.y<900,"leaf controls fit")
	scene.birch_tabs.current_tab=0;await capture("controls-branches")
	var file:=FileAccess.open(output.path_join("verification.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"accepted_birch_exact":true,"scope":"LAB leaf controls only, no new production serialization","manual_mouse_motion":"OPEN"},"\t"));file.close()
	print(control_marker()+" ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
