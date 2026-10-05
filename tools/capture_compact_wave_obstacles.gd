extends SceneTree
## Actual study renderer, fixed view/time, paired images and GPU timestamps.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := (load("res://scenes/compact_wave_obstacle_study.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var study := scene.get_node("PlanarReflection")
	while not study._prepared or study._wave_obstacles == null or not study._wave_obstacles.ready: await process_frame
	var map := scene.get_node("Map") as EmberMapLoader
	var projection := map.get("_visual_surface_projection") as EmberTerrainPilotProjection
	while projection.pending_tile_count()>0: await process_frame
	var field: RefCounted = study._wave_obstacles
	assert(field.patches.size() == 2,"real study must include separate river and sea obstacles")
	var version := projection.column_revision()
	var builds: int = study._fields_build_count
	var starts: int = field.steps_taken
	var atlas_bytes: int = field.atlas.get_data().size()
	for node in scene.find_children("*","CanvasLayer",true,false): node.visible=false
	for node in scene.find_children("*","EmberFollowCamera",true,false): node.set_process(false); node.set_physics_process(false)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.fov=48
	camera.far=1600
	camera.make_current()
	var sea_prop := scene.get_node("Map/Props/SeaWaveDivider") as Node3D
	var sea_target := Vector3(sea_prop.global_position.x,study._water_height,sea_prop.global_position.z)
	camera.position=sea_target+Vector3(55,64,-80)
	camera.look_at(sea_target)
	var output := "user://ember-tests/wave-obstacles"
	DirAccess.make_dir_recursive_absolute(output)
	for place in ["river","sea"]:
		if "--bench-only" in OS.get_cmdline_user_args(): break
		var prop := scene.get_node("Map/Props/WaterContactStone" if place=="river" else "Map/Props/SeaWaveDivider") as Node3D
		var target := Vector3(prop.global_position.x,study._water_height,prop.global_position.z)
		camera.position=target+Vector3(50,70,85) if place=="river" else target+Vector3(55,64,-80)
		camera.look_at(target)
		for mode in [0,1,2]:
			study.obstacle_wave_mode=mode
			study.refresh_water_settings()
			for frame in 48:
				var seconds := float(frame)*0.15
				study._material.set_shader_parameter("preview_time",seconds)
				study._refresh_sea_swash()
				study._refresh_wave_obstacles()
				await process_frame
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				image.save_png(output.path_join("%s-%d-%02d.png" % [place,mode,frame]))
			assert(projection.column_revision()==version and study._fields_build_count==builds)
			if mode==1: assert(field.steps_taken==starts,"baked playback must not run the solver")
			starts=field.steps_taken
	study.obstacle_wave_mode=1
	study._material.set_shader_parameter("preview_time",3.0)
	study.refresh_water_settings()
	var stone := scene.get_node("Map/Props/WaterContactStone") as Node3D
	var original := stone.position
	stone.position.x += 12.0
	study._obstacle_poll_ms=0
	study._refresh_wave_obstacles()
	assert(study._obstacle_runtime_motion and study._wave_obstacles==field)
	assert(study._material.get_shader_parameter("obstacle_patch_count")==0)
	stone.position=original
	study._obstacle_poll_ms=0
	study._refresh_wave_obstacles()
	assert(not study._obstacle_runtime_motion and study._wave_obstacles==field)
	assert(study._material.get_shader_parameter("obstacle_patch_count")==2)
	print("OBSTACLE runtime motion pause/restore, no per-frame bake PASS")
	# Same time/camera/resolution for paired timing; timestamps cover every active
	# viewport. Solver timing is separate and must not be presented as total FPS.
	var viewports: Array[SubViewport]=[study._viewport,study._floor_viewport]
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for viewport in viewports: RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	study._material.set_shader_parameter("preview_time",3.0)
	var measurements := {}
	assert(camera.global_position.y>study._water_height,"benchmark must see the water from above")
	for mode in [0,1,2,2,1,0]:
		study.obstacle_wave_mode=mode
		study.refresh_water_settings()
		for warmup in 16: await process_frame
		var gpu := PackedFloat32Array()
		var cpu := PackedFloat32Array()
		for frame in 64:
			study._material.set_shader_parameter("preview_time",3.0+float(frame)*0.025)
			await process_frame
			await RenderingServer.frame_post_draw
			var value := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			for viewport in viewports:
				if viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
					value+=RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
			gpu.append(value)
			cpu.append(float(field.update_us)/1000.0)
		gpu.sort()
		cpu.sort()
		var result := {"gpu_p50_ms":gpu[32],"gpu_p95_ms":gpu[60],"solver_p50_ms":cpu[32],"solver_p95_ms":cpu[60]}
		if not measurements.has(mode): measurements[mode]=[]
		measurements[mode].append(result)
		print("OBSTACLE_BENCH mode=",mode," ",result)
	var report := {"render_size":root.get_texture().get_image().get_size(),"patches":field.patches.size(),
		"atlas_bytes":atlas_bytes,"build_us":field.build_us,"cache_hit":field.cache_hit,"measurements":measurements}
	var file := FileAccess.open(output.path_join("benchmark.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("OBSTACLE_CAPTURE PASS output=",ProjectSettings.globalize_path(output)," report=",report)
	quit()
