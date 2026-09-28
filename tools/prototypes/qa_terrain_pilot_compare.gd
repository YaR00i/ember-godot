extends SceneTree
## Visual reference at the pilot camera pose, read-only on the copied Surface.

const SCENE := "res://scenes/landscape_v2_experimental.tscn"
const OUTPUT := "user://terrain_pilot_original_close.png"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1400, 900)
	var packed := load(SCENE) as PackedScene
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.current = true
	camera.far = 2400.0
	root.add_child(camera)
	var center := Vector3(192, 0, 200)
	camera.position = center + Vector3(sin(0.35) * cos(0.9), sin(0.9), cos(0.35) * cos(0.9)) * 220.0
	camera.look_at(center)
	var projection: Node3D = scene.get_node("Map").get("_visual_surface_projection")
	var deadline := Time.get_ticks_msec() + 30000
	while projection.call("pending_chunk_count") > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if projection.call("pending_chunk_count") > 0:
		printerr("FAIL terrain reference capture: exact chunks did not settle")
		quit(1)
		return
	for layer in scene.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	camera.make_current()
	for i in 4:
		await process_frame
	camera.make_current()
	await process_frame
	var error := root.get_texture().get_image().save_png(OUTPUT)
	print("TERRAIN_REFERENCE_CAPTURE path=", ProjectSettings.globalize_path(OUTPUT), " result=", error, " chunks=", projection.call("rendered_chunk_count"))
	camera.free()
	scene.free()
	quit(0 if error == OK else 1)
