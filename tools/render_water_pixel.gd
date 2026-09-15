extends "res://tools/render_water_stand.gd"
## W02 native A/B. Same Surface fixture, optics and lighting as W01.
var variant := "fine"
var view_kind := "close"
var animate := false
var ocean: MeshInstance3D

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variant="): variant = arg.trim_prefix("--variant=")
		if arg.begins_with("--view="): view_kind = arg.trim_prefix("--view=")
		if arg == "--motion": animate = true
	run.call_deferred()

func previous_material() -> ShaderMaterial:
	var previous := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string("res://art/water/checkpoint-w01/shaders/ember_voxel_surface_water.gdshader")
	previous.shader = shader
	previous.render_priority = 1
	var text := FileAccess.get_file_as_string("res://art/water/checkpoint-w01/materials/ember_voxel_surface_water.tres")
	for line in text.split("\n"):
		if line.begins_with("shader_parameter/"):
			var pair := line.split(" = ",true,1)
			previous.set_shader_parameter(pair[0].trim_prefix("shader_parameter/"),str_to_var(pair[1]))
	return previous

func select_water() -> void:
	if variant == "w01": water = previous_material()
	elif variant == "smooth": water.set_shader_parameter("reflection_pixel_strength",0.0)
	elif variant == "coarse": water.set_shader_parameter("reflection_pixel_size",0.125)
	elif variant != "fine": errors.append("unknown variant "+variant)
	water.set_shader_parameter("preview_time",3.25)
	for i in visual.mesh.get_surface_count():
		if visual.mesh.surface_get_name(i) == "water": visual.set_surface_override_material(i,water)

func wide_fixture() -> void:
	# Broad open water is a disposable material fixture, not a gameplay island map.
	ocean = MeshInstance3D.new()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Leave the complete Source fixture uncovered: no second transparent layer
	# or opaque backdrop may hide its authored shallow/deep bottom.
	for bounds in [Vector4(-18,-18,26,0),Vector4(-18,8,26,26),Vector4(-18,0,0,8),Vector4(8,0,26,8)]:
		var first := vertices.size()
		vertices.append_array(PackedVector3Array([Vector3(bounds.x,1,bounds.w),Vector3(bounds.x,1,bounds.y),Vector3(bounds.z,1,bounds.y),Vector3(bounds.z,1,bounds.w)]))
		for i in 4:
			normals.append(Vector3.UP)
			uvs.append(Vector2.ONE)
		indices.append_array(PackedInt32Array([first,first+1,first+2,first,first+2,first+3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	ocean.mesh = mesh
	var material := water.duplicate() as ShaderMaterial
	material.set_shader_parameter("background_water",true)
	material.set_shader_parameter("coordinate_scale",1.0)
	ocean.material_override = material
	scene.add_child(ocean)
	for center in [Vector3(-6,1.3,12),Vector3(16,1.3,0)]:
		box(center,Vector3(5,0.7,4),Color("bcae81"))
		box(center+Vector3(0,0.35,0),Vector3(3.8,0.12,2.8),Color("83a675"))
		box(center+Vector3(0.6,1.0,0),Vector3(0.3,1.0,0.3),Color("786446"))
		for layer in 3:
			box(center+Vector3(0.6,1.7+layer*0.25,0),Vector3(1.6-layer*0.3,0.4,1.6-layer*0.3),Color("83ad72"))
	probe.position = Vector3(4,3,4)
	probe.size = Vector3(52,12,52)
	sun.directional_shadow_max_distance = 100

func run() -> void:
	root.size = Vector2i(1280,900)
	output = "res://art/water/pixel/qa/"+view_kind+"-"+variant+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	build()
	select_water()
	if view_kind == "close":
		camera.size = 6.0
		camera.position = Vector3(8.6,5.6,9.6)
		camera.look_at(Vector3(4.3,1,4.3))
	elif view_kind == "game":
		camera.size = 11.0
	elif view_kind == "wide":
		wide_fixture()
		camera.size = 31.0
		camera.position = Vector3(25,17,28)
		camera.look_at(Vector3(4,1,4))
	elif view_kind == "perspective":
		wide_fixture()
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.position = Vector3(4.3,2.8,10.5)
		camera.look_at(Vector3(4,1,0))
	else: errors.append("unknown view "+view_kind)
	await capture("water")
	if animate:
		for frame in 48:
			var seconds := 3.25+float(frame)/12.0
			water.set_shader_parameter("preview_time",seconds)
			if ocean != null: (ocean.material_override as ShaderMaterial).set_shader_parameter("preview_time",seconds)
			await frames(2)
			if root.get_texture().get_image().save_png(output+"motion-%03d.png"%frame) != OK: errors.append("motion frame save failed")
		# A slow camera translation checks the world-anchored reflection cells.
		if variant == "fine":
			var start := camera.position
			for frame in 24:
				camera.position = start+Vector3(float(frame)*0.0125,0,0)
				await frames(2)
				root.get_texture().get_image().save_png(output+"camera-%03d.png"%frame)
	scene.queue_free()
	await frames(10)
	for error in errors: push_error(error)
	print("PASS WATER_PIXEL_CAPTURE variant=",variant," view=",view_kind," native_motion=",animate if errors.is_empty() else "FAIL")
	quit(0 if errors.is_empty() else 1)
