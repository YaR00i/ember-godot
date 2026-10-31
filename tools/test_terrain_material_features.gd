extends SceneTree
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Patch = preload("res://scripts/ember_grass_patch.gd")
var errors: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: errors.append(label); printerr("MATERIAL_FEATURE_FAIL ", label)

func features(material: ShaderMaterial) -> Dictionary:
	return material.shader.get_meta("ember_feature_values", {})

func textures(material: ShaderMaterial) -> Dictionary:
	var result: Dictionary = {}
	for item in material.shader.get_shader_uniform_list():
		var value: Variant = material.get_shader_parameter(item.name)
		if value is Texture: result[item.name] = value.get_rid()
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var roles := PackedStringArray(["", "soil", "grass"])
	var ids := PackedStringArray(["", "cartoon_soil", "cartoon_grass"])
	var map := EmberMapLoader.new()
	var patch := Patch.new()
	patch._visual = MultiMeshInstance3D.new()
	patch.add_child(patch._visual)
	var material := Materials.compact_flower_material()
	Materials.set_compact_terrain_roles(material, roles, ids)
	material.set_shader_parameter("smooth_surface_enabled", true)
	material.set_shader_parameter("painterly_blades", true)
	material.set_shader_parameter("material_light_mode", 1)
	material.set_shader_parameter("material_gray_preview", false)
	map.bind_voxel_light(material, 0, 16.0)
	var original := material.shader
	check(Materials._expand_terrain_feature_code(original.code) == reference_source(original.code), "resource loading preserves the measured shader source")
	var before_textures := textures(material)
	var names: Array = []
	for item in original.get_shader_uniform_list(): names.append(item.name)
	Materials.refresh_terrain_features(material)
	var initial := material.shader
	check(initial != original and initial.get_meta("ember_feature_base") == original, "published cards select a derived program")
	var after_names: Array = []
	for item in initial.get_shader_uniform_list(): after_names.append(item.name)
	check(names == after_names and textures(material) == before_textures, "uniform interface and existing texture RIDs survive")
	check(bool(features(material).grass_light_profiles_enabled), "prepared grass profile stays enabled")
	patch._visual.material_override = material
	patch.set_material_light(2, true)
	check(features(material).material_light_mode == 2 and features(material).material_gray_preview, "real patch light/gray command updates the program")
	map.bind_voxel_light(material, 2, 16.0, true)
	check(features(material).voxel_light_enabled and features(material).voxel_light_anomaly, "real look/anomaly binding updates the program")
	var pattern = Materials.load_compact_terrain_variant("cartoon_grass").duplicate()
	pattern.grass_light_enabled = false
	Materials.update_grass_light_profile(material, 2, pattern)
	check(not features(material).grass_light_profiles_enabled, "live profile disable is not frozen")
	pattern.style_rim_custom = true
	pattern.style_rim_enabled = true
	Materials.update_style_rim_profile(material, 2, pattern)
	check(features(material).style_rim_profiles_enabled, "live rim enable is not frozen")
	Materials.set_compact_terrain_roles(material, roles, ids)
	patch.set_material_light(1, false)
	map.bind_voxel_light(material, 0, 16.0)
	check(material.shader == initial, "cancel/restore reuses the initial program")
	check(textures(material).size() == before_textures.size(), "full role refresh retains every texture binding")
	var sibling := Materials.compact_flower_material()
	Materials.set_compact_terrain_roles(sibling, roles, ids)
	for field in Materials.TERRAIN_FEATURE_FIELDS:
		var value: Variant = material.get_shader_parameter(field)
		if value != null: sibling.set_shader_parameter(field, value)
	Materials.refresh_terrain_features(sibling)
	check(sibling != material and sibling.shader == material.shader, "private bindings share an immutable feature program")
	check(sibling.get_shader_parameter("grass_light_lookup") != material.get_shader_parameter("grass_light_lookup"), "editable profile textures remain private")
	var ground := Materials.compact_terrain_material()
	ground.shader = Materials.compact_terrain_bank_far_shader()
	check(Materials._expand_terrain_feature_code(ground.shader.code) == reference_source(ground.shader.code), "ground resource loading preserves the measured shader source")
	Materials.set_compact_terrain_roles(ground, roles, ids)
	var projection := TerrainProjection.new()
	map.add_child(projection)
	projection._ground_material = ground
	projection.ground_style = 1
	for look in [0, 1, 2, 0]:
		projection.set_world_look(look)
		check(features(ground).look_study_mode == look and bool(features(ground).voxel_light_enabled) == (look == 2), "ground world look updates " + str(look))
		check(bool(features(ground).smooth_surface_enabled) == (look != 2), "ground layout follows look " + str(look))
	projection.set_material_light(2, true)
	check(features(ground).material_light_mode == 2 and features(ground).material_gray_preview, "ground light/gray command updates")
	var far := Materials.compact_terrain_far_material(ground)
	check(features(far) == features(ground), "far material retains the same current features")
	var unknown := ShaderMaterial.new()
	unknown.shader = Shader.new()
	unknown.shader.code = "shader_type spatial; void fragment(){ALBEDO=vec3(1.0);}"
	var untouched := unknown.shader
	Materials.refresh_terrain_features(unknown)
	check(unknown.shader == untouched, "foreign shader remains untouched")
	var generic_cover := Materials.compact_grass_material()
	Materials.set_compact_terrain_roles(generic_cover, roles, ids)
	for field in Materials.TERRAIN_FEATURE_FIELDS:
		var value: Variant = material.get_shader_parameter(field)
		if value != null: generic_cover.set_shader_parameter(field, value)
	Materials.refresh_terrain_features(generic_cover)
	check(Materials._expand_terrain_feature_code(generic_cover.shader.get_meta("ember_feature_base").code) == reference_source(generic_cover.shader.get_meta("ember_feature_base").code), "generic cover resource source remains identical")
	await render_looks(map, projection, ground, material, generic_cover)
	patch.free(); map.free()
	await process_frame
	print("MATERIAL_FEATURES ", JSON.stringify({"pass": errors.is_empty(), "errors": errors, "cached_programs": Materials._terrain_feature_programs.size()}))
	quit(0 if errors.is_empty() else 1)

func reference_source(code: String) -> String:
	var lines := PackedStringArray()
	for line in code.split("\n"):
		if line.strip_edges().begins_with("#include "):
			lines.append(reference_source(FileAccess.get_file_as_string(line.get_slice('"', 1))))
		else: lines.append(line)
	return "\n".join(lines)

func render_looks(map: EmberMapLoader, projection: Node3D, ground: ShaderMaterial, cover: ShaderMaterial, generic_cover: ShaderMaterial) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(0,0,0),Vector3(16,0,0),Vector3(0,0,16),Vector3(16,0,0),Vector3(16,0,16),Vector3(0,0,16)]:
		surface.set_normal(Vector3.UP)
		surface.set_color(Color(0.5, 0.5, 0, 2.0/255.0))
		surface.set_uv(Vector2(2, 1)/255.0)
		surface.set_uv2(Vector2(2, 0)/255.0)
		surface.add_vertex(point)
	var visual := MeshInstance3D.new()
	visual.mesh = surface.commit()
	viewport.add_child(visual)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(23, 25, 23), Vector3(8, 0, 8))
	camera.make_current()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -25, 0)
	sun.shadow_enabled = true
	viewport.add_child(sun)
	var atlas := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0.3, 0.7, 0.2, 1))
	cover.set_shader_parameter("flower_atlas", ImageTexture.create_from_image(atlas))
	cover.set_shader_parameter("flower_palette_slot", 2.0)
	projection.set_material_light(1, false)
	for look in [0, 1, 2]:
		projection.set_world_look(look)
		map.bind_voxel_light(cover, look, 16.0)
		map.bind_voxel_light(generic_cover, look, 16.0)
		for material: ShaderMaterial in [ground, cover, generic_cover]:
			var label := "ground" if material == ground else "cover" if material == cover else "generic_cover"
			visual.material_override = material
			var program := material.shader
			var base: Shader = program.get_meta("ember_feature_base")
			material.shader = base
			for i in 15: await process_frame
			await RenderingServer.frame_post_draw
			var expected := viewport.get_texture().get_image().get_data()
			var visible_pixels := 0
			for i in range(3, expected.size(), 4):
				if expected[i] > 0: visible_pixels += 1
			check(visible_pixels > 1000, "render fixture is visible")
			material.shader = program
			for i in 15: await process_frame
			await RenderingServer.frame_post_draw
			var actual := viewport.get_texture().get_image().get_data()
			var changed := 0
			var error_sum := 0
			for i in range(0, expected.size(), 4):
				var pixel_error := 0
				for channel in 3: pixel_error += absi(int(actual[i+channel])-int(expected[i+channel]))
				if pixel_error > 0: changed += 1
				error_sum += pixel_error
			check(changed <= 65 and error_sum <= 655, "mixed render parity look " + str(look) + " " + label)
			print("MATERIAL_FEATURE_RENDER ", look, " ", label, " changed_pixels=", changed, " error_sum=", error_sum)
	viewport.free()
