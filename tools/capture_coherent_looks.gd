extends "res://tools/capture_tree_foliage21_study.gd"
func physics_hash() -> int:
	var values:=[]
	for tile in scene._projection._tiles.values():values.append(hash(tile.get_node("GroundPhysics/Shape").shape.get_faces()))
	return hash(values)

func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var quick:=OS.get_cmdline_user_args().has("--quick")
	scene=load("res://scenes/compact_coherent_looks_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.coherent_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.hide();scene.followers.set_physics_process(false)
	scene.follow_camera.set_physics_process(false);scene.follow_camera.set_process(false);scene.reset_actors()
	var original:=hash(scene.look_source.to_definition());var physics:=physics_hash()
	var collider: Shape3D=scene.look_prop.get_node("Collision/Shape").shape
	var height: PackedByteArray=scene.height_texture.get_image().get_data()
	var scatter: PackedFloat32Array=scene.grass_scatter[0].buffer
	var floor:=floor_geometry()
	for preset in [1,0,2]:
		if quick and preset!=1:continue
		scene.set_lighting_preset(preset);scene.set_sun_pose(1)
		for view in [0,2,3]:
			scene.set_study_view(view);scene.follow_camera.set_process(false)
			var camera: Camera3D=scene.follow_camera._cam
			var transform:=camera.global_transform;var fov:=camera.fov
			var baseline: Image
			for look in 3:
				scene.set_material_style(look)
				check(camera.global_transform==transform and camera.fov==fov,"one camera")
				var img:=await capture("look-%d-%d-%d"%[look,preset,view])
				if look==0:baseline=img
				check(physics_hash()==physics,"physical floor unchanged")
				check(is_equal_approx(scene.depth_material.get_shader_parameter("material_depth_amplitude_m"),0.04),"POM 4cm")
				check(int(scene.depth_material.get_shader_parameter("material_depth_steps"))==32,"POM 32steps")
				if look==1:
					scene.set_coarse_grass(true);await capture("coarse-%d-%d"%[preset,view]);scene.set_coarse_grass(false)
				scene.set_material_style(0)
			check(baseline.get_data()==(await capture("return-%d-%d"%[preset,view])).get_data(),"return to smooth exact")
	scene.set_lighting_preset(0);scene.set_sun_pose(0);scene.set_study_view(2);scene.follow_camera.set_process(false)
	for look in 3:
		scene.set_material_style(look)
		var on:=await capture("depth-on-%d"%look)
		scene.depth_material.set_shader_parameter("material_depth_enabled",false)
		check(on.get_data()!=(await capture("depth-off-%d"%look)).get_data(),"POM contributes")
		scene.depth_material.set_shader_parameter("material_depth_enabled",true)
		check(on.get_data()==(await capture("depth-return-%d"%look)).get_data(),"POM restores exact")
	if not quick:
		scene.set_study_view(0);scene.follow_camera.set_process(false)
		var camera: Camera3D=scene.follow_camera._cam;var start:=camera.global_transform
		for look in [1,2]:
			scene.set_material_style(look)
			for i in 8:
				camera.global_position=start.origin+start.basis.x*(i-3.5)*0.035
				await capture("motion-%d-%02d"%[look,i])
		camera.global_transform=start
	scene.set_material_style(0)
	check(floor_geometry()==floor and physics_hash()==physics,"mesh restores and collider unchanged")
	check(hash(scene.look_source.to_definition())==original,"oak Source unchanged")
	check(scene.look_prop.get_node("Collision/Shape").shape==collider,"one oak collider")
	check(scene.height_texture.get_image().get_data()==height,"authored height unchanged")
	check(scene.grass_scatter[0].buffer==scatter,"original scatter retained")
	for look in [1,2]:
		check(scene.grass_scatter[look].instance_count==scene.grass_scatter[0].instance_count,"same density")
		for i in scene.grass_scatter[0].instance_count:
			var a: Transform3D=scene.grass_scatter[0].get_instance_transform(i)
			var b: Transform3D=scene.grass_scatter[look].get_instance_transform(i)
			check(a.basis==b.basis and a.origin.x==b.origin.x and a.origin.z==b.origin.z,"same scatter x/z and size")
	scene.get_node("Instructions").show();await capture("controls")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"geometry":scene.geometry_stats,"art_acceptance":"OPEN"},"\t"));file.close()
	print("COHERENT_LOOKS_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
