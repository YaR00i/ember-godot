@tool
extends "res://tools/editor_test_compact_section_selection.gd"
## Native UI/Forward+ fixture. Never enable this plugin in the author checkout.

const WATER_SCENE := "res://scenes/compact_material_light_study.tscn"
const PLAY_RESULT := "res://qa_selection/water_play_result.json"

func water_ready(scene: Node, label: String) -> void:
	var controller: Node = scene.get_node("PlanarReflection")
	var projection: EmberTerrainPilotProjection = scene.get_node("Map")._visual_surface_projection
	var deadline := Time.get_ticks_msec() + 180000
	var previous := Time.get_ticks_usec()
	var longest := 0
	var longest_working := 0
	var longest_idle := 0
	var pending_before := projection.pending_tile_count()
	while Time.get_ticks_msec() < deadline:
		await frames(1)
		var now := Time.get_ticks_usec()
		longest = maxi(longest, now - previous)
		# An unfocused, unchanged editor can deliberately sleep for 100 ms.
		# Keep the raw interval, but the stall gate excludes only that declared
		# engine sleep. The old synchronous 10-second build still fails this gate.
		var idle := OS.low_processor_usage_mode_sleep_usec if OS.low_processor_usage_mode else 0
		longest_idle = maxi(longest_idle, idle)
		longest_working = maxi(longest_working, now - previous - idle)
		if now - previous > 90000:
			print("WATER_NATIVE_LONG ", label, " ms=", (now - previous)/1000.0, " pending_before=", pending_before,
				" focused=", DisplayServer.window_is_focused(), " sleep_us=", idle, " cpu=", controller._water_regions._thread.is_alive() if controller._water_regions != null else false,
				" stats=", controller._water_regions.stats if controller._water_regions != null else {})
		pending_before = projection.pending_tile_count()
		previous = now
		if controller._prepared and controller._field_revision == projection.column_revision() and projection.pending_tile_count() == 0: break
	check(controller._prepared and controller._field_revision == projection.column_revision(), label + ": fields timed out")
	check(longest_working < 100000, label + ": preparation blocked a frame for %.1f ms beyond declared editor sleep" % (longest_working / 1000.0))
	print("WATER_NATIVE_PREP ", label, " max_gap_ms=", longest / 1000.0, " beyond_sleep_ms=", longest_working / 1000.0, " max_idle_us=", longest_idle, " ", controller._water_regions.stats)

func add_region(world: Node, importer: Node) -> void:
	importer._extend_compact_map()
	drag(world, Vector2i(4, 0), Vector2i(7, 3))
	world._section_next.pressed.emit()
	var dialog: Control = world._generation_panel
	check(dialog.visible, "192x120 Next did not open parameters")
	if not dialog.visible: return
	dialog._preview_button.pressed.emit()
	await ready_dialog(dialog)
	check(world._generation_context.candidate.sections.size() == 36, "preview lost occupied terrain or selected sections")
	dialog.get_apply_button().pressed.emit()
	check(not dialog.visible, "Apply did not commit")

func _run() -> void:
	if ProjectSettings.get_setting("application/config/name") != "Ember River Preview QA":
		printerr("Water region QA is forbidden in the author checkout."); return
	var importer := get_parent().get_node("EmberImportPlugin")
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	EditorInterface.open_scene_from_path(WATER_SCENE)
	EditorInterface.set_main_screen_editor("3D")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var scene := EditorInterface.get_edited_scene_root()
	await water_ready(scene, "initial96x120")
	var map: EmberMapLoader = scene.get_node("Map")
	var controller: Node = scene.get_node("PlanarReflection")
	var initial: RefCounted = controller._water_regions.regions[Vector2i.ZERO].sea
	var original_hash := FileAccess.get_sha256(map.compact_terrain.resource_path)
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	await frames(3)
	_camera = Camera3D.new()
	EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.position = Vector3(2400, 2900, 3700)
	_camera.look_at_from_position(_camera.position, Vector3(1500, 30, 850))
	_camera.far = 12000
	_camera.make_current()
	await add_region(world, importer)
	await water_ready(scene, "expanded192x120")
	check(map.authored_size_blocks == Vector2i(192, 120), "wrong expanded footprint")
	check(controller._water_regions.regions[Vector2i.ZERO].sea == initial, "far-away field lost foam history")
	check(controller._water_regions.stats.reused_regions > 0, "expansion recalculated every field")
	check(FileAccess.get_sha256(world.entry.path) == original_hash, "Apply saved author data before Save")
	await capture("water_regions192")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	check(world.entry.resource.sections.size() == 20, "single Undo lost original sections")
	await water_ready(scene, "undo96x120")
	history.redo()
	check(world.entry.resource.sections.size() == 36, "Redo did not restore candidate")
	await water_ready(scene, "redo192x120")
	world.sessions.discard(scene)
	check(world.entry.resource.sections.size() == 20, "Discard did not restore saved map")
	# Replace the pending discarded version before it can publish.
	await add_region(world, importer)
	await water_ready(scene, "afterDiscard192x120")
	var playback := Node.new()
	playback.name = "WaterRegionsPlaybackCheck"
	playback.set_script(load("res://tools/test_compact_water_regions_playback.gd"))
	scene.add_child(playback)
	playback.owner = scene
	world.save_all()
	deadline = Time.get_ticks_msec() + 120000
	while not world.sessions.pending_native_save.is_empty() and Time.get_ticks_msec() < deadline: await frames(1)
	check(world.sessions.dirty_count(scene) == 0, "Save did not finish")
	_camera.queue_free()
	EditorInterface.reload_scene_from_path(WATER_SCENE)
	await frames(3)
	scene = EditorInterface.get_edited_scene_root()
	await water_ready(scene, "reopen192x120")
	check(scene.get_node("Map").compact_terrain.sections.size() == 36, "Reopen lost sections")
	if FileAccess.file_exists(PLAY_RESULT): DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAY_RESULT))
	EditorInterface.play_current_scene()
	deadline = Time.get_ticks_msec() + 240000
	while not FileAccess.file_exists(PLAY_RESULT) and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(PLAY_RESULT), "F6 result missing")
	if FileAccess.file_exists(PLAY_RESULT):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PLAY_RESULT))
		check(result.get("ok", false), "F6: " + str(result))
	EditorInterface.stop_playing_scene()
	await frames(5)
	print("WATER_REGIONS_NATIVE ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
