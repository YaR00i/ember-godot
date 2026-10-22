extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var baseline:=OS.get_cmdline_user_args().has("--baseline")
	var quick:=OS.get_cmdline_user_args().has("--quick")
	scene=load("res://scenes/compact_oak_looks_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	var limit:=Time.get_ticks_msec()+150000
	while not scene.looks_ready and Time.get_ticks_msec()<limit:await process_frame
	check(scene.looks_ready,"ready")
	if not scene.looks_ready:quit(1);return
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	# Startup/bake duration must not choose a different companion pose.
	scene.followers._last_forward=Vector3(0,0,-1)
	scene.followers.get_node("PartyFollower_mira").rotation=Vector3.ZERO
	scene.reset_actors()
	# Companion presentation can finish a queued pose update during startup.
	# Keep Kai as the scale reference; exclude companions from fixed comparisons.
	scene.followers.hide()
	var camera: Camera3D=scene.follow_camera._cam
	var source_hash:=hash(scene.look_source.to_definition());var grass:=hash(scene.tuft_visual.multimesh.buffer);var floor_hash:=floor_geometry()
	var collision: Shape3D=scene.look_prop.get_node("Collision/Shape").shape
	var collider_hash:=hash(collision.get_faces())
	for preset in [1,0,2]:
		for pose in [1,0]:
			if quick and (preset!=1 or pose!=1):continue
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for view in [1,2,3,0]:
				if quick and view==0:continue
				scene.set_look_view(view);scene.follow_camera.set_process(false)
				var label:="%d-%d-%d"%[preset,pose,view]
				if baseline:
					await capture("baseline-"+label);continue
				scene.set_look_fraction(0);var before:=await capture("smooth-"+label)
				if FileAccess.file_exists(output.path_join("baseline-"+label+".png")):
					check(before.get_data()==Image.load_from_file(output.path_join("baseline-"+label+".png")).get_data(),"smooth exact before shaders "+label)
				for detail in 2:
					scene.set_voxel_detail(detail)
					for fraction in [0.5,1.0]:
						scene.set_look_fraction(fraction);await capture(("split" if fraction==0.5 else "voxel")+"-%d-"%detail+label)
				scene.set_look_fraction(0)
				check(before.get_data()==(await capture("return-"+label)).get_data(),"smooth exact return "+label)
	if baseline:print("OAK_LOOKS_NATIVE PASS baseline");quit();return
	scene.set_lighting_preset(0);scene.set_sun_pose(1);scene.set_look_view(1);scene.set_voxel_detail(0);scene.set_look_fraction(0.5)
	var original_transform:=camera.global_transform
	var target: Vector3=scene.look_prop.to_global(scene.look_bounds.get_center())
	for i in (3 if quick else 12):
		camera.global_position=target+(original_transform.origin-target).rotated(Vector3.UP,(float(i)-5.5)*0.025);camera.look_at(target)
		await capture("motion-%02d"%i)
	camera.global_transform=original_transform
	for i in (3 if quick else 11):
		scene.set_look_fraction(float(i)/(2.0 if quick else 10.0));await capture("boundary-%02d"%i)
	check(scene.bake_count==2,"moving boundary and camera do not rebake")
	check(hash(scene.look_source.to_definition())==source_hash,"Source unchanged")
	check(hash(scene.tuft_visual.multimesh.buffer)==grass and floor_geometry()==floor_hash,"grass floor POM scene preserved")
	check(scene.look_prop.get_node("Collision/Shape").shape==collision and hash(collision.get_faces())==collider_hash,"single wood collider retained")
	scene.set_look_fraction(0.5);scene.get_node("Instructions").show();await capture("controls")
	var stats: Dictionary={}
	for key in scene.baked_looks:
		var bake: Dictionary=scene.baked_looks[key];stats[str(key)]={"cells":bake.cells,"triangles":bake.triangles,"puffs":bake.puffs.size(),"cards":bake.cards,"build_ms":bake.build_ms}
	var report:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"stats":stats,"manual_art":"OPEN","low_poly":"NOT IMPLEMENTED"},"\t"));report.close()
	print("OAK_LOOKS_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
