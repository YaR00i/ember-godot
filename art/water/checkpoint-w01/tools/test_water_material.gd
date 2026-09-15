extends SceneTree
## Exact storage/clone contract of the existing water ShaderMaterial, no Source schema changes.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var errors := PackedStringArray()

func _init() -> void: run.call_deferred()

func alpha_probe(depth: float, sky_color := Color.BLACK) -> Color:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128,128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.BLACK
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_energy = 0.0
	if sky_color != Color.BLACK:
		world.environment.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		for key in ["sky_top_color","sky_horizon_color","ground_bottom_color","ground_horizon_color"]: sky_material.set(key,sky_color)
		sky.sky_material = sky_material
		world.environment.sky = sky
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position = Vector3(0,4,0)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO,Vector3.FORWARD)
	camera.current = true
	var backing := MeshInstance3D.new()
	var backing_mesh := BoxMesh.new()
	backing_mesh.size = Vector3(2.8,0.1,2.8)
	backing.mesh = backing_mesh
	backing.position.y = -0.2
	var backing_material := StandardMaterial3D.new()
	backing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backing_material.albedo_color = Color.RED
	backing.material_override = backing_material
	viewport.add_child(backing)
	var surface := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.8,2.8)
	var arrays := plane.surface_get_arrays(0)
	var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	uvs.fill(Vector2(depth,0))
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	surface.mesh = mesh
	var material := Materials.water_material().duplicate() as ShaderMaterial
	material.set_shader_parameter("preview_time",3.25)
	material.set_shader_parameter("wave_strength",0.0)
	material.set_shader_parameter("highlight_strength",0.0)
	material.set_shader_parameter("ripple_alpha",0.0)
	material.set_shader_parameter("tone_alpha",0.0)
	material.set_shader_parameter("reflection_alpha",0.0)
	if sky_color != Color.BLACK:
		material.set_shader_parameter("background_water",true)
		material.set_shader_parameter("highlight_strength",0.36)
	surface.material_override = material
	viewport.add_child(surface)
	for frame in 16: await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var name_text := "alpha-"+("shallow" if depth == 0.0 else "deep") if sky_color == Color.BLACK else "reflection-"+("red" if sky_color == Color.RED else "green")
	image.save_png("res://art/water/qa/"+name_text+".png")
	var pixel := image.get_pixel(64,64)
	viewport.queue_free()
	for frame in 8: await process_frame
	return pixel

func run() -> void:
	var original := Materials.water_material()
	var options := {"wave_length":2.4,"wave_speed":0.55,"wave_strength":0.14,
		"surface_roughness":0.34,"highlight_strength":0.32,"body_emission":0.01,
		"patch_strength":0.22,"decorative_glints":true,"shallow_opacity":0.38,
		"deep_opacity":0.82,"water_tint":Color(0.12,0.65,0.71),"preview_time":-1.0}
	var before := {}
	for key in options: before[key] = original.get_shader_parameter(key)
	var material := original.duplicate() as ShaderMaterial
	for key in options: material.set_shader_parameter(key,options[key])
	for key in before:
		if original.get_shader_parameter(key) != before[key]: errors.append("shared material mutated: "+key)
	var path := "user://water-w01-storage.tres"
	if ResourceSaver.save(material,path) != OK: errors.append("save failed")
	var reopened := ResourceLoader.load(path,"ShaderMaterial",ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	if reopened == null: errors.append("reopen failed")
	else:
		for key in options:
			if reopened.get_shader_parameter(key) != options[key]: errors.append("storage differs: "+key)
	DirAccess.remove_absolute(path)
	if original.get_shader_parameter("preview_time") != -1.0: errors.append("frozen QA time escaped")
	if original.get_shader_parameter("decorative_glints") != false: errors.append("decorative glints enabled by default")
	if original.shader != load("res://shaders/ember_voxel_surface_water.gdshader"): errors.append("water shader owner changed")
	if "VERTEX +=" in original.shader.code: errors.append("optical waves changed geometry")
	if "SPECULAR_LIGHT +=" not in original.shader.code: errors.append("direct reflection response missing")
	if DisplayServer.get_name() != "headless":
		var shallow := await alpha_probe(0.0)
		var deep := await alpha_probe(1.0)
		if shallow.r <= deep.r+0.1 or shallow.r < 0.5 or deep.r < 0.05: errors.append("shallow/deep alpha transmission is wrong")
		print("WATER_ALPHA_TRANSMISSION shallow=",shallow," deep=",deep)
		var red := await alpha_probe(1.0,Color.RED)
		var green := await alpha_probe(1.0,Color.GREEN)
		if red.r <= red.g+0.03 or green.g <= green.r+0.03: errors.append("water does not reflect the actual Sky color without direct lights")
		print("WATER_SKY_REFLECTION red=",red," green=",green," no direct lights/ambient")
	for error in errors: push_error(error)
	print("PASS WATER_MATERIAL: independent clone and exact custom parameter save/reopen; existing owner and live time" if errors.is_empty() else "FAIL WATER_MATERIAL")
	quit(0 if errors.is_empty() else 1)
