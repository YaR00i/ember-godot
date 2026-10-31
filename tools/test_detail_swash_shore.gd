extends SceneTree
## Native Forward+: a wave crosses the physical ramp inside a source cell.
## Legacy coverage must stay stepped; detailed water/foam share the true edge.
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Builder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
var failures: Array[String] = []
var camera: Camera3D
var material: ShaderMaterial

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, text: String) -> void:
	if not ok: failures.append(text); printerr("DETAIL_SHORE FAIL ", text)
func frames() -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
func pixel(image: Image, x: float) -> Color:
	var screen := camera.unproject_position(Vector3(x, 24.0, 32.0))
	var scale := Vector2(image.get_size()) / root.get_visible_rect().size
	return image.get_pixelv(Vector2i(screen * scale))
func difference(a: Color, b: Color) -> float:
	return Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.size = Vector2i(800, 600)
	var source := Terrain.new()
	source.width = 64; source.depth = 64; source.height_limit = 96
	source.palette = PackedColorArray([Color.TRANSPARENT, Color(0.45,0.25,0.1)])
	for key in ["heights","water_levels","water_materials","top_materials","base_materials","cap_depths"]:
		var channel = source.get(key); channel.resize(4096); source.set(key,channel)
	for z in 64:
		for x in 64:
			var i := x+z*64
			source.heights[i] = x+1
			source.top_materials[i] = 1; source.base_materials[i] = 1
	var authored := source.heights.duplicate()
	var cells := PackedVector4Array()
	for z in range(28,36):
		for x in range(20,28): cells.append(Vector4(x,z,x+1,24))
	var built: Dictionary = Builder.build_tile(source,16,16,32,1,false,cells,{},false,false,true)
	var ground := MeshInstance3D.new(); ground.mesh = built.terrain
	var brown := StandardMaterial3D.new(); brown.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brown.albedo_color = Color(0.45,0.25,0.1); ground.material_override = brown; root.add_child(ground)
	var water := MeshInstance3D.new(); water.mesh = built.water
	material = ShaderMaterial.new(); material.shader = load("res://shaders/ember_compact_sky_reflection_study.gdshader")
	var info := Image.create(32,32,false,Image.FORMAT_RGBAF)
	var state := Image.create(32,32,false,Image.FORMAT_RGBAF)
	var extra := Image.create(32,32,false,Image.FORMAT_RGBAF)
	for z in 32:
		for x in 32:
			var gx := x+16
			info.set_pixel(x,z,Color(gx-22.5,gx+1,24,1))
			state.set_pixel(x,z,Color(maxf(24,gx+1.025),0,0,1 if gx<23 else 0))
			# Wave falls toward inland (+X), while the physical ramp rises.
			extra.set_pixel(x,z,Color(8,24-(gx+0.5-23.5)*0.08,0,1))
	var parameters := {"sea_swash_available":1.0,"sea_swash_strength":1.0,"sea_swash_origin":Vector2(16,16),
		"sea_swash_extent":Vector2(32,32),"sea_swash_info":ImageTexture.create_from_image(info),
		"sea_swash_state":ImageTexture.create_from_image(state),"sea_foam_age":ImageTexture.create_from_image(extra),
		"preview_time":0.0,"water_level_offset_voxels":0.0,"absorption_per_block":Vector3(64,64,64),
		"sky_reflection_strength":0.0,"planar_reflection_mix":0.0,"wave_height_voxels":0.0,
		"shore_foam_strength":0.0,"sea_foam_strength":0.0,"sea_foam_trail_strength":0.0,"foam_trail_strength":0.0}
	for key in parameters: material.set_shader_parameter(key,parameters[key])
	water.material_override = material; root.add_child(water)
	camera = Camera3D.new(); root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 4
	camera.position = Vector3(23.5,40,32); camera.look_at(Vector3(23.5,24,32),Vector3.FORWARD); camera.current = true
	await frames()
	var legacy := root.get_texture().get_image()
	material.set_shader_parameter("sea_smooth_shore",true)
	await frames()
	var detail := root.get_texture().get_image()
	# Ground crosses y=24 at x=23.5. Raw cell 23 is dry, but its left half
	# is genuinely submerged on the smoothed physical ramp.
	check(difference(pixel(detail,23.2),pixel(legacy,23.2))>0.03,"detailed wave still discarded a whole dry cell")
	check(difference(pixel(detail,23.8),pixel(legacy,23.8))<0.02,"water painted beyond the physical shoreline")
	# Raw-cell coverage/foam is zero on this cell, yet its submerged half needs
	# the same continuous, crisp edge. The deep side must not become a white fog.
	material.set_shader_parameter("sea_foam_strength",1.0)
	await frames()
	var foamed := root.get_texture().get_image()
	check(difference(pixel(foamed,23.2),pixel(detail,23.2))>0.03,"foam still follows raw-cell coverage instead of the physical edge")
	check(difference(pixel(foamed,22.3),pixel(detail,22.3))<0.02,"shore foam blurred over the deep side")
	check(difference(pixel(foamed,23.8),pixel(legacy,23.8))<0.02,"foam painted dry ground")
	material.set_shader_parameter("shore_foam_width_voxels",0.4)
	await frames()
	check(difference(pixel(root.get_texture().get_image(),23.2),pixel(detail,23.2))<0.02,"existing shore width control did not narrow the foam front")
	material.set_shader_parameter("shore_foam_width_voxels",1.8)
	# Neither a calm sheet nor the shallow trailing side of the same wave
	# may paint a second shore front. Keep the advancing-face check above.
	for wave_slope in [0.0,0.08]:
		for z in 32:
			for x in 32: extra.set_pixel(x,z,Color(8,24+(x+16.5-23.5)*wave_slope,0,1))
		(parameters.sea_foam_age as ImageTexture).update(extra)
		material.set_shader_parameter("sea_foam_strength",0.0)
		await frames()
		var bare := root.get_texture().get_image()
		material.set_shader_parameter("sea_foam_strength",1.0)
		await frames()
		check(difference(pixel(root.get_texture().get_image(),23.2),pixel(bare,23.2))<0.02,
			"calm/trailing shallows painted an independent second foam front: slope="+str(wave_slope))
	material.set_shader_parameter("sea_foam_strength",0.0)
	material.set_shader_parameter("sea_smooth_shore",false)
	await frames()
	check(difference(pixel(root.get_texture().get_image(),23.2),pixel(legacy,23.2))<0.005,"legacy shoreline changed after look return")
	check(source.heights==authored,"rendering changed source heights")
	print("DETAIL_SHORE ","PASS" if failures.is_empty() else "FAIL", " failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
