extends SceneTree
var scene
var output: String
var errors: Array[String]=[]
var measurements: Array=[]
var timings: Array=[]
var walk_results: Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func frames(count:=8) -> void:
	for i in count:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> Image:
	await frames();var image:=root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"capture "+name)
	return image
func geometry() -> int:
	var result: Array=[]
	for tile in scene._projection._tiles.values():
		result.append(hash(tile.get_node("Ground").mesh.surface_get_arrays(0)))
		result.append(hash(tile.get_node("GroundPhysics/Shape").shape.get_faces()))
	return hash(result)

func silhouette_measurement(label: String) -> Dictionary:
	# Render the actual existing body meshes in a disposable unlit mask viewport.
	# Projected AABBs include empty capsule corners; do not call them pixel silhouettes.
	var result: Dictionary=scene.measurements()
	result["kai_projected_aabb_height_px"]=result.kai_height_px
	result["kai_projected_aabb_frame_share"]=result.kai_frame_share
	var viewport:=SubViewport.new();viewport.size=root.size;viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var world:=WorldEnvironment.new();world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color.BLACK
	viewport.add_child(world)
	var camera:=Camera3D.new();camera.transform=scene.follow_camera._cam.global_transform
	camera.fov=scene.follow_camera._cam.fov;camera.near=0.05;camera.far=250.0
	viewport.add_child(camera);camera.make_current()
	var kai: MeshInstance3D=scene.walker.get_node("Viz")
	var mira: MeshInstance3D=scene.followers.get_node("PartyFollower_mira/Body")
	for pair in [[kai,Color.WHITE],[mira,Color.CYAN]]:
		var body:=MeshInstance3D.new();body.mesh=pair[0].mesh;body.transform=pair[0].global_transform
		var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=pair[1];body.material_override=material;viewport.add_child(body)
	await frames(4)
	var mask:=viewport.get_texture().get_image();mask.save_png(output.path_join("body-mask-"+label+".png"))
	for pair in [["kai",kai],["mira",mira]]:
		var bounds: Rect2=scene.projected_body(pair[1],scene.follow_camera._cam)
		var lo:=Vector2i(mask.get_size());var hi:=Vector2i(-1,-1)
		for y in range(maxi(0,floori(bounds.position.y)),mini(mask.get_height(),ceili(bounds.end.y)+1)):
			for x in range(maxi(0,floori(bounds.position.x)),mini(mask.get_width(),ceili(bounds.end.x)+1)):
				var c:=mask.get_pixel(x,y)
				var match_colour: bool=c.g>0.8 and c.b>0.8 and (c.r>0.8 if pair[0]=="kai" else c.r<0.2)
				if match_colour:lo=lo.min(Vector2i(x,y));hi=hi.max(Vector2i(x,y))
		check(hi.y>=lo.y,"actual body silhouette pixels")
		result[pair[0]+"_height_px"]=hi.y-lo.y+1
		result[pair[0]+"_frame_share"]=float(hi.y-lo.y+1)/float(mask.get_height())
		result[pair[0]+"_silhouette_rect"]=[lo.x,lo.y,hi.x-lo.x+1,hi.y-lo.y+1]
	viewport.queue_free();await frames(3)
	result["pixel_measurement_method"]="actual body meshes; isolated unlit mask, excluding labels/markers"
	return result
func freeze(enabled: bool) -> void:
	scene.walker.set_physics_process(not enabled);scene.followers.set_physics_process(not enabled)
	scene.follow_camera.set_process(not enabled);scene.follow_camera.set_physics_process(not enabled)
func timing(mode: int) -> void:
	await frames(15);var samples: Array[float]=[]
	for i in 45:
		await process_frame;samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	samples.sort();timings.append({"mode":mode,"median_ms":samples[22],"p95_ms":samples[42],"vram_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
func ray_floor(point: Vector2) -> float:
	var at:=Vector3(point.x,8.0,point.y)
	var sample: Dictionary=scene.get_node("Map").surface_floor_sample(at)
	var query:=PhysicsRayQueryParameters3D.create(at,Vector3(point.x,-2.0,point.y),1)
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty(),"voxel floor ray")
	return absf(hit.position.y-sample.position.y) if not hit.is_empty() else INF
func walk(mode: int) -> void:
	freeze(true);scene.reset_actors();scene.set_comparison(mode);await frames()
	freeze(false)
	var start: Vector3=scene.walker.global_position
	var contacts:=0;var max_error:=0.0;var crossed:=false
	# Use the existing real movement controller across the Source-authored step.
	var camera_yaw: float=scene.follow_camera.yaw
	scene.follow_camera.yaw=0.0;Input.action_press("move_north",1.0)
	for i in 110:
		await physics_frame
		if scene.walker.global_position.z<=scene.walk_route[-1].y:Input.action_release("move_north")
		if scene.walker.is_on_floor():contacts+=1
		if scene.walker.global_position.z<scene.Fixture.STEP_AREA.position.y/16.0:crossed=true
		if i in [0,35,70,109]:await capture("walk-%d-%03d"%[mode,i])
		if scene.walker.is_on_floor():
			var floor: Dictionary=scene.get_node("Map").surface_floor_sample(scene.walker.global_position)
			max_error=maxf(max_error,absf(scene.walker.global_position.y-floor.position.y))
	Input.action_release("move_north");scene.follow_camera.yaw=camera_yaw
	freeze(true)
	check(contacts>=90 and crossed,"player crosses step with unchanged dimensions")
	walk_results.append({"mode":mode,"floor_ticks":contacts,"crossed_step":crossed,"floor_max_error_m":max_error,"travel_m":start.distance_to(scene.walker.global_position)})
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	scene=load("res://scenes/compact_diorama_readability_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+120000
	while not scene.ready_for_diorama and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_diorama,"ready")
	if not scene.ready_for_diorama:quit(1);return
	scene.get_node("Instructions").hide();freeze(true);scene.reset_actors();scene.set_comparison(0);await frames(12)
	check(scene.get_node("Map").compact_ground_style==0,"voxel baseline first")
	check(scene.walker.get_node("Status").text.begins_with("Кай"),"canonical Kai name in real player")
	check(scene.followers.get_node("PartyFollower_mira/Status").text.begins_with("Мира"),"canonical Mira name")
	check(scene.walker.progress_state.active_hero_ids==["protagonist","mira"],"private canonical pair")
	check(scene.find_children("*","CharacterBody3D",true,false).size()==1,"one real player/controller")
	var source: Resource=scene._projection.document.working_copy()
	var before:=geometry();var buffer: PackedFloat32Array=scene.tuft_visual.multimesh.buffer.duplicate()
	var capsule: CapsuleShape3D=scene.walker.get_node("Shape").shape
	check(is_equal_approx(capsule.height,1.8) and is_equal_approx(capsule.radius,0.15625),"canonical Kai capsule unchanged")
	var height: Texture2D=scene.height_texture
	var grass_hash:=hash(scene._grass.pixels)
	var sun: Transform3D=scene.get_node("Map/Look/Sun").global_transform
	var floor_error:=0.0
	for p in [Vector2(4.25,7.4),Vector2(4.25,6.6),Vector2(4.25,6.35),Vector2(4.25,6.05),Vector2(8.1,8.0)]:floor_error=maxf(floor_error,ray_floor(p))
	check(floor_error<0.001,"physics and Map share exact voxel step floor")
	var a:=await capture("comparison-0")
	measurements.append(await silhouette_measurement("0"))
	for mode in [1,2,3]:
		scene.set_comparison(mode);await capture("comparison-%d"%mode)
		measurements.append(await silhouette_measurement(str(mode)))
		check(geometry()==before and scene._projection.document.same_terrain_data(source),"Source/terrain geometry unchanged")
		check(scene.tuft_visual.multimesh.buffer==buffer and hash(scene._grass.pixels)==grass_hash,"same accepted grass and paint")
		check(scene.height_texture==height and scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM retained")
		check(scene.get_node("Map/Look/Sun").global_transform==sun,"fixed light")
		check(is_equal_approx(capsule.height,1.8) and scene.walker.scale==Vector3.ONE,"no hero shrink")
		check(scene.door.get_node("Mesh").global_transform.is_equal_approx(scene.door.get_node("Collision/Shape").global_transform),"door visual/collider share scale and offsets")
		await timing(mode)
	scene.set_comparison(0);await timing(0)
	check(a.get_data()==(await capture("comparison-return")).get_data(),"return A exact")
	scene.set_camera_candidate(2);await capture("camera-alternative")
	measurements.append(await silhouette_measurement("alternative"))
	scene.set_camera_candidate(1)
	# Matched camera translation on identical actor positions and light.
	for mode in 4:
		scene.set_comparison(mode)
		var original: Transform3D=scene.follow_camera._cam.global_transform
		for i in 10:
			scene.follow_camera._cam.global_transform=original
			scene.follow_camera._cam.global_position+=Vector3(i*0.04,0.0,-i*0.025)
			await capture("motion-%d-%02d"%[mode,i])
		scene.follow_camera._cam.global_transform=original
	# All roots stay on voxel floor; no smooth-only cached support is used.
	var root_error:=0.0
	for i in scene.tuft_points.size():
		var p: Vector2=scene.tuft_points[i]
		var sample: Dictionary=scene.get_node("Map").surface_floor_sample(Vector3(p.x,8.0,p.y))
		root_error=maxf(root_error,scene.tuft_visual.multimesh.get_instance_transform(i).origin.distance_to(sample.position-Vector3.UP*0.005))
	check(root_error<0.001,"every accepted grass root follows active voxel floor")
	await walk(0);await walk(3)
	scene.reset_actors();scene.set_comparison(1);scene.get_node("Instructions").show();await capture("controls")
	var report:={"errors":errors,"measurements":measurements,"timings":timings,"walk":walk_results,"root_max_error_m":root_error,"floor_ray_error_m":floor_error,"architecture_probe_available":scene.architecture_probe_available,"manual_visual_acceptance":"OPEN","source_unchanged":scene._projection.document.same_terrain_data(source)}
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("DIORAMA_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
