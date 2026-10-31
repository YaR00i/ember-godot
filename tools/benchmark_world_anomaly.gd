extends SceneTree
## Read-only performance comparison. Use a disposable checkout/user directory.
## mode=compare|off|low|voxel; optional diagnostics=1 and out=<absolute directory>.
## Forward+ required. Forces the detailed exterior in memory; never saves the map.
var report: Dictionary = {"startup":{},"frames":[],"startup_phases":{}}
var output := "user://anomaly-performance"
var mode := "compare"
var scene: Node
var map: EmberMapLoader
var sphere: Node3D
var projection: Node
var viewports: Array[Viewport] = []
var diagnostics := false
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int(values.size()*0.95)],"max":values.back()}
func checkpoint() -> void:
	var file := FileAccess.open(output.path_join(mode+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
func display_stats() -> Dictionary:
	var counts := {"bindings":sphere._bindings.size(),"visible_bindings":0,"grass_tufts_submitted":0,"voxel_grass_tufts_submitted":0,"potential_vertices":0}
	for binding: Dictionary in sphere._bindings:
		if not binding.visual.visible or binding.visual.layers == 0: continue
		counts.visible_bindings += 1
		var mesh: Mesh = binding.visual.mesh if binding.visual is MeshInstance3D else binding.visual.multimesh.mesh
		var instances: int = binding.visual.multimesh.instance_count if binding.visual is MultiMeshInstance3D else 1
		if binding.visual is MultiMeshInstance3D:
			counts.grass_tufts_submitted += instances
			if binding.voxel_only: counts.voxel_grass_tufts_submitted += instances
		for surface in mesh.get_surface_count(): counts.potential_vertices += mesh.surface_get_array_len(surface)*instances
	return counts
func measure(label: String, capture := false) -> void:
	var preparation_count: int = sphere.preparations
	var target_count: int = sphere.Correspondence.builds
	await frames(90)
	var gpu: Array = [];var cpu: Array = [];var gaps: Array = []
	var primitives: Array = [];var draws: Array = []
	var subviews: Dictionary = {}
	for viewport in viewports: subviews[str(viewport.get_path())] = []
	var previous := Time.get_ticks_usec()
	var samples := 0
	var sample_deadline := Time.get_ticks_usec()+2000000
	while samples < 180 or Time.get_ticks_usec() < sample_deadline:
		await process_frame
		samples += 1
		var now := Time.get_ticks_usec();gaps.append((now-previous)/1000.0);previous=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		primitives.append(root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
		draws.append(root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))
		for viewport in viewports: subviews[str(viewport.get_path())].append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
	var process_cost: Array = []
	for i in 30:
		var began := Time.get_ticks_usec();sphere._process(0.0);process_cost.append(Time.get_ticks_usec()-began)
	var row := {"case":label,"samples":samples,"gpu_ms":stats(gpu),"render_cpu_ms":stats(cpu),"frame_ms":stats(gaps),"fps_median":1000.0/stats(gaps).median,"primitives":stats(primitives),"draw_calls":stats(draws),"sphere_unchanged_call_us":stats(process_cost),"display":display_stats(),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"preparations":sphere.preparations,"target_builds":sphere.Correspondence.builds,"subviews":{}}
	for key in subviews: row.subviews[key] = stats(subviews[key])
	if sphere.preparations != preparation_count or sphere.Correspondence.builds != target_count:
		report.invalid = "Unexpected preparation during measurement: "+label
		push_error("ANOMALY_INVALID: "+report.invalid);checkpoint();quit(2);return
	report.frames.append(row)
	print("ANOMALY_FRAME ",JSON.stringify(row));checkpoint()
	if capture:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(label+".png"))
func set_mode(value: int) -> void:
	sphere.enabled = value > 0;sphere.inner_look = maxi(value,1)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("mode="): mode = arg.trim_prefix("mode=")
		if arg.begins_with("out="): output = arg.trim_prefix("out=")
		if arg == "diagnostics=1": diagnostics = true
	if mode not in ["compare","off","low","voxel"] or (mode == "off" and diagnostics):
		push_error("ANOMALY_INVALID: unsupported mode/diagnostics combination");quit(2);return
	if DisplayServer.get_name() == "headless":
		push_error("ANOMALY_INVALID: native Forward+ rendering required for FPS");quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	report.environment = {"user_data":OS.get_user_data_dir(),"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"size":DisplayServer.window_get_size(),"max_fps":Engine.max_fps,"low_processor_usage":OS.low_processor_usage_mode}
	print("ANOMALY_ENV ",JSON.stringify(report.environment))
	var began := Time.get_ticks_usec()
	var packed := load("res://scenes/landscape_compact.tscn") as PackedScene
	report.startup.resource_load_ms = (Time.get_ticks_usec()-began)/1000.0
	var phase := Time.get_ticks_usec()
	scene = packed.instantiate()
	report.startup.instantiate_ms = (Time.get_ticks_usec()-phase)/1000.0
	map = scene.get_node("Map");projection = null;sphere = map.get_node("WorldAnomaly")
	report.authored_settings = {"world_look":map.world_look,"sphere_enabled":sphere.enabled,"inner_look":sphere.inner_look,"sphere_position":str(sphere.position)}
	map.world_look = 0
	set_mode(0 if mode == "off" else 2 if mode == "voxel" else 1)
	phase = Time.get_ticks_usec();root.add_child(scene);current_scene = scene
	report.startup.add_scene_ms = (Time.get_ticks_usec()-phase)/1000.0
	projection = map.get_node("DerivedCompactWorldTerrain")
	var previous := Time.get_ticks_usec()
	var label := "initialization"
	var deadline := Time.get_ticks_msec()+180000
	while not scene._startup_complete and Time.get_ticks_msec()<deadline:
		await process_frame
		var now := Time.get_ticks_usec();var gap := (now-previous)/1000.0;previous=now
		var record: Dictionary = report.startup_phases.get(label,{"wall_ms":0.0,"max_frame_ms":0.0,"frames":0})
		record.wall_ms += gap;record.max_frame_ms = maxf(record.max_frame_ms,gap);record.frames += 1
		report.startup_phases[label] = record
		label = str(scene._startup_status().text)
	report.startup.total_ms = (Time.get_ticks_usec()-began)/1000.0
	report.startup.ready = scene._startup_complete
	if mode != "off" and (not sphere._prepared or sphere._bindings.is_empty()):
		push_error("ANOMALY_INVALID: sphere was not prepared");checkpoint();quit(2);return
	report.startup.geometry_profile = projection.profile_snapshot()
	report.startup.tree_builds = load("res://scripts/ember_tree_look_bake.gd").builds
	report.startup.tree_disk_hits = load("res://scripts/ember_tree_look_bake.gd").disk_hits
	report.startup.tree_carrier_keys = load("res://scripts/ember_tree_look_bake.gd")._anomaly_meshes.size()
	report.startup.target_builds = sphere.Correspondence.builds
	report.startup.target_disk_hits = sphere.Correspondence.cache_hits
	if sphere.has_meta("performance_probe"): report.startup.probe = sphere.get_meta("performance_probe")
	print("ANOMALY_STARTUP ",JSON.stringify(report.startup));checkpoint()
	if not scene._startup_complete: quit(1);return
	scene._player.set_physics_process(false);scene._party_followers.set_physics_process(false);scene._player.camera_rig.set_process(false)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for node in scene.find_children("*","SubViewport",true,false):
		viewports.append(node);RenderingServer.viewport_set_measure_render_time(node.get_viewport_rid(),true)
	if mode == "compare":
		for state in [0,1,2]:
			set_mode(state)
			await measure(["off","low","voxel"][state],true)
		set_mode(0);await measure("off_repeat")
	else: await measure(mode,true)
	# One variable per diagnostic: layers only; no meshes/materials/Source rebuilt.
	if diagnostics:
		set_mode(2)
		for kind in ["grass_growth","leaf_growth","all_grass"]:
			var hidden: Array[Dictionary] = []
			for binding: Dictionary in sphere._bindings:
				var selected: bool = binding.visual is MultiMeshInstance3D and (binding.voxel_only or kind == "all_grass") if kind != "leaf_growth" else binding.materials[0].get_shader_parameter("ember_anomaly_grow_cells") == true
				if selected: hidden.append({"node":binding.visual,"layers":binding.visual.layers});binding.visual.layers=0
			await measure("voxel_without_"+kind)
			for item in hidden: item.node.layers = item.layers
	checkpoint();sphere.set_process(false);quit()
