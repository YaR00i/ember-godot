extends SceneTree
## Forward+ view of the scene-owned compact terrain without authoring writes.

const SCENE := "res://scenes/landscape_compact.tscn"
const OUTPUT := "user://landscape_compact_capture.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1400,900)
	var packed := load(SCENE) as PackedScene
	if packed == null:
		printerr("LANDSCAPE_COMPACT_CAPTURE scene load failed")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var map := scene.get_node("Map") as EmberMapLoader
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	var deadline := Time.get_ticks_msec() + 20000
	while projection != null and projection.pending_tile_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if projection == null or projection.pending_tile_count() > 0:
		printerr("LANDSCAPE_COMPACT_CAPTURE terrain did not settle")
		quit(1)
		return
	for i in 8: await process_frame
	var result := root.get_texture().get_image().save_png(OUTPUT)
	print("LANDSCAPE_COMPACT_CAPTURE path=",ProjectSettings.globalize_path(OUTPUT)," result=",result," tiles=",projection.built_tile_count())
	scene.free()
	quit(0 if result == OK else 1)
