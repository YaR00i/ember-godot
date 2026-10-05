extends Node
## Saved only in the guarded disposable editor fixture.


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
		var start := player.global_position
		Input.action_press("move_east")
		await get_tree().create_timer(1.5).timeout
		Input.action_release("move_east")
		for i in 15: await get_tree().physics_frame
		var map := scene.get_node("Map") as EmberMapLoader
		var floor_sample := map.surface_floor_sample(player.global_position)
		var moved_xz := Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(start.x, start.z))
		# At a step edge the capsule can rest on the higher neighbour while its
		# centre samples the lower column. Check the body's real supporting face.
		var support := KinematicCollision3D.new()
		var supported := player.test_move(player.global_transform, Vector3.DOWN * 2.0, support)
		supported = supported and support.get_normal().dot(Vector3.UP) >= cos(player.floor_max_angle) - 0.01 and absf(support.get_travel().y) < 1.1
		result = {"ok": player.is_on_floor() and supported and floor_sample.solid and moved_xz > 5,
			"from": str(start), "to": str(player.global_position), "floor": str(floor_sample.position), "on_floor": player.is_on_floor(),
			"body_supported": supported,
			"support_normal": str(support.get_normal()), "support_travel": str(support.get_travel()),
			"renderer": RenderingServer.get_current_rendering_method(), "height_limit": map.compact_terrain.height_limit}
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://qa_generation/f6.png")
	var file := FileAccess.open("res://qa_generation/play_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	print("GENERATOR_PLAYBACK ", result)
