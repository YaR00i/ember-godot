extends SceneTree
## Standalone visible Forward+ terrain profile. Authored files are read-only.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Diagnostics = preload("res://addons/ember_import/ember_terrain_diagnostics.gd")
const FLAT := "res://content/world_terrains/large_landscape_test.res"
const BEACH := "res://content/terrain_pilot/beach_region.res"
const OUTPUT := "user://ember_terrain_diagnostics"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("This profile requires a visible Forward+ renderer")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.42, 0.56, 0.62)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.86, 0.8)
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var camera := Camera3D.new()
	camera.far = 6000.0
	camera.fov = 50.0
	root.add_child(camera)
	var flat := ResourceLoader.load(FLAT, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	var beach := ResourceLoader.load(BEACH, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	if flat == null or beach == null or not flat.validation_errors().is_empty() or not beach.validation_errors().is_empty():
		push_error("Terrain profile source is missing or invalid")
		quit(1)
		return
	var flat_result: Dictionary = await _measure_map("flat", flat, camera)
	var mixed := _repeat_4x4(beach)
	var mixed_result: Dictionary = await _measure_map("mixed_beach", mixed, camera)
	var report := {"schema": 1, "context": "standalone_forward_plus", "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "window": [1280, 720],
		"flat": flat_result, "mixed_beach": mixed_result,
		"limitations": "Standalone Forward+ window, not the editor 3D viewport. Sources contain terrain only; no city props."}
	var path: String = Diagnostics.save_report(report)
	if path.is_empty() or flat_result.is_empty() or mixed_result.is_empty():
		push_error("Forward+ terrain profile did not complete")
		quit(1)
		return
	print("TERRAIN_FORWARD flat=", JSON.stringify(_brief(flat_result)), " mixed=", JSON.stringify(_brief(mixed_result)), " report=", ProjectSettings.globalize_path(path))
	quit()


func _measure_map(label: String, source: TerrainResource, camera: Camera3D) -> Dictionary:
	camera.position = Vector3(source.width * 0.5, 1450, source.depth * 1.35)
	camera.look_at(Vector3(source.width * 0.5, 0, source.depth * 0.5))
	camera.make_current()
	var map := EmberMapLoader.new()
	map.map_id = "forward_profile_" + label
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i(source.width / 16, source.depth / 16)
	map.compact_terrain = source
	var started := Time.get_ticks_usec()
	root.add_child(map)
	var enter_ms := _ms(started)
	camera.make_current()
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var previous := Time.get_ticks_usec()
	var frame_gaps: Array[float] = []
	var first_tile_ms := -1.0
	var first_draw_ms := -1.0
	var deadline := Time.get_ticks_msec() + 60000
	while projection.pending_tile_count() > 0 and Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_gaps.append(float(now - previous) / 1000.0)
		previous = now
		if first_tile_ms < 0 and projection.built_tile_count() > 0:
			first_tile_ms = _ms(started)
		if first_draw_ms < 0 and projection.built_tile_count() > 0 and _draws(rid) > 0:
			first_draw_ms = _ms(started)
	var all_tiles_ms := _ms(started)
	frame_gaps.sort()
	for i in 12:
		await RenderingServer.frame_post_draw
	var steady := {"frame_ms": [], "render_cpu_ms": [], "render_gpu_ms": [],
		"visible_draw_calls": [], "shadow_draw_calls": [], "visible_primitives": []}
	previous = Time.get_ticks_usec()
	for i in 90:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		(steady.frame_ms as Array).append(float(now - previous) / 1000.0)
		previous = now
		(steady.render_cpu_ms as Array).append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		(steady.render_gpu_ms as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		(steady.visible_draw_calls as Array).append(_draws(rid))
		(steady.shadow_draw_calls as Array).append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		(steady.visible_primitives as Array).append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
	RenderingServer.viewport_set_measure_render_time(rid, false)
	var summarized := {}
	for key in steady:
		var values: Array = steady[key]
		values.sort()
		summarized[key + "_median"] = values[int(values.size() / 2)]
		summarized[key + "_p95"] = values[clampi(ceili(values.size() * 0.95) - 1, 0, values.size() - 1)]
	var image_path := OUTPUT.path_join("forward_%s.png" % label)
	var image_error := root.get_texture().get_image().save_png(image_path)
	var result := {"size": [source.width, source.depth], "enter_ms": enter_ms,
		"first_tile_ms": first_tile_ms, "first_draw_ms": first_draw_ms, "all_tiles_ms": all_tiles_ms,
		"build_frame_p95_ms": frame_gaps[clampi(ceili(frame_gaps.size() * 0.95) - 1, 0, frame_gaps.size() - 1)] if not frame_gaps.is_empty() else 0.0,
		"build_frame_max_ms": frame_gaps.back() if not frame_gaps.is_empty() else 0.0,
		"steady": summarized, "terrain": projection.profile_snapshot(),
		"image": ProjectSettings.globalize_path(image_path) if image_error == OK else "", "image_error": image_error}
	map.free()
	for i in 3:
		await process_frame
	return result


func _draws(rid: RID) -> int:
	return RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)


func _brief(result: Dictionary) -> Dictionary:
	return {"first_draw_ms": result.first_draw_ms, "all_tiles_ms": result.all_tiles_ms,
		"build_frame_p95_ms": result.build_frame_p95_ms, "build_frame_max_ms": result.build_frame_max_ms,
		"steady_frame_p95_ms": result.steady.frame_ms_p95,
		"gpu_ms": result.steady.render_gpu_ms_median,
		"visible_draw_calls": result.steady.visible_draw_calls_median,
		"shadow_draw_calls": result.steady.shadow_draw_calls_median,
		"image_error": result.image_error}


func _repeat_4x4(source: TerrainResource) -> TerrainResource:
	var result := TerrainResource.new()
	result.width = source.width * 4
	result.depth = source.depth * 4
	result.height_limit = source.height_limit
	result.origin_y = source.origin_y
	result.palette = source.palette.duplicate()
	var count := result.width * result.depth
	result.heights.resize(count)
	result.top_materials.resize(count)
	result.base_materials.resize(count)
	result.cap_depths.resize(count)
	result.water_levels.resize(count)
	result.water_materials.resize(count)
	for z in result.depth:
		for x in result.width:
			var dst := x + z * result.width
			var src := x % source.width + (z % source.depth) * source.width
			result.heights[dst] = source.heights[src]
			result.top_materials[dst] = source.top_materials[src]
			result.base_materials[dst] = source.base_materials[src]
			result.cap_depths[dst] = source.cap_depths[src]
			result.water_levels[dst] = source.water_levels[src]
			result.water_materials[dst] = source.water_materials[src]
			if source.column_material_overrides.has(src):
				result.column_material_overrides[dst] = (source.column_material_overrides[src] as Dictionary).duplicate(true)
	return result


func _ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0
