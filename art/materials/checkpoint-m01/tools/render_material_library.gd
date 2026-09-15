extends SceneTree
const STAND = preload("res://scenes/material_library_stand.tscn")
var errors := PackedStringArray()

func _init() -> void:
	_run.call_deferred()

func wait_frames(count: int = 30) -> void:
	for i in count: await process_frame
	await RenderingServer.frame_post_draw

func capture(name_text: String) -> void:
	await wait_frames()
	var image := root.get_texture().get_image()
	var path := "res://art/materials/qa/"+name_text+".png"
	var result := image.save_png(path)
	print("CAPTURE ",path," size=",image.get_size()," result=",result)
	if result != OK: errors.append("capture failed "+name_text)

func pixel_probe(preset: String, options: Dictionary = {}, blockers := false, light_mode := "none", reopen := false) -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment_node := WorldEnvironment.new()
	environment_node.environment = Environment.new()
	environment_node.environment.background_mode = Environment.BG_COLOR
	environment_node.environment.background_color = Color(0.01,0.01,0.01)
	environment_node.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_node.environment.ambient_light_energy = 0.0
	viewport.add_child(environment_node)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3
	camera.position = Vector3(0,0,4)
	viewport.add_child(camera)
	camera.current = true
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.8,1.8,0.4)
	box.mesh = mesh
	box.material_override = load("res://scripts/ember_material_library.gd").create(preset,options)
	if reopen:
		var path := "user://material_library_native_reopen.tres"
		if ResourceSaver.save(box.material_override,path) != OK: errors.append("native save failed")
		box.material_override = ResourceLoader.load(path,"ShaderMaterial",ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
		if box.material_override == null: errors.append("native reopen failed")
		DirAccess.remove_absolute(path)
	viewport.add_child(box)
	if light_mode != "none":
		var light := DirectionalLight3D.new()
		light.light_color = Color.WHITE
		light.light_energy = 0.4
		light.light_specular = 1.0
		light.rotation_degrees.y = 180.0 if light_mode == "back" else 25.0
		viewport.add_child(light)
	if blockers:
		for front in [false,true]:
			var blocker := MeshInstance3D.new()
			var blocker_mesh := BoxMesh.new()
			blocker_mesh.size = Vector3(0.7,1.4,0.2)
			blocker.mesh = blocker_mesh
			blocker.position = Vector3(0.45 if front else -0.45,0,0.5 if front else -0.5)
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color.GREEN if front else Color.RED
			blocker.material_override = material
			viewport.add_child(blocker)
	await wait_frames(12)
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	await process_frame
	return image

func _run() -> void:
	root.size = Vector2i(1600,900)
	root.content_scale_size = Vector2i(1600,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/materials/qa"))
	var stand := STAND.instantiate()
	root.add_child(stand)
	stand.select_preset(6)
	await capture("library-day")
	stand.set_lighting("back")
	stand.select_preset(4)
	await capture("library-backlight")
	stand.set_lighting("night")
	stand.select_preset(8)
	await capture("library-night")
	stand.lamp.visible = false
	await capture("library-night-emission-only")
	stand.set_lighting("day")
	stand.select_preset(7)
	stand._edit(false,"emission_follow_base")
	stand._edit(Color(0.7,0.2,0.95),"emission_color")
	stand._edit(1.2,"emission_energy")
	stand.select_preset(7)
	await capture("library-emissive-crystal")
	stand.queue_free()
	await process_frame
	var dark := await pixel_probe("matte",{"base_color":Color.WHITE})
	var glowing := await pixel_probe("emissive",{"emission_follow_base":false,"emission_color":Color.RED,"emission_energy":2.0})
	var center := glowing.get_pixel(128,128)
	var reopened := await pixel_probe("emissive",{"emission_follow_base":false,"emission_color":Color.RED,"emission_energy":2.0},false,"none",true)
	if reopened.get_data() != glowing.get_data(): errors.append("save/reopen changed native emission pixels")
	if center.r <= dark.get_pixel(128,128).r+0.2 or center.r < center.g*2: errors.append("emission color/energy not visible without lights")
	var overlap := await pixel_probe("glass",{},true)
	var left := overlap.get_pixel(90,128)
	var right := overlap.get_pixel(166,128)
	if left.r < 0.2 or left.r <= left.g*2 or right.g < 0.5 or right.g <= right.r*2: errors.append("transparent behind/front depth overlap failed")
	var dull := await pixel_probe("matte",{"base_color":Color(0.15,0.15,0.15)},false,"front")
	var shiny := await pixel_probe("matte",{"base_color":Color(0.15,0.15,0.15),"highlight_strength":1.0,"surface_roughness":0.65},false,"front")
	if shiny.get_pixel(128,128).r <= dull.get_pixel(128,128).r+0.01: errors.append("direct highlight not visible")
	var plain_leaf := await pixel_probe("leaf",{"transmission_strength":0.0},false,"back")
	var thin_leaf := await pixel_probe("leaf",{},false,"back")
	if thin_leaf.get_pixel(128,128).g <= plain_leaf.get_pixel(128,128).g+0.05: errors.append("light-driven transmission not visible")
	overlap.save_png("res://art/materials/qa/probe-alpha-depth.png")
	glowing.save_png("res://art/materials/qa/probe-emission.png")
	print("PIXEL_PROBES emission=",center," alpha_back=",left," opaque_front=",right,
		" dull=",dull.get_pixel(128,128)," shiny=",shiny.get_pixel(128,128),
		" leaf_plain=",plain_leaf.get_pixel(128,128)," leaf_thin=",thin_leaf.get_pixel(128,128))
	if errors.is_empty(): print("PASS MATERIAL_LIBRARY_NATIVE: day/night/backlight, separate lamp, emission without lights, glass front/behind depth, specular and transmission")
	else:
		for error in errors: push_error(error)
	quit(0 if errors.is_empty() else 1)
