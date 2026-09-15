extends SceneTree
## Native material evidence; procedural fixture uses the existing Source and Surface mesher.
const Mesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var scene: Node3D
var sun: DirectionalLight3D
var environment: Environment
var camera: Camera3D
var water: ShaderMaterial
var visual: MeshInstance3D
var probe: ReflectionProbe
var output := "res://art/water/qa/"
var errors := PackedStringArray()

func _init() -> void: run.call_deferred()

func frames(count := 20) -> void:
	for frame in count: await process_frame
	await RenderingServer.frame_post_draw

func capture(name_text: String) -> Image:
	await frames()
	var image := root.get_texture().get_image()
	if image.save_png(output+name_text+".png") != OK: errors.append("capture "+name_text)
	return image

func box(position_value: Vector3, size_value: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_value
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	node.material_override = material
	node.position = position_value
	scene.add_child(node)
	return node

func fixture() -> EmberVoxelModelResource:
	var source := EmberVoxelModelResource.new()
	source.model_id = "water_w01_disposable"
	source.size_blocks = Vector3i(8,2,8)
	source.height_voxels = 32
	source.palette = PackedColorArray([Color.TRANSPARENT,Color("d1bf88"),Color("82a46e"),Color("438e95")])
	var grid := source.grid_size()
	source.voxels.resize(grid.x*grid.y*grid.z)
	source.surface_fill_levels.resize(grid.x*grid.z)
	source.surface_fill_materials.resize(grid.x*grid.z)
	source.surface_fill_palette.resize(grid.x*grid.z)
	for z in grid.z:
		for x in grid.x:
			var height := 20 if x < 24 else 15 if x < 42 else 10
			for y in height: source.voxels[x+z*grid.x+y*grid.x*grid.z] = 2 if x < 24 else 1
			if x >= 24:
				source.surface_fill_levels[x+z*grid.x] = 16
				source.surface_fill_materials[x+z*grid.x] = 1
				source.surface_fill_palette[x+z*grid.x] = 3
	return source

func build() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	var world := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b4c4c0")
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("608eaa")
	sky_material.sky_horizon_color = Color("d4dcd1")
	sky_material.ground_horizon_color = Color("8cab9b")
	sky_material.ground_bottom_color = Color("354d43")
	sky.sky_material = sky_material
	environment.sky = sky
	world.environment = environment
	scene.add_child(world)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1,0.93,0.79)
	sun.light_energy = 0.6
	sun.light_specular = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 50
	scene.add_child(sun)
	var source := fixture()
	visual = MeshInstance3D.new()
	visual.mesh = Mesher.build_region(source,Vector3i.ZERO,source.grid_size(),1.0/16.0)
	scene.add_child(visual)
	for i in visual.mesh.get_surface_count():
		if visual.mesh.surface_get_name(i) == "water":
			water = Materials.water_material().duplicate() as ShaderMaterial
			visual.set_surface_override_material(i,water)
		elif visual.mesh.surface_get_name(i) == "water_foam":
			var foam := Materials.foam_material().duplicate() as ShaderMaterial
			var frozen := Shader.new()
			frozen.code = foam.shader.code.replace("TIME","3.25")
			foam.shader = frozen
			visual.set_surface_override_material(i,foam)
		else: visual.set_surface_override_material(i,Materials.opaque_material())
	for i in 9: box(Vector3(1.4+i*0.34,1.37,3.0),Vector3(0.30,0.16,1.6),Color("b0925b"))
	for x in [2.0,3.6]:
		for z in [2.4,3.6]: box(Vector3(x,0.95,z),Vector3(0.12,0.9,0.12),Color("796343"))
	box(Vector3(5.7,1.05,5.2),Vector3(0.8,0.8,0.7),Color("8f9a90"))
	box(Vector3(5.65,1.5,5.15),Vector3(0.48,0.3,0.48),Color("9dac9c"))
	box(Vector3(0.5,1.55,5.3),Vector3(0.3,0.7,0.3),Color("786446"))
	for y in 3: box(Vector3(0.5,2.0+y*0.3,5.3),Vector3(1.2-y*0.24,0.5,1.2-y*0.24),Color("83ad72"))
	probe = ReflectionProbe.new()
	probe.position = Vector3(4,2,4)
	probe.size = Vector3(12,8,12)
	probe.box_projection = true
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	scene.add_child(probe)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11
	camera.position = Vector3(11,8,12)
	scene.add_child(camera)
	camera.look_at(Vector3(4,1,4))
	camera.current = true
	var view := (camera.position-Vector3(4,1,4)).normalized()
	sun.basis = Basis.looking_at(-Vector3(-view.x,view.y,-view.z),Vector3.UP)

func run() -> void:
	root.size = Vector2i(1280,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	build()
	water.set_shader_parameter("preview_time",3.25)
	await capture("stand-day")
	camera.size = 9.0
	camera.position = Vector3(6.5,2.8,12.0)
	camera.look_at(Vector3(4,1,4))
	await capture("stand-grazing")
	camera.size = 6.0
	camera.position = Vector3(8.6,5.6,9.6)
	camera.look_at(Vector3(4.3,1,4.3))
	var previous := ShaderMaterial.new()
	var previous_shader := Shader.new()
	previous_shader.code = FileAccess.get_file_as_string("res://art/water/checkpoint-pre-w01/shaders/ember_voxel_surface_water.gdshader")
	previous.shader = previous_shader
	var previous_text := FileAccess.get_file_as_string("res://art/water/checkpoint-pre-w01/materials/ember_voxel_surface_water.tres")
	for line in previous_text.split("\n"):
		if line.begins_with("shader_parameter/"):
			var pair := line.split(" = ",true,1)
			previous.set_shader_parameter(pair[0].trim_prefix("shader_parameter/"),str_to_var(pair[1]))
	previous.set_shader_parameter("preview_time",3.25)
	for i in visual.mesh.get_surface_count():
		if visual.mesh.surface_get_name(i) == "water": visual.set_surface_override_material(i,previous)
	await capture("stand-before")
	for i in visual.mesh.get_surface_count():
		if visual.mesh.surface_get_name(i) == "water": visual.set_surface_override_material(i,water)
	var first := await capture("stand-close")
	water.set_shader_parameter("wave_strength",0.0)
	var no_wave := await capture("stand-without-ripples")
	if first.get_data() == no_wave.get_data(): errors.append("normal ripples have no native response")
	water.set_shader_parameter("wave_strength",0.10)
	water.set_shader_parameter("preview_time",6.25)
	var moved := await capture("stand-time-6-25")
	if first.get_data() == moved.get_data(): errors.append("water animation did not change pixels")
	water.set_shader_parameter("preview_time",3.25)
	sun.light_specular = 0.0
	var no_specular := await capture("stand-without-direct-highlights")
	if first.get_data() == no_specular.get_data(): errors.append("real direct highlight has no native response")
	sun.light_specular = 1.0
	var path := "user://water-w01-reopen.tres"
	if ResourceSaver.save(water,path) != OK: errors.append("water material save failed")
	var reopened := ResourceLoader.load(path,"ShaderMaterial",ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	if reopened == null: errors.append("water material reopen failed")
	else:
		for i in visual.mesh.get_surface_count():
			if visual.mesh.surface_get_name(i) == "water": visual.set_surface_override_material(i,reopened)
		var same := await capture("stand-reopened")
		if same.get_data() != first.get_data(): errors.append("water save/reopen changed native pixels")
	DirAccess.remove_absolute(path)
	for i in visual.mesh.get_surface_count():
		if visual.mesh.surface_get_name(i) == "water": visual.set_surface_override_material(i,water)
	for frame in 48:
		water.set_shader_parameter("preview_time",3.25+float(frame)/12.0)
		await frames(2)
		if root.get_texture().get_image().save_png(output+"motion-%03d.png"%frame) != OK: errors.append("motion frame save failed")
	sun.rotation_degrees = Vector3(-45,-30,0)
	sun.light_color = Color("6685be")
	sun.light_energy = 0.14
	environment.ambient_light_color = Color("294462")
	environment.ambient_light_energy = 0.12
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	sky_material.sky_top_color = Color("050e1e")
	sky_material.sky_horizon_color = Color("142a3d")
	sky_material.ground_bottom_color = Color("030a12")
	sky_material.ground_horizon_color = Color("13222c")
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(3.5,2.5,2.7)
	lamp.light_color = Color("ffbb72")
	lamp.light_energy = 1.3
	lamp.light_specular = 1.0
	lamp.omni_range = 8
	scene.add_child(lamp)
	await capture("stand-night")
	scene.queue_free()
	await frames(10)
	for error in errors: push_error(error)
	print("PASS WATER_STAND: actual normal/time/specular response, exact material save/reopen, 48 real motion frames" if errors.is_empty() else "FAIL WATER_STAND")
	quit(0 if errors.is_empty() else 1)
