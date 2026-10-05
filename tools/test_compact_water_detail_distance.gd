extends SceneTree
## Native Forward+ checks of the real fragment's camera-distance transition.
## Colour diagnostics preserve the actual fragment, vertex and region materials.

const OUTPUT := "user://ember-tests/water-detail-distance"
var _viewport: SubViewport
var _camera: Camera3D
var _materials: Array[ShaderMaterial] = []


func _initialize() -> void:
	_run.call_deferred()


func _render(height: float) -> Image:
	_camera.position = Vector3(0, height, 0)
	_camera.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	for frame in 10: await process_frame
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()


func _run() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 256)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	_viewport.add_child(environment)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 32
	_camera.far = 2000
	_viewport.add_child(_camera)
	_camera.make_current()
	var source := FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader")
	var diagnostic := Shader.new()
	diagnostic.code = source.replace("render_mode blend_mix, depth_draw_never, cull_disabled;",
		"render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;").replace(
		"EMISSION = mix(surface_color, vec3(0.70, 0.95, 1.0), foam);", "EMISSION = vec3(0.0);").replace(
		"NORMAL = view_normal;", "ALBEDO = vec3(detail_weight); NORMAL = view_normal;")
	for side in [-1, 1]:
		var mesh := MeshInstance3D.new()
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_normal(Vector3.UP)
		builder.set_color(Color.WHITE)
		# UV.y > .5 denotes compact side walls, not ordinary PlaneMesh UVs.
		builder.set_uv(Vector2.ZERO)
		for point in [Vector3(-8, 0, -16), Vector3(-8, 0, 16), Vector3(8, 0, -16),
			Vector3(8, 0, -16), Vector3(-8, 0, 16), Vector3(8, 0, 16)]:
			builder.add_vertex(point)
		mesh.mesh = builder.commit()
		mesh.position.x = side * 8
		var material := ShaderMaterial.new()
		material.shader = diagnostic
		material.set_shader_parameter("preview_time", 3.0)
		material.set_shader_parameter("wave_height_voxels", 0.0)
		material.set_shader_parameter("water_detail_begin_m", 10.0)
		material.set_shader_parameter("water_detail_end_m", 30.0)
		mesh.material_override = material
		_materials.append(material)
		_viewport.add_child(mesh)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var near := await _render(80.0)
	var middle := await _render(320.0)
	var far := await _render(640.0)
	var returned := await _render(80.0)
	print("WATER_DETAIL weights near=", near.get_pixel(128, 128).r,
		" middle=", middle.get_pixel(128, 128).r, " far=", far.get_pixel(128, 128).r)
	assert(near.get_pixel(128, 128).r > 0.98)
	assert(middle.get_pixel(128, 128).r > 0.2 and middle.get_pixel(128, 128).r < 0.95)
	assert(far.get_pixel(128, 128).r < 0.01)
	assert(near.get_data() == returned.get_data(), "returning camera must restore detail without stale regional state")
	assert(absf(middle.get_pixel(127, 128).r - middle.get_pixel(128, 128).r) < 0.01,
		"detail distance must be continuous at a region boundary")
	# A temporarily reversed pair of slider values must remain finite and render.
	for material in _materials: material.set_shader_parameter("water_detail_end_m", 1.0)
	var reversed := await _render(320.0)
	assert(reversed.get_pixel(128, 128).r < 0.01)
	for material in _materials: material.set_shader_parameter("water_detail_end_m", 30.0)
	# Compare the complete, time-pinned near material to the same shader forced
	# to full detail. This checks the actual optics/foam, not just the diagnostic.
	var complete := Shader.new()
	complete.code = source
	for material in _materials:
		material.shader = complete
		material.set_shader_parameter("ripple_cell_field", preload("res://scripts/prototypes/ember_compact_ripple_field.gd").texture())
		material.set_shader_parameter("ripple_field_available", 1.0)
	var normal_near := await _render(80.0)
	for material in _materials:
		material.set_shader_parameter("water_detail_begin_m", 511.0)
		material.set_shader_parameter("water_detail_end_m", 512.0)
	var full_near := await _render(80.0)
	assert(normal_near.get_data() == full_near.get_data(), "near optics must retain the full material")
	for pair in [["near", near], ["middle", middle], ["far", far], ["full-near", full_near]]:
		assert(pair[1].save_png(OUTPUT + "/" + pair[0] + ".png") == OK)
	print("PASS water detail distance: native near/transition/far, region seam, return, reversed thresholds, complete near optics")
	_viewport.queue_free()
	await process_frame
	quit()
