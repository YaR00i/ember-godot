extends SceneTree
## Native optical-cell probes, including negative coordinates and split meshes.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var errors := PackedStringArray()
var world: Node3D
var camera: Camera3D
var material: ShaderMaterial

func _init() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func plane(width: float) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,0,8),Vector3.ZERO,Vector3(width,0,0),Vector3(width,0,8)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ONE,Vector2.ONE,Vector2.ONE,Vector2.ONE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func surface(width: float, position: Vector3) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = plane(width)
	visual.material_override = material
	visual.position = position
	world.add_child(visual)
	return visual

func capture(label: String) -> Image:
	for frame in 16: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png("res://art/water/pixel/qa/probe-"+label+".png")
	return result

func at(image: Image, point: Vector3) -> Color:
	var pixel := camera.unproject_position(point)
	return image.get_pixel(clampi(int(pixel.x),0,image.get_width()-1),clampi(int(pixel.y),0,image.get_height()-1))

func delta(a: Color, b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))

func run() -> void:
	var original := Materials.water_material()
	check(original.get_shader_parameter("reflection_pixel_size") == 0.0625,"canonical cell size must be one voxel")
	check(original.get_shader_parameter("reflection_pixel_strength") == 1.0,"canonical pixel effect missing")
	check(original.get_shader_parameter("preview_time") == -1.0,"QA time escaped")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(512,512)
		root.content_scale_size = Vector2i(512,512)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/water/pixel/qa"))
		world = Node3D.new()
		root.add_child(world)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color.BLACK
		world.add_child(environment)
		camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 8
		camera.position = Vector3(0,8,0)
		world.add_child(camera)
		camera.look_at(Vector3.ZERO,Vector3.FORWARD)
		camera.current = true
		material = original.duplicate() as ShaderMaterial
		# Execute the production fragment. Only its output is replaced to expose
		# its optical NORMAL directly, independently of environment/body shading.
		var code := original.shader.code
		code = code.substr(0,code.find("void light()"))
		code = code.substr(0,code.rfind("}"))+"\nALBEDO = vec3(NORMAL.xy * 0.5 + vec2(0.5), 0.0); EMISSION = vec3(0.0); ALPHA = 1.0;\n}"
		code = code.replace("specular_schlick_ggx, specular_occlusion_disabled","unshaded")
		var diagnostic := Shader.new()
		diagnostic.code = code
		material.shader = diagnostic
		material.set_shader_parameter("coordinate_scale",1.0)
		material.set_shader_parameter("reflection_pixel_size",0.25)
		material.set_shader_parameter("preview_time",3.25)
		var single := surface(8,Vector3(-4,0,-4))
		var full := await capture("cells-full")
		var variation := 0.0
		for z in 24:
			for x in 24:
				var center := Vector3(-2.875+x*0.25,0,-2.875+z*0.25)
				variation = maxf(variation,delta(at(full,center+Vector3(-0.055,0,-0.055)),at(full,center+Vector3(0.055,0,0.055))))
		print("WATER_PIXEL_WITHIN_CELL_MAX ",variation," negative/positive world coordinates")
		check(variation < 0.0041,"optical cells are not constant within their bounds")
		single.visible = false
		var left := surface(3.37,Vector3(-4,0,-4))
		var right := surface(4.63,Vector3(-0.63,0,-4))
		var split := await capture("cells-split")
		var changed := 0
		var sum := 0.0
		for y in full.get_height():
			for x in full.get_width():
				var d := delta(full.get_pixel(x,y),split.get_pixel(x,y))
				sum += d
				if d > 0.04: changed += 1
		print("WATER_PIXEL_SPLIT_DIFF significant=",changed," average=",sum/(full.get_width()*full.get_height())," boundary=-0.63 not aligned to cells")
		check(changed < 20 and sum/(full.get_width()*full.get_height()) < 0.0005,"split optical cells show seams")
		left.visible = false
		right.visible = false
		single.visible = true
		material.set_shader_parameter("reflection_pixel_strength",0.0)
		var smooth := await capture("cells-smooth")
		var continuous_cells := 0
		for z in 24:
			for x in 24:
				var center := Vector3(-2.875+x*0.25,0,-2.875+z*0.25)
				if delta(at(smooth,center+Vector3(-0.055,0,-0.055)),at(smooth,center+Vector3(0.055,0,0.055))) > 0.0041: continuous_cells += 1
		print("WATER_PIXEL_DISABLED_CONTINUOUS_CELLS ",continuous_cells,"/576")
		check(continuous_cells > 100,"pixel strength zero did not restore continuous normals")
		material.set_shader_parameter("reflection_pixel_strength",1.0)
		material.set_shader_parameter("preview_time",6.25)
		var motion := await capture("cells-time")
		check(motion.get_data() != full.get_data(),"cell optics stopped moving")
		material.set_shader_parameter("preview_time",3.25)
		material.set_shader_parameter("reflection_pixel_size",0.5)
		var coarse := await capture("cells-coarse")
		check(coarse.get_data() != full.get_data(),"cell size has no native response")
		# Tiny cell footprint must converge to the continuous W01 normal field.
		material.set_shader_parameter("reflection_pixel_size",0.015625)
		camera.size = 32
		var filtered := await capture("cells-filtered")
		material.set_shader_parameter("reflection_pixel_strength",0.0)
		var distant_smooth := await capture("cells-distant-smooth")
		check(filtered.get_data() == distant_smooth.get_data(),"subpixel cells do not fade back to continuous optics")
		world.free()
	for error in errors: push_error(error)
	var checks := "material defaults/live time" if DisplayServer.get_name() == "headless" else "world cells/split/negative coordinates, size/strength/time, subpixel convergence"
	print("PASS WATER_PIXEL: "+checks if errors.is_empty() else "FAIL WATER_PIXEL")
	quit(0 if errors.is_empty() else 1)
