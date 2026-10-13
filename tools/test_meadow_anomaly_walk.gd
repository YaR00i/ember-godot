extends SceneTree
const Map=preload("res://scripts/ember_map_loader.gd")
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
var scene
var player: EmberPlayer
var errors: Array[String]=[]
var measurements: Array[Dictionary]=[]
var capture:=false
var outputs:="C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs"
var frames:="C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/work/meadow-walk-frames"
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func release_input() -> void:
	for action in ["move_west","move_east","move_north","move_south"]:Input.action_release(action)
func height_at(point: Vector2) -> float:
	var floor: Dictionary=scene.get_node("Map").surface_floor_sample(Vector3(point.x,30,point.y))
	return floor.position.y
func settle(point: Vector2) -> void:
	release_input();scene.playing=false;scene.set_phase(0.0);player._cancel_step();player.velocity=Vector3.ZERO
	player.position=Vector3(point.x,height_at(point)+0.03,point.y)
	for i in 15:await physics_frame;player._physics_process(1.0/Engine.physics_ticks_per_second)
func feet_gap() -> float:
	return player.position.y-height_at(Vector2(player.position.x,player.position.z))
func standing_case(hz: int,carry: bool) -> void:
	Engine.physics_ticks_per_second=hz;scene.carry_support_enabled=carry
	await settle(Vector2(27.25,29.25))
	var max_gap:=0.0;var min_gap:=0.0;var unsupported:=0
	var start:=player.position;var min_y:=start.y;var max_y:=start.y
	for i in hz*4:
		await physics_frame
		var phase:=float(i)/(hz*2-1) if i<hz*2 else float(hz*4-1-i)/(hz*2-1)
		scene.set_phase(phase);player._physics_process(1.0/hz)
		var gap:=feet_gap();max_gap=maxf(max_gap,gap);min_gap=minf(min_gap,gap)
		unsupported+=int(not player.is_on_floor());min_y=minf(min_y,player.position.y);max_y=maxf(max_y,player.position.y)
	var record:={"case":"standing","hz":hz,"carry":carry,"min_gap_m":min_gap,"max_gap_m":max_gap,"unsupported_ticks":unsupported,"vertical_range_m":max_y-min_y,"horizontal_drift_m":Vector2(player.position.x-start.x,player.position.z-start.z).length()}
	measurements.append(record);print("MEADOW_CASE ",record)
	if carry:
		check(min_gap>=-0.018 and max_gap<0.045,"standing floor contact at "+str(hz))
		check(record.horizontal_drift_m<0.035 and max_y-min_y>0.15,"standing follows rising/lowering ground")
func walk_case(hz: int,from: Vector2,to: Vector2,label: String) -> void:
	Engine.physics_ticks_per_second=hz;scene.carry_support_enabled=true;await settle(from)
	var direction:=(to-from).normalized();var length:=from.distance_to(to)
	var min_gap:=0.0;var max_gap:=0.0;var unsupported:=0
	Input.action_press("move_east" if direction.x>=0 else "move_west",absf(direction.x))
	Input.action_press("move_south" if direction.y>=0 else "move_north",absf(direction.y))
	var total:=ceili((length/3.0+0.35)*hz)
	for i in total:
		await physics_frame
		scene.set_phase((1.0-cos(float(i)/maxi(total-1,1)*TAU))*0.5)
		player._physics_process(1.0/hz)
		var gap:=feet_gap();min_gap=minf(min_gap,gap);max_gap=maxf(max_gap,gap);unsupported+=int(not player.is_on_floor())
	var end:=Vector2(player.position.x,player.position.z)
	var travel:=(end-from).dot(direction)
	var record:={"case":label,"hz":hz,"travel_m":travel,"needed_m":length,"min_gap_m":min_gap,"max_gap_m":max_gap,"unsupported_ticks":unsupported}
	measurements.append(record);print("MEADOW_CASE ",record)
	check(travel>=length-0.2,"walk crosses "+label+" at "+str(hz))
	check(min_gap>=-0.04 and max_gap<0.27,"walk stays above physical terrain "+label)
	release_input()
	for i in ceili(hz*0.3):await physics_frame;player._physics_process(1.0/hz)
	check(player.is_on_floor() and absf(feet_gap())<0.04 and not player._step_active,"walk ends supported without a stuck step "+label)
func ceiling_case() -> void:
	Engine.physics_ticks_per_second=60;await settle(Vector2(27.25,29.25))
	# Start at the lower voxel phase, then try raising the mound back up.
	scene.set_phase(1.0)
	for i in 12:await physics_frame;player._physics_process(1.0/60.0)
	var ceiling:=StaticBody3D.new();var col:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(2,0.1,2);col.shape=shape;ceiling.add_child(col)
	var actor_height: float=(player.get_node("Shape").shape as CapsuleShape3D).height
	ceiling.position=player.position+Vector3(0,actor_height+0.07,0);scene.add_child(ceiling)
	await physics_frame;await physics_frame
	var previous: float=scene.phase;var blocked: int=scene.blocked_phases
	scene.set_phase(0.0)
	check(scene.phase==previous and scene.blocked_phases==blocked+1,"ceiling pauses phase before crushing player")
	ceiling.queue_free();await process_frame;await physics_frame
	scene.set_phase(0.0);check(scene.phase==0.0,"phase can resume after ceiling removal")
	print("MEADOW_CASE ceiling pause/resume")
func image_capture(name: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(outputs.path_join(name))==OK,"capture "+name);print("CAPTURE ",name)
func run() -> void:
	capture="--capture-meadow" in OS.get_cmdline_user_args()
	scene=load("res://scenes/compact_meadow_anomaly_walk_study.tscn").instantiate();root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+150000
	while not scene.ready_for_morph and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_morph and is_instance_valid(scene.walker),"map and real EmberPlayer prepared")
	if not scene.ready_for_morph:quit(1);return
	player=scene.walker;player.set_physics_process(false);scene.set_physics_process(false)
	var map:=scene.get_node("Map") as EmberMapLoader;var source: Resource=map.compact_terrain;var before: Resource=source.working_copy()
	check(map.compact_ground_style==1 and source.width==1024 and source.depth==768,"large smooth map stays smooth")
	var ordinary:=Map.new();check(ordinary.smooth_column_limit()==Smooth.MAX_COLUMNS,"ordinary map guard unchanged");ordinary.free()
	check(map.smooth_column_limit()==786432,"study limit explicit")
	check(source.column_value("heights",source.column_index(42*16,22*16))>=280,"mountain retained off-centre")
	check(source.column_value("water_levels",source.column_index(15*16,21*16))>source.column_value("heights",source.column_index(15*16,21*16)),"river contains water")
	var flowing:=0
	for flow: Vector2 in source.water_flow:
		if flow.length()>0.01:flowing+=1
	check(flowing>0,"river uses existing flow channel");print("MEADOW_FLOW flowing_blocks=",flowing)
	if capture:
		(scene.get_node("Camera3D") as Camera3D).make_current();await image_capture("meadow-map-overview.png")
		player.camera_rig._cam.make_current()
	await standing_case(60,false)
	for hz in [30,60,120]:
		await standing_case(hz,true)
		await walk_case(hz,Vector2(23,29),Vector2(31,29),"forward")
		await walk_case(hz,Vector2(31,29),Vector2(23,29),"reverse")
	await walk_case(60,Vector2(23,26),Vector2(31,32),"diagonal")
	await walk_case(60,Vector2(34,32),Vector2(42,32),"foothill-edge")
	await ceiling_case()
	Engine.physics_ticks_per_second=60
	check(source.same_terrain_data(before),"walking/morph preserve source, materials and river")
	check(scene.carry_count>0,"actual support changes exercised")
	# Saved study parameters survive; transient player/state/morph nodes do not.
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"study pack")
	var path:="user://meadow-walk-reopen.tscn";check(ResourceSaver.save(packed,path)==OK,"save study")
	var reopened=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	check(reopened.walk_test_enabled and reopened.walk_route==scene.walk_route and reopened.get_node("Map").smooth_column_limit()==786432 and not reopened.has_node("StudyPlayer"),"reopen saved setup without transient actors");reopened.free()
	if capture and errors.is_empty():
		await settle(Vector2(23,29));scene.follow_camera._cam.make_current()
		await image_capture("meadow-walk-start.png")
		DirAccess.make_dir_recursive_absolute(frames)
		# Continuous native physics and the real controller; no actor teleports.
		player.set_physics_process(true);scene.set_physics_process(true);scene.set_demo_walking(true)
		var min_x: float=player.position.x;var max_x:=min_x;var min_gap:=0.0;var max_gap:=0.0
		for i in 80:
			for j in 6:await physics_frame
			await process_frame;await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();image.resize(960,540,Image.INTERPOLATE_LANCZOS);image.save_png(frames.path_join("frame_%03d.png"%i))
			min_x=minf(min_x,player.position.x);max_x=maxf(max_x,player.position.x)
			min_gap=minf(min_gap,feet_gap());max_gap=maxf(max_gap,feet_gap())
			if i in [20,40,60]:await image_capture("meadow-walk-%d.png"%i)
		scene.set_demo_walking(false)
		player.set_physics_process(false);scene.set_physics_process(false)
		check(max_x-min_x>6.0 and min_gap>=-0.04 and max_gap<0.27,"continuous native controller playback crosses and stays on floor")
		measurements.append({"case":"continuous-native","travel_range_m":max_x-min_x,"min_gap_m":min_gap,"max_gap_m":max_gap})
	print("MEADOW_METRIC max_phase_ms=",scene.worst_phase_us/1000.0," carry_count=",scene.carry_count," blocked_phases=",scene.blocked_phases)
	var report:={"cases":measurements,"errors":errors,"max_phase_ms":scene.worst_phase_us/1000.0,"carry_count":scene.carry_count,"blocked_phases":scene.blocked_phases}
	var file:=FileAccess.open(outputs.path_join("meadow-walk-physics-"+("native" if capture else "headless")+".json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MEADOW_WALK ","PASS" if errors.is_empty() else errors)
	release_input();scene.queue_free();await process_frame;await process_frame;quit(0 if errors.is_empty() else 1)
