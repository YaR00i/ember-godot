extends SceneTree
## Hidden Forward+ visual gate for the disposable terrain pilot.

const SCENE := "res://scenes/terrain_region_pilot.tscn"
const OUTPUT := "user://terrain_pilot_capture.png"
const CLOSE_OUTPUT := "user://terrain_pilot_close.png"
const LARGE_BRUSH_OUTPUT := "user://terrain_pilot_large_brush.png"
const RELIEF_OUTPUT := "user://terrain_pilot_relief_example.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1400, 900)
	var packed := load(SCENE) as PackedScene
	if packed == null:
		printerr("FAIL terrain pilot capture: scene did not load")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var projection := scene.get_node("TerrainProjection")
	var deadline := Time.get_ticks_msec() + 20000
	while projection.call("pending_tile_count") > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if projection.call("pending_tile_count") > 0:
		printerr("FAIL terrain pilot capture: ground did not settle")
		quit(1)
		return
	for i in 4:
		await process_frame
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT)
	scene.set("_distance", 220.0)
	scene.call("_update_camera")
	for i in 4:
		await process_frame
	var close_error := root.get_texture().get_image().save_png(CLOSE_OUTPUT)
	scene.set("_distance", 490.0)
	scene.call("_update_camera")
	scene.call("set_tool_mode", 10)
	scene.call("set_brush_radius_blocks", 8.0)
	scene.call("_set_hover_cell", Vector3(192.5, 0, 200.5))
	for i in 4:
		await process_frame
	var large_error := root.get_texture().get_image().save_png(LARGE_BRUSH_OUTPUT)
	scene.call("set_brush_radius_blocks", 2.0)
	scene.call("set_tool_mode", 10)
	(scene.find_child("BrushDepth", true, false) as SpinBox).value = 8
	(scene.find_child("ReliefDetail", true, false) as SpinBox).value = 3
	scene.call("begin_stroke", 10)
	scene.call("stamp_cell", 145, 180)
	scene.call("end_stroke")
	while projection.call("pending_tile_count") > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if projection.call("pending_tile_count") > 0:
		printerr("FAIL terrain pilot capture: relief did not settle")
		quit(1)
		return
	scene.set("_distance", 220.0)
	scene.call("_update_camera")
	for i in 4:
		await process_frame
	var relief_error := root.get_texture().get_image().save_png(RELIEF_OUTPUT)
	print("TERRAIN_PILOT_CAPTURE path=", ProjectSettings.globalize_path(OUTPUT), " close=", ProjectSettings.globalize_path(CLOSE_OUTPUT), " large_brush=", ProjectSettings.globalize_path(LARGE_BRUSH_OUTPUT), " relief=", ProjectSettings.globalize_path(RELIEF_OUTPUT), " result=", error, "/", close_error, "/", large_error, "/", relief_error, " tiles=", projection.call("built_tile_count"))
	scene.free()
	quit(0 if error == OK and close_error == OK and large_error == OK and relief_error == OK else 1)
