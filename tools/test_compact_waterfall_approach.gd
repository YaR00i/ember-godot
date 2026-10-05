extends SceneTree
## Real shared fragment: a coloured floor behind the fall must not leak through.

var _camera: Camera3D
var _water: MeshInstance3D
var _material: ShaderMaterial

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "this is a Forward+ image test")
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	root.add_child(env)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 4.0
	_camera.position = Vector3(0, 0, -5)
	root.add_child(_camera)
	_camera.look_at(Vector3.ZERO)
	_camera.make_current()
	_material = (load("res://materials/ember_compact_sky_reflection_study.tres") as ShaderMaterial).duplicate()
	for key in ["wave_height_voxels", "local_bob_strength", "river_flow_enabled", "shore_field_available", "object_contact_available",
		"shore_foam_strength", "object_foam_strength", "river_crest_whiteness", "foam_trail_strength", "water_glint_strength",
		"sky_reflection_strength", "planar_reflection_mix", "waterfall_irregularity", "water_level_offset_voxels"]:
		_material.set_shader_parameter(key, 0.0)
	_material.set_shader_parameter("waterfall_available", 1.0)
	_material.set_shader_parameter("waterfall_strength", 1.0)
	_material.set_shader_parameter("preview_time", 2.4)
	_water = MeshInstance3D.new()
	_water.mesh = _quad(PackedVector3Array([Vector3(-1, 1, 0), Vector3(1, 1, 0), Vector3(1, -1, 0), Vector3(-1, -1, 0)]),
		PackedVector2Array([Vector2(-4, 0.2), Vector2(-5, 0.2), Vector2(-5, 0.8), Vector2(-4, 0.8)]))
	_water.material_override = _material
	root.add_child(_water)
	var floor_mesh := MeshInstance3D.new()
	var plane := QuadMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	floor_mesh.position.z = 1
	var floor_material := StandardMaterial3D.new()
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	floor_mesh.material_override = floor_material
	root.add_child(floor_mesh)
	floor_material.albedo_color = Color(0.9, 0.1, 0.1)
	var red := await _frame()
	floor_material.albedo_color = Color(0.1, 0.9, 0.1)
	var green := await _frame()
	var rect := _rect(Vector3(-0.35, 0.35, 0), Vector3(0.35, -0.35, 0))
	var leak := _difference(red, green, rect)
	print("WATERFALL_OPACITY behind_floor_difference=", leak)
	var output := "user://ember-tests/waterfall-approach"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	red.save_png(output + "/floor-red.png")
	green.save_png(output + "/floor-green.png")
	if leak > 0.012:
		push_error("FAIL WATERFALL: upper river floor colour is visible through the actual falling sheet")
		quit(1)
		return
	print("PASS WATERFALL opacity: actual sheet hides the upper floor")
	_water.mesh = _quad(PackedVector3Array([Vector3(-26, 0, -20), Vector3(-26, 0, 52), Vector3(26, 0, 52), Vector3(26, 0, -20)]),
		PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
	_camera.size = 86.0
	_camera.position = Vector3(0, 60, 16)
	_camera.look_at(Vector3(0, 0, 16), Vector3.FORWARD)
	floor_mesh.rotation.x = -PI * 0.5
	floor_mesh.position = Vector3(0, -8, 16)
	plane.size = Vector2(100, 100)
	floor_material.albedo_color = Color(0.4, 0.3, 0.2)
	_material.set_shader_parameter("waterfall_source", Vector4(0, 0, 0, -24))
	_material.set_shader_parameter("waterfall_direction", Vector2.UP)
	_material.set_shader_parameter("waterfall_width", 34.0)
	_material.set_shader_parameter("waterfall_available", 0.0)
	var quiet := await _frame()
	_material.set_shader_parameter("waterfall_available", 1.0)
	var approach := await _frame()
	var inlet_rect := _rect(Vector3(-12, 0, 3), Vector3(12, 0, 24))
	var far_rect := _rect(Vector3(-10, 0, 36), Vector3(10, 0, 46))
	var lower_rect := _rect(Vector3(-10, 0, -13), Vector3(10, 0, -5))
	var inlet := _difference(quiet, approach, inlet_rect)
	var far := _difference(quiet, approach, far_rect)
	var lower := _difference(quiet, approach, lower_rect)
	print("WATERFALL_APPROACH inlet=", inlet, " far=", far, " lower=", lower)
	quiet.save_png(output + "/quiet.png")
	approach.save_png(output + "/approach.png")
	if inlet < 0.025 or far > 0.012 or lower > 0.012:
		push_error("FAIL WATERFALL: visible approach streaks must be local to the upstream lip")
		quit(1)
		return
	_material.set_shader_parameter("preview_time", 3.9)
	var moved := await _frame()
	var motion := _difference(approach, moved, inlet_rect)
	if motion < 0.015:
		push_error("FAIL WATERFALL: approach streaks must move with every other wave disabled")
		quit(1)
		return
	_material.set_shader_parameter("waterfall_direction", Vector2.DOWN)
	var reversed := await _frame()
	var reversed_rect := _rect(Vector3(-10, 0, -18), Vector3(10, 0, -4))
	if _difference(quiet, reversed, reversed_rect) < 0.025 or _difference(quiet, reversed, inlet_rect) > 0.012:
		push_error("FAIL WATERFALL: the approach must follow the spill direction")
		quit(1)
		return
	_material.set_shader_parameter("waterfall_strength", 0.0)
	if _difference(quiet, await _frame(), inlet_rect) > 0.012:
		push_error("FAIL WATERFALL: disabling the fall must remove its approach")
		quit(1)
		return
	print("PASS WATERFALL approach: local upstream motion=", motion, ", far/lower unchanged, strength off")
	quit()

func _frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _rect(a: Vector3, b: Vector3) -> Rect2i:
	var pixel_scale := Vector2(root.get_texture().get_image().get_size()) / root.get_visible_rect().size
	var pa := _camera.unproject_position(a) * pixel_scale
	var pb := _camera.unproject_position(b) * pixel_scale
	var start := Vector2i(minf(pa.x, pb.x), minf(pa.y, pb.y))
	var end := Vector2i(maxf(pa.x, pb.x), maxf(pa.y, pb.y))
	return Rect2i(start, end - start)

func _difference(a: Image, b: Image, rect: Rect2i) -> float:
	var sum := 0.0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return sum / float(rect.size.x * rect.size.y)

func _quad(points: PackedVector3Array, uvs: PackedVector2Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var tex_uv := PackedVector2Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for index in [0, 1, 2, 0, 2, 3]:
		vertices.append(points[index])
		tex_uv.append(uvs[index])
		normals.append(Vector3.UP)
		colors.append(Color(0.1, 0.7, 0.8, 0.1875))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = tex_uv
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
