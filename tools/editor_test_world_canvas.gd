@tool
extends EditorPlugin
## Opt-in fixture, only in a disposable native editor copy.
var errors: Array[String] = []

func _enter_tree() -> void: _run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func frames(count: int) -> void:
	for i in count: await get_tree().process_frame

func ready_projection(projection: Node) -> void:
	var deadline := Time.get_ticks_msec()+120000
	while not projection.is_projection_complete() and Time.get_ticks_msec() < deadline: await frames(1)
	check(projection.is_projection_complete(), "projection timeout")

func stroke(world: Node, hit: Dictionary) -> void:
	world._begin_stroke(hit)
	world.released = true
	var deadline := Time.get_ticks_msec()+60000
	while world.dragging and Time.get_ticks_msec() < deadline: await frames(1)
	check(not world.dragging, "stroke timeout")

func native_undo() -> void:
	# Drive the real menu shortcut. Calling the per-scene UndoRedo directly
	# bypasses EditorUndoRedoManager's global redo stack and makes Save diagnostics
	# inconsistent, even when the underlying voxel delta is restored correctly.
	var container := EditorInterface.get_editor_viewport_3d(0).get_parent() as Control
	if container != null: container.grab_focus()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_Z
	key.physical_keycode = KEY_Z
	key.ctrl_pressed = true
	Input.parse_input_event(key)
	await frames(3)
	key.pressed = false
	Input.parse_input_event(key)
	await frames(2)

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-world-native-"):
		printerr("FAIL NATIVE_WORLD_CANVAS fixture requires a disposable ember-world-native project")
		return
	await frames(15)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: printerr("FAIL NATIVE_WORLD_CANVAS importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while importer._editor_preparation.visible and Time.get_ticks_msec() < deadline: await frames(1)
	EditorInterface.open_scene_from_path("res://scenes/world_canvas.tscn")
	await frames(20)
	EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	var map: EmberMapLoader = scene.get_node("Map")
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	check(world.active and not world.entry.is_empty(), "world mode did not open saved canvas")
	await ready_projection(map._visual_surface_projection)
	var draft: EmberVoxelModelResource = world.entry.resource
	var original := draft.voxels.duplicate()
	var original_water := draft.surface_fill_levels.duplicate()
	world.category.select(0)
	world._category_changed(0)
	world.radius.value = 1
	await stroke(world,{"hit":Vector3i(63,37,127),"normal":Vector3i.UP})
	check(draft.voxels != original, "seam-crossing native raise did nothing")
	await native_undo()
	check(draft.voxels == original, "native Undo did not restore authored canvas")
	world.category.select(1)
	world._category_changed(1)
	world.radius.value = 0.25
	world.palette.select(2)
	await stroke(world,{"hit":Vector3i(0,25,127),"normal":Vector3i.LEFT})
	check(draft.voxels[world.Model.index_of(Vector3i(0,25,127),draft.grid_size())] == 3, "native wall paint failed")
	var saved_start := Time.get_ticks_usec()
	check(world.save_all(), "native canvas Save: "+world.sessions.error)
	print("NATIVE_WORLD_CANVAS_PROFILE save_ms=", (Time.get_ticks_usec()-saved_start)/1000)
	var reopened := (ResourceLoader.load(scene.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").visual_surface.voxels == draft.voxels, "native Save/reopen lost paint")
	reopened.free()
	await native_undo()
	check(draft.voxels == original, "post-Save Undo did not restore original canvas")
	world.category.select(2)
	world._category_changed(2)
	world.water_height.value = 2
	await stroke(world,{"hit":Vector3i(340,11,200),"normal":Vector3i.UP})
	check(draft.surface_fill_levels[340+200*384] == 34, "native water level brush failed")
	await native_undo()
	check(draft.surface_fill_levels == original_water, "native water Undo failed")
	world.hide_water.button_pressed = true
	await frames(5)
	world.hide_water.button_pressed = false
	check(world.save_all(), "native restore baseline Save: "+world.sessions.error)
	await ready_projection(map._visual_surface_projection)
	world.category.select(0)
	world._category_changed(0)
	world.hover = {}
	world._update_overlay()
	# A background fixture has no desktop viewport focus. This single QA frame
	# uses a fixed camera immediately before force_draw; do not await editor frames
	# in between, because the native cursor owns and restores its camera each frame.
	# This tests native projection/rendering, not camera-shortcut ergonomics.
	EditorInterface.get_selection().clear()
	var native_camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	await frames(2)
	native_camera.fov = 40
	native_camera.near = 1
	native_camera.far = 2400
	native_camera.look_at_from_position(Vector3(520,500,580),Vector3(192,0,200))
	check(native_camera.is_position_in_frustum(Vector3(192,0,200)),"QA overview camera excludes map")
	check(native_camera.get_world_3d().scenario == map.get_world_3d().scenario,"native camera and map use different render worlds")
	var native_viewport := EditorInterface.get_editor_viewport_3d(0)
	print("NATIVE_WORLD_CANVAS_RENDER before=",native_camera.global_transform," update_mode=",native_viewport.render_target_update_mode," viewport=",native_viewport.size)
	native_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	RenderingServer.camera_set_transform(native_camera.get_camera_rid(),native_camera.get_camera_transform())
	# An idle/background native editor may skip draws indefinitely. Force one
	# QA frame instead of awaiting a signal that only active animation emits.
	RenderingServer.force_draw(false)
	print("NATIVE_WORLD_CANVAS_RENDER after=",native_camera.global_transform)
	# The window chrome may still cache its old composite in the background;
	# capture the actual editor 3D render target, not that stale window image.
	var screenshot := ProjectSettings.globalize_path("user://native-world-canvas-viewport.png")
	check(native_viewport.get_texture().get_image().save_png(screenshot) == OK,"native viewport screenshot failed")
	print("NATIVE_WORLD_CANVAS_SCREENSHOT ", screenshot)
	if errors.is_empty(): print("PASS NATIVE_WORLD_CANVAS full coastal canvas, seam brush, native wall paint, water/working view, Undo, shared Save/reopen")
	else:
		for error in errors: printerr("FAIL NATIVE_WORLD_CANVAS ", error)
	await frames(5)
	get_tree().quit(0 if errors.is_empty() else 1)
