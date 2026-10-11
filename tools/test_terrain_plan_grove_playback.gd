extends Node
@export var result_file := ""
func _ready() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-") or result_file.is_empty(): return
	Engine.max_fps = 30
	var scene := get_parent(); var player: EmberPlayer; var deadline := Time.get_ticks_msec()+45000
	while player == null and Time.get_ticks_msec() < deadline:
		player = scene.get_node_or_null("Player") as EmberPlayer; await get_tree().process_frame
	var result := {"ok":false,"reason":"startup/player timeout"}
	if player != null:
		for i in 45: await get_tree().physics_frame
		var map := scene.get_node("Map") as EmberMapLoader; var count := 0; var colliders := 0; var below := 0
		for prop in map.get_node("Props").get_children():
			if not prop is EmberVoxelProp: continue
			count += 1
			if prop.get_node_or_null("Collision/Shape") != null: colliders += 1
			if prop.get_node("Mesh").mesh == null: below += 1
		var start := player.global_position; Input.action_press("move_east")
		await get_tree().create_timer(0.5).timeout; Input.action_release("move_east"); for i in 15: await get_tree().physics_frame
		result = {"ok":count > 0 and colliders == count and below == 0 and player.is_on_floor() and player.global_position.distance_to(start) > 5,
			"trees":count,"colliders":colliders,"floor":player.is_on_floor(),"moved":player.global_position.distance_to(start),"renderer":RenderingServer.get_current_rendering_method()}
		var overview := Camera3D.new(); scene.add_child(overview)
		var projection := map._visual_surface_projection as EmberTerrainPilotProjection
		overview.look_at_from_position(projection.to_global(Vector3(400,450,500)),projection.to_global(Vector3(192,96,192))); overview.far = 5000; overview.make_current()
		for i in 8: await get_tree().process_frame
		await RenderingServer.frame_post_draw; get_viewport().get_texture().get_image().save_png(result_file.get_basename()+"-overview.png")
	var file := FileAccess.open(result_file,FileAccess.WRITE); file.store_string(JSON.stringify(result)); print("GROVE_PLAYBACK ",result)
