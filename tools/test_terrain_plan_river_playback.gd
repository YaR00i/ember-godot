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
		for i in 35: await get_tree().physics_frame
		var start := player.global_position
		Input.action_press("move_east"); await get_tree().create_timer(1.0).timeout; Input.action_release("move_east")
		for i in 15: await get_tree().physics_frame
		var map := scene.get_node("Map") as EmberMapLoader; var terrain := map.compact_terrain
		var lake: int = terrain.column_value("water_levels",terrain.column_index(352,448))
		var sea: int = terrain.column_value("water_levels",terrain.column_index(544,48))
		var middle: int = terrain.column_value("water_levels",terrain.column_index(400,208))
		var flow := terrain.flow_at_cell(400,208)
		var fields: RefCounted = scene.get_node("PlanarReflection").get("_water_regions")
		var moved := Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(start.x,start.z))
		result = {"ok":player.is_on_floor() and moved > 5 and lake == 80 and sea == 32 and middle > 32 and middle < 80 and flow.y < 0 and fields != null,
			"moved":moved,"floor":player.is_on_floor(),"lake":lake,"sea":sea,"middle":middle,"flow":str(flow),"fields":fields != null,"renderer":RenderingServer.get_current_rendering_method()}
		var overview := Camera3D.new(); scene.add_child(overview)
		var projection := map._visual_surface_projection as EmberTerrainPilotProjection
		overview.look_at_from_position(projection.to_global(Vector3(750,900,-200)),projection.to_global(Vector3(384,64,384))); overview.far = 8000; overview.make_current()
		for i in 8: await get_tree().process_frame
		await RenderingServer.frame_post_draw; get_viewport().get_texture().get_image().save_png(result_file.get_basename()+"-overview.png")
	var file := FileAccess.open(result_file,FileAccess.WRITE); file.store_string(JSON.stringify(result)); print("RIVER_PLAYBACK ",result)
