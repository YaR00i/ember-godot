extends Node
## Opt-in native build probe. No gameplay decisions or persistent authoring state.
const Storage=preload("res://scripts/prototypes/ember_derived_data_cache.gd")
static var started_us:=0
static var active:=false
static var stages:Array=[]
var _file:FileAccess
var _world:Node
var _last_us:=0
var _report_us:=0
var _ready_us:=0
var _phase:=""
var _samples:Array=[]
var _viewports:Array[Viewport]=[]
var _exit_seconds:=0.0
var _spikes:=0

static func enabled()->bool:
	return "--ember-profile" in OS.get_cmdline_user_args()

static func start()->void:
	if not enabled():return
	active=true;started_us=Time.get_ticks_usec();Storage.diagnostics_enabled=true

static func stage(label:String)->void:
	if active:stages.append({"event":"stage","at_ms":(Time.get_ticks_usec()-started_us)/1000.0,"label":label})

func _ready()->void:
	_world=get_parent()
	if "--ember-profile-sphere" in OS.get_cmdline_user_args():
		var anomaly=_world.get_node_or_null("Map/WorldAnomaly")
		if anomaly!=null:anomaly.enabled=true;stage("sphere_enabled_by_probe")
	var directory:="user://startup-logs"
	DirAccess.make_dir_recursive_absolute(directory)
	var path:=directory.path_join("startup-%d-%d.jsonl"%[OS.get_process_id(),Time.get_unix_time_from_system()])
	_file=FileAccess.open(path,FileAccess.WRITE)
	_last_us=Time.get_ticks_usec();_report_us=_last_us
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ember-profile-exit="):_exit_seconds=maxf(1,argument.trim_prefix("--ember-profile-exit=").to_float())
	_emit({"event":"begin","engine":Engine.get_version_info(),"user_dir":OS.get_user_data_dir(),"executable":OS.get_executable_path(),"log":ProjectSettings.globalize_path(path),"viewport":get_viewport().size,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode()})
	print("EMBER_STARTUP_LOG ",ProjectSettings.globalize_path(path))
	_collect_viewports(get_tree().root)

func _collect_viewports(node:Node)->void:
	if node is Viewport and not node in _viewports:
		_viewports.append(node);RenderingServer.viewport_set_measure_render_time(node.get_viewport_rid(),true)
	for child in node.get_children():_collect_viewports(child)

func _emit(entry:Dictionary)->void:
	entry["at_ms"] = entry.get("at_ms",(Time.get_ticks_usec()-started_us)/1000.0)
	if _file!=null:_file.store_line(JSON.stringify(entry))

func _state()->Dictionary:
	var map=_world.get_node_or_null("Map")
	if map==null:return {}
	var projection=map._visual_surface_projection
	var result:={"look":map.world_look,"play_ready":_world._startup_complete,"foliage_pending":0,"instances":0}
	if is_instance_valid(projection):
		result["terrain_pending"]=projection.pending_tile_count()
		result["physics_pending"]=projection.pending_physics_chunk_count()
		result["lod_pending"]=projection.pending_runtime_lod_count()
		result["look_pending"]=projection._look_pending.size()
	for patch in get_tree().get_nodes_in_group("ember_grass_patches"):
		if not map.is_ancestor_of(patch):continue
		if patch.detail_preparation_pending():result.foliage_pending+=1
		if patch._visual!=null and patch._visual.multimesh!=null:result.instances+=patch._visual.multimesh.instance_count
	var anomaly=map.get_node_or_null("WorldAnomaly")
	if anomaly!=null:result["sphere"]={"enabled":anomaly.enabled,"ready":anomaly._prepared,"preparing":anomaly._preparing,"bindings":anomaly._bindings.size(),"status":anomaly.preparation_state}
	return result

static func distribution(values:Array)->Dictionary:
	if values.is_empty():return {}
	var ordered:=values.duplicate();ordered.sort()
	var sum:=0.0
	for value in ordered:sum+=value
	return {"mean":sum/ordered.size(),"p50":ordered[int((ordered.size()-1)*0.50)],"p95":ordered[int((ordered.size()-1)*0.95)],"p99":ordered[int((ordered.size()-1)*0.99)],"max":ordered[-1]}

func _process(_delta:float)->void:
	var now:=Time.get_ticks_usec()
	var wall_ms:=(now-_last_us)/1000.0;_last_us=now
	var cpu:=0.0;var gpu:=0.0
	for viewport in _viewports:
		if not is_instance_valid(viewport):continue
		cpu+=RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
		gpu+=RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
	_samples.append([wall_ms,cpu,gpu,DisplayServer.window_is_focused()])
	if wall_ms>100 and _spikes<16:
		_emit({"event":"long_frame","wall_ms":wall_ms,"render_cpu_ms":cpu,"gpu_ms":gpu,"phase":_phase});_spikes+=1
	if now-_report_us<1000000:return
	_report_us=now
	for event in stages:_emit(event)
	stages.clear()
	_collect_viewports(get_tree().root)
	var state:=_state()
	if state.get("play_ready",false) and _ready_us==0:
		_ready_us=now;_phase="gameplay";_emit({"event":"world_revealed","state":state})
	var walls:Array=[];var cpus:Array=[];var gpus:Array=[];var focused:=0
	for sample in _samples:
		walls.append(sample[0]);cpus.append(sample[1]);gpus.append(sample[2]);focused+=int(sample[3])
	_emit({"event":"frames","phase":_phase,"count":walls.size(),"focused_frames":focused,"wall_ms":distribution(walls),"render_cpu_ms":distribution(cpus),"gpu_ms":distribution(gpus),"gpu_measured":gpu>0,"frame_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000,"draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"state":state,"caches":Storage.diagnostics_snapshot()})
	_samples.clear();_spikes=0
	if _file!=null:_file.flush()
	if now-started_us>600000000:finish("timeout",1)
	elif _ready_us>0 and _exit_seconds>0 and now-_ready_us>=_exit_seconds*1000000:finish("complete",0)

func finish(reason:String,code:int)->void:
	var map=_world.get_node_or_null("Map")
	var projection=map._visual_surface_projection if map!=null else null
	_emit({"event":"end","reason":reason,"state":_state(),"terrain_profile":projection.profile_snapshot() if is_instance_valid(projection) else {},"caches":Storage.diagnostics_snapshot(),"cache_records":Storage.diagnostic_records()})
	# Screenshot readback is deliberately after the measured frame windows.
	if DisplayServer.get_name()!="headless" and _ready_us>0:
		var image_path:=_file.get_path().trim_suffix(".jsonl")+".png" if _file!=null else ""
		if not image_path.is_empty():get_viewport().get_texture().get_image().save_png(image_path)
	if _file!=null:_file.flush();_file.close();_file=null
	get_tree().quit(code)
