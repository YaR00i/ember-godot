extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var quick:=OS.get_cmdline_user_args().has("--quick")
	scene=load("res://scenes/compact_material_shapes_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.styles_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.hide();scene.followers.set_physics_process(false)
	scene.follow_camera.set_physics_process(false);scene.follow_camera.set_process(false);scene.reset_actors()
	var original:=hash(scene.look_source.to_definition());var ground:=floor_geometry();var scatter:=hash(scene.tuft_visual.multimesh.buffer)
	var collider: Shape3D=scene.look_prop.get_node("Collision/Shape").shape;var collision:=hash(collider.get_faces())
	var height: PackedByteArray=scene.height_texture.get_image().get_data()
	for look in 3:
		for role in ["leaf","grass","stone"]:scene.study_images[look][role].save_png(output.path_join("art-%s-%d.png"%[role,look]))
		var material: ShaderMaterial=scene.material_variants[look]
		check(material.get_shader_parameter("material_depth_height")==scene.height_texture,"same height texture")
		check(is_equal_approx(material.get_shader_parameter("material_depth_amplitude_m"),0.04),"4cm depth")
		check(int(material.get_shader_parameter("material_depth_steps"))==32,"32 steps")
	for preset in [1,0,2]:
		for pose in [1,0]:
			if quick and (preset!=1 or pose!=1):continue
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for view in [0,1,2,3]:
				scene.set_study_view(view);scene.follow_camera.set_process(false)
				var tail:="%d-%d-%d"%[preset,pose,view]
				scene.set_material_style(0)
				scene.depth_material.shader=scene.original_depth_shader;scene._sync_tuft_material()
				var original_frame:=await capture("before-"+tail)
				scene.depth_material.shader=scene.depth_shader;scene._sync_tuft_material()
				check(original_frame.get_data()==(await capture("look-0-"+tail)).get_data(),"neutral shared shader exact "+tail)
				for look in [1,2]:
					scene.set_material_style(look);await capture("look-%d-"%look+tail)
				scene.set_material_style(0)
				check(original_frame.get_data()==(await capture("return-"+tail)).get_data(),"smooth returns exact "+tail)
	scene.set_study_view(2);scene.follow_camera.set_process(false);scene.set_lighting_preset(0);scene.set_sun_pose(1)
	for look in 3:
		scene.set_material_style(look)
		var with_depth:=await capture("depth-on-%d"%look)
		scene.depth_material.set_shader_parameter("material_depth_enabled",false)
		var without_depth:=await capture("depth-off-%d"%look)
		check(with_depth.get_data()!=without_depth.get_data(),"POM contributes in look%d"%look)
		scene.depth_material.set_shader_parameter("material_depth_enabled",true)
		check(with_depth.get_data()==(await capture("depth-return-%d"%look)).get_data(),"POM returns exact")
	scene.set_study_view(0);scene.follow_camera.set_process(false)
	var camera: Camera3D=scene.follow_camera._cam;var initial:=camera.global_transform
	for look in [1,2]:
		scene.set_material_style(look)
		for i in 8:
			camera.global_position=initial.origin+initial.basis.x*(float(i)-3.5)*0.035
			await capture("motion-%d-%02d"%[look,i])
	camera.global_transform=initial
	check(scene.study_bake_count==3 and scene.bake_count==2,"prebaked once; controls and light do not rebuild")
	check(hash(scene.look_source.to_definition())==original and floor_geometry()==ground and hash(scene.tuft_visual.multimesh.buffer)==scatter,"Source ground and grass placement unchanged")
	check(scene.height_texture.get_image().get_data()==height,"height bytes unchanged")
	check(scene.look_prop.get_node("Collision/Shape").shape==collider and hash(collider.get_faces())==collision,"one collider")
	scene.get_node("Instructions").show();await capture("controls")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"recipes":scene.style_stats,"art_acceptance":"OPEN","terrain_geometry":"held fixed; this is a material style comparison"},"\t"));file.close()
	print("MATERIAL_SHAPES_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
