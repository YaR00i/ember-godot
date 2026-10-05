extends SceneTree
## Forward+ proof that editing shadow tone changes the actual compact terrain.

const SCENE := preload("res://scenes/new_landscape4.tscn")
const PANEL := preload("res://addons/ember_import/ember_world_look_panel.gd")
const OUTPUT := "user://ember-tests/world-look-shadow-tone"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var scene := SCENE.instantiate()
	root.add_child(scene)
	var map := scene.get_node("Map") as EmberMapLoader
	var projection: EmberTerrainPilotProjection
	for frame in 360:
		await process_frame
		projection = map.get("_visual_surface_projection") as EmberTerrainPilotProjection
		if projection != null and projection.pending_tile_count() == 0 and frame > 20:
			break
	if projection == null or projection.pending_tile_count() > 0:
		push_error("shadow tone study terrain did not finish")
		quit(1)
		return
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.far = 2400.0
	camera.fov = 55.0
	camera.global_position = Vector3(910.0, 430.0, -260.0)
	camera.look_at(Vector3(360.0, 18.0, 350.0))
	camera.make_current()
	var canvas := scene.get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas != null: canvas.hide()
	var env := (map.get_node("Look/WorldEnvironment") as WorldEnvironment).environment
	if env.ambient_light_source != Environment.AMBIENT_SOURCE_SKY or env.ambient_light_sky_contribution < 0.999:
		push_error("shadow tone fixture is not sky-only")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) != OK:
		push_error("cannot create shadow tone output")
		quit(1)
		return
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	before.save_png(OUTPUT + "/before.png")
	var panel := PANEL.new()
	root.add_child(panel)
	panel.hide()
	panel.set_target(scene, map, null)
	panel._commit("ambient_color", env.ambient_light_color, Color(0.96, 0.10, 0.15), env.adjustment_enabled)
	if not is_equal_approx(env.ambient_light_sky_contribution, 0.25):
		push_error("shadow tone did not engage authored ambient")
		quit(1)
		return
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	after.save_png(OUTPUT + "/after.png")
	var difference := 0.0
	var samples := 0
	for y in range(0, 720, 8):
		for x in range(0, 1280, 8):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			samples += 3
	difference /= float(samples)
	if difference < 0.005:
		push_error("shadow tone had no visible Forward+ effect (%.4f)" % difference)
		quit(1)
		return
	print("PASS Forward+ shadow tone visible pixel change: %.4f" % difference)
	print("Shadow tone captures: ", ProjectSettings.globalize_path(OUTPUT))
	quit()
