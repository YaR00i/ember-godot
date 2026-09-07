extends SceneTree
## Native 3D smoke for the Stage 1 vertical Combat Lab modes.

const LAB_SCENE := preload("res://scenes/combat_lab.tscn")
const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid := preload("res://scripts/prototypes/ember_combat_grid.gd")
const TileLibrary := preload("res://scripts/prototypes/ember_battlefield_tile_library.gd")


func _init() -> void:
	root.size = Vector2i(1600, 900)
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var errors: Array[String] = []
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	await physics_frame

	var world := lab as Node3D
	var hud := lab.find_child("CombatHUD", true, false) as Control
	var mode_picker := lab.find_child("CombatEncounterMode", true, false) as OptionButton
	var camera_menu := lab.find_child("CombatCameraMenu", true, false) as MenuButton
	var grid_map := lab.find_child("CombatGridMap", true, false) as GridMap
	var camera := lab.find_child("CombatCamera3D", true, false) as Camera3D
	var camera_rig := lab.find_child("CameraRig", true, false) as Node3D
	if world == null or hud == null or mode_picker == null or grid_map == null:
		errors.append("vertical lab is missing its world, HUD, mode picker or GridMap")
		_finish(lab, errors)
		return
	if camera == null or camera_rig == null:
		errors.append("vertical lab is missing its native Camera3D rig")
		_finish(lab, errors)
		return
	if mode_picker.item_count < 5:
		errors.append("Combat Lab did not expose the E4 and E5 modes")
	else:
		if str(mode_picker.get_item_metadata(3)) != "vertical":
			errors.append("E4 mode metadata is not vertical")
		if str(mode_picker.get_item_metadata(4)) != "stress":
			errors.append("E5 mode metadata is not stress")

	mode_picker.select(3)
	mode_picker.item_selected.emit(3)
	await process_frame
	await process_frame
	var vertical_state := hud.call("state_snapshot") as Dictionary
	var vertical_grid := vertical_state.get("grid", {}) as Dictionary
	var vertical_field = world.get("battlefield")
	if int(vertical_grid.get("width", 0)) != 10 or int(vertical_grid.get("height", 0)) != 8:
		errors.append("E4 did not build the 10x8 resolver state")
	if grid_map.get_used_cells().size() != 80:
		errors.append("E4 did not project exactly 80 dense battlefield columns")
	if vertical_field == null or str(vertical_field.get("field_id")) != "vertical_forge_10x8":
		errors.append("E4 world does not own the authored 10x8 Battlefield resource")
	if lab.find_child("CombatUnitOutline_mira", true, false) == null:
		errors.append("vertical units have no always-visible outline mesh")
	var expected_overview := (
		(world.call("_world_position", Vector2i.ZERO, 0.0) as Vector3)
		+ (world.call("_world_position", Vector2i(9, 7), 0.0) as Vector3)
	) * 0.5
	if not (camera_rig.get("target") as Vector3).is_equal_approx(expected_overview):
		errors.append("E4 started attached to a unit instead of the full-field overview")
	if float(camera_rig.get("distance")) < 20.0:
		errors.append("E4 camera distance is too short to protect low-angle framing")
	if camera_menu == null:
		errors.append("visible overview and camera toggle controls are missing")
	var default_controls := world.call("camera_control_snapshot") as Dictionary
	if (
		bool(default_controls.get("axisLock", true))
		or bool(default_controls.get("horizontalLock", true))
		or not bool(default_controls.get("verticalLock", false))
	):
		errors.append("combat camera does not default to free horizontal orbit with locked pitch")

	var q_event := InputEventKey.new()
	q_event.keycode = KEY_Q
	q_event.pressed = true
	var yaw_before_q := float(camera_rig.get("yaw_degrees"))
	if bool(world.call("handle_camera_input", q_event)) or not is_equal_approx(
		float(camera_rig.get("yaw_degrees")), yaw_before_q
	):
		errors.append("Q is still captured by the combat camera")
	var orbit := InputEventMouseMotion.new()
	orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	var default_pitch := float(camera_rig.get("pitch_degrees"))
	orbit.relative = Vector2(60.0, 30.0)
	if not bool(world.call("handle_camera_input", orbit)):
		errors.append("right mouse drag was not handled by the combat camera")
	if (
		is_equal_approx(float(camera_rig.get("yaw_degrees")), yaw_before_q)
		or not is_equal_approx(float(camera_rig.get("pitch_degrees")), default_pitch)
	):
		errors.append("default combat orbit is not continuous horizontally with a fixed vertical angle")
	world.call("set_camera_axis_lock", true)
	await create_timer(0.4).timeout
	var yaw_before_axis_step := float(camera_rig.get("yaw_degrees"))
	orbit.relative = Vector2(60.0, 0.0)
	world.call("handle_camera_input", orbit)
	var immediate_axis_yaw := float(camera_rig.get("yaw_degrees"))
	if absf(immediate_axis_yaw - yaw_before_axis_step) >= 89.0:
		errors.append("axis step still cuts instantly to the next side")
	await create_timer(0.4).timeout
	var axis_yaw := float(camera_rig.get("yaw_degrees"))
	if not is_equal_approx(absf(axis_yaw - yaw_before_axis_step), 90.0):
		errors.append("smooth side rotation did not settle on one consistent 90-degree side")
	world.call("set_camera_invert_vertical", false)
	world.call("set_camera_horizontal_lock", true)
	world.call("set_camera_vertical_lock", false)
	var pitch_before := float(camera_rig.get("pitch_degrees"))
	var vertical_drag := InputEventMouseMotion.new()
	vertical_drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	vertical_drag.relative = Vector2(0.0, 10.0)
	world.call("handle_camera_input", vertical_drag)
	var normal_pitch := float(camera_rig.get("pitch_degrees"))
	world.call("set_camera_invert_vertical", true)
	world.call("handle_camera_input", vertical_drag)
	var inverted_pitch := float(camera_rig.get("pitch_degrees"))
	if normal_pitch >= pitch_before or inverted_pitch <= normal_pitch:
		errors.append("vertical inversion does not reverse the mouse pitch direction")
	var horizontal_locked_yaw := float(camera_rig.get("yaw_degrees"))
	orbit.relative = Vector2(80.0, 40.0)
	world.call("handle_camera_input", orbit)
	await create_timer(0.35).timeout
	if not is_equal_approx(float(camera_rig.get("yaw_degrees")), horizontal_locked_yaw):
		errors.append("horizontal rotation lock still allows yaw changes")
	world.call("set_camera_horizontal_lock", false)
	world.call("set_camera_vertical_lock", true)
	var vertical_locked_pitch := float(camera_rig.get("pitch_degrees"))
	var unlocked_yaw := float(camera_rig.get("yaw_degrees"))
	orbit.relative = Vector2(60.0, 30.0)
	world.call("handle_camera_input", orbit)
	await create_timer(0.4).timeout
	if not is_equal_approx(float(camera_rig.get("pitch_degrees")), vertical_locked_pitch):
		errors.append("vertical rotation lock still allows pitch changes")
	if is_equal_approx(float(camera_rig.get("yaw_degrees")), unlocked_yaw):
		errors.append("vertical-only lock also blocked horizontal rotation")
	world.call("set_camera_vertical_lock", false)
	world.call("set_camera_invert_vertical", false)

	camera_rig.set("target", Vector3(99.0, 0.0, 99.0))
	camera_rig.call("apply_settings")
	var focus_event := InputEventKey.new()
	focus_event.keycode = KEY_F
	focus_event.pressed = true
	Input.parse_input_event(focus_event)
	await create_timer(0.5).timeout
	var active_id := Combat.current_unit_id(vertical_state)
	var active_cell: Vector2i = Combat.unit_definition(vertical_state, active_id).get(
		"cell", Vector2i.ZERO
	)
	var expected_focus: Vector3 = world.call("_world_position", active_cell, 0.0)
	if not (camera_rig.get("target") as Vector3).is_equal_approx(expected_focus):
		errors.append("the actual Combat Lab F input route did not focus the active unit")
	if camera_menu != null:
		camera_menu.get_popup().id_pressed.emit(0)
		await create_timer(0.5).timeout
		if not (camera_rig.get("target") as Vector3).is_equal_approx(expected_overview):
			errors.append("the visible overview button did not restore full-field framing")

	var staged_cell := active_cell
	for candidate in Grid.reachable_cells(vertical_state, active_id):
		if candidate != active_cell:
			staged_cell = candidate
			break
	if staged_cell == active_cell:
		errors.append("E4 has no reachable destination for staged camera follow")
	var staged_focus: Vector3 = world.call("_world_position", staged_cell, 0.0)
	hud.call("_toggle_move_mode")
	hud.call("_on_grid_cell_chosen", staged_cell, "")
	var immediate_staged_target := camera_rig.get("target") as Vector3
	if immediate_staged_target.is_equal_approx(staged_focus):
		errors.append("camera snapped to the staged movement cell instead of following smoothly")
	await create_timer(0.5).timeout
	if not (camera_rig.get("target") as Vector3).is_equal_approx(staged_focus):
		errors.append("camera did not follow the hero to the staged movement cell")
	var staged_snapshot := hud.call("state_snapshot") as Dictionary
	var staged_active := Combat.unit_definition(
		staged_snapshot, Combat.current_unit_id(staged_snapshot)
	)
	if staged_active.get("cell", Vector2i(-1, -1)) == staged_cell:
		errors.append("camera follow committed staged movement before the action")
	camera_rig.set("target", Vector3(99.0, 0.0, 99.0))
	camera_rig.call("apply_settings")
	Input.parse_input_event(focus_event)
	await create_timer(0.5).timeout
	if not (camera_rig.get("target") as Vector3).is_equal_approx(staged_focus):
		errors.append("F focused the old canonical cell instead of the staged hero position")
	hud.call("_cancel_pending_move")
	await create_timer(0.5).timeout

	var library := grid_map.mesh_library
	if (
		library == null
		or not TileLibrary.has_item(library, TileLibrary.ITEM_BLOCKED_FADED)
		or library.get_item_mesh(TileLibrary.ITEM_BLOCKED_FADED) == null
		or library.get_item_shapes(TileLibrary.ITEM_BLOCKED_FADED).is_empty()
	):
		errors.append("faded blocker tile is missing its mesh or collision")
	else:
		camera_rig.set_process(false)
		var focus_position: Vector3 = world.call("_world_position", Vector2i(0, 2), 0.48)
		camera.global_position = world.call("_world_position", Vector2i(9, 2), 0.0)
		camera.look_at(focus_position, Vector3.UP)
		world.call("_update_occlusion", true)
		if int(world.call("projected_item_at", Vector2i(4, 2))) != TileLibrary.ITEM_BLOCKED_FADED:
			errors.append("a blocker between camera and active unit did not become transparent")
		camera_rig.set_process(true)

	mode_picker.select(4)
	mode_picker.item_selected.emit(4)
	await process_frame
	await process_frame
	var stress_state := hud.call("state_snapshot") as Dictionary
	var stress_grid := stress_state.get("grid", {}) as Dictionary
	var stress_field = world.get("battlefield")
	if int(stress_grid.get("width", 0)) != 16 or int(stress_grid.get("height", 0)) != 12:
		errors.append("E5 did not build the 16x12 resolver state")
	if grid_map.get_used_cells().size() != 192:
		errors.append("E5 did not project exactly 192 dense battlefield columns")
	if stress_field == null or str(stress_field.get("field_id")) != "vertical_forge_16x12":
		errors.append("E5 world does not own the authored 16x12 Battlefield resource")
	if camera.size < 16.0:
		errors.append("E5 camera did not widen its home framing for the large arena")
	if float(camera_rig.get("distance")) < 28.0:
		errors.append("E5 camera can still enter the large field at a low pitch")

	mode_picker.select(1)
	mode_picker.item_selected.emit(1)
	await process_frame
	await process_frame
	if grid_map.get_used_cells().size() != 35:
		errors.append("returning to E2 did not restore the 7x5 comparison field")
	if not is_equal_approx(camera.size, 9.2):
		errors.append("returning to E2 did not restore the authored camera home")

	_finish(lab, errors)


func _finish(lab: Node, errors: Array[String]) -> void:
	lab.free()
	if not errors.is_empty():
		printerr("FAIL combat vertical view")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat vertical view")
	print("  E4 projects 80 dense columns; E5 projects 192")
	print("  Q/E are free; inversion, smooth side turns and independent axis locks work")
	print("  camera follows staged movement smoothly; F focuses its pre-commit position")
	print("  the visible overview restores the field without changing combat state")
	print("  initial overview and safe camera distance protect large low-angle fields")
	print("  occluding blockers fade while retaining collision; unit outlines remain visible")
	print("  leaving a large field restores the authored E2 camera home")
	quit(0)
