extends SceneTree
## Timestamp signals on the real game loop. Records are written after each leg.
var world
var leg := ""
var events: Array = []
var recent: Array = []
var last_process := 0
var before_draw := 0
var after_draw := 0
var physics_first := 0
var physics_last := 0
var physics_count := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var out:=OS.get_environment("EMBER_KM_EVIDENCE")
	DirAccess.make_dir_recursive_absolute(out)
	world=load("res://kilometre/location.tscn").instantiate()
	root.add_child(world)
	while not world.ready_to_play:await process_frame
	await create_timer(0.5).timeout
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	physics_frame.connect(on_physics)
	process_frame.connect(on_process)
	RenderingServer.frame_pre_draw.connect(on_pre_draw)
	RenderingServer.frame_post_draw.connect(on_post_draw)
	if "--clock-marks" in OS.get_cmdline_user_args():await clock_marks()
	for pair in [["village","mountain"],["mountain","village"]]:
		leg=pair[0]+"_"+pair[1]
		last_process=0
		recent.clear()
		await world.traverse(root,pair[0],pair[1])
		leg=""
		world.save_report(out)
		FileAccess.open(out+"/stalls.json",FileAccess.WRITE).store_string(JSON.stringify(events,"  "))
	world.report["over_10_ms"]=events.size()
	world.report["floor_mode"]=world.terrain.collision.mode
	world.report["worker_limit"]=ProjectSettings.get_setting("threading/worker_pool/max_threads")
	world.save_report(out)
	if "--clock-marks" in OS.get_cmdline_user_args():await clock_marks()
	print("TRAVEL_TRACE ",events.size()," long intervals")
	quit()

func clock_marks() -> void:
	for i in 8:
		await process_frame
		print("CLOCK_MARK ",Time.get_ticks_usec())

func on_pre_draw() -> void:before_draw=Time.get_ticks_usec()
func on_post_draw() -> void:after_draw=Time.get_ticks_usec()
func on_physics() -> void:
	physics_last=Time.get_ticks_usec()
	if physics_count==0:physics_first=physics_last
	physics_count+=1

func on_process() -> void:
	var now:=Time.get_ticks_usec()
	if leg!="" and world.surveying and last_process!=0:
		var item: Dictionary={"wall_ms":(now-last_process)/1000.,
			"pre_draw_ms":(before_draw-last_process)/1000.,"post_draw_ms":(after_draw-last_process)/1000.,
			"first_physics_ms":(physics_first-last_process)/1000. if physics_count else null,
			"last_physics_ms":(physics_last-last_process)/1000. if physics_count else null,
			"physics_steps":physics_count,"x":world.actor.position.x,"z":world.actor.position.z,
			"grass_cell":str(world.meadow.cell),"collision_cell":str(world.scenery.last_cell)}
		if now-last_process>10000:
			events.append({"leg":leg,"end_tick_us":now,"previous":recent.duplicate(),"frame":item})
		recent.append(item)
		if recent.size()>2:recent.pop_front()
	last_process=now
	physics_count=0
