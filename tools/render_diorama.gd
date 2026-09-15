extends SceneTree
## QA only. Fixed camera, frozen water, isolated saves; never publishes Source.
const SurfaceProjection = preload("res://scripts/ember_voxel_surface_projection.gd")
const Prefab = preload("res://scripts/ember_voxel_prefab.gd")
const SurfaceMesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const SurfaceMaterials = preload("res://scripts/ember_voxel_surface_materials.gd")
var label := "baseline"
var mode := "corner"
var night := false
var diagnostic := false
var unlit := false
var frozen_time := 3.25
var profile := 8
var warm_moon := false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg == "--night": night = true
		if arg == "--diagnostic": diagnostic = true
		if arg == "--unlit": unlit = true
		if arg == "--warm-moon": warm_moon = true
		if arg.begins_with("--time="): frozen_time = float(arg.trim_prefix("--time="))
		if arg.begins_with("--profile="): profile = int(arg.trim_prefix("--profile="))
	_run.call_deferred()

func freeze_fixture_physics(node: Node) -> void:
	# Rendering fixture only: keep runtime avatars at identical authored spawn
	# while async Surface prepares. This is not an input/physics acceptance test.
	node.set_physics_process(false)

func corner_source() -> EmberVoxelModelResource:
	var source := EmberVoxelModelResource.new()
	source.model_id = "graphics_corner_fixture"
	source.size_blocks = Vector3i(8,2,7)
	source.height_voxels = 32
	source.palette = PackedColorArray([Color.TRANSPARENT,Color("71945d"),Color("c5a36e"),Color("598d99")])
	var grid := source.grid_size()
	source.voxels.resize(grid.x*grid.y*grid.z)
	source.surface_fill_levels.resize(grid.x*grid.z)
	source.surface_fill_materials.resize(grid.x*grid.z)
	source.surface_fill_palette.resize(grid.x*grid.z)
	for z in grid.z:
		for x in grid.x:
			var coast := 60.0 + sin(float(z)*0.036)*10.0
			var h := clampi(int(22.0-(float(x)-coast)*0.4),4,22)
			var color := 1 if float(x)<coast-8.0 else 2
			for y in h: source.voxels[x+z*grid.x+y*grid.x*grid.z] = color
			if h<16:
				var column := x+z*grid.x
				source.surface_fill_levels[column] = 16
				source.surface_fill_materials[column] = 1
				source.surface_fill_palette[column] = 3
	return source

func bounds(node: Node3D) -> AABB:
	var result := AABB()
	var valid := false
	for visual in node.find_children("*","MeshInstance3D",true,false):
		var box: AABB = (visual as MeshInstance3D).get_aabb()
		var transform := Transform3D.IDENTITY
		var cursor: Node3D = visual
		while cursor != node:
			transform = cursor.transform * transform
			cursor = cursor.get_parent() as Node3D
		box = transform * box
		result = result.merge(box) if valid else box
		valid = true
	return result

func object(scene: Node3D, path: String, position: Vector3, width: float) -> Node3D:
	var prop := (load(path) as PackedScene).instantiate() as Node3D
	# Published geometry is reused; no generator, publication or Source mutation.
	prop.set_script(null)
	var box := bounds(prop)
	var scale_factor := width/maxf(box.size.x,0.01)
	prop.scale = Vector3.ONE*scale_factor
	prop.position = position - Vector3(box.get_center().x,box.position.y,box.get_center().z)*scale_factor
	scene.add_child(prop)
	return prop

func corner() -> Node3D:
	var scene := Node3D.new()
	scene.name = "DioramaQA"
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.43,0.57,0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.77,0.84,0.8)
	env.environment.ambient_light_energy = 0.35
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-58,-32,0)
	sun.light_color = Color(1,0.96,0.87)
	sun.light_energy = 0.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 800
	scene.add_child(sun)
	var terrain := SurfaceProjection.new()
	terrain.position.y = -16
	scene.add_child(terrain)
	terrain.configure(corner_source(),16.0,Vector2i(8,7),null,false)
	object(scene,"res://prefabs/voxels/vox_tree_522448705.tscn",Vector3(31,6,39),61)
	object(scene,"res://prefabs/voxels/vox_fan_rock.tscn",Vector3(76,1,69),17)
	object(scene,"res://prefabs/voxels/vox_fan_rock.tscn",Vector3(91,-2,74),11)
	# Six instances of the published wooden section; only fixture transforms.
	for i in 6:
		var plank := object(scene,"res://prefabs/voxels/vox_shape_block_15328782_canvas_117422242_part_32556083_0.tscn",Vector3(54+i*7.5,7,35),7.0)
		var box := bounds(plank)
		plank.scale.z *= 4.5
		plank.position.z = 35-box.get_center().z*plank.scale.z
	object(scene,"res://prefabs/voxels/vox_fan_barrel.tscn",Vector3(50,7,80),10)
	if not label.begins_with("baseline"):
		(load("res://scripts/ember_lights.gd") as Script).call("apply_diorama_environment",env.environment,sun)
	return scene


func agent_water() -> Node3D:
	# Real authored Surface data, cropped around its water basin for deterministic
	# visual QA without loading unrelated gameplay systems.
	var scene := Node3D.new()
	scene.name = "AgentWaterQA"
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.43, 0.57, 0.60)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.77, 0.84, 0.80)
	env.environment.ambient_light_energy = 0.35
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-58, -32, 0)
	sun.light_color = Color(1.0, 0.96, 0.87)
	sun.light_energy = 0.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 800
	scene.add_child(sun)
	var source := load("res://content/world_surfaces/agent_sandbox_surface.tres") as EmberVoxelModelResource
	var shore_field := SurfaceMesher.build_water_shore_field(source)
	var mesh := SurfaceMesher.build_region(
		source, Vector3i(32, 0, 224), Vector3i(96, source.grid_size().y, 96),
		1.0 / float(source.normalized_density()), false, true, -1, shore_field,
	)
	for surface_index in mesh.get_surface_count():
		var surface_name := mesh.surface_get_name(surface_index)
		mesh.surface_set_material(
			surface_index,
			SurfaceMaterials.water_material() if surface_name == "water"
			else SurfaceMaterials.foam_material() if surface_name == "water_foam"
			else SurfaceMaterials.opaque_material(),
		)
	var visual := MeshInstance3D.new()
	visual.name = "AuthoredAgentWaterCrop"
	visual.mesh = mesh
	visual.scale = Vector3.ONE * 16.0
	scene.add_child(visual)
	(load("res://scripts/ember_lights.gd") as Script).call("apply_diorama_environment", env.environment, sun)
	return scene

func freeze_water(scene: Node) -> void:
	for visual in scene.find_children("*","MeshInstance3D",true,false):
		var mesh: Mesh = visual.mesh
		if mesh == null: continue
		for i in mesh.get_surface_count():
			var material: Material = visual.get_active_material(i)
			if material is ShaderMaterial and material.shader != null and "TIME" in material.shader.code:
				var frozen := material.duplicate() as ShaderMaterial
				var shader := Shader.new()
				shader.code = material.shader.code.replace("TIME",str(frozen_time))
				frozen.shader = shader
				frozen.set_shader_parameter("preview_time",frozen_time)
				visual.set_surface_override_material(i,frozen)

func capture(scene: Node3D, camera: Camera3D, tag: String, eye: Vector3, target: Vector3) -> void:
	camera.position = eye
	camera.look_at(target)
	RenderingServer.camera_set_transform(camera.get_camera_rid(),camera.global_transform)
	for i in 35: await process_frame
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://art/lighting/qa")
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("%s-%s%s-%s.png" % [label,mode,"-night" if night else "",tag])
	var image := root.get_texture().get_image()
	var result := image.save_png(path)
	print("CAPTURE ",path," size=",image.get_size()," result=",result)
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	for i in 120:
		await process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
	gpu.sort(); cpu.sort()
	print("METRICS ",label," ",mode," ",tag," night=",night," gpu_ms_median=",gpu[60]," cpu_render_ms_median=",cpu[60]," draw_calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," objects=",Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)," video_bytes=",Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280,900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1280,900)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	node_added.connect(freeze_fixture_physics)
	var scene: Node3D
	if mode == "corner": scene = corner()
	elif mode == "agent-water": scene = agent_water()
	else:
		var progress := root.get_node("EmberExploreProgress")
		progress.set_meta("world_canvas_storage_root","user://ember-tests/graphics-world-%d" % Time.get_ticks_usec())
		progress.set_meta("test_pier_storage_root","user://ember-tests/graphics-pier-%d" % Time.get_ticks_usec())
		var paths := {"world":"res://scenes/world_canvas.tscn","pier":"res://scenes/test_pier.tscn","fan":"res://scenes/fan_town.tscn","combat":"res://scenes/combat_lab.tscn"}
		var path: String = paths[mode]
		scene = (load(path) as PackedScene).instantiate() as Node3D
		root.add_child(scene)
		for node in scene.find_children("*","Node",true,false): node.set_physics_process(false)
		scene.set_physics_process(false)
		current_scene = scene
		if scene.has_node("CanvasLayer"): scene.get_node("CanvasLayer").hide()
		if scene.has_node("Map"):
			scene.get_node("Map").set_lighting_test_profile(profile)
			print("LIGHT_PROFILE requested=",profile," actual=",scene.get_node("Map").omni_shadow_active_count())
	var deadline := Time.get_ticks_msec()+120000
	if scene == null: printerr("FAIL QA scene creation"); quit(1); return
	while Time.get_ticks_msec()<deadline:
		var complete := true
		for node in scene.find_children("*","Node3D",true,false):
			if node.has_method("is_projection_complete") and not node.is_projection_complete(): complete = false
			if node.has_method("pending_physics_chunk_count") and node.pending_physics_chunk_count() > 0: complete = false
		if complete: break
		await process_frame
	if Time.get_ticks_msec()>=deadline: printerr("FAIL projection timeout"); quit(1); return
	freeze_water(scene)
	if night:
		for node in scene.find_children("*","DirectionalLight3D",true,false):
			node.light_color = Color(1,0.78,0.52) if warm_moon else Color(0.48,0.64,1)
			node.light_energy = 0.22
			if warm_moon: node.name = "Moon"
		for node in scene.find_children("*","WorldEnvironment",true,false):
			node.environment.ambient_light_color = Color(0.08,0.18,0.38)
			node.environment.ambient_light_energy = 0.12
			node.environment.background_color = Color(0.025,0.045,0.08)
		var lamp := EmberLights.make_omni("QALamp",Vector3(51,17,56),Color(1,0.69,0.34),3,1,true,16,1,1)
		scene.add_child(lamp)
	if diagnostic:
		for node in scene.find_children("*","DirectionalLight3D",true,false): node.shadow_enabled = false
	if unlit:
		var shader := Shader.new()
		shader.code = "shader_type spatial; render_mode unshaded; void fragment(){ ALBEDO=COLOR.rgb; }"
		var material := ShaderMaterial.new()
		material.shader = shader
		for visual in scene.find_children("*","MeshInstance3D",true,false):
			if not visual.mesh is ArrayMesh: continue
			for i in visual.mesh.get_surface_count():
				if visual.mesh.surface_get_name(i) not in ["water","water_foam"]: visual.set_surface_override_material(i,material)
	var camera := Camera3D.new()
	camera.fov = 38
	camera.near = 0.5
	camera.far = 2400
	scene.add_child(camera)
	camera.make_current()
	if mode == "corner":
		await capture(scene,camera,"near",Vector3(188,156,200),Vector3(59,12,54))
		await capture(scene,camera,"overview",Vector3(245,238,269),Vector3(59,10,54))
	elif mode == "agent-water":
		await capture(scene,camera,"near",Vector3(170,105,365),Vector3(80,5,273))
		await capture(scene,camera,"overview",Vector3(220,175,420),Vector3(80,3,273))
	elif mode == "world":
		await capture(scene,camera,"near",Vector3(385,133,340),Vector3(210,0,208))
		await capture(scene,camera,"overview",Vector3(520,500,580),Vector3(192,0,200))
	elif mode == "pier":
		await capture(scene,camera,"near",Vector3(392,255,427),Vector3(177,15,165))
		await capture(scene,camera,"overview",Vector3(610,540,680),Vector3(192,0,192))
	elif mode == "fan":
		var focus: Vector3 = scene.get_node("Map").spawn_world()
		await capture(scene,camera,"near",focus+Vector3(145,185,218),focus+Vector3(0,10,0))
		await capture(scene,camera,"overview",Vector3(755,650,780),Vector3(256,0,256))
	else:
		await capture(scene,camera,"near",Vector3(19,22,27),Vector3(5,1,5))
		await capture(scene,camera,"overview",Vector3(26,32,37),Vector3(5,1,5))
	print("PASS DIORAMA_RENDER")
	quit()
