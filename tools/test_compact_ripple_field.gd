extends SceneTree
## Actual optical fragment: deformation, pause, periodic seam and texture reuse.
const FIELD := preload("res://scripts/prototypes/ember_compact_ripple_field.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var started := Time.get_ticks_usec()
	var field := FIELD.texture()
	print("RIPPLE field_build_us=", Time.get_ticks_usec() - started)
	assert(field == FIELD.texture(), "static basis must not be rebuilt for animation")
	var image := field.get_image()
	assert(image.get_size() == Vector2i(128, 128) and image.has_mipmaps())
	var seam := 0.0
	var interior := 0.0
	for y in 128:
		var a := image.get_pixel(0, y)
		var b := image.get_pixel(127, y)
		seam += Vector2(a.r-b.r, a.g-b.g).length()
		for x in range(1, 128):
			var c := image.get_pixel(x, y)
			var d := image.get_pixel(x-1, y)
			assert(is_finite(c.r) and is_finite(c.g))
			interior += Vector2(c.r-d.r, c.g-d.g).length()
	seam /= 128
	interior /= 128*127
	assert(seam < interior * 2.0, "periodic seam must not be a Cartesian discontinuity")
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader").replace(
		"render_mode blend_mix, depth_draw_never, cull_disabled;", "render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;").replace(
		"NORMAL = view_normal;", "ALBEDO = vec3(slope * 0.3 + vec2(0.5), 0.0); NORMAL = view_normal;").replace(
		"study_fine_slope(water_point, seconds)", "study_ripple_slope(water_point, seconds)")
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("ripple_cell_field", field)
	material.set_shader_parameter("ripple_field_available", 1.0)
	material.set_shader_parameter("wave_height_voxels", 0.0)
	material.set_shader_parameter("water_glint_strength", 1.0)
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(-48,0,-48),Vector3(-48,0,48),Vector3(48,0,-48),Vector3(48,0,-48),Vector3(-48,0,48),Vector3(48,0,48)]:
		builder.set_color(Color.WHITE)
		builder.set_uv(Vector2.ZERO)
		builder.set_normal(Vector3.UP)
		builder.add_vertex(point)
	var plane := MeshInstance3D.new()
	plane.mesh = builder.commit()
	plane.material_override = material
	root.add_child(plane)
	var camera := Camera3D.new()
	camera.fov = 55.0
	root.add_child(camera)
	camera.position = Vector3(0, 40, -23.094)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var frames: Array[Image] = []
	for morph in [0.0, 1.0]:
		material.set_shader_parameter("ripple_morph_strength", morph)
		for seconds in [0.0, 5.0, 5.01]:
			material.set_shader_parameter("preview_time", seconds)
			for frame in 5: await process_frame
			await RenderingServer.frame_post_draw
			frames.append(root.get_texture().get_image())
	var paused := _difference(frames[0], frames[1])
	var moving := _difference(frames[3], frames[4])
	var small_step := _difference(frames[4], frames[5])
	assert(paused < 0.0001, "zero deformation must stop shape morphing")
	assert(moving > 0.003, "optical cell shapes must evolve")
	assert(small_step < moving * 0.1, "deformation must be smooth rather than switch frames")
	print("RIPPLE seam=", seam, " interior=", interior, " paused=", paused, " morph=", moving, " small_step=", small_step)
	print("PASS RIPPLE: shared texture, continuous seam, real fragment deformation/pause")
	quit()

func _difference(a: Image, b: Image) -> float:
	var sum := 0.0
	var count := 0
	for y in range(a.get_height()/4, a.get_height()*3/4):
		for x in range(a.get_width()/4, a.get_width()*3/4):
			var left := a.get_pixel(x,y)
			var right := b.get_pixel(x,y)
			sum += absf(left.r-right.r) + absf(left.g-right.g)
			count += 1
	return sum/maxi(count,1)
