extends SceneTree
## Actual Forward+ top/sides and light response, independent of the water scene.

const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const OUTPUT := "user://ember-tests/material-relief"
const ROLES := ["grass", "soil", "sand", "stone"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("627c89")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a0bfd3")
	environment.environment.ambient_light_energy = 0.12
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 0.5
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 215
	camera.position = Vector3(80, 140, 235)
	camera.look_at(Vector3(0, 8, 0))
	camera.make_current()
	var materials: Array[ShaderMaterial] = []
	for index in 4:
		var box := BoxMesh.new()
		box.size = Vector3(64, 32, 64)
		var arrays := box.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices.size(): vertices[vertex] += Vector3(32, 16, 32)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var colors := PackedColorArray()
		colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		colors.fill(Color(1, 1, 1, 1.0 / 255.0))
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance := MeshInstance3D.new()
		world.add_child(instance)
		instance.mesh = mesh
		instance.position = Vector3((index - 1.5) * 76 - 32, 0, -32)
		var material := Materials.compact_terrain_material()
		material.set_shader_parameter("band_floor", 0.19)
		instance.material_override = material
		materials.append(material)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var images: Dictionary = {}
	for variant in ["before", "after", "after-flat", "after-sun"]:
		for index in 4:
			Materials.set_compact_terrain_roles(materials[index], PackedStringArray(["", ROLES[index]]),
				PackedStringArray(["", ROLES[index] + ("" if variant == "before" else "_relief")]))
			if variant == "after-flat":
				var finish: Texture2D = materials[index].get_shader_parameter("finish_lookup")
				var data := finish.get_image()
				var pixel := data.get_pixel(1, 0)
				pixel.b = 0.0
				data.set_pixel(1, 0, pixel)
				materials[index].set_shader_parameter("finish_lookup", ImageTexture.create_from_image(data))
		if variant == "after-sun": sun.rotation_degrees.y = 65
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		images[variant] = image
		assert(image.save_png("%s/swatches-%s.png" % [OUTPUT, variant]) == OK)
	var relief_pixels := _different_pixels(images["after"], images["after-flat"])
	var sun_pixels := _different_pixels(images["after"], images["after-sun"])
	assert(relief_pixels > 100, "painted relief must affect Forward+ light, not just change RGB artwork")
	assert(sun_pixels > 1000, "materials must respond when the sun rotates")
	print("PASS Forward+ four materials: top/sides, relief_changed_pixels=", relief_pixels, " rotated_sun_pixels=", sun_pixels)
	world.queue_free()
	await process_frame
	quit()


func _different_pixels(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ac := a.get_pixel(x, y)
			var bc := b.get_pixel(x, y)
			if absf(ac.r - bc.r) + absf(ac.g - bc.g) + absf(ac.b - bc.b) > 0.025: count += 1
	return count
