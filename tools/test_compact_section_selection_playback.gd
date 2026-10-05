extends Node
## Attached only to the disposable native selection fixture.

func _ready() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	var scene := get_parent()
	var player: EmberPlayer
	for i in 1200:
		player = scene.get_node_or_null("Player") as EmberPlayer
		if player != null: break
		await get_tree().process_frame
	var result := {"ok": false, "reason": "player did not spawn"}
	if player != null:
		for i in 40: await get_tree().physics_frame
		var map := scene.get_node("Map") as EmberMapLoader
		var start := player.global_position
		Input.action_press("move_east")
		await get_tree().create_timer(1.0).timeout
		Input.action_release("move_east")
		for i in 15: await get_tree().physics_frame
		var fresh := map.surface_floor_sample(Vector3(-192, 1000, -192))
		var supported := false
		if fresh.get("solid", false):
			var ray := PhysicsRayQueryParameters3D.create(fresh.position + Vector3.UP * 5, fresh.position - Vector3.UP * 5)
			var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(ray)
			supported = not hit.is_empty() and absf(hit.position.y - fresh.position.y) < 0.1
		var floor_sample := map.surface_floor_sample(player.global_position)
		result = {"ok": map.compact_terrain.sections.size() == 7 and map.position == Vector3(-384, 0, -384)
			and player.is_on_floor() and floor_sample.solid and supported
			and Vector2(start.x, start.z).distance_to(Vector2(player.global_position.x, player.global_position.z)) > 5,
			"from": str(start), "to": str(player.global_position), "on_floor": player.is_on_floor(),
			"new_land_collision": supported, "map_origin": str(map.position), "sections": map.compact_terrain.sections.size(),
			"renderer": RenderingServer.get_current_rendering_method()}
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://qa_selection/f6.png")
	var file := FileAccess.open("res://qa_selection/play_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	print("SECTION_SELECTION_PLAYBACK ", result)
