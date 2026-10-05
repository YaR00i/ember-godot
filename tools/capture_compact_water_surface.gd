extends SceneTree
## Deterministic Forward+ comparison; never saves an authored scene.

const OUTPUT := "user://ember-tests/water-surface"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var compare_level := "--water-level" in OS.get_cmdline_user_args()
	var compare_sea_foam := "--sea-foam" in OS.get_cmdline_user_args()
	var compare_approach := "--sea-approach" in OS.get_cmdline_user_args()
	var compare_sea := "--sea-swash" in OS.get_cmdline_user_args() or compare_sea_foam or compare_approach
	var output := OUTPUT + ("-approach" if compare_approach else "-sea-foam" if compare_sea_foam else "-sea" if compare_sea else "-level" if compare_level else "")
	var scene := (load("res://scenes/compact_sky_reflection_study.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var study := scene.get_node("PlanarReflection")
	for frame in 600:
		await process_frame
		if study.get("_prepared") and frame > 30 and scene.get_node("Map").get("_visual_surface_projection").pending_tile_count() == 0: break
	assert(study.get("_prepared"))
	assert(scene.get_node("Map").get("_visual_surface_projection").pending_tile_count() == 0, "coastal geometry must finish its tile queue")
	(scene.get_node("CanvasLayer") as CanvasLayer).hide()
	for player in scene.find_children("*", "EmberPlayer", true, false):
		(player as Node3D).hide()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.fov = 55.0
	camera.far = 2400.0
	camera.global_position = Vector3(465, 132, 642)
	camera.look_at(Vector3(371, 16, 545))
	if compare_level:
		camera.global_position = Vector3(438, 44, 526)
		camera.look_at(Vector3(408, 16, 487))
	if compare_sea:
		var swash: RefCounted = study.get("_sea_swash")
		assert(swash != null and not swash.records.is_empty())
		var best := Vector3.ZERO
		var distance := INF
		for record in swash.records:
			if record.z <= 0.0 or record.z > 1.0: continue
			var score: float = absf(record.x - 768.0 * 0.25) + absf(record.y - 180.0) * 0.15
			if score < distance:
				distance = score
				best = Vector3(record.x, float(study.get("_water_height")), record.y)
		camera.global_position = best + Vector3(35, 25, 46)
		camera.look_at(best + Vector3(-3, 0, -5))
		print("SEA_CAPTURE bank=", best, " cells=", swash.records.size(), " bounds=", swash.bounds)
	camera.make_current()
	var material: ShaderMaterial = study.get("_material")
	var original: Dictionary = study.water_settings_snapshot()
	var build_count: int = study.get("_fields_build_count")
	var sea_update_total := 0
	var sea_update_max := 0
	var sea_update_count := 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for variant in ["before", "after"]:
		if compare_approach:
			study.sea_approach_distance = 6.0 if variant == "before" else original.sea_approach_distance
		elif compare_sea_foam:
			study.sea_foam_trail_strength = 0.0 if variant == "before" else original.sea_foam_trail_strength
		elif compare_sea:
			study.sea_swash_height = 0.0 if variant == "before" else original.sea_swash_height
			study.sand_wet_strength = 0.0 if variant == "before" else original.sand_wet_strength
		elif compare_level:
			study.water_level_offset_voxels = 0.0 if variant == "before" else original.water_level_offset_voxels
		else:
			for key in ["water_glint_strength", "foam_trail_strength", "shore_foam_breakup", "foam_width_pulse"]:
				study.set(key, 0.0 if variant == "before" else original[key])
		study.refresh_water_settings()
		for frame in (90 if compare_sea else 40):
			material.set_shader_parameter("preview_time", frame * 0.15 if compare_sea else 3.0 + frame * 0.12)
			study.refresh_water_settings()
			if compare_sea:
				var update_cost: int = study.get("_sea_swash").update_us
				sea_update_total += update_cost
				sea_update_max = maxi(sea_update_max, update_cost)
				sea_update_count += 1
			await process_frame
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png("%s/%s-%02d.png" % [output, variant, frame]) == OK)
	assert(study.get("_fields_build_count") == build_count, "surface controls must not rebuild derived terrain fields")
	if compare_sea: print("SEA_CAPTURE update_us avg=", sea_update_total / maxi(sea_update_count, 1), " max=", sea_update_max)
	for key in original: study.set(key, original[key])
	study.refresh_water_settings()
	print("PASS surface Forward+: paired frames, same authored settings, no field rebuild")
	scene.queue_free()
	camera.queue_free()
	await process_frame
	quit()
