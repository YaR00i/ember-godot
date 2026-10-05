extends SceneTree
## Fixed-camera, fixed-time Forward+ water and ground-finish comparisons.

const MAP_PATH := "res://scenes/new_landscape4.tscn"
const OUTPUT_DIR := "user://ember-tests/water-look"
const WATER_VARIANTS := {
	"c_surface_play": {
		"flow_network_strength": 0.0,
		"water_tint": Color(0.025, 0.69, 0.90),
		"water_light_tone": Color(0.32, 0.90, 0.99),
		"water_deep_tone": Color(0.028, 0.51, 0.82),
		"wave_shadow_tone": Color(0.02, 0.44, 0.72),
		"wave_crest_tone": Color(0.27, 0.84, 0.96),
		"tint_strength": 0.48,
		"tone_strength": 0.17,
		"patch_strength": 0.12,
		"palette_strength": 0.0,
		"shallow_opacity": 0.58,
		"deep_opacity": 0.92,
		"layered_water_mix": 0.0,
		"wave_natural_mix": 0.86,
		"wave_strength": 0.19,
		"wave_length": 1.3,
		"wave_band_strength": 0.08,
		"surface_crest_strength": 0.12,
		"sun_glitter_strength": 0.0,
		"lagoon_shimmer_strength": 0.80,
		"reflection_pixel_strength": 0.0,
		"reflection_strength": 0.22,
		"surface_roughness": 0.30,
		"highlight_strength": 0.27,
		"underwater_light_mix": 0.0,
		"underwater_caustic_strength": 0.0,
		"underwater_depth_range": 1.5,
		"underwater_caustic_wave_link": 1.0,
	},
}


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load(MAP_PATH) as PackedScene).instantiate()
	root.add_child(scene)
	var projection: EmberTerrainPilotProjection
	for frame in 320:
		await process_frame
		projection = _find_projection(scene)
		if projection != null and projection.pending_tile_count() == 0 and frame > 25:
			break
	if projection == null or projection.pending_tile_count() > 0:
		push_error("compact terrain did not finish")
		quit(1)
		return
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 460.0
	camera.far = 2400.0
	camera.global_position = Vector3(970.0, 660.0, -470.0)
	camera.look_at(Vector3(350.0, 18.0, 350.0))
	camera.make_current()
	var material := projection.get("_water_material") as ShaderMaterial
	if material == null:
		push_error("compact water material is missing")
		quit(1)
		return
	var directory := ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("cannot create water-look output directory")
		quit(1)
		return
	var original: Dictionary = {}
	for variant in WATER_VARIANTS.values():
		for key in variant:
			original[key] = material.get_shader_parameter(key)
	for name in ["current", "c_surface_play"]:
		for key in original:
			material.set_shader_parameter(key, original[key])
		if name != "current":
			for key in WATER_VARIANTS[name]:
				material.set_shader_parameter(key, WATER_VARIANTS[name][key])
		for moment in [0.0, 4.0]:
			material.set_shader_parameter("preview_time", moment)
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/%s-t%d.png" % [OUTPUT_DIR, name, int(moment)]
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("cannot save " + path)
				quit(1)
				return
			print("PASS water look capture: ", ProjectSettings.globalize_path(path))
	for key in original:
		material.set_shader_parameter(key, original[key])
	var ground := projection.get("_ground_material") as ShaderMaterial
	if ground == null:
		push_error("compact ground material is missing")
		quit(1)
		return
	var original_finish := ground.get_shader_parameter("finish_lookup") as Texture2D
	if original_finish == null:
		push_error("compact finish lookup is missing")
		quit(1)
		return
	for finish_name in ["matte", "toy"]:
		var image := original_finish.get_image()
		if finish_name == "toy":
			for index in projection.document.palette_surface_roles.size():
				var role: String = projection.document.palette_surface_roles[index]
				if role == "grass": image.set_pixel(index, 0, Color(1.0, 1.0, 1.0, 1.0))
				if role == "sand": image.set_pixel(index, 0, Color(1.0, 1.0, 1.0, 1.0))
		ground.set_shader_parameter("finish_lookup", ImageTexture.create_from_image(image))
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/ground-%s.png" % [OUTPUT_DIR, finish_name]
		if root.get_texture().get_image().save_png(path) != OK:
			push_error("cannot save " + path)
			quit(1)
			return
		print("PASS ground finish capture: ", ProjectSettings.globalize_path(path))
	var unshaded := StandardMaterial3D.new()
	unshaded.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	unshaded.albedo_color = Color(0.7, 0.7, 0.7)
	for visual in projection.find_children("Ground", "MeshInstance3D", true, false):
		(visual as MeshInstance3D).material_override = unshaded
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var diagnostic := "%s/ground-unshaded-debug.png" % OUTPUT_DIR
	if root.get_texture().get_image().save_png(diagnostic) != OK:
		push_error("cannot save " + diagnostic)
		quit(1)
		return
	print("PASS ground unshaded diagnostic: ", ProjectSettings.globalize_path(diagnostic))
	quit()


func _find_projection(node: Node) -> EmberTerrainPilotProjection:
	if node is EmberTerrainPilotProjection:
		return node as EmberTerrainPilotProjection
	for child in node.get_children():
		var found := _find_projection(child)
		if found != null:
			return found
	return null
