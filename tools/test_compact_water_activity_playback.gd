extends Node
## Attached by the guarded editor fixture; uses the actual F6 startup/player.
func _ready() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	var scene := get_parent()
	var controller: Node = scene.get_node("PlanarReflection")
	var deadline := Time.get_ticks_msec() + 180000
	while not scene._startup_complete and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	for i in 5: await get_tree().process_frame
	var projection: EmberTerrainPilotProjection = scene.get_node("Map")._visual_surface_projection
	var fields: RefCounted = controller._water_regions
	var result := {"ok": scene._startup_complete and controller._prepared and fields._runtime_activity
		and projection.pending_runtime_lod_count() == 0 and projection.pending_tile_count() == 0,
		"renderer": RenderingServer.get_current_rendering_method()}
	var position: Vector3 = projection.to_local(scene._player.global_position)
	var player_entry: Dictionary = fields._region(Vector2(position.x, position.z))
	result.ok = result.ok and not player_entry.is_empty() and player_entry.get("runtime_near", false)
	# Keep the physical hero protected while the study camera moves far away.
	controller._study_target.global_position = projection.to_global(Vector3(2200, 32, 1400))
	controller._follow.follow_distance = 3200
	controller._follow.cam_far = 12000
	for i in 30: await get_tree().process_frame
	result.ok = result.ok and fields.stats.far_regions > 0 and player_entry.get("runtime_near", false)
	result["far_regions"] = fields.stats.far_regions
	controller._material.set_shader_parameter("preview_time", 7.0)
	controller._refresh_sea_swash()
	result.ok = result.ok and not fields._runtime_activity and fields.stats.far_regions == 0
	result["frozen_full_rate"] = not fields._runtime_activity
	controller._material.set_shader_parameter("preview_time", -1.0)
	controller._sea_update_ms = 0
	controller._refresh_sea_swash()
	result.ok = result.ok and fields._runtime_activity
	var file := FileAccess.open("res://qa_selection/activity_play_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	print("WATER_ACTIVITY_PLAYBACK ", JSON.stringify(result))
