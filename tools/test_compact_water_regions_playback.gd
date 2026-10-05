extends Node
## Attached only to the disposable native water region fixture.

func _ready() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	var scene := get_parent()
	var map: EmberMapLoader = scene.get_node("Map")
	var controller: Node = scene.get_node("PlanarReflection")
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var projection: EmberTerrainPilotProjection = map._visual_surface_projection
		if scene._startup_complete and projection != null and controller._prepared and projection.pending_tile_count() == 0: break
	var fields: RefCounted = controller._water_regions
	var projection: EmberTerrainPilotProjection = map._visual_surface_projection
	var result := {"ok": controller._prepared and fields != null and fields.regions.size() == 36
		and map.compact_terrain.sections.size() == 36 and map.authored_size_blocks == Vector2i(192, 120),
		"renderer": RenderingServer.get_current_rendering_method()}
	if controller._prepared:
		var checks := 0
		for key: Vector2i in fields.regions:
			var entry: Dictionary = fields.regions[key]
			if entry.sea.records.is_empty(): continue
			var cell := Vector2i(-1, -1)
			for record: Vector4 in entry.sea.records:
				var point: Vector2i = Vector2i(record.x, record.y) + entry.window.position
				if entry.core.has_point(point) and record.z <= 0:
					cell = point; break
			if cell.x < 0: continue
			var query: Dictionary = projection.water_surface_sample(projection.to_global(Vector3(cell.x + 0.5, 1000, cell.y + 0.5)))
			result.ok = result.ok and query.get("wet", false)
			checks += 1
		result["water_query_regions"] = checks
		result.ok = result.ok and checks > 0
		controller._study_target.global_position = projection.to_global(Vector3(1536, controller._water_height, 960))
		controller._follow.follow_distance = 3400
		controller._follow.cam_far = 12000
		controller._follow.polar_angle = 0.68
		var times: Array[int] = []
		var cpu: Array[int] = []
		var rid := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(rid, true)
		var previous := Time.get_ticks_usec()
		for i in 120:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			times.append(now - previous)
			cpu.append(fields.update_us)
			previous = now
		times.sort(); cpu.sort()
		result["frame_median_ms"] = times[60] / 1000.0
		result["water_cpu_median_ms"] = cpu[60] / 1000.0
		result["fields"] = fields.stats
		result["gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		result["draw_calls"] = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		result["primitives"] = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		RenderingServer.viewport_set_measure_render_time(rid, false)
		result.ok = result.ok and int(result.primitives) > 10000
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://qa_selection/water_regions_f6.png")
	var file := FileAccess.open("res://qa_selection/water_play_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	print("WATER_REGIONS_PLAYBACK ", JSON.stringify(result))
