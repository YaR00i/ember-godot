extends SceneTree
var scene
var output: String
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message); printerr("FAIL ",message)
func frames(count: int) -> void:
	for i in count: await process_frame
	await RenderingServer.frame_post_draw
func capture(label: String) -> Image:
	await frames(6)
	var image := root.get_texture().get_image()
	check(image.save_png(output.path_join(label+".png")) == OK,"capture "+label)
	return image
func geometry() -> Array:
	var result := []
	for tile in scene._projection._tiles.values():
		result.append(hash(tile.get_node("Ground").mesh.surface_get_arrays(0)))
		for shape in tile.get_node("GroundPhysics").get_children():
			if shape is CollisionShape3D and shape.shape is ConcavePolygonShape3D:
				result.append(hash(shape.shape.get_faces()))
	return result
func freeze_material_time() -> void:
	# The inherited scene contains a small water patch. Freeze its animation
	# for pixel-exact comparisons; neither A nor B changes the water material.
	for node in scene.find_children("*","MeshInstance3D",true,false):
		if node.mesh == null: continue
		for surface in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(surface)
			if not material is ShaderMaterial: continue
			for uniform in material.shader.get_shader_uniform_list():
				if uniform.name == "preview_time": material.set_shader_parameter("preview_time",0.0)
func run() -> void:
	output = OS.get_cmdline_user_args()[0]; DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scenes/compact_bevel_light_study.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	var deadline := Time.get_ticks_msec()+60000
	while not scene.ready_for_bevel and Time.get_ticks_msec()<deadline: await process_frame
	check(scene.ready_for_bevel,"ready")
	if not scene.ready_for_bevel: quit(1); return
	scene.get_node("Instructions").hide(); freeze_material_time(); await frames(20)
	var original: Resource = scene._projection.document.working_copy()
	var original_geometry := geometry()
	var floor: Dictionary = scene.get_node("Map").surface_floor_sample(Vector3(1,8,2))
	var height: Texture2D = scene.height_texture
	for pose in 2:
		scene.set_sun(pose)
		var name: String = ["side","back"][pose]
		scene.set_bevel(false); var before := await capture(name+"-before")
		var variant: Shader = scene.depth_material.shader
		scene.depth_material.shader = scene.Materials.compact_terrain_depth_shader()
		var sol := await capture(name+"-sol-original")
		check(before.get_data()==sol.get_data(),"disabled accent = original Sol pixels")
		scene.depth_material.shader = variant
		scene.set_bevel(true); var after := await capture(name+"-after")
		check(before.get_data()!=after.get_data(),"visible bevel accent "+name)
		scene.set_bevel(false); var returned := await capture(name+"-return")
		check(before.get_data()==returned.get_data(),"A return exact "+name)
		check(geometry()==original_geometry,"mesh/collision unchanged")
		check(scene.get_node("Map").surface_floor_sample(Vector3(1,8,2))==floor,"floor unchanged")
	check(scene.height_texture==height and scene.steps==32 and is_equal_approx(scene.amplitude_m,0.04),"Sol POM parameters retained")
	# Read actual GPU depth with both lighting states. No visual depth inference.
	var probe := MeshInstance3D.new(); var quad := QuadMesh.new(); quad.size=Vector2(2,2)
	probe.mesh=quad; probe.extra_cull_margin=1024
	var material := ShaderMaterial.new(); var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled; uniform sampler2D depth_image : hint_depth_texture, filter_nearest; void vertex(){POSITION=vec4(VERTEX.xy,1.0,1.0);} void fragment(){float d=textureLod(depth_image,SCREEN_UV,0.0).r; vec4 p=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,d,1.0); uint bits=uint(round(clamp(-p.z/p.w,0.0,160.0)*100000.0));vec3 c=vec3(float((bits>>16u)&255u),float((bits>>8u)&255u),float(bits&255u))/255.0; ALBEDO=mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),c));}"
	material.shader=shader; material.render_priority=127; probe.material_override=material
	scene.follow_camera._cam.add_child(probe)
	var environment: Environment = scene.get_node("Map/Look/WorldEnvironment").environment
	var tonemap := environment.tonemap_mode; environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	scene.set_bevel(false); var depth_a := await capture("depth-before")
	scene.set_bevel(true); var depth_b := await capture("depth-after")
	check(depth_a.get_data()==depth_b.get_data(),"GPU depth exact before/after")
	probe.queue_free(); environment.tonemap_mode=tonemap; await frames(3)
	scene.get_node("Map/Look/Sun").light_energy=0
	scene.set_bevel(false); var dark_a := await capture("sun-off-before")
	scene.set_bevel(true); var dark_b := await capture("sun-off-after")
	check(dark_a.get_data()==dark_b.get_data(),"no accent without sun")
	check(scene._projection.document.same_terrain_data(original),"Source unchanged")
	scene.bevel_enabled=false
	var packed := PackedScene.new(); check(packed.pack(scene)==OK,"pack")
	check(ResourceSaver.save(packed,"user://bevel-light-reopen.tscn")==OK,"save")
	var reopened = ResourceLoader.load("user://bevel-light-reopen.tscn","",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(not reopened.bevel_enabled,"export reopens"); reopened.free()
	var report := {"errors":errors,"source_unchanged":scene._projection.document.same_terrain_data(original),"gpu_depth_exact":depth_a.get_data()==depth_b.get_data(),"camera":"EmberFollowCamera distance9.5 polar0.95 yaw0.35 fov40","resolution":"1600x900","scope":"Light-only on original Sol Source/artwork/POM"}
	var file := FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("BEVEL_NATIVE ","PASS" if errors.is_empty() else errors)
	scene.queue_free(); await process_frame; await process_frame; quit(0 if errors.is_empty() else 1)
