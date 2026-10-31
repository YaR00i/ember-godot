extends SceneTree
## Real controller upload + actual water shader must preserve separated islands.
const Contact := preload("res://scripts/ember_water_contact_3d.gd")
const Water := preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")
var errors: Array[String] = []
func _init() -> void: run.call_deferred()
func run() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var mesh := MeshInstance3D.new()
	var joined := ArrayMesh.new()
	for offset in [-5.0,5.0]:
		var box := BoxMesh.new()
		box.size = Vector3(2,4,2)
		var arrays := box.get_mesh_arrays()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size(): vertices[i].x += offset
		arrays[Mesh.ARRAY_VERTEX] = vertices
		joined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.mesh = joined
	host.add_child(mesh)
	var contact := Contact.new()
	host.add_child(contact)
	contact.set_process(false)
	var scene := Node3D.new()
	root.add_child(scene)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.hydrate_legacy_regions = false
	scene.add_child(map)
	var controller := Water.new()
	controller.study_controls = false
	scene.add_child(controller)
	controller.set_process(false)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var plane := MeshInstance3D.new()
	var geometry := PlaneMesh.new()
	geometry.size = Vector2(64,64)
	plane.mesh = geometry
	viewport.add_child(plane)
	var code := FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader")
	var shader := Shader.new()
	shader.code = code.substr(0,code.find("void vertex()")) + "\nvoid vertex(){water_point=VERTEX.xz/16.0;}\nvoid fragment(){EMISSION=vec3(step(0.0,study_object_distance(water_point)));ALBEDO=vec3(0.0);SPECULAR=0.0;ALPHA=1.0;}"
	var material := ShaderMaterial.new()
	material.shader = shader
	plane.material_override = material
	controller._material = material
	controller._water_height = 0.0
	controller._surface_contacts.assign([contact])
	controller.obstacle_wave_mode = 2
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 32
	camera.position = Vector3(0,32,0)
	camera.look_at(Vector3.ZERO,Vector3.FORWARD)
	camera.make_current()
	var first_texture: ImageTexture
	for moved in [false,true]:
		if moved:
			host.position = Vector3(4,0,4)
			host.rotation.y = PI * 0.5
		controller._upload_surface_contacts()
		if not moved: first_texture = controller._contact_texture
		else:
			if first_texture != controller._contact_texture: errors.append("movement rebuilt the atlas texture")
		for i in range(4): await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		for point in [Vector3(-5,0,0),Vector3(5,0,0),Vector3.ZERO,Vector3(8,0,0)]:
			var world: Vector3 = host.global_transform * point
			var pixel := Vector2i(camera.unproject_position(world))
			var wet: bool = absf(point.x) != 5.0
			var value := image.get_pixel(pixel.x,pixel.y).r
			if (wet and value < 0.9) or (not wet and value > 0.1): errors.append("GPU waterline mismatch " + str(point) + " moved=" + str(moved))
	print("MESH_CONTACT_GPU ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	viewport.free()
	scene.free()
	host.free()
	quit(0 if errors.is_empty() else 1)
