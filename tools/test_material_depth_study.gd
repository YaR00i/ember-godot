extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message);printerr("FAIL ",message)
func fingerprint(projection) -> Dictionary:
	var result: Dictionary={}
	for key: Vector2i in projection._tiles:
		var tile: Node3D=projection._tiles[key]
		var ground: MeshInstance3D=tile.get_node("Ground")
		var shape: ConcavePolygonShape3D=tile.get_node("GroundPhysics/Shape").shape
		result[key]=[ground.mesh.get_instance_id(),hash(ground.mesh.surface_get_arrays(0)),shape.get_instance_id(),hash(shape.get_faces())]
	return result
func run() -> void:
	var scene=load("res://scenes/compact_material_depth_study.tscn").instantiate();root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+60000
	while not scene.ready_for_depth and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_depth,"study prepared");if not scene.ready_for_depth:quit(1);return
	var map=scene.get_node("Map");var projection=map._visual_surface_projection
	var source: Resource=map.compact_terrain.working_copy()
	var material_id: int=scene.depth_material.get_instance_id()
	var coverage_id: int=scene.coverage_texture.get_instance_id()
	var old_pattern=Materials.load_compact_terrain_variant("cartoon_stone")
	check(old_pattern.pattern_size_m!=scene._depth_stone.pattern_size_m,"private artwork does not mutate shared Pattern")
	var cache: Dictionary={}
	for point in [Vector2i(7,7),Vector2i(43,30),Vector2i(64,29),Vector2i(80,64)]:
		var weights:=Smooth.material_weights(source,point,cache)
		check(absf(scene.coverage_image.get_pixelv(point).r-float(weights.get(1,0.0)))<0.000001,"derived coverage uses same owner/kernel")
	for phase in [0.0,0.25,0.5,0.75,1.0,0.0]:
		scene.set_phase(phase);await physics_frame;await physics_frame
		var geometry:=fingerprint(projection)
		check(scene.reference_attribute_bytes==0,"metric projection needs no frozen morph coordinates")
		var navigation: PackedVector3Array=projection.navigation_path(Vector3(0.5,2,0.5),Vector3(2.5,2,0.5),32)
		var samples: Array=[]
		for p in [Vector3(0.7,4,1.0),Vector3(2.65,4,2.5),Vector3(3.98,4,2.6),Vector3(4.02,4,2.6)]:
			samples.append([projection.floor_surface_sample(p),projection.pick_ground_top(p,p-Vector3.UP*5)])
		for enabled in [false,true,false,true]:
			scene.set_depth(enabled);await process_frame;await physics_frame
			check(scene.depth_material.shader==(scene.depth_shader if enabled else scene.baseline_shader),"actual A/B shader path")
			check(fingerprint(projection)==geometry,"effect preserves mesh and collision in every appearance")
			check(projection.navigation_path(Vector3(0.5,2,0.5),Vector3(2.5,2,0.5),32)==navigation,"navigation unchanged by decorative depth")
			for index in samples.size():
				var p: Vector3=[Vector3(0.7,4,1.0),Vector3(2.65,4,2.5),Vector3(3.98,4,2.6),Vector3(4.02,4,2.6)][index]
				check(projection.floor_surface_sample(p)==samples[index][0],"floor unchanged by decorative depth")
				check(projection.pick_ground_top(p,p-Vector3.UP*5)==samples[index][1],"picking unchanged by decorative depth")
			check(map.compact_terrain.same_terrain_data(source),"Source and all painted/water channels immutable")
			check(scene.coverage_texture.get_instance_id()==coverage_id,"A/B does not regenerate coverage texture")
	var geometry:=fingerprint(projection)
	var camera: Camera3D=scene.get_node("Camera3D")
	for i in 12:
		camera.rotate_y(0.01);await process_frame
	check(scene.texture_build_count==2 and fingerprint(projection)==geometry,"camera does not remesh or run CPU texture jobs")
	check(scene.depth_material.get_instance_id()==material_id,"one private material across all appearances")
	# Real controller playback at fixed geometry, with identical start/input.
	var walker: EmberPlayer=scene.walker
	var start:=walker.global_position
	var endpoints: Array[Vector3]=[]
	for enabled in [false,true]:
		walker.global_position=start;walker.velocity=Vector3.ZERO;walker._step_active=false;walker._step_elapsed=0.0
		scene.set_depth(enabled)
		for i in 4:await physics_frame
		Input.action_press("move_east",1.0)
		for i in 30:await physics_frame
		Input.action_release("move_east")
		for i in 4:await physics_frame
		endpoints.append(walker.global_position)
		check(walker.global_position.distance_to(start)>0.3,"existing Player walks in both A/B states")
	print("MATERIAL_DEPTH_WALK endpoints=",endpoints," delta=",endpoints[0].distance_to(endpoints[1]))
	check(endpoints[0].distance_to(endpoints[1])<0.03,"A/B leaves real walking trajectory unchanged")
	scene.amplitude_m=0.0;scene.apply_depth();check(scene.depth_material.shader==scene.baseline_shader,"zero amplitude restores actual baseline")
	scene.amplitude_m=0.027;scene.steps=48;scene.depth_enabled=false
	var packed:=PackedScene.new();check(packed.pack(scene)==OK,"study pack")
	check(ResourceSaver.save(packed,"user://material-depth-reopen.tscn")==OK,"study save")
	var reopened=ResourceLoader.load("user://material-depth-reopen.tscn","",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(is_equal_approx(reopened.amplitude_m,0.027) and reopened.steps==48 and not reopened.depth_enabled,"study exported settings reopen")
	reopened.free()
	check(ResourceSaver.save(source,"user://material-depth-source.res")==OK,"source save")
	var read=ResourceLoader.load("user://material-depth-source.res","",ResourceLoader.CACHE_MODE_IGNORE)
	check(read.same_terrain_data(source),"ordinary Source serialization unchanged")
	print("MATERIAL_DEPTH ","PASS" if errors.is_empty() else errors," Source/paint/water/physics/picking/3 appearances/off/zero/Save-Reopen/no camera jobs")
	scene.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
