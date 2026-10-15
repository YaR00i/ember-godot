extends "res://tools/capture_tree_foliage21_study.gd"
var reference_deltas: Dictionary={}
func reference_equal(picture: Image,path: String,label: String) -> bool:
	var previous:=Image.load_from_file(path)
	var a:=picture.get_data();var b:=previous.get_data()
	if a==b:reference_deltas[label]={"pixels":0,"max_rgb8":0};return true
	if a.size()!=b.size():return false
	var stride:=3
	if a.size()==picture.get_width()*picture.get_height()*4:stride=4
	if a.size()!=picture.get_width()*picture.get_height()*stride:return false
	var count:=0;var peak:=0
	for i in range(0,a.size(),stride):
		var difference:=0
		for channel in stride:difference=maxi(difference,absi(int(a[i+channel])-int(b[i+channel])))
		if difference>0:count+=1;peak=maxi(peak,difference)
	reference_deltas[label]={"pixels":count,"max_rgb8":peak}
	return count<=8 and peak<=1
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_spruce_needles_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.species_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false);scene.reset_actors();scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam;camera.fov=scene.follow_camera.fov
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	var ground:=floor_geometry();var grass:=hash(scene.tuft_visual.multimesh.buffer);var terrain: Resource=scene._projection.document.working_copy()
	scene.set_lighting_preset(1);scene.set_sun_pose(1)
	for count in [1,6]:scene.show_leaf_sample(count);await capture("patch-%d"%count)
	scene.show_canopy_reference()
	check((await capture("accepted-canopy")).get_data()==Image.load_from_file("C:/Users/novos/Documents/Codex/2026-10-15/ember-spruce-shape/view-1-mode-2.png").get_data(),"provisional shape reference exact")
	for view in [1,2,3]:scene.set_birch_revision(2);scene.set_species_view(view);await capture("tree-%d"%view)
	scene.set_species_view(1);scene.set_birch_revision(1);await capture("plain");scene.set_birch_revision(2)
	var initial:=await capture("baseline")
	var leaf_buffers:=hash(scene.birch_inputs.full_leaves.mesh.surface_get_arrays(0))
	var panel=scene.birch_recipe_panel
	panel.controls.main_branch_count.value=9;check(panel.creation==null,"draft without regeneration")
	panel.undo_parameters();check(panel.recipe.parameters.main_branch_count==7,"branch Undo")
	panel.redo_parameters();panel.prepare()
	check(scene.birch_inputs.parameters.main_branch_count==9,"branch preview uses same controller")
	var expected: Dictionary=scene.Species.spruce_needles(7,{"main_branch_count":9})
	check(scene.birch_inputs.full_leaves.mesh.surface_get_arrays(0)==expected.full_leaves.mesh.surface_get_arrays(0),"preview preserves needle placement options")
	panel.discard();check(leaf_buffers==hash(scene.birch_inputs.full_leaves.mesh.surface_get_arrays(0)),"discard card buffers exact")
	check(initial.get_data()==(await capture("discard")).get_data(),"discard frame exact")
	scene.set_birch_setting("density",80);await capture("density80");scene.reset_birch_settings()
	check(initial.get_data()==(await capture("reset")).get_data(),"density reset frame exact")
	scene.species_mode=0;scene.set_birch_revision(2);await capture("bare");scene.species_mode=2;scene.set_birch_revision(2)
	camera.global_position=scene.smooth_tree.global_position+Vector3(5,9,10)
	camera.look_at(scene.smooth_tree.global_position+Vector3(0,3.8,0));camera.fov=43;await capture("above");scene.set_species_view(1)
	if not OS.get_cmdline_user_args().has("--quick"):
		for preset in [1,0,2]:
			for pose in [1,0]:
				scene.set_lighting_preset(preset);scene.set_sun_pose(pose);scene.set_species_view(1);await capture("light-%d-%d"%[preset,pose])
				camera.global_transform=game_transform;camera.fov=game_fov;await capture("game-%d-%d"%[preset,pose])
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_species_view(1)
	for row in [[0,"ember-savanna-tip-cover/tree-1.png"],[1,"ember-bark-species/tree-1-1-painted.png"],[2,"ember-birch-species/birch-2.png"],[3,"ember-maple-shapes/upright.png"]]:
		scene.choose_species(row[0]);var picture:=await capture("accepted-%d"%row[0])
		check(reference_equal(picture,"C:/Users/novos/Documents/Codex/2026-10-15/"+row[1],str(row[0])),"previous species frame within numeric GPU tolerance")
	scene.set_birch_revision(2);await capture("baseline")
	check(scene.birch_inputs.source.voxels.hex_encode().sha256_text()=="dfd9f45476078d53b05505d7c586d559d0a74be273b31d4e8b616a76d6e677e0","provisional spruce Source exact")
	check(terrain.same_terrain_data(scene._projection.document) and ground==floor_geometry() and grass==hash(scene.tuft_visual.multimesh.buffer),"terrain paint grass physics exact")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM exact")
	scene.get_node("Instructions").show();await capture("controls")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"cards":scene.birch_inputs.leaves.cards,"full_cards":scene.birch_inputs.full_leaves.cards,"references":reference_deltas,"reference_limit":"max1 RGB8 level, at most8 pixels in 1600x900; source/geometry guards remain exact","quick":OS.get_cmdline_user_args().has("--quick"),"art":"needle placement and shape OPEN; source unchanged"},"\t"));file.close()
	print("SPRUCE_NEEDLES_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
