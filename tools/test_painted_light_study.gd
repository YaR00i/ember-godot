extends SceneTree
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message); printerr("FAIL ", message)
func fingerprint(projection) -> Array:
	var result := []
	for tile in projection._tiles.values():
		var ground: MeshInstance3D = tile.get_node("Ground")
		var collision: ConcavePolygonShape3D = tile.get_node("GroundPhysics/Shape").shape
		result.append([ground.mesh.get_instance_id(), hash(ground.mesh.surface_get_arrays(0)), hash(collision.get_faces())])
	return result
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var scene = load(args[0] if not args.is_empty() else "res://scenes/compact_painted_light_study.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	var deadline := Time.get_ticks_msec() + 60000
	while not scene.ready_for_painted and Time.get_ticks_msec() < deadline: await process_frame
	check(scene.ready_for_painted, "scene prepared")
	if not scene.ready_for_painted: quit(1); return
	var source: Resource = scene.get_node("Map").compact_terrain
	var original: Resource = source.working_copy()
	check(source.same_terrain_data(scene.PaintedFixture.source(source.width,source.depth)), "saved Source matches deterministic fixture")
	check(source.validation_errors().is_empty(), "valid Source")
	check(scene._grass.validation_errors().is_empty() and scene._stone.validation_errors().is_empty(), "valid existing Pattern schema")
	var height: Texture2D = scene.height_texture
	var projection = scene._projection
	check(scene.tuft_points.size() > 100 and scene.tuft_points.size() <= scene.TUFT_LIMIT, "bounded patch cover")
	var material_cache: Dictionary = {}
	var inner_count := 0
	for i in scene.tuft_points.size():
		var p: Vector2 = scene.tuft_points[i]
		var radius: float = scene.tuft_bases[i].x.length()*0.128
		check(scene.tuft_footprint_clear(p,radius,material_cache),"full tuft footprint clear of stone and steep steps")
		var weights: Dictionary = scene.Smooth.material_weights(source,Vector2i(p*16.0),material_cache)
		check(float(weights.get(3,0.0))>=0.6,"root stays on grass side")
		if float(weights.get(3,0.0))>0.99: inner_count+=1
	check(inner_count>100,"grass covers interiors as well as boundaries")
	var triangle_count: int = scene.tuft_visual.multimesh.mesh.get_faces().size() / 3
	check(triangle_count > 0 and triangle_count <= 64, "small tuft geometry budget")
	check(scene.tuft_visual.find_children("*", "CollisionObject3D", true, false).is_empty(), "decorative tufts have no physics")
	var anchors: PackedVector2Array = scene.tuft_points.duplicate()
	for phase in [0.0, 0.25, 0.5, 0.75, 1.0, 0.0]:
		scene.set_phase(phase); await physics_frame; await physics_frame
		check(Array(scene.tuft_fit).min()>0.0,"morph retains every clump")
		check(scene.tuft_points == anchors, "morph keeps scatter stable")
		for i in anchors.size():
			var position: Vector3 = scene.tuft_visual.multimesh.get_instance_transform(i).origin
			var floor: Dictionary = scene.get_node("Map").surface_floor_sample(Vector3(anchors[i].x,8,anchors[i].y))
			# Dummy RenderingServer returns identity for MultiMesh transforms.
			# Forward+ capture verifies the actual GPU instance roots in every phase.
			if DisplayServer.get_name() != "headless":
				check(position.distance_to(floor.position-Vector3.UP*0.005) < 0.001, "tuft roots follow common floor")
		# Actual physics rays on the new rock planes and on both sides of a
		# tile boundary must agree with the shared floor used by the Player.
		for point in [Vector2(1.5,1.6), Vector2(1.9,2.8), Vector2(0.8,2.65), Vector2(3.98,1.4), Vector2(4.02,1.4), Vector2(4.65,1.4)]:
			var from := Vector3(point.x,8.0,point.y)
			var ray := PhysicsRayQueryParameters3D.create(from, Vector3(point.x,-1.0,point.y))
			var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(ray)
			var floor: Dictionary = scene.get_node("Map").surface_floor_sample(from)
			check(not hit.is_empty() and floor.get("solid",false), "rock physics/floor present")
			if not hit.is_empty() and floor.get("solid",false):
				check(absf(hit.position.y - floor.position.y) < 0.003, "rock physics/floor agree in morph")
		var geometry := fingerprint(projection)
		var tuft_mesh: Mesh = scene.tuft_visual.multimesh.mesh
		var tuft_count: int = scene.tuft_visual.multimesh.instance_count
		var floor_before: Dictionary = scene.get_node("Map").surface_floor_sample(Vector3(4.2, 4.0, 4.3))
		for enabled in [false, true]:
			scene.set_painted(enabled); scene.calm_stone = enabled; scene.set_grass(enabled)
			scene.set_tufts(enabled)
			scene.set_grass_masses(enabled)
			scene.set_grass_color(enabled)
			await process_frame
			check(scene.tuft_visual.visible == enabled, "tuft A/B visibility")
			check(scene.tuft_visual.material_override.get_shader_parameter("painterly_enabled") == enabled, "tufts share light mode")
			check(scene.tuft_visual.material_override.get_shader_parameter("material_depth_enabled") == false and scene.depth_material.get_shader_parameter("material_depth_enabled") == true, "only ground traces POM")
			check(fingerprint(projection) == geometry, "looks preserve mesh/collision in morph phases")
			check(scene.tuft_visual.multimesh.mesh == tuft_mesh and scene.tuft_visual.multimesh.instance_count == tuft_count and scene.tuft_points == anchors, "mass lighting does not remesh or scatter")
			check(scene.tuft_visual.material_override.get_shader_parameter("painterly_grass_masses") == enabled and scene.depth_material.get_shader_parameter("painterly_grass_masses") == enabled, "ground and cards share mass lighting")
			check(scene.tuft_visual.material_override.get_shader_parameter("painterly_grass_color") == enabled and scene.depth_material.get_shader_parameter("painterly_grass_color") == enabled, "ground and cards share pigment tint")
			check(scene.get_node("Map").surface_floor_sample(Vector3(4.2, 4.0, 4.3)) == floor_before, "one floor")
			check(scene.height_texture == height and scene.depth_material.get_shader_parameter("material_depth_steps") == 32, "Sol depth retained")
	check(source.same_terrain_data(original), "all Source channels unchanged")
	var stable_geometry:=fingerprint(projection)
	for preset in 3:
		scene.set_lighting_preset(preset)
		check(scene.lighting_preset==preset,"lighting preset selected")
		check(fingerprint(projection)==stable_geometry and source.same_terrain_data(original),"presets do not change geometry or Source")
		check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"presets retain POM depth")
	scene.set_lighting_preset(0)
	check(scene._grass.pixel_relief == 0.0 and scene._grass.micro_relief == 0.0, "grass is flat artwork")
	var walker: EmberPlayer = scene.walker
	var start := walker.global_position
	var endpoints: Array[Vector3] = []
	for enabled in [false, true]:
		walker.global_position = start; walker.velocity = Vector3.ZERO
		walker._step_active = false; walker._step_elapsed = 0.0
		scene.set_painted(enabled)
		for i in 4: await physics_frame
		Input.action_press("move_north", 1.0)
		for i in 25: await physics_frame
		Input.action_release("move_north")
		for i in 4: await physics_frame
		endpoints.append(walker.global_position)
	check(endpoints[0].distance_to(endpoints[1]) < 0.03, "real Player A/B trajectory")
	check(endpoints[0].distance_to(start) > 0.3, "Player actually moves")
	scene.painted_light = false; scene.painted_grass = false; scene.calm_stone = false; scene.grass_tufts = false
	scene.grass_masses = false
	scene.grass_color = false
	scene.grass_low=0.71; scene.grass_tint_strength=0.45; scene.grass_shadow_fill=0.04
	scene.grass_warm=Color(1,0.96,0.9); scene.lighting_preset=2; scene.apply_grass_settings()
	var packed := PackedScene.new(); check(packed.pack(scene) == OK, "pack")
	check(ResourceSaver.save(packed, "user://painted-light-reopen.tscn") == OK, "save")
	var reopened = ResourceLoader.load("user://painted-light-reopen.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(not reopened.painted_light and not reopened.painted_grass and not reopened.calm_stone and not reopened.grass_tufts, "exported settings reopen")
	check(not reopened.grass_masses, "mass lighting choice reopens")
	check(not reopened.grass_color, "pigment choice reopens")
	check(is_equal_approx(reopened.grass_low,0.71) and is_equal_approx(reopened.grass_tint_strength,0.45) and is_equal_approx(reopened.grass_shadow_fill,0.04) and reopened.grass_warm.is_equal_approx(scene.grass_warm) and reopened.lighting_preset==2,"LAB light settings save/reopen")
	reopened.free()
	print("PAINTED_TEST ", "PASS" if errors.is_empty() else errors, " geometry/floor/POM/Source/morph/Player/save-reopen")
	scene.queue_free(); await process_frame; quit(0 if errors.is_empty() else 1)
