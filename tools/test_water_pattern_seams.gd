extends SceneTree
## Native rendering comparison: one water plane versus independently placed halves.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var errors: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func _init() -> void:
	_run.call_deferred()

func plane(width: float) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,0,8),Vector3.ZERO,Vector3(width,0,0),Vector3(width,0,8)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ONE,Vector2.ONE,Vector2.ONE,Vector2.ONE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func capture(name: String) -> Image:
	for frame in 16: await process_frame
	RenderingServer.force_draw(false)
	var result := root.get_texture().get_image()
	result.save_png("user://"+name+".png")
	print("WATER_PATTERN_CAPTURE ",ProjectSettings.globalize_path("user://"+name+".png"))
	return result

func _run() -> void:
	var material := Materials.water_material().duplicate() as ShaderMaterial
	check(float(material.get_shader_parameter("glint_density")) <= 0.05,"glint density too high")
	check(float(material.get_shader_parameter("glint_length")) <= 6.0,"glint strip too long")
	check(float(material.get_shader_parameter("glint_thickness")) <= 1.0,"glint strip too thick")
	if DisplayServer.get_name() != "headless":
		material.set_shader_parameter("background_water",true)
		material.set_shader_parameter("coordinate_scale",16.0)
		material.set_shader_parameter("preview_time",0.0)
		var world := Node3D.new()
		root.add_child(world)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("233e46")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.65
		world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-55,-30,0)
		world.add_child(light)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(0,95,105)
		camera.look_at(Vector3.ZERO)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 145
		camera.current = true
		var single := MeshInstance3D.new()
		single.mesh = plane(8)
		single.material_override = material
		single.scale = Vector3.ONE*16
		single.position = Vector3(-64,0,-64)
		world.add_child(single)
		var halves: Array[MeshInstance3D] = []
		for half in 2:
			var visual := MeshInstance3D.new()
			visual.mesh = plane(4)
			visual.material_override = material
			visual.scale = Vector3.ONE*16
			visual.position = Vector3(-64+half*64,0,-64)
			visual.visible = false
			world.add_child(visual)
			halves.append(visual)
		var full := await capture("water_pattern_single")
		single.visible = false
		for half in halves: half.visible = true
		var split := await capture("water_pattern_split")
		var significant_pixels := 0
		var difference := 0.0
		var total := 0
		for y in full.get_height():
			for x in full.get_width():
				var a := full.get_pixel(x,y)
				var b := split.get_pixel(x,y)
				var delta := maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
				difference += delta
				total += 1
				if delta > 0.04: significant_pixels += 1
		check(significant_pixels < 50 and difference/total < 0.0005,"independent water halves show a visible seam")
		print("WATER_PATTERN_SEAM_DIFF pixels=",significant_pixels," average=",difference/total)
		material.set_shader_parameter("preview_time",4.0)
		var motion := await capture("water_pattern_motion")
		var moving := 0
		for y in range(0,full.get_height(),4):
			for x in range(0,full.get_width(),4):
				if motion.get_pixel(x,y) != split.get_pixel(x,y): moving += 1
		check(moving > 100,"broad water pattern no longer moves")
		# Isolate camera reflection from deliberate pixel-art patch boundaries.
		# Perspective VIEW varies across a flat plane: quantizing it creates
		# long unrelated cuts through every patch, even without any chunk seam.
		material.set_shader_parameter("water_tint",Color(0.2,0.6,0.6))
		material.set_shader_parameter("water_light_tone",Color(0.2,0.6,0.6))
		material.set_shader_parameter("water_deep_tone",Color(0.2,0.6,0.6))
		material.set_shader_parameter("reflection_strength",0.4)
		material.set_shader_parameter("sky_reflection_color",Color.WHITE)
		material.set_shader_parameter("ripple_alpha",0.0)
		material.set_shader_parameter("glint_strength",0.0)
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.position = Vector3(0,55,100)
		camera.look_at(Vector3.ZERO)
		var reflection := await capture("water_pattern_reflection")
		var near_pixel := camera.unproject_position(Vector3(0,0,50))
		var far_pixel := camera.unproject_position(Vector3(0,0,-50))
		var maximum_jump := 0.0
		var sample_x := clampi(int(near_pixel.x),0,reflection.get_width()-1)
		var first_y := maxi(1,int(minf(near_pixel.y,far_pixel.y)))
		var last_y := mini(reflection.get_height()-1,int(maxf(near_pixel.y,far_pixel.y)))
		check(last_y-first_y > 40,"reflection probe must span the tilted water plane")
		for y in range(first_y,last_y):
			var a := reflection.get_pixel(sample_x,y)
			var b := reflection.get_pixel(sample_x,y+1)
			maximum_jump = maxf(maximum_jump,maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))))
		print("WATER_REFLECTION_MAX_JUMP ",maximum_jump)
		check(maximum_jump < 0.012,"camera reflection cuts the water into abrupt bands")
		for half in halves: half.visible = false
		var harbour := MeshInstance3D.new()
		var harbour_mesh := BoxMesh.new()
		harbour_mesh.size = Vector3(1800,2,1500)
		harbour.mesh = harbour_mesh
		harbour.position = Vector3(192,-9,80)
		var harbour_material := Materials.water_material().duplicate() as ShaderMaterial
		harbour_material.set_shader_parameter("background_water",true)
		harbour_material.set_shader_parameter("coordinate_scale",16.0)
		harbour_material.set_shader_parameter("preview_time",0.0)
		harbour.material_override = harbour_material
		world.add_child(harbour)
		camera.transform = Transform3D(Vector3(0.555523,0,0.831501),Vector3(0.593532,0.700342,-0.396536),Vector3(-0.582336,0.713807,0.389056),Vector3(580.1181,107.5877,314.4935))
		camera.fov = 70.01
		await capture("water_pattern_harbour")
		var diagnostic_shader := Shader.new()
		var diagnostic_code := harbour_material.shader.code.replace("return floor(clamp(broad, 0.0, 0.999) * 3.0) / 2.0;","return broad;")
		diagnostic_code = diagnostic_code.substr(0,diagnostic_code.find("void fragment()"))
		diagnostic_code = diagnostic_code.replace("diffuse_toon, specular_disabled","unshaded")
		diagnostic_shader.code = diagnostic_code + "void fragment() { float tone = stepped_tone_drift(floor(surface_coordinate * 16.0),0.0); ALBEDO = vec3(tone); }"
		harbour_material.shader = diagnostic_shader
		await capture("water_pattern_harbour_continuous")
		# Probe both sides of many interpolation-cell boundaries on the GPU.
		# Deliberately discrete palette bands are not part of this comparison.
		diagnostic_shader.code = diagnostic_code + "void fragment() { vec2 cell = floor(FRAGCOORD.xy / 8.0) - vec2(100.0,60.0); float a = broad_value_noise(cell + vec2(0.9999,0.37)); float b = broad_value_noise(cell + vec2(1.0001,0.37)); float c = broad_value_noise(cell + vec2(0.37,0.9999)); float d = broad_value_noise(cell + vec2(0.37,1.0001)); ALBEDO = vec3(step(0.005,max(abs(a-b),abs(c-d)))); }"
		var boundaries := await capture("water_pattern_noise_boundaries")
		var torn_pixels := 0
		for y in boundaries.get_height():
			for x in boundaries.get_width():
				var color := boundaries.get_pixel(x,y)
				if color.r > 0.9 and color.g > 0.9 and color.b > 0.9: torn_pixels += 1
		print("WATER_NOISE_TORN_PIXELS ",torn_pixels)
		check(torn_pixels == 0,"broad water noise tears across interpolation-cell boundaries")
		world.free()
	for message in errors: push_error(message)
	print("test_water_pattern_seams: ","PASS" if errors.is_empty() else "FAIL"," · ",errors.size())
	quit(0 if errors.is_empty() else 1)
