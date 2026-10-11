extends Node
@export var result_file := ""
func _ready() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-") or result_file.is_empty(): return
	var scene := get_parent(); var player: EmberPlayer
	var deadline := Time.get_ticks_msec()+100000
	while player == null and Time.get_ticks_msec() < deadline:
		player = scene.get_node_or_null("Player") as EmberPlayer; await get_tree().process_frame
	var result := {"ok":false,"reason":"startup/player timeout"}
	if player != null:
		for i in 45: await get_tree().physics_frame
		# Player creation can precede the initial fall onto the prepared surface.
		# Start the traversal after landing, not while finishing spawn.
		deadline = Time.get_ticks_msec()+15000
		while not player.is_on_floor() and Time.get_ticks_msec() < deadline: await get_tree().physics_frame
		var map := scene.get_node("Map") as EmberMapLoader; var terrain := map.compact_terrain
		var projection := map._visual_surface_projection as EmberTerrainPilotProjection
		var index: int = terrain.column_index(384,384); var height: int = terrain.column_value("heights",index)
		var ground := projection.to_global(Vector3(384,height,384))
		var ray := PhysicsRayQueryParameters3D.create(ground+Vector3.UP*32,ground-Vector3.UP*16,1,[player.get_rid()])
		var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
		var start := player.global_position; var floor_frames := 0
		var start_floor := player.is_on_floor()
		Input.action_press("move_east")
		for i in 120:
			await get_tree().physics_frame
			if player.is_on_floor(): floor_frames += 1
		Input.action_release("move_east"); for i in 15: await get_tree().physics_frame
		var moved := Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(start.x,start.z))
		var soil: int = terrain.column_value("top_materials",index); var sea: int = terrain.column_value("water_levels",terrain.column_index(32,32))
		var physics_same: bool = not hit.is_empty() and absf(Vector3(hit.position).y-ground.y) < 0.1
		result = {"ok":player.is_on_floor() and moved > 80 and floor_frames >= 110 and height == 96 and terrain.surface_role_for_palette(soil) == "soil" and sea == 32 and physics_same,
			"moved":moved,"start":str(start),"finish":str(player.global_position),"start_floor":start_floor,"floor":player.is_on_floor(),"floor_frames":floor_frames,"height":height,"soil":soil,"sea":sea,"physics_same":physics_same,"renderer":RenderingServer.get_current_rendering_method()}
		var overview := Camera3D.new(); scene.add_child(overview)
		overview.look_at_from_position(projection.to_global(Vector3(650,700,850)),projection.to_global(Vector3(384,120,384))); overview.far = 8000; overview.make_current()
		for i in 8: await get_tree().process_frame
		await RenderingServer.frame_post_draw; get_viewport().get_texture().get_image().save_png(result_file.get_basename()+"-overview.png")
	var file := FileAccess.open(result_file,FileAccess.WRITE); file.store_string(JSON.stringify(result)); print("ROAD_PLAYBACK ",result)
