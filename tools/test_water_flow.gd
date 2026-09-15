extends SceneTree
## Native W03 light-network probes: world seams, time, depth and distant fade.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var errors := PackedStringArray()
var world: Node3D
var camera: Camera3D
var material: ShaderMaterial

func _init() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func plane(width: float, depth: float) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,0,8),Vector3.ZERO,Vector3(width,0,0),Vector3(width,0,8)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(depth,0),Vector2(depth,0),Vector2(depth,0),Vector2(depth,0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func surface(width: float, position: Vector3, depth := 0.0) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = plane(width,depth)
	visual.material_override = material
	visual.position = position
	world.add_child(visual)
	return visual

func capture(label: String) -> Image:
	for frame in 16: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	result.save_png("res://art/water/flow/qa/probe-"+label+".png")
	return result

func image_delta(a: Image, b: Image) -> Array:
	var significant := 0
	var sum := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var av := a.get_pixel(x,y).r
			var difference := absf(av-b.get_pixel(x,y).r)
			sum += difference
			if difference > 0.04: significant += 1
	return [significant,sum/(a.get_width()*a.get_height())]

func brightness(image: Image) -> float:
	var result := 0.0
	var count := 0
	for y in range(64,448,4):
		for x in range(64,448,4):
			result += image.get_pixel(x,y).r
			count += 1
	return result/count

func run() -> void:
	var original := Materials.water_material()
	check(original.get_shader_parameter("flow_network_strength") == 0.6,"canonical light-network strength changed")
	check(original.get_shader_parameter("flow_network_deep_ratio") == 0.32,"canonical deep attenuation changed")
	check(original.get_shader_parameter("flow_pixel_density") == 32.0,"canonical network pixel scale changed")
	check(original.get_shader_parameter("body_emission") == 0.0,"water/network must not glow by default")
	check("flowing_ripple_network" in original.shader.code,"shared water shader lost the moving network")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(512,512)
		root.content_scale_size = Vector2i(512,512)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/water/flow/qa"))
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
		var code := original.shader.code
		code = code.substr(0,code.find("void light()"))
		code = code.substr(0,code.rfind("}"))+"\nALBEDO = vec3(flow_weight); EMISSION = vec3(0.0); ALPHA = 1.0;\n}"
		code = code.replace("specular_schlick_ggx, specular_occlusion_disabled","unshaded")
		var diagnostic := Shader.new()
		diagnostic.code = code
		material.shader = diagnostic
		material.set_shader_parameter("coordinate_scale",1.0)
		material.set_shader_parameter("preview_time",3.25)
		var single := surface(8,Vector3(-4,0,-4))
		var full := await capture("network-full")
		check(brightness(full) > 0.02,"light network is not visible")
		single.visible = false
		var left := surface(3.37,Vector3(-4,0,-4))
		var right := surface(4.63,Vector3(-0.63,0,-4))
		var split := await capture("network-split")
		var seam := image_delta(full,split)
		print("WATER_FLOW_SPLIT_DIFF significant=",seam[0]," average=",seam[1]," boundary=-0.63, negative/positive world coordinates")
		check(seam[0] < 20 and seam[1] < 0.0005,"light network tears across split meshes")
		left.visible = false
		right.visible = false
		single.visible = true
		material.set_shader_parameter("preview_time",3.75)
		var moved := await capture("network-time")
		var motion := image_delta(full,moved)
		print("WATER_FLOW_MOTION significant=",motion[0]," average=",motion[1])
		check(motion[0] > 100,"light-network figures do not change over continuous time")
		material.set_shader_parameter("preview_time",3.25)
		single.visible = false
		var deep_surface := surface(8,Vector3(-4,0,-4),1.0)
		var deep := await capture("network-deep")
		var shallow_value := brightness(full)
		var deep_value := brightness(deep)
		print("WATER_FLOW_DEPTH shallow=",shallow_value," deep=",deep_value)
		check(deep_value > 0.005 and shallow_value > deep_value*1.2,"network depth attenuation is wrong")
		deep_surface.visible = false
		single.visible = true
		material.set_shader_parameter("flow_network_strength",0.0)
		var disabled := await capture("network-disabled")
		check(brightness(disabled) < 0.001,"disabled light network remains visible")
		material.set_shader_parameter("flow_network_strength",0.6)
		camera.size = 64
		var distant := await capture("network-distant")
		check(brightness(distant) < 0.001,"subpixel light network does not fade")
		world.free()
	for error in errors: push_error(error)
	var checks := "material defaults/no glow" if DisplayServer.get_name() == "headless" else "moving world network, split/negative coordinates, depth and distance"
	print("PASS WATER_FLOW: "+checks if errors.is_empty() else "FAIL WATER_FLOW")
	quit(0 if errors.is_empty() else 1)
