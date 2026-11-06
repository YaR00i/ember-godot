extends SceneTree
## Same view and continuous camera sweep for each sample, no scene edits on disk.
var world
var out: String
var result := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	out=OS.get_environment("EMBER_KM_EVIDENCE")
	DirAccess.make_dir_recursive_absolute(out)
	world=load("res://kilometre/location.tscn").instantiate()
	root.add_child(world)
	while not world.ready_to_play:await process_frame
	await create_timer(0.5).timeout
	await world.go_to("meadow")
	world.ui.hide()
	world.rig.fov=70
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	world.set_shape(1)
	world.set_tuft_lod(false)
	world.set_ao(2)
	if "--population" in OS.get_cmdline_user_args():
		world.set_ao(0)
		world.set_tuft_lod(true)
		var valid: bool=await population_samples()
		quit(0 if valid else 1)
		return
	await sample("full")
	world.set_shape(3)
	world.cover.hide()
	world.scenery.hide()
	world.actor.hide()
	for child in world.get_children():
		if child is MeshInstance3D:child.hide()
	await sample("ground_frame")
	world.terrain.hide()
	await sample("sky_frame")
	world.terrain.show()
	world.cover.show()
	world.scenery.show()
	world.actor.show()
	for child in world.get_children():
		if child is MeshInstance3D:child.show()
	world.set_shape(1)
	await sample("full_return")
	world.set_tuft_lod(false)
	await sample("tuft8_a")
	await capture("tuft8")
	world.set_tuft_lod(true)
	await sample("tuft_lod")
	await capture("tuft_lod")
	world.set_tuft_lod(false)
	await sample("tuft8_b")
	for mode in [0,1,2,0]:
		world.set_ao(mode)
		await sample("ao_%d_%d"%[mode,result.size()])
	world.set_fog(true)
	await sample("fog_ao_off")
	await capture("fog_on")
	world.set_fog(false)
	await sample("fog_off_return")
	FileAccess.open(out+"/field.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("FIELD_DONE ",out)
	quit()

func capture(label: String) -> void:
	var yaw: float=world.rig.yaw
	# Sample the real wind and small orbit. Readbacks stay outside timing windows.
	for frame in 12:
		world.rig.yaw=yaw+0.09*sin(TAU*frame/12.)
		await create_timer(0.075).timeout
		await RenderingServer.frame_post_draw
		if frame==0 or label!="fog_on":
			var im:=root.get_texture().get_image()
			im.resize(960,540,Image.INTERPOLATE_LANCZOS)
			im.save_jpg(out+"/%s_%02d.jpg"%[label,frame],0.93)
		if label=="fog_on":break
	world.rig.yaw=yaw

func population_samples() -> bool:
	await sample("empty_a")
	var start:=Time.get_ticks_usec()
	await world.population.populate(world,true)
	result["activation_ms"]=(Time.get_ticks_usec()-start)/1000.
	result["characters"]=world.population.get_child_count()
	if result.characters!=12:
		push_error("Expected 8 NPCs and 4 boars")
		return false
	var before: Vector3=world.population.get_child(0).position
	await sample("8_npc_4_boars")
	result["walk_distance"]=before.distance_to(world.population.get_child(0).position)
	result["on_floor"]=world.population.get_children().filter(func(body):return body.is_on_floor()).size()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+"/population.png")
	await world.population.populate(world,false)
	await sample("empty_b")
	print("POPULATION_DONE ",result.characters," ",result.on_floor," ",out)
	if result.on_floor!=12 or result.walk_distance<0.1:
		push_error("Moving population did not reach the expected test conditions")
		return false
	return true

func sample(label: String) -> void:
	var yaw: float=world.rig.yaw
	for i in 45:await process_frame
	var wall: Array[float]=[]
	var gpu: Array[float]=[]
	var start:=Time.get_ticks_usec()
	var prev:=start
	var peak_ms:=0.
	var peak: Dictionary={}
	while Time.get_ticks_usec()-start<3500000:
		world.rig.yaw=yaw+1.5*sin((Time.get_ticks_usec()-start)*0.000003)
		await process_frame
		var now:=Time.get_ticks_usec()
		wall.append((now-prev)/1000.0)
		prev=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		if wall[-1]>peak_ms:
			peak_ms=wall[-1]
			peak={"seconds":(now-start)/1000000.0,"yaw":world.rig.yaw,"gpu_ms":gpu[-1],
				"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())}
	world.rig.yaw=yaw
	result[label]=world.summary(wall,gpu)
	result[label]["peak_observation"]=peak
	if label.begins_with("tuft"):
		var state=world.meadow.state
		state.readback_done=false
		RenderingServer.call_on_render_thread(state.read_counts)
		while not state.readback_done:await process_frame
		result[label]["lod_instances"]=state.counts.duplicate()
	result[label]["draw_calls"]=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	result[label]["primitives"]=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	FileAccess.open(out+"/field.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
