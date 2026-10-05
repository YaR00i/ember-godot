extends SceneTree
## Exercise the scene's actual water setup in play and in an isolated editor.

const Study = preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var setup_script: Script = load("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")
	if not setup_script.is_tool():
		push_error("FAIL water preview: the shared foam setup does not run in the 3D editor")
		quit(1)
		return
	var scene := Node3D.new()
	scene.name = "WaterPreviewFixture"
	root.add_child(scene)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.hydrate_legacy_regions = false
	map.compact_terrain = _fixture().sectioned_copy()
	map.compact_water_visual_material = load("res://materials/ember_compact_sky_reflection_study.tres")
	var look := Node3D.new()
	look.name = "Look"
	map.add_child(look)
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	environment.environment = Environment.new()
	look.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	look.add_child(sun)
	scene.add_child(map)
	var prop := Node3D.new()
	prop.name = "Prop"
	prop.position = Vector3(16, 8, 24)
	map.add_child(prop)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8, 12, 8)
	mesh.mesh = box
	mesh.position.y = 5
	prop.add_child(mesh)
	var contact := EmberWaterContact3D.new()
	contact.static_surface_foam_footprint = true
	prop.add_child(contact)
	var study := Study.new()
	assert(study.terrain_extent_error(Vector2i(8832, 8832)) != "")
	assert(study.terrain_extent_error(Vector2i(1920, 1920)) == "")
	assert(study.terrain_extent_error(Vector2i(3072, 1920)) == "")
	scene.add_child(study)
	for frame in 120:
		await process_frame
		if study.get("_prepared"):
			break
	var ready_deadline := Time.get_ticks_msec() + 30000
	while not study.get("_prepared") and Time.get_ticks_msec() < ready_deadline: await process_frame
	assert(study.get("_prepared"), "water fields were not prepared")
	var material: ShaderMaterial = study.get("_material")
	assert(float(material.get_shader_parameter("shore_field_available")) == 1.0)
	assert(float(material.get_shader_parameter("object_contact_available")) == 1.0)
	assert(float(material.get_shader_parameter("river_flow_enabled")) == 1.0)
	assert(not (contact.get("_visual") as MeshInstance3D).visible)
	assert(int(material.get_shader_parameter("object_shape_count")) == 1)
	var regional: ShaderMaterial = study._water_regions.regions[Vector2i.ZERO].water
	var original := regional.get_shader_parameter("shore_distance_map") as Texture2D
	var preview_revision: int = study.get("_fields_build_count")
	var level_projection := map.get("_visual_surface_projection") as EmberTerrainPilotProjection
	level_projection.set_material_light(2, true)
	var regional_ground: ShaderMaterial = study._water_regions.regions[Vector2i.ZERO].ground
	assert(int(regional_ground.get_shader_parameter("material_light_mode")) == 2)
	assert(bool(regional_ground.get_shader_parameter("material_gray_preview")))
	level_projection.set_material_light(0, false)
	var sample_point := Vector3(16, 0, 24)
	var original_surface: Dictionary = level_projection.water_surface_sample(sample_point)
	var levels := map.compact_terrain.water_levels.duplicate()
	var revision := level_projection.column_revision()
	var original_history: Texture2D = study._water_regions.regions[Vector2i.ZERO].sea.foam_age_texture
	study.water_detail_begin_m = 25.0
	study.water_detail_end_m = 85.0
	study.refresh_water_settings()
	assert(regional.get_shader_parameter("water_detail_begin_m") == 25.0)
	assert(regional.get_shader_parameter("water_detail_end_m") == 85.0)
	assert(study._water_regions.regions[Vector2i.ZERO].sea.foam_age_texture == original_history)
	assert(level_projection.water_surface_sample(sample_point).position == original_surface.position)
	assert(level_projection.column_revision() == revision and study.get("_fields_build_count") == preview_revision)
	study.water_level_offset_voxels = -0.5
	study.refresh_water_settings()
	var lower_surface: Dictionary = level_projection.water_surface_sample(sample_point)
	assert(lower_surface.wet and is_equal_approx(lower_surface.position.y, original_surface.position.y - 0.5))
	assert(is_equal_approx(float(material.get_shader_parameter("water_level_offset_voxels")), -0.5))
	assert(is_equal_approx(float(material.get_shader_parameter("water_level_world")), 7.52))
	assert(level_projection.column_revision() == revision and map.compact_terrain.water_levels == levels)
	assert(study.get("_fields_build_count") == preview_revision)
	study.water_level_offset_voxels = 0.0
	study.refresh_water_settings()
	assert(level_projection.water_surface_sample(sample_point).position == original_surface.position)
	study.river_crest_whiteness = 1.0
	study.call("_apply_parameters")
	assert(float(material.get_shader_parameter("river_crest_whiteness")) == 1.0)
	assert(regional.get_shader_parameter("shore_distance_map") == original)
	var history := UndoRedo.new()
	history.create_action("Preview crest whiteness")
	history.add_do_property(study, "river_crest_whiteness", 0.3)
	history.add_undo_property(study, "river_crest_whiteness", 1.0)
	history.commit_action()
	study.call("_apply_parameters")
	assert(is_equal_approx(float(material.get_shader_parameter("river_crest_whiteness")), 0.3))
	history.undo()
	study.call("_apply_parameters")
	assert(is_equal_approx(float(material.get_shader_parameter("river_crest_whiteness")), 1.0))
	history.redo()
	study.call("_apply_parameters")
	assert(is_equal_approx(float(material.get_shader_parameter("river_crest_whiteness")), 0.3))
	assert(study.get("_fields_build_count") == preview_revision)
	var foam_width: float = study.object_foam_width_voxels
	study.shore_foam_width_voxels = 5.0
	study.object_foam_width_voxels = 0.3
	study.river_wave_spacing_blocks = 10.0
	study.river_arc_opening = 0.2
	study.foam_width_pulse = 0.67
	study.call("_apply_parameters")
	assert(is_equal_approx(float(material.get_shader_parameter("object_foam_width_voxels")), 0.3))
	assert(is_equal_approx(float(material.get_shader_parameter("shore_foam_width_voxels")), 5.0))
	assert(is_equal_approx(float(material.get_shader_parameter("river_wave_spacing_blocks")), 10.0))
	assert(is_equal_approx(float(material.get_shader_parameter("foam_width_pulse")), 0.67))
	assert(study.get("_fields_build_count") == preview_revision)
	study.object_foam_width_voxels = foam_width
	if not Engine.is_editor_hint():
		contact.set_process(false)
		contact.wake_length_blocks = 4.0
		contact.sample_motion(0.1)
		contact.refresh_now()
		prop.position.z += 8.0
		contact.sample_motion(0.25)
		contact.refresh_now()
		contact._advance_wake(0.1)
		study._upload_surface_contacts()
		assert(int(material.get_shader_parameter("reaction_count")) > 0, "motion must emit surface arcs")
		assert(not (contact.get("_wake_visual") as MeshInstance3D).visible, "integrated contact must not draw a second flat wake")
		var shapes: PackedVector4Array = material.get_shader_parameter("object_shapes")
		assert(is_equal_approx(shapes[0].y, prop.global_position.z / 16.0), "moving outline must follow the real footprint")
		var emitted := contact.surface_wake_samples()
		prop.position.z += 2.0
		contact.sample_motion(0.1)
		contact.refresh_now()
		var advanced := contact.surface_wake_samples()
		for old_sample in emitted:
			var retained := false
			for sample in advanced:
				if sample["position"] == old_sample["position"]: retained = true
			if not retained:
				printerr("FAIL surface arcs: a living arc jumps to a different origin on the next emission")
				quit(1)
				return
		var sample_count := contact.wake_sample_count()
		prop.position.z -= 10.0
		contact.reset_motion_tracking()
		contact.sample_motion(0.1)
		contact.refresh_now()
		assert(contact.wake_sample_count() == sample_count, "restoring a preview transform must not emit a false wake")
		contact._advance_wake(3.0)
		study._upload_surface_contacts()
		assert(int(material.get_shader_parameter("reaction_count")) == 0, "stopped wake must expire")
		assert(study.get("_fields_build_count") == preview_revision)
		contact.set_process(true)
	history.clear_history()
	history.free()
	if Engine.is_editor_hint():
		assert(study.get("_viewport") == null and study.get("_floor_viewport") == null)
		assert(float(material.get_shader_parameter("floor_camera_available")) == 0.0)
		# Moving a prop refreshes its contour without rebuilding shore/flow fields.
		prop.position.x += 4.0
		var old_shapes: PackedVector4Array = material.get_shader_parameter("object_shapes")
		await create_timer(0.6).timeout
		assert(study.get("_fields_build_count") == preview_revision)
		assert(regional.get_shader_parameter("shore_distance_map") == original)
		assert(material.get_shader_parameter("object_shapes") != old_shapes)
		# Undo-like transform restoration, then removal, also invalidates the contour.
		prop.position.x -= 4.0
		await create_timer(0.6).timeout
		contact.static_surface_foam_footprint = false
		await create_timer(0.6).timeout
		assert(float(material.get_shader_parameter("object_contact_available")) == 0.0)
		assert((contact.get("_visual") as MeshInstance3D).visible)
		contact.static_surface_foam_footprint = true
		await create_timer(0.6).timeout
		assert(float(material.get_shader_parameter("object_contact_available")) == 1.0)
		# A terrain edit refreshes derived fields; reverting it restores the mask.
		var projection := map.get("_visual_surface_projection") as EmberTerrainPilotProjection
		projection.apply_heights(PackedInt32Array([17 + 24 * 32]), PackedInt32Array([10]))
		await create_timer(0.6).timeout
		assert(study.get("_fields_build_count") > preview_revision)
	var path := "user://ember-tests/water-editor-preview.tscn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ember-tests"))
	# Save only authored settings; temporary masks/cameras must stay derived.
	var authored := Node.new()
	authored.name = "WaterSettingsFixture"
	var settings := Study.new()
	settings.name = "Settings"
	authored.add_child(settings)
	settings.owner = authored
	settings.river_crest_whiteness = 0.77
	var packed := PackedScene.new()
	assert(packed.pack(authored) == OK)
	assert(ResourceSaver.save(packed, path) == OK)
	var reopened := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	assert(is_equal_approx(reopened.get_child(0).river_crest_whiteness, 0.77))
	assert(reopened.get_child(0).get_child_count() == 0)
	reopened.free()
	authored.free()
	print("PASS water preview: shared foam/flow, prop move/removal, parameter Undo/Redo, terrain refresh, authored save/reopen; editor=", Engine.is_editor_hint())
	scene.queue_free()
	await process_frame
	_authored_contact_settings()
	if Engine.is_editor_hint() and "--native-scene" in OS.get_cmdline_user_args():
		await _native_scene_preview()
	quit()


func _native_scene_preview() -> void:
	EditorInterface.open_scene_from_path("res://scenes/compact_sky_reflection_study.tscn")
	EditorInterface.set_main_screen_editor("3D")
	var authored: Node
	var study: Node
	for frame in 900:
		await process_frame
		authored = EditorInterface.get_edited_scene_root()
		if authored == null:
			continue
		study = authored.get_node_or_null("PlanarReflection")
		if study != null and study.get("_prepared"):
			break
	assert(study != null and study.get("_prepared"), "native scene water preview did not prepare")
	var material: ShaderMaterial = study.get("_material")
	var projection = authored.get_node("Map").get("_visual_surface_projection")
	assert(material == projection.get("_water_material"))
	assert(float(material.get_shader_parameter("ripple_field_available")) == 1.0)
	assert(float(material.get_shader_parameter("shore_field_available")) == 1.0)
	assert(float(material.get_shader_parameter("object_contact_available")) == 1.0)
	assert(int(material.get_shader_parameter("object_shape_count")) == 2)
	assert(study.get("_viewport") == null)
	for node in authored.find_children("*", "EmberWaterContact3D", true, false):
		var contact := node as EmberWaterContact3D
		if contact.static_surface_foam_footprint:
			assert(not (contact.get("_visual") as MeshInstance3D).visible)
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	assert(viewport != null)
	var camera := viewport.get_camera_3d()
	assert(camera != null)
	camera.far = 2400.0
	for view in ["contact", "bend"]:
		for setting in ["crest0", "crest1"]:
			material.set_shader_parameter("river_crest_whiteness", 1.0 if setting == "crest1" else 0.0)
			material.set_shader_parameter("preview_time", 4.0)
			camera.global_position = Vector3(430, 88, 525) if view == "contact" else Vector3(475, 140, 715)
			camera.look_at(Vector3(390, 16, 485) if view == "contact" else Vector3(367, 16, 610))
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var output := "user://ember-tests/water-editor-native-%s-%s.png" % [view, setting]
			assert(viewport.get_texture().get_image().save_png(output) == OK)
			print("PASS native 3D water screenshot: ", ProjectSettings.globalize_path(output))
	print("PASS actual native edited scene: integrated box/cylinder foam and shore fields; no gameplay cameras")


func _authored_contact_settings() -> void:
	# The compact fixture alone cannot catch a rig left above lowered water.
	# Inspect real saved scenes, without building their full terrain/cameras.
	for path in ["res://scenes/compact_sky_reflection_study.tscn",
		"res://scenes/compact_wave_obstacle_study.tscn",
		"res://scenes/compact_waterfall_study.tscn"]:
		var authored := (load(path) as PackedScene).instantiate()
		var settings := authored.get_node("PlanarReflection")
		assert(is_equal_approx(authored.get_node("Map/Look/Sun").light_angular_distance, 0.8))
		for pair in [["water_glint_strength", 0.32], ["ripple_cell_scale", 1.1],
			["ripple_morph_strength", 0.75], ["ripple_morph_speed", 0.6]]:
			assert(is_equal_approx(float(settings.get(pair[0])), pair[1]))
		var props := authored.get_node("Map/Props")
		props.owner = null
		props.get_parent().remove_child(props)
		root.add_child(props)
		for contact in props.find_children("*", "EmberWaterContact3D", true, false):
			contact.set_process(false)
			# Both ends of the existing water offset slider must intersect the rig.
			for height in [15.27, 16.02]:
				assert(not contact.foam_footprint_shape(height).is_empty(),
					"authored rig is above lowered water: " + path + "/" + str(contact.get_parent().name))
		props.free()
		authored.free()
	print("PASS saved water scenes: approved light/ripple settings; box/cylinder immersion across water slider")


func _fixture() -> Terrain:
	var terrain := Terrain.new()
	terrain.width = 32
	terrain.depth = 48
	terrain.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.AQUA])
	var count := terrain.width * terrain.depth
	# Packed arrays are values: assign each explicitly.
	terrain.heights.resize(count)
	terrain.heights.fill(4)
	terrain.top_materials.resize(count)
	terrain.top_materials.fill(1)
	terrain.base_materials = terrain.top_materials.duplicate()
	terrain.cap_depths.resize(count)
	terrain.cap_depths.fill(1)
	terrain.water_levels.resize(count)
	terrain.water_levels.fill(8)
	terrain.water_materials.resize(count)
	terrain.water_materials.fill(2)
	for z in terrain.depth:
		terrain.water_materials[z * terrain.width] = 0
	terrain.water_flow.resize(6)
	terrain.water_flow.fill(Vector2(0, -0.8))
	assert(terrain.validation_errors().is_empty())
	return terrain
