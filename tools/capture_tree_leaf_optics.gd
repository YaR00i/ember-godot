extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+140000
	while not scene.ready_for_foliage21 and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_foliage21,"optics ready")
	if not scene.ready_for_foliage21:quit(1);return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	var terrain: Resource=scene._projection.document.working_copy()
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var cards_hash:=hash(scene.foliage21_cards.mesh.surface_get_arrays(0))
	var ground_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var bark: ShaderMaterial=scene.parametric_wood.material_override
	var center: Vector3=scene.smooth_tree.global_position+Vector3(0,3.5,0)
	var offsets: Array[Vector3]=[Vector3(2,-0.4,13),Vector3(-13,-0.4,2),Vector3(-2,-0.4,-13)]
	scene.set_lighting_preset(1);scene.set_sun_pose(0)
	for stage in 5:
		scene.set_leaf_optics_mode(stage)
		for pose in (1 if OS.get_cmdline_user_args().has("--quick") else 3):
			camera.fov=40;camera.global_position=center+offsets[pose];camera.look_at(center)
			await capture("view-%d-stage-%d"%[pose,stage])
		camera.global_position=center+offsets[0]*0.47;camera.look_at(center)
		await capture("close-stage-%d"%stage)
	if not OS.get_cmdline_user_args().has("--quick"):
		for preset in 3:
			for light in 2:
				scene.set_lighting_preset(preset);scene.set_sun_pose(light)
				for stage in 5:
					scene.set_leaf_optics_mode(stage)
					camera.fov=40;camera.global_position=center+offsets[0];camera.look_at(center)
					await capture("light-%d-%d-stage-%d"%[preset,light,stage])
					camera.global_transform=game_transform;camera.fov=game_fov
					await capture("game-%d-%d-stage-%d"%[preset,light,stage])
		for stage in [1,4]:
			scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_leaf_optics_mode(stage)
			for name in ["near","far"]:
				camera.fov=40;camera.global_position=center+offsets[0]*(0.72 if name=="near" else 1.7);camera.look_at(center)
				await capture("%s-stage-%d"%[name,stage])
			for i in 8:
				var angle:=i*0.12
				camera.global_position=center+Vector3(sin(angle)*13,0.5,cos(angle)*13);camera.look_at(center)
				await capture("motion-%d-stage-%d"%[i,stage])
		# Separate the two additions at identical backlight, not different colours.
		scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_network_view(1);scene.set_leaf_optics_mode(3)
		scene.set_leaf_optics_value("transmission",0);await capture("rim-only")
		scene.set_leaf_optics_value("transmission",0.28);scene.set_leaf_optics_value("rim",0);await capture("transmission-only")
		scene.set_leaf_optics_value("rim",0.23);await capture("rim-and-transmission")
		var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
		var energy:=sun.light_energy;sun.light_energy=0
		scene.set_leaf_optics_mode(2);var dark:=await capture("zero-sun-no-optics")
		scene.set_leaf_optics_mode(3)
		var dark_after:=(await capture("zero-sun-optics")).get_data()
		var dark_before:=dark.get_data();var max_dark_delta:=0;var changed_channels:=0
		for i in dark_before.size():
			var delta:=absi(int(dark_before[i])-int(dark_after[i]))
			max_dark_delta=maxi(max_dark_delta,delta)
			if delta>0:changed_channels+=1
		check(max_dark_delta<=1 and changed_channels<600,"zero-energy additions stay within one 8-bit rounding level, no visible glow")
		print("LEAF_OPTICS_ZERO_ENERGY max_delta=",max_dark_delta," changed_channels=",changed_channels)
		sun.light_energy=energy
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text(),"Source unchanged")
	check(wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)) and cards_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)),"wood/cards/UV/macro normals unchanged")
	check(bark==scene.parametric_wood.material_override,"soft bark unchanged")
	check(scene._projection.document.same_terrain_data(terrain) and ground_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"paint/floor/collision/grass unchanged")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM retained")
	var profile: Resource=load("res://content/terrain_materials/painted_light_grass.tres")
	for material in scene.optical_materials:
		for key in ["low","cool","warm","tint_strength","shadow_color","shadow_fill"]:
			var expected: Variant=profile.get("grass_light_"+key)
			var actual: Variant=material.get_shader_parameter("painterly_grass_"+key)
			if expected is Color:expected=Vector3(expected.r,expected.g,expected.b)
			if actual is Color:actual=Vector3(actual.r,actual.g,actual.b)
			check(actual==expected,"shared base light profile "+key)
	scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_network_view(1)
	scene.set_leaf_optics_mode(0);var before:=await capture("previous-return")
	scene.set_leaf_optics_mode(4);await frames();scene.set_leaf_optics_mode(0)
	check(before.get_data()==(await capture("previous-return-repeat")).get_data(),"previous material returns pixel-exactly")
	scene.set_leaf_optics_mode(4);scene.get_node("Instructions").show();await capture("controls")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"source_sha256":source_hash,"cards":scene.foliage21_inputs.cards,"card_triangles":scene.foliage21_inputs.triangles,"saturation":scene.leaf_saturation,"transmission":scene.leaf_transmission,"rim_strength":scene.leaf_rim_strength,"alpha_cutoff":scene.optical_materials[4].get_shader_parameter("painted_leaf_card_cutoff"),"art_acceptance":"OPEN"},"\t"));file.close()
	print("TREE_LEAF_OPTICS_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
