extends Node
## Attached only to the disposable native fixture by its editor test.
@export var geometry_cache_directory := ""


func _ready() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-") and not ProjectSettings.globalize_path("res://").contains("ember-sections-native-"): return
	var scene := get_parent()
	var started := Time.get_ticks_msec()
	var projection: EmberTerrainPilotProjection = scene.get_node("Map")._visual_surface_projection
	if not geometry_cache_directory.is_empty(): projection.runtime_geometry_cache_directory = geometry_cache_directory
	var player: EmberPlayer
	for i in 1200:
		player = scene.get_node_or_null("Player") as EmberPlayer
		if player != null: break
		await get_tree().process_frame
	var result := {"ok": false, "reason": "player did not spawn"}
	if player != null:
		assert(projection.pending_runtime_lod_count() == 0, "player appeared before ground LOD preparation finished")
		var startup_ms := Time.get_ticks_msec() - started
		for i in 30: await get_tree().physics_frame
		player.camera_rig.yaw = 0
		var before := player.global_position
		Input.action_press("move_east")
		await get_tree().create_timer(2.0).timeout
		Input.action_release("move_east")
		for i in 12: await get_tree().physics_frame
		var map := scene.get_node("Map") as EmberMapLoader
		var floor_sample := map.surface_floor_sample(player.global_position)
		result = {"ok": before.x < 768 and player.global_position.x > 788 and player.is_on_floor() and floor_sample.solid and absf(player.global_position.y - floor_sample.position.y) < 1.1, "from": str(before), "to": str(player.global_position), "on_floor": player.is_on_floor(), "floor": str(floor_sample.position), "sections": map.compact_terrain.sections.size(), "renderer": RenderingServer.get_current_rendering_method()}
		result["ground_lod_jobs"] = projection.profile_snapshot().ground_lod_jobs
		result["pending_ground_lods"] = projection.pending_runtime_lod_count()
		result["startup_ms"] = startup_ms
		result["geometry_cache_hits"] = projection.profile_snapshot().geometry_cache_hits
		result["geometry_cache_misses"] = projection.profile_snapshot().geometry_cache_misses
		result["geometry_cache_failures"] = projection.profile_snapshot().geometry_cache_failures
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://qa_sections/f6.png")
	var file := FileAccess.open("res://qa_sections/play_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	print("ADDRESSED_PLAYBACK ", result)
