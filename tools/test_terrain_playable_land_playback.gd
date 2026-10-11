extends Node
@export var result_file := ""
func _ready() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-") or result_file.is_empty(): return
	var scene := get_parent(); var player: EmberPlayer
	var deadline := Time.get_ticks_msec()+90000
	while player == null and Time.get_ticks_msec() < deadline:
		player = scene.get_node_or_null("Player") as EmberPlayer; await get_tree().process_frame
	var result := {"ok":false,"reason":"player missing"}
	if player != null:
		for frame in 40: await get_tree().physics_frame
		var start := player.global_position
		Input.action_press("move_east"); await get_tree().create_timer(1.5).timeout; Input.action_release("move_east")
		for frame in 15: await get_tree().physics_frame
		var support := KinematicCollision3D.new()
		var supported := player.test_move(player.global_transform,Vector3.DOWN*2.0,support)
		supported = supported and support.get_normal().dot(Vector3.UP) >= cos(player.floor_max_angle)-0.01 and absf(support.get_travel().y) < 1.1
		var moved := Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(start.x,start.z))
		result = {"ok":player.is_on_floor() and supported and moved > 5,"from":str(start),"to":str(player.global_position),"moved":moved,
			"on_floor":player.is_on_floor(),"support":supported,"renderer":RenderingServer.get_current_rendering_method()}
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(result_file.get_basename()+".png")
	var file := FileAccess.open(result_file,FileAccess.WRITE); file.store_string(JSON.stringify(result))
	print("PLAYABLE_LAND_PLAYBACK ",result)
