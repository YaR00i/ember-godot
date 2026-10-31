extends SceneTree
## Real fragment output: accepted defaults and independent depth/transmission controls.
var failures: Array[String] = []
var viewport: SubViewport
var material: ShaderMaterial
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); printerr("WATER_COLOR_RENDER FAIL ", label)
func sample() -> Image:
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func difference(a: Image, b: Image) -> float:
	var total := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var delta := a.get_pixel(x, y) - b.get_pixel(x, y)
			total += absf(delta.r) + absf(delta.g) + absf(delta.b)
	return total / (a.get_width() * a.get_height() * 3)
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	viewport = SubViewport.new(); viewport.size = Vector2i(256, 256); viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var mesh := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = Vector2(2, 2); mesh.mesh = plane
	viewport.add_child(mesh)
	var code := FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader")
	var shader := Shader.new()
	shader.code = code.substr(0, code.find("void vertex()")) + """
uniform bool test_legacy = false;
void vertex() { water_point = VERTEX.xz; }
void fragment() {
 float depth = UV.x * 4.0;
 float gradient = test_legacy ? smoothstep(deep_start_blocks, deep_end_blocks, depth) : study_water_depth_mix(depth);
 vec3 transmission = test_legacy ? exp(-absorption_per_block * depth) : study_water_transmission(depth);
 vec3 result = UV.y < 0.33 ? vec3(gradient) : (UV.y < 0.66 ? transmission : mix(shallow_color, deep_color, gradient));
 EMISSION = result; ALBEDO = vec3(0.0); SPECULAR = 0.0; ALPHA = 1.0;
}
"""
	material = ShaderMaterial.new(); material.shader = shader; mesh.material_override = material
	var camera := Camera3D.new(); viewport.add_child(camera); camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0; camera.position = Vector3(0, 3, 0); camera.rotation_degrees.x = -90; camera.make_current()
	var defaults: Image = await sample()
	material.set_shader_parameter("test_legacy", true); var legacy: Image = await sample()
	check(difference(defaults, legacy) < 0.00001, "defaults reproduce accepted gradient and transmission")
	material.set_shader_parameter("test_legacy", false)
	material.set_shader_parameter("water_transparency", 0.0); var opaque: Image = await sample()
	check(opaque.get_pixel(64, 128).r < 0.005, "zero transparency hides floor contribution")
	material.set_shader_parameter("water_transparency", 1.0); material.set_shader_parameter("water_density", 0.0)
	var clear: Image = await sample()
	check(clear.get_pixel(128, 128).r > defaults.get_pixel(128, 128).r + 0.1, "zero density preserves floor with depth")
	material.set_shader_parameter("water_density", 4.0); var dense: Image = await sample()
	check(dense.get_pixel(64, 128).r < defaults.get_pixel(64, 128).r - 0.1, "greater density hides floor sooner")
	material.set_shader_parameter("water_density", 1.0); material.set_shader_parameter("water_color_softness", 0.0)
	var sharp: Image = await sample()
	check(difference(defaults, sharp) > 0.02, "softness changes actual transition")
	material.set_shader_parameter("water_color_softness", 1.0); material.set_shader_parameter("deep_end_blocks", 0.6)
	var shallow_transition: Image = await sample()
	check(difference(defaults, shallow_transition) > 0.05, "depth endpoints move actual transition")
	material.set_shader_parameter("deep_end_blocks", 2.35); material.set_shader_parameter("shallow_color", Color.RED)
	var red: Image = await sample()
	check(difference(defaults, red) > 0.01, "shallow color changes surface color")
	material.set_shader_parameter("shallow_color", Color(0.12, 0.72, 0.78)); material.set_shader_parameter("deep_color", Color.GREEN)
	check(difference(defaults, await sample()) > 0.05, "deep color changes surface color")
	print("WATER_COLOR_RENDER ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	viewport.free(); quit(0 if failures.is_empty() else 1)
