extends SceneTree
## Native GPU regression for the missing-floor seam at an animated shoreline.
## Synthetic nodes only; no map or authored Resource is saved or modified.
const WATER = preload("res://shaders/ember_compact_sky_reflection_study.gdshader")
var material: ShaderMaterial
var floor_mesh: MeshInstance3D
var failures: Array[String] = []
func _init() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:failures.append(label);printerr("FAIL ",label)
func sample() -> Color:
	for frame in 5:await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	return image.get_pixel(image.get_width()/2,image.get_height()/2)
func run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("Native Forward+ required");quit(2);return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(256,256))
	var scene := Node3D.new();root.add_child(scene);current_scene=scene
	var environment := WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color.BLACK;scene.add_child(environment)
	floor_mesh=MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(16,16)
	floor_mesh.mesh=plane;floor_mesh.position.y=3
	var ground := StandardMaterial3D.new();ground.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.albedo_color=Color(0.55,0.25,0.07);floor_mesh.material_override=ground;scene.add_child(floor_mesh)
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-8,4,-8),Vector3(8,4,8),Vector3(8,4,-8),Vector3(-8,4,-8),Vector3(-8,4,8),Vector3(8,4,8)])
	var normals := PackedVector3Array();var uv := PackedVector2Array();var colors := PackedColorArray()
	for i in 6:normals.append(Vector3.UP);uv.append(Vector2.ZERO);colors.append(Color(1,1,1,1.0/64.0))
	arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	material=ShaderMaterial.new();material.shader=WATER;material.render_priority=1
	for key in ["wave_height_voxels","local_bob_strength","refraction_strength","sky_reflection_strength","planar_reflection_mix","river_crest_whiteness","object_foam_strength","sea_swash_strength","foam_trail_strength","water_glint_strength"]:material.set_shader_parameter(key,0.0)
	material.set_shader_parameter("preview_time",0.0)
	material.set_shader_parameter("floor_camera_available",1.0)
	# This is the actual input when the submerged-only camera clips the seabed
	# at the mean plane, while a crest above that plane still covers it.
	var missing := Image.create(2,2,false,Image.FORMAT_RGBA8);missing.fill(Color.TRANSPARENT)
	material.set_shader_parameter("floor_refraction",ImageTexture.create_from_image(missing))
	var water := MeshInstance3D.new();water.mesh=mesh;water.material_override=material;scene.add_child(water)
	var camera := Camera3D.new();scene.add_child(camera)
	camera.look_at_from_position(Vector3(0,24,12),Vector3(0,3,0));camera.make_current()
	var former := Shader.new()
	former.code=WATER.code.replace("floor_color += (scene_floor - water_color) * (1.0 - floor_coverage);","floor_color += vec3(0.0);")
	material.shader=former
	var before: Color=await sample()
	material.shader=WATER
	var after: Color=await sample()
	check(before.b>before.r*1.4,"negative control reproduces cyan missing-floor colour")
	check(after.r>after.b*1.3,"clipped floor retains brown opaque terrain through water")
	floor_mesh.hide();var no_ground: Color=await sample()
	check(Vector3(no_ground.r,no_ground.g,no_ground.b).distance_to(Vector3(before.r,before.g,before.b))<0.04,"sky/absent depth is not pulled into the water")
	floor_mesh.show()
	var valid := Image.create(2,2,false,Image.FORMAT_RGBA8);valid.fill(Color(0.05,0.5,0.1,1))
	material.set_shader_parameter("floor_refraction",ImageTexture.create_from_image(valid))
	var present: Color=await sample()
	check(present.g>present.r*1.4,"valid dedicated floor-camera coverage is retained")
	valid.fill(Color(0.05,0.5,0.1,0.5))
	material.set_shader_parameter("floor_refraction",ImageTexture.create_from_image(valid))
	var partial: Color=await sample()
	var expected := after.srgb_to_linear().lerp(present.srgb_to_linear(),0.5).linear_to_srgb()
	check(absf(partial.r-expected.r)<0.025 and absf(partial.g-expected.g)<0.025,"filtered edge combines the two actual floor colours without a water-colour seam")
	print("WATER_FLOOR_GAP ","PASS" if failures.is_empty() else "FAIL"," before=",before," after=",after," missing=",no_ground," valid=",present," partial=",partial," expected=",expected," errors=",failures)
	quit(0 if failures.is_empty() else 1)
