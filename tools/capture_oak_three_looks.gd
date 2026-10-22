extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var reference:=OS.get_cmdline_user_args()[1]
	var quick:=OS.get_cmdline_user_args().has("--quick")
	scene=load("res://scenes/compact_oak_looks_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	while not scene.looks_ready:await process_frame
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.hide();scene.followers.set_physics_process(false)
	scene.follow_camera.set_physics_process(false);scene.follow_camera.set_process(false);scene.reset_actors()
	var original:=hash(scene.look_source.to_definition());var ground:=floor_geometry();var grass:=hash(scene.tuft_visual.multimesh.buffer)
	var collider: Shape3D=scene.look_prop.get_node("Collision/Shape").shape;var collision:=hash(collider.get_faces())
	scene.set_alternate_look(1);scene.set_alternate_look(0)
	for preset in [1,0,2]:
		for pose in [1,0]:
			if quick and (preset!=1 or pose!=1):continue
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for view in [1,2,3,0]:
				scene.set_look_view(view);scene.follow_camera.set_process(false)
				var tail:="%d-%d-%d"%[preset,pose,view]
				scene.set_look_fraction(0);var smooth:=await capture("smooth-"+tail)
				check(smooth.get_data()==Image.load_from_file(reference.path_join("smooth-"+tail+".png")).get_data(),"smooth exact "+tail)
				scene.set_alternate_look(0);scene.set_look_fraction(1)
				var material: ShaderMaterial=scene.voxel_visual.mesh.surface_get_material(1)
				material.set_shader_parameter("voxel_leaf_rim_form_weight",0.0);var before:=await capture("voxel-before-"+tail)
				check(before.get_data()==Image.load_from_file(reference.path_join("voxel-0-"+tail+".png")).get_data(),"voxel shape and original light exact "+tail)
				material.set_shader_parameter("voxel_leaf_rim_form_weight",1.0);await capture("voxel-"+tail)
				scene.set_look_fraction(0.5);await capture("split-voxel-"+tail)
				scene.set_alternate_look(1);await capture("split-faceted-"+tail)
				scene.set_look_fraction(1);await capture("faceted-"+tail)
				scene.set_look_fraction(0);check(smooth.get_data()==(await capture("return-"+tail)).get_data(),"smooth returns exact "+tail)
	scene.set_lighting_preset(0);scene.set_look_view(1);scene.follow_camera.set_process(false)
	for pose in [1,0]:
		scene.set_sun_pose(pose);scene.set_alternate_look(0);scene.set_look_fraction(1)
		for enabled in [false,true]:
			scene.set_look_rim(enabled);await capture("rim-%d-%s"%[pose,"on" if enabled else "off"])
	scene.set_look_rim(true);scene.set_alternate_look(1);scene.set_look_fraction(0.5)
	var camera: Camera3D=scene.follow_camera._cam;var initial:=camera.global_transform
	var target: Vector3=scene.look_prop.to_global(scene.look_bounds.get_center())
	for i in 12:
		camera.global_position=target+(initial.origin-target).rotated(Vector3.UP,(float(i)-5.5)*0.025);camera.look_at(target);await capture("motion-%02d"%i)
	camera.global_transform=initial
	for i in 11:
		scene.set_look_fraction(i/10.0);await capture("boundary-%02d"%i)
	check(scene.bake_count==2,"only one bake for each alternate look")
	check(hash(scene.look_source.to_definition())==original and floor_geometry()==ground and hash(scene.tuft_visual.multimesh.buffer)==grass,"Source ground grass unchanged")
	check(scene.look_prop.get_node("Collision/Shape").shape==collider and hash(collider.get_faces())==collision,"single collider retained")
	scene.set_look_fraction(0.5);scene.get_node("Instructions").show();await capture("controls")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"faceted_triangles":scene.baked_looks[2].triangles,"voxel_triangles":scene.baked_looks[0].triangles,"art_acceptance":"OPEN"},"\t"));file.close()
	print("OAK_THREE_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
