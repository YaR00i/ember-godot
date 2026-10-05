extends Node
## Guarded QA probe attached only to a copied scene for real Editor F6.


func _ready() -> void:
	if ProjectSettings.get_setting("application/config/name") != "Ember River Preview QA": return
	var scene := get_parent()
	var study = scene.get_node("PlanarReflection")
	var started := Time.get_ticks_msec()
	var deadline := started + 180000
	var frames := 0
	var early_player := false
	var early_hud := false
	var loading_capture := false
	while not scene._startup_complete and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		frames += 1
		if not study._prepared and scene._player != null: early_player = true
		if scene.get_node("CanvasLayer").visible and not scene._startup_complete: early_hud = true
		if frames == 8:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_TAB
			key.pressed = true
			Input.parse_input_event(key)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://qa_selection/world_loading.png")
			loading_capture = true
	var result := {"ok": scene._startup_complete and not early_player and not early_hud and loading_capture,
		"wait_ms": Time.get_ticks_msec() - started, "responsive_frames": frames,
		"early_player": early_player, "early_hud": early_hud,
		"source_sections": scene.get_node("Map").compact_terrain.sections.size(),
		"water_stats": study._water_regions.stats if study._water_regions != null else {}}
	if scene._startup_complete:
		var target = study._follow.target
		var yaw: float = study._follow.yaw
		for frame in 30: await get_tree().process_frame
		result["camera_stable"] = study._follow.target == target and is_equal_approx(study._follow.yaw, yaw)
		result.ok = result.ok and result.camera_stable
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://qa_selection/world_loaded.png")
	var file := FileAccess.open("res://qa_selection/world_startup_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	print("WORLD_STARTUP_F6 ", result)
	get_tree().quit(0 if result.ok else 1)
