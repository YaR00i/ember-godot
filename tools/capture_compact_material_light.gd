extends SceneTree
## Same colors/art/geometry and fixed camera/light. Includes an achromatic control.

const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const OUTPUT := "user://ember-tests/material-light"
const MODES := ["previous", "natural", "plastic"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	await _swatches()
	await _world()
	quit()


func _swatches() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	environment.environment = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("627c89")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.25
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-38, 158, 0)
	sun.light_energy = 1.0
	sun.light_color = Color(1.0, 0.97, 0.90)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 215
	camera.position = Vector3(80, 140, 235)
	camera.look_at(Vector3(0, 8, 0))
	camera.make_current()
	# Put the reflected sun in view, rather than compare off-angle matte faces.
	var view_direction := camera.global_basis.z
	sun.look_at(-Vector3(-view_direction.x, view_direction.y, -view_direction.z), Vector3.UP)
	var materials: Array[ShaderMaterial] = []
	var roles := PackedStringArray(["grass", "soil", "sand", "stone"])
	for index in 4:
		var box := BoxMesh.new()
		box.size = Vector3(64, 32, 64)
		var arrays := box.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices.size(): vertices[vertex] += Vector3(32, 16, 32)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		colors.fill(Color(1, 1, 1, 1.0 / 255.0))
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance := MeshInstance3D.new()
		world.add_child(instance)
		instance.mesh = mesh
		instance.position = Vector3((index - 1.5) * 76 - 32, 0, -32)
		var material := Materials.compact_terrain_material()
		Materials.set_compact_terrain_roles(material, PackedStringArray(["", roles[index]]),
			PackedStringArray(["", roles[index] + "_relief"]))
		instance.material_override = material
		materials.append(material)
	var baseline: Image
	for mode in 3:
		for gray in [false, true]:
			for material in materials:
				material.set_shader_parameter("material_light_mode", mode)
				material.set_shader_parameter("material_gray_preview", gray)
			var image := await _shot("swatches-%s%s" % [MODES[mode], "-gray" if gray else ""])
			if mode == 1 and gray: baseline = image
	for material in materials: material.set_shader_parameter("material_light_mode", 1)
	var original_sun := sun.transform
	sun.rotation_degrees.y += 40.0
	var turned_sun := await _shot("swatches-natural-gray-sun")
	assert(_difference(baseline, turned_sun) > 1000, "gray materials must respond to the sun")
	sun.transform = original_sun
	camera.position = Vector3(-110, 140, 235)
	camera.look_at(Vector3(0, 8, 0))
	var turned_camera := await _shot("swatches-natural-gray-camera")
	assert(_difference(baseline, turned_camera) > 1000)
	# Suppress direct light: new modes have no permanent emission on sides.
	sun.light_energy = 0.0
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	await _shot("swatches-natural-unlit")
	print("PASS MATERIAL_LIGHT Forward+ colored/gray three modes, sun and camera response")
	world.free()
	await process_frame


func _world() -> void:
	var scene := (load("res://scenes/compact_material_light_study.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var map := scene.get_node("Map") as EmberMapLoader
	var study := scene.get_node("PlanarReflection")
	for frame in 600:
		await process_frame
		if study.get("_prepared") and frame > 30 and map.get("_visual_surface_projection").pending_tile_count() == 0: break
	var terrain = map.get("_visual_surface_projection")
	assert(terrain.pending_tile_count() == 0)
	for layer in scene.find_children("*", "CanvasLayer", true, false): layer.hide()
	for player in scene.find_children("*", "EmberPlayer", true, false): player.hide()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 170.0
	camera.far = 2400.0
	camera.position = Vector3(465, 155, 630)
	camera.look_at(Vector3(365, 20, 530))
	camera.make_current()
	var builds: int = study.get("_fields_build_count")
	var tiles: Array = terrain.get("_tiles").values().duplicate()
	for mode in 3:
		map.compact_material_light_mode = mode
		for frame in 12:
			(study.get("_material") as ShaderMaterial).set_shader_parameter("preview_time", 4.0)
			study.refresh_water_settings()
			await process_frame
		await _shot("world-%s" % MODES[mode])
	assert(study.get("_fields_build_count") == builds)
	assert(terrain.get("_tiles").values() == tiles)
	map.compact_material_light_mode = 1
	var environment: Environment = map.get_node("Look/WorldEnvironment").environment
	environment.ssao_enabled = false
	await _shot("world-natural-no-ao")
	print("PASS MATERIAL_LIGHT world: fixed art/geometry/camera/wave, no remesh or water fields build; AO separately")
	camera.free()
	scene.free()
	await process_frame


func _shot(name: String) -> Image:
	for frame in 14: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.save_png("%s/%s.png" % [OUTPUT, name]) == OK)
	return image


func _difference(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ac := a.get_pixel(x, y)
			var bc := b.get_pixel(x, y)
			if absf(ac.r - bc.r) + absf(ac.g - bc.g) + absf(ac.b - bc.b) > 0.025: count += 1
	return count
