extends SceneTree
var scene
var output: String
var errors: Array[String]=[]
var timings: Array=[]
var changes: Array=[]
func _initialize() -> void: run.call_deferred()
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
func change_count(a: Image,b: Image) -> int:
	var left:=a.get_data();var right:=b.get_data();var count:=0
	for i in range(0,left.size(),4):
		if left[i]!=right[i] or left[i+1]!=right[i+1] or left[i+2]!=right[i+2]:count+=1
	return count
func timing(mode: int) -> void:
	scene.set_presentation(mode);await frames(15)
	var samples: Array[float]=[]
	for i in 45:
		await process_frame
		samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	samples.sort()
	timings.append({"mode":mode,"gpu_median_ms":samples[22],"gpu_p95_ms":samples[42],"vram_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	scene=load("res://scenes/compact_material_looks_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+100000
	while not scene.ready_for_looks and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_looks,"ready")
	if not scene.ready_for_looks:quit(1);return
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	await frames(12)
	var camera: Camera3D=scene.follow_camera._cam
	var camera_before:=camera.global_transform
	var source: Resource=scene._projection.document.working_copy()
	var before_geometry:=geometry()
	var tuft_buffer: PackedFloat32Array=scene.tuft_visual.multimesh.buffer.duplicate()
	var tuft_count: int=scene.tuft_points.size()
	check(tuft_count>9000 and scene.tuft_visual.visible,"accepted grass field is present")
	check(is_equal_approx(scene.grass_low,0.64) and is_equal_approx(scene.grass_shadow_fill,0.07),"accepted grass light retained")
	var height: Texture2D=scene.height_texture
	var colour: Texture2D=scene._stone.albedo_texture
	var look_shader: Shader=scene.depth_shader
	var tuft_material: ShaderMaterial=scene.tuft_visual.material_override
	# The new A must reproduce the real accepted shader on both ground and tufts.
	scene.set_presentation(0)
	var a:=await capture("baseline-a")
	scene.depth_material.shader=scene.accepted_shader;tuft_material.shader=scene.accepted_shader
	var accepted:=await capture("baseline-accepted")
	check(a.get_data()==accepted.get_data(),"A equals accepted field exactly")
	# Compare to the accepted renderer saved before this slice, not only to
	# the current opt-out shader. The path is supplied by the isolated QA runner.
	if OS.get_cmdline_user_args().size()>1:
		var historical:=Shader.new()
		historical.code="#define EMBER_PAINTERLY_STUDY\n#define EMBER_TERRAIN_MATERIAL_DEPTH\n"+FileAccess.get_file_as_string(OS.get_cmdline_user_args()[1])
		scene.depth_material.shader=historical;tuft_material.shader=historical
		var historical_frame:=await capture("baseline-before-slice")
		check(a.get_data()==historical_frame.get_data(),"A equals pre-slice renderer exactly")
	scene.depth_material.shader=look_shader;tuft_material.shader=look_shader
	scene.set_presentation(0)
	check(a.get_data()==(await capture("baseline-return")).get_data(),"A return exact")
	scene.set_light_motion(true)
	var sun_start: Basis=scene.get_node("Map/Look/Sun").global_basis
	await frames(15)
	check(not scene.get_node("Map/Look/Sun").global_basis.is_equal_approx(sun_start),"sun motion advances through real process")
	check(scene._sun_motion_switch.button_pressed,"motion checkbox follows state")
	scene.set_light_motion(false)
	var sun_stop: Basis=scene.get_node("Map/Look/Sun").global_basis
	await frames()
	check(scene.get_node("Map/Look/Sun").global_basis.is_equal_approx(sun_stop) and not scene._sun_motion_switch.button_pressed,"sun motion stops")
	for preset in 3:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			var reference: Image
			for mode in 3:
				scene.set_presentation(mode)
				var image:=await capture("look-%d-%d-%d"%[mode,preset,pose])
				if mode==0:reference=image
				else:
					var count:=change_count(reference,image)
					changes.append({"mode":mode,"preset":preset,"pose":pose,"changed_pixels":count})
					check(count>100,"look alters rendered field")
				check(geometry()==before_geometry and scene._projection.document.same_terrain_data(source),"look preserves Source/mesh/collision")
				check(scene.tuft_visual.multimesh.buffer==tuft_buffer,"no grass scatter or remesh")
				check(camera.global_transform.is_equal_approx(camera_before),"fixed game camera")
				check(scene.height_texture==height and scene._stone.albedo_texture==colour,"POM/colour source retained")
				check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04 and scene.depth_material.get_shader_parameter("material_depth_steps")==32,"POM4cm/32")
	# Independent pixel size and light levels; neither changes geometry/paint.
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_presentation(2)
	for size_m in [0.03125,0.0625,0.125]:
		scene.presentation_pixel_m=size_m;scene.set_presentation(2)
		await capture("pixel-%d"%roundi(size_m*1024.0))
	scene.presentation_pixel_m=0.0625
	for count in [4,8,16]:
		scene.presentation_light_levels=count;scene.set_presentation(2)
		await capture("levels-%d"%count)
	scene.presentation_light_levels=8
	# Identical deterministic sun/camera trajectories for visual motion review.
	for mode in 3:
		scene.set_presentation(mode)
		for frame in 12:
			camera.global_transform=camera_before
			camera.global_position+=Vector3(frame*0.035,0.0,-frame*0.018)
			scene.set_sun_yaw(deg_to_rad(-110.0+frame*4.0))
			await capture("motion-%d-%02d"%[mode,frame])
		camera.global_transform=camera_before
		scene.set_sun_pose(1)
		await timing(mode)
	# Far and grazing views expose unstable grid boundaries without changing Source.
	for mode in 3:
		scene.set_presentation(mode)
		camera.global_transform=camera_before
		camera.global_position+=(camera.global_position-scene.walker.global_position)*0.55
		await capture("far-%d"%mode)
		camera.global_transform=camera_before
		camera.look_at_from_position(Vector3(7.5,1.5,10.0),Vector3(3.8,0.8,4.0))
		await capture("grazing-%d"%mode)
	camera.global_transform=camera_before;scene.set_presentation(0);scene.set_sun_pose(0)
	# Real shadows and no-light controls: no new self-emission in any look.
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	var slot: int=scene._projection.document.palette_material_ids.find("cartoon_grass")
	var profile=scene._grass.duplicate(true)
	for mode in 3:
		scene.set_presentation(mode);sun.light_energy=0.0
		profile.grass_light_shadow_fill=0.07
		scene.Materials.update_grass_light_profile(scene.depth_material,slot,profile);scene._sync_tuft_material()
		var fill:=await capture("zero-light-%d"%mode)
		profile.grass_light_shadow_fill=0.0
		scene.Materials.update_grass_light_profile(scene.depth_material,slot,profile);scene._sync_tuft_material()
		check(fill.get_data()==(await capture("zero-light-no-fill-%d"%mode)).get_data(),"no zero-light emission")
	# Check all roots against the same gameplay floor, then a short real player pass.
	var root_error:=0.0
	for i in tuft_count:
		var p: Vector2=scene.tuft_points[i]
		var floor: Dictionary=scene.get_node("Map").surface_floor_sample(Vector3(p.x,8,p.y))
		root_error=maxf(root_error,scene.tuft_visual.multimesh.get_instance_transform(i).origin.distance_to(floor.position-Vector3.UP*0.005))
	check(root_error<0.001,"all grass roots follow shared floor")
	scene.apply_grass_settings();scene.set_presentation(0);scene.set_lighting_preset(0)
	scene.get_node("Instructions").show();await capture("controls")
	scene.get_node("Instructions").hide();scene.walker.set_physics_process(true)
	scene.follow_camera.set_process(true);scene.follow_camera.set_physics_process(true)
	var contacts:=0;Input.action_press("move_east",1.0)
	for i in 60:
		await physics_frame
		if scene.walker.is_on_floor():contacts+=1
		if i in [0,30,59]:await capture("walk-%02d"%i)
	Input.action_release("move_east");check(contacts>=50,"player retains physical support")
	check(scene._projection.document.same_terrain_data(source),"Source unchanged after walk")
	var report:={"errors":errors,"tufts":tuft_count,"tuft_root_max_error_m":root_error,"player_floor_ticks":contacts,"changes":changes,"timings":timings,"baseline_exact":a.get_data()==accepted.get_data(),"manual_visual_acceptance":"OPEN","geometry":"existing smooth field; B is lighting only"}
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MATERIAL_LOOKS_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
