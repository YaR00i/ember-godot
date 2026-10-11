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
		var lake_level: int = terrain.column_value("water_levels",terrain.column_index(384,384))
		var sea_level: int = terrain.column_value("water_levels",terrain.column_index(32,32))
		var projection := map._visual_surface_projection as EmberTerrainPilotProjection
		var water := projection._tiles[Vector2i(6,6)].get_node("Water") as MeshInstance3D
		var geometry_level := true
		for vertex: Vector3 in water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: geometry_level = geometry_level and absf(vertex.y-80.02) < 0.05
		var moved := Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(start.x,start.z))
		var study := scene.get_node("PlanarReflection"); var fields: RefCounted = study.get("_water_regions")
		var closed: bool = fields != null and fields.sample(Vector2i(384,384)).is_empty()
		result = {"ok":player.is_on_floor() and moved > 5 and lake_level == 80 and sea_level == 32 and geometry_level and closed,
			"moved":moved,"floor":player.is_on_floor(),"lake":lake_level,"sea":sea_level,"geometry_level":geometry_level,"renderer":RenderingServer.get_current_rendering_method()}
		result.closed_lake = closed
		await RenderingServer.frame_post_draw; get_viewport().get_texture().get_image().save_png(result_file.get_basename()+".png")
		var overview := Camera3D.new(); scene.add_child(overview)
		overview.look_at_from_position(Vector3(700,600,850),Vector3(384,64,384)); overview.far = 8000; overview.make_current()
		for i in 8: await get_tree().process_frame
		await RenderingServer.frame_post_draw; get_viewport().get_texture().get_image().save_png(result_file.get_basename()+"-overview.png")
	var file := FileAccess.open(result_file,FileAccess.WRITE); file.store_string(JSON.stringify(result)); print("LAKE_PLAYBACK ",result)
