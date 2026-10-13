extends SceneTree
const Brush=preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
var scene
var output: String
var errors: Array[String]=[]
var metrics: Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func frames(count:=5) -> void:
	for i in count:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await frames();root.get_texture().get_image().save_png(output.path_join(name+".png"))
func shape_ready() -> void:
	while scene.rebuilding:await process_frame
	await physics_frame;await physics_frame
func parity(label: String) -> void:
	var error:=0.0
	for point in [Vector2(2,1.1875),Vector2(4,2),Vector2(5.75,3.7),Vector2(4,6.4)]:
		var ray:=PhysicsRayQueryParameters3D.create(Vector3(point.x,12,point.y),Vector3(point.x,-1,point.y));ray.exclude=[scene.walker.get_rid()]
		var floor: Dictionary=scene.get_node("Map").surface_floor_sample(ray.from)
		var hit:=root.world_3d.direct_space_state.intersect_ray(ray)
		check(not hit.is_empty(),label+" physics hit")
		if not hit.is_empty():error=maxf(error,hit.position.distance_to(floor.position))
		var pick: Dictionary=scene._projection.pick_ground_top(ray.from,ray.to)
		check(not pick.is_empty() and pick.world.distance_to(floor.position)<0.001,label+" picking parity")
	check(error<0.001,label+" visible/query/physical surface")
	metrics[label]=error
func matrix(stage: int,camera_pose: Transform3D) -> void:
	for material in 2:
		scene.set_diagnostic(material==0)
		for preset in 3:
			for pose in 2:
				scene.set_light(preset,pose);scene.follow_camera._cam.global_transform=camera_pose
				await capture("rule-%d-%d-%d-%d"%[stage,material,preset,pose])
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_terrain_shape_study.tscn").instantiate();scene.shape_mode=0
	scene.get_node("Map").compact_terrain=scene.get_node("Map").compact_terrain.working_copy()
	root.add_child(scene);current_scene=scene
	while not scene.ready_for_shape:await process_frame
	scene.get_node("Instructions").hide();await frames(12)
	scene.follow_camera.set_process(false)
	var camera_pose: Transform3D=scene.follow_camera._cam.global_transform
	var source: Resource=scene.get_node("Map").compact_terrain;var initial: Resource=source.working_copy()
	await matrix(0,camera_pose);parity("before")
	var history:=UndoRedo.new();var brush:=Brush.new()
	brush.configure({"resource":source,"target":weakref(scene.get_node("Map"))},history,scene)
	var started:=Time.get_ticks_usec()
	brush.begin("shape_protect",0.9,1,1,0,16,0,1,0,-99999,"detail","circle",0,false,255)
	brush.stamp(Vector2i(32,19));brush.end()
	while scene._projection.pending_tile_count()>0:await process_frame
	metrics["brush_update_ms"]=(Time.get_ticks_usec()-started)/1000.0
	# Refresh the existing LAB morph owner after changing the same Source.
	scene.choose_shape(0);await shape_ready()
	await matrix(1,camera_pose);parity("after")
	check(source.heights==initial.heights and source.top_materials==initial.top_materials,"Source heights/paint unchanged")
	check(not source.surface_rules.is_empty(),"native uses saved source rules")
	check(is_equal_approx(float(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")),0.04),"POM retained")
	for phase in [0.0,0.25,0.5,0.75,1.0]:
		scene.set_phase(phase);await frames(3);parity("phase%.2f"%phase)
		if phase in [0.5,1.0]:await capture("endpoint-%.1f"%phase)
	scene.set_phase(0);scene.reset_walker();scene.set_light(0,1);scene.set_diagnostic(false)
	scene.follow_camera.set_process(true);await frames(10)
	var axis:=Vector2.RIGHT.rotated(scene.follow_camera.yaw)
	Input.action_press("move_east",axis.x);Input.action_press("move_south",axis.y)
	var contacts:=0
	for tick in 90:
		await physics_frame
		if scene.walker.position.x>5.8:Input.action_release("move_east");Input.action_release("move_south")
		if scene.walker.is_on_floor():contacts+=1
		if tick in [0,60]:await capture("walk-%02d"%tick)
	Input.action_release("move_east");Input.action_release("move_south")
	check(contacts>75 and scene.walker.position.x>4.2,"real Player walk across seam")
	metrics["floor_ticks"]=contacts
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"errors":errors,"metrics":metrics},"\t"));file.close()
	history.free();print("SURFACE_RULES_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
