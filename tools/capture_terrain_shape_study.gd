extends SceneTree
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
var scene
var output: String
var errors: Array[String]=[]
var measurements: Dictionary={}
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func frames(count:=5) -> void:
	for i in count:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await frames();root.get_texture().get_image().save_png(output.path_join(name+".png"))
func choose(mode: int) -> void:
	scene.choose_shape(mode)
	while scene.rebuilding:await process_frame
	await physics_frame;await physics_frame
func parity(label: String) -> void:
	var maximum:=0.0;var pick_error:=0.0
	for p in [Vector2(2,1.2),Vector2(4,2),Vector2(5.35,3.7),Vector2(4,4),Vector2(4,6.4),Vector2(6,6.4),Vector2(3.98,3.98)]:
		var from:=Vector3(p.x,12,p.y);var to:=Vector3(p.x,-1,p.y)
		var floor: Dictionary=scene.get_node("Map").surface_floor_sample(from)
		var ray:=PhysicsRayQueryParameters3D.create(from,to);ray.exclude=[scene.walker.get_rid()]
		var hit:=root.world_3d.direct_space_state.intersect_ray(ray)
		check(not hit.is_empty(),label+" physical hit")
		if not hit.is_empty():maximum=maxf(maximum,hit.position.distance_to(floor.position))
		var pick: Dictionary=scene._projection.pick_ground_top(from,to)
		check(not pick.is_empty(),label+" brush pick")
		if not pick.is_empty():pick_error=maxf(pick_error,pick.world.distance_to(floor.position))
	check(maximum<0.001 and pick_error<0.001,label+" floor/physics/pick parity")
	var seam_error:=0.0
	for i in range(1,128):
		var half:=0 if i<64 else 1
		seam_error=maxf(seam_error,absf(Smooth.corner(scene._projection._smooth_field(Vector2i(0,half)),64,i)-Smooth.corner(scene._projection._smooth_field(Vector2i(1,half)),64,i)))
		seam_error=maxf(seam_error,absf(Smooth.corner(scene._projection._smooth_field(Vector2i(half,0)),i,64)-Smooth.corner(scene._projection._smooth_field(Vector2i(half,1)),i,64)))
	check(seam_error<0.0001,label+" morph seam continuity")
	# Navigation uses the same installed field; evaluate its sampled centre.
	var grid: Dictionary=scene._projection._build_navigation_grid()
	var samples: Array[int]=[]
	for z in [20,24,28]:
		for x in [20,24,28]:samples.append(roundi(Smooth.sample(scene._projection._smooth_field(Vector2i.ZERO),Vector2(x,z))-scene._projection.document.origin_y)-1)
	samples.sort();var expected:=samples[4]
	check(grid.heights[1+grid.width]==expected,label+" navigation derived surface")
	measurements[label]={"physics_error_m":maximum,"pick_error_m":pick_error,"seam_error_voxels":seam_error,"rebuild_ms":scene.rebuild_ms}
func run() -> void:
	output=OS.get_cmdline_user_args()[0];DirAccess.make_dir_recursive_absolute(output)
	scene=load("res://scenes/compact_terrain_shape_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+90000
	while not scene.ready_for_shape and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_shape,"fixture ready")
	if not scene.ready_for_shape:quit(1);return
	await frames(20)
	scene.get_node("Instructions").hide();scene.follow_camera.set_process(false)
	var camera: Camera3D=scene.follow_camera._cam;camera.make_current();var camera_pose:=camera.global_transform
	var before: Resource=scene._projection.document.working_copy()
	for mode in [0,1,2]:
		await choose(mode);camera.global_transform=camera_pose
		parity("mode%d"%mode)
		for material in 2:
			scene.set_diagnostic(material==0)
			for preset in 3:
				for pose in 2:
					scene.set_light(preset,pose)
					await capture("shape-%d-%d-%d-%d"%[mode,material,preset,pose])
					check(camera.global_transform.is_equal_approx(camera_pose),"fixed game camera")
					check(scene._projection.document.same_terrain_data(before),"Source unchanged in comparisons")
					check(is_equal_approx(float(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")),0.04),"POM retained")
	await choose(1);scene.set_diagnostic(false);scene.set_light(0,1)
	for phase in [0.0,0.25,0.5,0.75,1.0]:
		scene.set_phase(phase);await frames(3);parity("phase%.2f"%phase)
		if phase in [0.5,1.0]:await capture("endpoint-%.1f"%phase)
	scene.set_phase(0);scene.reset_walker();await frames(10)
	scene.get_node("Instructions").show();await capture("controls");scene.get_node("Instructions").hide()
	var controls: Node=scene.get_node("Instructions/ShapeControls")
	var ground: MeshInstance3D=scene._projection._tiles[Vector2i.ZERO].get_node("Ground")
	var old_mesh: int=ground.mesh.get_instance_id()
	controls.get_node("Strength").value=0.6;controls.get_node("Radius").select(1)
	await frames(2)
	check(ground.mesh.get_instance_id()==old_mesh,"draft controls do not remesh on small input")
	controls.get_node("Apply").pressed.emit()
	while scene.rebuilding:await process_frame
	await frames(3);parity("control-adjusted")
	check(is_equal_approx(scene.rounding_strength,0.6) and scene.rounding_radius_cells==2,"explicit Apply consumes controls")
	controls.get_node("Strength").value=1.0;controls.get_node("Radius").select(2)
	controls.get_node("Apply").pressed.emit()
	while scene.rebuilding:await process_frame
	await frames(3)
	# Actual EmberPlayer controller: a 3-second pass up the mild slope across x=4 tile seam.
	scene.walker.position=Vector3(3.0,8,6.4)
	scene.walker.position.y=scene.get_node("Map").surface_floor_sample(scene.walker.global_position).position.y+0.04
	scene.follow_camera.set_process(true);await frames(12)
	var start: Vector3=scene.walker.global_position;var contacts:=0;var gaps:=0.0
	var axis:=Vector2.RIGHT.rotated(scene.follow_camera.yaw)
	Input.action_press("move_east",axis.x);Input.action_press("move_south",axis.y)
	for tick in 150:
		await physics_frame
		if scene.walker.global_position.x>5.8:
			Input.action_release("move_east");Input.action_release("move_south")
		if scene.walker.is_on_floor():contacts+=1
		var floor: Dictionary=scene.get_node("Map").surface_floor_sample(scene.walker.global_position)
		if floor.solid:gaps=maxf(gaps,absf(scene.walker.global_position.y-floor.position.y))
		if tick in [0,60,120]:await capture("walk-%03d"%tick)
	Input.action_release("move_east");Input.action_release("move_south")
	var end: Vector3=scene.walker.global_position
	check(end.x>4.2 and contacts>100,"real Player crosses tile seam on slope with floor support")
	check(gaps<0.12,"walking support stays on rendered surface")
	measurements["walk"]={"start":str(start),"end":str(end),"floor_ticks":contacts,"ticks":150,"max_gap_m":gaps}
	check(scene._projection.document.same_terrain_data(before),"Source unchanged after morph and walk")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"measurements":measurements,"errors":errors,"matrix":"A/B/C x plain/material x evening/day/night x back/side; fixed game camera"},"\t"));file.close()
	print("TERRAIN_SHAPE_NATIVE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
