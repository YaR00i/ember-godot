extends "res://kilometre/travel_probe.gd"
## Reproduce the original six-site camera route, then repeat its mountain view.
var out: String
var cases: Array=[]
var focus_events: Array=[]

func run() -> void:
	out=OS.get_environment("EMBER_KM_EVIDENCE")
	DirAccess.make_dir_recursive_absolute(out)
	world=load("res://kilometre/location.tscn").instantiate()
	root.add_child(world)
	while not world.ready_to_play:await process_frame
	await create_timer(0.5).timeout
	root.focus_exited.connect(func():focus_events.append([Time.get_ticks_usec(),false]))
	root.focus_entered.connect(func():focus_events.append([Time.get_ticks_usec(),true]))
	physics_frame.connect(on_physics)
	process_frame.connect(on_process)
	RenderingServer.frame_pre_draw.connect(on_pre_draw)
	RenderingServer.frame_post_draw.connect(on_post_draw)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for key: String in world.MARKS:
		await world.go_to(key)
		for i in 20:await process_frame
		for lens in [40,70]:await measure(key,lens,"original")
	for repeat in 12:
		await world.go_to("mountain")
		for i in 20:await process_frame
		await measure("mountain",40,"repeat_%02d"%repeat)
		await measure("mountain",70,"repeat_%02d"%repeat)
	write()
	print("MOUNTAIN_DONE ",cases.size()," cases, ",events.size()," intervals above 10 ms")
	quit()

func measure(site: String,lens: int,group: String) -> void:
	world.rig.fov=lens
	var yaw: float=world.rig.yaw
	var begin: Vector3=world.actor.position
	var start:=Time.get_ticks_usec()
	var previous:=start
	var wall: Array[float]=[]
	var gpu: Array[float]=[]
	var peak: Dictionary={}
	var maximum:=0.
	var invalid_focus:=0
	var missing_shift:=0
	var shift:=InputEventKey.new()
	shift.physical_keycode=KEY_SHIFT
	shift.pressed=lens==70
	Input.parse_input_event(shift)
	if lens==70:Input.action_press("move_north")
	leg=group+"_"+site+str(lens)
	recent.clear()
	last_process=0
	world.surveying=true
	while Time.get_ticks_usec()-start<2200000:
		world.rig.yaw=yaw+1.7*sin((Time.get_ticks_usec()-start)*0.000003)
		await process_frame
		var now:=Time.get_ticks_usec()
		wall.append((now-previous)/1000.)
		previous=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		invalid_focus+=int(not root.has_focus())
		missing_shift+=int(lens==70 and not Input.is_physical_key_pressed(KEY_SHIFT))
		if wall[-1]>maximum:
			maximum=wall[-1]
			peak={"tick_us":now,"gpu_ms":gpu[-1],"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
				"focus":root.has_focus(),"shift":Input.is_physical_key_pressed(KEY_SHIFT),"position":str(world.actor.position)}
	world.surveying=false
	Input.action_release("move_north")
	shift.pressed=false
	Input.parse_input_event(shift)
	world.rig.yaw=yaw
	var row: Dictionary=world.summary(wall,gpu)
	row.merge({"case":leg,"peak":peak,"unfocused_frames":invalid_focus,"missing_shift_frames":missing_shift,
		"displacement_m":begin.distance_to(world.actor.position),"actual_fov":world.rig._cam.fov})
	cases.append(row)
	leg=""
	write()

func write() -> void:
	var mountain_cases:=cases.filter(func(row):return "_mountain" in row.case)
	var reproduced:=mountain_cases.any(func(row):return row.max>=30.0)
	FileAccess.open(out+"/mountain.json",FileAccess.WRITE).store_string(JSON.stringify({
		"pixels":str(root.size),"scale":root.scaling_3d_scale,"gpu":RenderingServer.get_video_adapter_name(),
		"seed":world.spec.seed,"reproduced_30ms_or_more":reproduced,
		"workers":ProjectSettings.get_setting("threading/worker_pool/max_threads"),"floor":world.terrain.collision.mode,
		"cases":cases,"focus_events":focus_events,"stalls":events},"  "))
