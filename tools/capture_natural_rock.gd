extends "res://tools/capture_coherent_looks.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var quick:=OS.get_cmdline_user_args().has("--quick")
	scene=load("res://scenes/compact_natural_rock_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.rock_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.hide();scene.followers.set_physics_process(false)
	scene.follow_camera.set_physics_process(false);scene.follow_camera.set_process(false);scene.reset_actors()
	var physics:=physics_hash();var original:=hash(scene.look_source.to_definition())
	var height: PackedByteArray=scene.height_texture.get_image().get_data()
	scene.rock_maps.colour.save_png(output.path_join("rock-colour.png"));scene.rock_maps.height.save_png(output.path_join("rock-height.png"))
	for preset in [1,0,2]:
		if quick and preset!=1:continue
		for sun in [1,0]:
			if quick and sun!=1:continue
			scene.set_lighting_preset(preset);scene.set_sun_pose(sun)
			for view in [1,0]:
				scene.set_rock_view(view);scene.follow_camera.set_process(false)
				var camera: Camera3D=scene.follow_camera._cam;var transform:=camera.global_transform
				var baseline: Image
				for plain in [true,false]:
					scene.set_plain_rock(plain)
					for look in 3:
						scene.set_material_style(look)
						var img:=await capture("%s-%d-%d-%d-%d"%["form" if plain else "material",look,preset,sun,view])
						if plain and look==0:baseline=img
						check(camera.global_transform==transform,"same camera")
						check(physics_hash()==physics,"one physical surface")
					scene.set_material_style(0);scene.set_plain_rock(true)
					check(baseline.get_data()==(await capture("return-%d-%d-%d-%s"%[preset,sun,view,plain])).get_data(),"form restores exact")
	scene.set_plain_rock(false);scene.set_rock_view(1);scene.follow_camera.set_process(false);scene.set_lighting_preset(0);scene.set_sun_pose(1)
	for look in 3:
		scene.set_material_style(look)
		check(is_equal_approx(scene.depth_material.get_shader_parameter("material_depth_amplitude_m"),0.04),"4cm POM")
		check(int(scene.depth_material.get_shader_parameter("material_depth_steps"))==32,"32 steps")
		var on:=await capture("depth-on-%d"%look)
		scene.depth_material.set_shader_parameter("material_depth_enabled",false)
		check(on.get_data()!=(await capture("depth-off-%d"%look)).get_data(),"depth contributes")
		scene.depth_material.set_shader_parameter("material_depth_enabled",true)
		check(on.get_data()==(await capture("depth-return-%d"%look)).get_data(),"depth restores")
		check([hash(scene.grass_scatter[look].buffer),hash(scene.grass_variants[look].surface_get_arrays(0))]==scene.original_grass_hashes[look],"grass untouched")
		check(scene.tuft_visual.material_override==scene.saved_grass_materials[look],"original grass material")
	check(hash(scene.look_source.to_definition())==original and scene.height_texture.get_image().get_data()==height,"author sources retained")
	check(scene.rock_stats.max_grid_error_m<=0.0376,"adaptive shape error within budget")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"geometry":scene.rock_stats,"art_acceptance":"OPEN"},"\t"));file.close()
	print("NATURAL_ROCK_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
