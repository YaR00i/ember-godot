extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var before_only:=OS.get_cmdline_user_args().has("--before")
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+140000
	while not scene.ready_for_foliage21 and Time.get_ticks_msec()<deadline:await process_frame
	if not scene.ready_for_foliage21:printerr("FAIL ready");quit(1);return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0);scene.show_tree_leaf_trial(0.4)
	scene.set_tree_leaf_shared_light(true)
	var camera: Camera3D=scene.follow_camera._cam
	# show_tree_leaf_trial selects the full-tree view: explicitly restore gameplay
	# before storing its transform. Also restore FOV changed outside the follow cache.
	scene.set_comparison(0);camera.fov=scene.follow_camera.fov
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	scene.set_network_view(1)
	check(not game_transform.is_equal_approx(camera.global_transform),"game and tree camera differ")
	var mesh: ArrayMesh=scene.foliage21_cards.mesh
	var mesh_hash:=hash(mesh.surface_get_arrays(0))
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var wood_material: ShaderMaterial=scene.parametric_wood.material_override
	var ground_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var terrain: Resource=scene._projection.document.working_copy()
	var recipe_hash:=hash(scene.parameter_panel.recipe.parameters)
	for preset in [1,0,2]:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose);scene.set_network_view(1)
			if not before_only:scene.set_tree_rim(false)
			var a:=await capture("tree-%d-%d-%s"%[preset,pose,"original" if before_only else "before"])
			if before_only:continue
			check(a.get_data()==Image.load_from_file(output.path_join("tree-%d-%d-original.png"%[preset,pose])).get_data(),"off exact before extraction")
			scene.set_tree_rim(true);var b:=await capture("tree-%d-%d-after"%[preset,pose])
			check(a.get_data()!=b.get_data(),"rim changes frame")
			# The lower-left rectangle contains rock/actors/grass. Upper-left has leaves.
			check(a.get_region(Rect2i(0,550,500,350)).get_data()==b.get_region(Rect2i(0,550,500,350)).get_data(),"rock actors grass unaffected")
			scene.set_tree_rim(false)
			check(a.get_data()==(await capture("tree-%d-%d-return"%[preset,pose])).get_data(),"off return exact")
			camera.global_transform=game_transform;camera.fov=game_fov
			await capture("game-%d-%d-before"%[preset,pose])
			scene.set_tree_rim(true);await capture("game-%d-%d-after"%[preset,pose])
	if before_only:print("TREE_RIM_LIGHT PASS original");quit();return
	check(mesh==scene.foliage21_cards.mesh and mesh_hash==hash(mesh.surface_get_arrays(0)),"mesh identity and arrays exact")
	check(scene.tree_leaf_density_percent==45 and scene.tree_leaf_density_inputs.cards==885,"45 percent885 cards retained")
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text() and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"Source wood exact")
	check(scene._projection.document.same_terrain_data(terrain) and ground_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer) and recipe_hash==hash(scene.parameter_panel.recipe.parameters),"terrain floor grass Recipe exact")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM4cm retained")
	scene.set_lighting_preset(0);scene.set_sun_pose(0);scene.set_network_view(1)
	scene.set_tree_rim(false);var off:=await capture("components-off")
	var wood_strength: float=scene.tree_rim_wood_strength;var leaf_strength: float=scene.tree_rim_leaf_strength
	scene.tree_rim_leaf_strength=0;scene.set_tree_rim(true)
	check(off.get_data()!=(await capture("wood-only")).get_data(),"wood contribution visible")
	scene.tree_rim_wood_strength=0;scene.tree_rim_leaf_strength=leaf_strength;scene.set_tree_rim(true)
	check(off.get_data()!=(await capture("leaves-only")).get_data(),"leaf contribution visible")
	scene.tree_rim_leaf_strength=0;scene.set_tree_rim(true)
	check(off.get_data()==(await capture("strength-zero")).get_data(),"zero strength exact off")
	scene.tree_rim_wood_strength=wood_strength;scene.tree_rim_leaf_strength=leaf_strength
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	var energy:=sun.light_energy;sun.light_energy=0
	scene.set_tree_rim(false);var zero:=await capture("zero-off")
	scene.set_tree_rim(true);check(zero.get_data()==(await capture("zero-on")).get_data(),"no emission")
	sun.light_energy=energy
	var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(100,100,0.2)
	blocker.mesh=box;blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY;scene.add_child(blocker)
	blocker.global_transform=Transform3D(sun.global_basis,scene.smooth_tree.global_position+Vector3(0,4.3,0)+sun.global_basis.z*7)
	scene.set_tree_rim(false);var shadow:=await capture("shadow-off")
	scene.set_tree_rim(true);check(shadow.get_data()==(await capture("shadow-on")).get_data(),"real shadow fully suppresses new rim")
	blocker.queue_free();await frames()
	scene.set_tree_rim(false);check(scene.parametric_wood.material_override==wood_material,"base bark material restored")
	scene.set_tree_rim(true);scene.set_tree_leaf_shared_light(false)
	check(not scene.tree_rim_enabled and scene.parametric_wood.material_override==wood_material,"historical A disables rim and restores bark")
	var column: Node=scene.tree_rim_button.get_parent()
	for row: Node in column.get_children():
		if row is HBoxContainer and row.get_child_count()==2 and row.get_child(1) is HSlider:
			var label: Label=row.get_child(0)
			if label.text=="Кромка коры":
				row.get_child(1).value=0.12
				check(is_equal_approx(scene.tree_rim_wood_strength,0.12) and is_equal_approx(scene.tree_rim_leaf_strength,leaf_strength),"bark slider independent")
				row.get_child(1).value=wood_strength
			elif label.text=="Кромка кроны":
				row.get_child(1).value=0.11
				check(is_equal_approx(scene.tree_rim_leaf_strength,0.11) and is_equal_approx(scene.tree_rim_wood_strength,wood_strength),"leaf slider independent")
				row.get_child(1).value=leaf_strength
	scene.tree_rim_button.pressed.emit();check(not scene.tree_rim_enabled,"button off")
	scene.tree_rim_button.pressed.emit();check(scene.tree_rim_enabled,"button on")
	scene.set_tree_rim(true);scene.get_node("Instructions").show();await capture("controls")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"density":45,"cards":885,"wood_strength":wood_strength,"leaf_strength":leaf_strength,"source_sha256":source_hash,"art_acceptance":"OPEN"},"\t"));file.close()
	print("TREE_RIM_LIGHT ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
