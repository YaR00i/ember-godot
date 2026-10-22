extends SceneTree
var errors: Array[String]=[]
var output: String
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);printerr("FAIL ",message)
func frames(count:=8) -> void:
	for i in count:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> Image:
	await frames();var image:=root.get_texture().get_image();check(image.save_png(output.path_join(name+".png"))==OK,"capture "+name);return image
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	var path:="res://scenes/compact_environment_material_review.tscn"
	var packed: PackedScene=load(path)
	var scene=packed.instantiate();root.add_child(scene);current_scene=scene
	while not scene.ready_for_play:await process_frame
	scene.player.set_physics_process(false);scene.camera.set_process(false)
	var camera: Camera3D=scene.camera._cam
	var pose:=camera.global_transform;var fov:=camera.fov
	var records: Array=[]
	var exact_count:=0;var edge_rounding: Array=[]
	for preset in 3:
		for side in 2:
			scene.set_lighting(preset,side)
			for view in 3:
				camera.fov=fov;camera.global_transform=pose
				if view==1:camera.fov=40;camera.global_position=Vector3(3,3.1,6.5);camera.look_at(Vector3(2,1.1,2.5))
				if view==2:camera.fov=42;camera.global_position=Vector3(10,8,16);camera.look_at(Vector3(4.5,1.1,4.7))
				var name:="cold-%d-%d-%d"%[preset,side,view]
				var image:=await capture(name)
				if view<2:
					var previous:=Image.load_from_file(output.path_join("after-%d-%d-%d.png"%[preset,side,view]))
					var a:=image.get_data();var b:=previous.get_data()
					if a==b:exact_count+=1
					else:
						var pixels:=0;var maximum:=0
						for i in range(0,a.size(),4):
							var changed:=false
							for channel in 4:
								var difference:=absi(int(a[i+channel])-int(b[i+channel]));maximum=maxi(maximum,difference)
								if difference>0:changed=true
							if changed:pixels+=1
						check(maximum<=1 and pixels<=16,"fresh-process frame bounded edge rounding "+name)
						edge_rounding.append({"frame":name,"pixels":pixels,"maximum_rgb8":maximum})
				records.append({"file":name+".png","preset":preset,"side":side,"view":view})
	# Native shadow response on the new geometry, then exact return.
	scene.set_lighting(1,1);camera.fov=40;camera.global_position=Vector3(3,3.1,6.5);camera.look_at(Vector3(2,1.1,2.5))
	var original:=await capture("shadow-on")
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun");sun.shadow_enabled=false
	var without:=await capture("shadow-off")
	check(original.get_data()!=without.get_data(),"real shadows affect combined rock scene")
	sun.shadow_enabled=true
	check(original.get_data()==(await capture("shadow-return")).get_data(),"shadow return exact")
	var map: EmberMapLoader=scene.get_node("Map")
	var prop: EmberVoxelProp=map.get_node("Props/PaintedRockGroup")
	# Rotate the real object and compare transformed query against physics.
	var previous_transform:=prop.transform
	prop.rotation=Vector3(0.08,0.12,0.03)
	await physics_frame;await physics_frame
	var centre: Vector3=prop.get_node("Mesh").to_global(Vector3(1.52,2.5,1.6))
	var query:=PhysicsRayQueryParameters3D.create(Vector3(centre.x,8,centre.z),Vector3(centre.x,-2,centre.z),1)
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
	var sample:=map.surface_floor_sample(centre)
	check(not hit.is_empty() and sample.get("solid",false) and absf(hit.position.y-sample.position.y)<0.0001,"rotated rock floor equals actual collider")
	prop.transform=previous_transform
	await physics_frame;await physics_frame
	# Real player capsule lands on the same broad top and remains supported.
	scene.player.global_position=Vector3(1.52,3.1,1.6);scene.player.velocity=Vector3.ZERO;scene.player.set_physics_process(true)
	for i in 75:await physics_frame
	check(scene.player.is_on_floor(),"real player lands on accepted rock")
	var support:=map.surface_floor_sample(scene.player.global_position)
	check(support.get("solid",false) and absf(scene.player.global_position.y-support.position.y)<0.02,"capsule support follows real plane, not old rounded height")
	scene.player.set_physics_process(false)
	var file:=FileAccess.open(output.path_join("cold.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"frames":records,"cold_exact_frames":exact_count,"edge_rounding":edge_rounding,"transformed_physics":true,"player_landing":true,"shadow_return_exact":true,"runtime_lab_recipes":false},"\t"));file.close()
	print("ROCK_SHAPE_COLD ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
