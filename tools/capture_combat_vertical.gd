extends SceneTree
## Reproducible Forward+ screenshot of the Stage 1 E4 Combat Lab demonstration.

const LAB_SCENE := preload("res://scenes/combat_lab.tscn")
const OUTPUT_PATH := "user://combat_vertical_stage1.png"
const LOW_ANGLE_OUTPUT_PATH := "user://combat_vertical_stage1_low_angle.png"
const FEEDBACK_OUTPUT_PATH := "user://combat_vertical_stage1_feedback.png"
const RULES_OUTPUT_PATH := "user://combat_vertical_stage3_rules.png"
const COMMAND_BROWSE_OUTPUT_PATH := "user://combat_vertical_stage3_command_browse.png"
const COMMAND_TARGET_OUTPUT_PATH := "user://combat_vertical_stage3_command_target.png"
const ELEMENTS_OUTPUT_PATH := "user://combat_vertical_stage3_elements.png"
const PERSONAL_OUTPUT_PATH := "user://combat_vertical_stage3_personal_actions.png"
const ITEMS_OUTPUT_PATH := "user://combat_vertical_stage3_items.png" # Adaptive item drawer.
const PAIRS_OUTPUT_PATH := "user://combat_vertical_stage3_pairs.png"
const PAIRS_FAR_OUTPUT_PATH := "user://combat_vertical_stage3_pairs_far.png"
const PROGRESSION_OUTPUT_PATH := "user://combat_vertical_stage3_progression.png"
const APPROACH_OUTPUT_PATH := "user://combat_vertical_stage3_auto_approach.png"
const EncounterCatalog := preload("res://scripts/prototypes/ember_encounter_catalog.gd")


func _init() -> void:
	root.size = Vector2i(1600, 900)
	_capture_and_quit.call_deferred()


func _capture_and_quit() -> void:
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	var mode_picker := lab.find_child("CombatEncounterMode", true, false) as OptionButton
	if mode_picker == null or mode_picker.item_count < 4:
		printerr("FAIL capture combat vertical: E4 mode is missing")
		lab.free()
		quit(1)
		return
	mode_picker.select(3)
	mode_picker.item_selected.emit(3)
	await process_frame
	await process_frame
	await create_timer(0.45).timeout
	var error := root.get_texture().get_image().save_png(OUTPUT_PATH)
	if error != OK:
		printerr("FAIL capture combat vertical: ", error_string(error))
		lab.free()
		quit(1)
		return
	mode_picker.select(4)
	mode_picker.item_selected.emit(4)
	await process_frame
	await process_frame
	var camera_rig := lab.find_child("CameraRig", true, false) as Node3D
	if camera_rig != null:
		camera_rig.set("pitch_degrees", float(camera_rig.get("min_pitch_degrees")))
		camera_rig.call("apply_settings")
		await create_timer(0.25).timeout
		error = root.get_texture().get_image().save_png(LOW_ANGLE_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL low-angle combat vertical capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	mode_picker.select(3)
	mode_picker.item_selected.emit(3)
	await process_frame
	await process_frame
	var hud := lab.find_child("CombatHUD", true, false) as Control
	var world := lab as Node3D
	if hud != null:
		hud.call("_console_add_status", "wisp", "wet", 2)
		hud.call("_console_add_status", "raider", "burning", 2)
		hud.call("_refresh")
		hud.call("_select_action", "lift_throw")
		world.emit_signal("cell_chosen", Vector2i(0, 4), "orik")
		await create_timer(0.35).timeout
		error = root.get_texture().get_image().save_png(FEEDBACK_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL combat feedback capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	if hud != null:
		var rules_state := hud.call("state_snapshot") as Dictionary
		var rules_units: Dictionary = rules_state.get("units", {})
		for raw_id in rules_units:
			var unit: Dictionary = rules_units[raw_id]
			unit["nextAt"] = 0.0 if str(raw_id) == "mira" else 100.0
			rules_units[raw_id] = unit
		var mira: Dictionary = rules_units.get("mira", {})
		var wisp: Dictionary = rules_units.get("wisp", {})
		mira["cell"] = Vector2i(3, 1)
		wisp["cell"] = Vector2i(4, 1)
		rules_units["mira"] = mira
		rules_units["wisp"] = wisp
		rules_state["units"] = rules_units
		rules_state["rngSeed"] = 1
		hud.set("_state", rules_state)
		hud.set("_pending_actor_id", "")
		hud.call("_refresh")
		await process_frame
		hud.call("_select_action", "douse")
		hud.set("_selected_target", "wisp")
		hud.call("_refresh")
		await create_timer(0.25).timeout
		hud.set("_selected_target", "wisp")
		hud.call("_set_inspected_enemy", "wisp")
		hud.call("_refresh_commands")
		hud.call("_refresh_enemy_info")
		await process_frame
		error = root.get_texture().get_image().save_png(RULES_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL combat production rules capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	if hud != null:
		hud.call("_cancel_radial_targeting")
		hud.call("_open_radial_page", "magic")
		await process_frame
		hud.call("_browse_radial_entry", {"id": "douse"})
		await create_timer(0.25).timeout
		error = root.get_texture().get_image().save_png(COMMAND_BROWSE_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL safe command-browse capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	if hud != null:
		hud.call("_select_action", "douse")
		await create_timer(0.25).timeout
		error = root.get_texture().get_image().save_png(COMMAND_TARGET_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL confirmed command-target capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	if hud != null:
		hud.call("_cancel_radial_targeting")
		hud.call("_open_radial_page", "magic")
		hud.call("_browse_radial_entry", {"id": "earth_raise"})
		await process_frame
		await create_timer(0.25).timeout
		error = root.get_texture().get_image().save_png(ELEMENTS_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL combat element-library capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	if hud != null:
		var personal_state := (hud.call("state_snapshot") as Dictionary).duplicate(true)
		var personal_units: Dictionary = personal_state.get("units", {})
		for raw_id in personal_units:
			var personal_unit: Dictionary = personal_units[raw_id]
			personal_unit["nextAt"] = 0.0 if str(raw_id) == "sena" else 100.0
			personal_units[raw_id] = personal_unit
		personal_state["units"] = personal_units
		hud.set("_state", personal_state)
		hud.set("_selected_action", "")
		hud.set("_selected_target", "")
		hud.set("_radial_targeting", false)
		hud.call("_refresh")
		hud.call("_open_radial_page", "skill")
		await process_frame
		hud.call("_browse_radial_entry", {"id": "remote_relay"})
		await create_timer(0.25).timeout
		error = root.get_texture().get_image().save_png(PERSONAL_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL combat personal-actions capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	if hud != null:
		hud.set("_selected_action", "")
		hud.set("_selected_target", "")
		hud.set("_radial_targeting", false)
		hud.set("_hovered_unit_id", "")
		hud.call("_activate_radial_entry", {"id": "__items"})
		hud.call("_refresh_enemy_info")
		await process_frame
		await create_timer(0.25).timeout
		error = root.get_texture().get_image().save_png(ITEMS_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL combat items capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	if hud != null:
		var pair_state := hud.call("state_snapshot") as Dictionary
		var pair_units: Dictionary = pair_state.get("units", {})
		for raw_id in pair_units:
			var pair_unit: Dictionary = pair_units[raw_id]
			pair_unit["nextAt"] = 0.0 if str(raw_id) == "sena" else 100.0
			if str(raw_id) == "mira":
				pair_unit["cell"] = Vector2i(1, 5)
			if str(raw_id) == "wisp":
				pair_unit["statuses"] = {"wet": 2}
				pair_unit["cell"] = Vector2i(2, 6)
			pair_units[raw_id] = pair_unit
		pair_state["units"] = pair_units
		hud.set("_state", pair_state)
		hud.call("_refresh")
		hud.call("_open_radial_page", "skill")
		hud.call("_browse_radial_entry", {"id": "duo_pulse"})
		await process_frame
		await create_timer(0.25).timeout
		error = root.get_texture().get_image().save_png(PAIRS_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL combat pair-technique capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	if hud != null:
		var far_pair_state := (hud.call("state_snapshot") as Dictionary).duplicate(true)
		var far_pair_units: Dictionary = far_pair_state.get("units", {})
		var far_mira: Dictionary = far_pair_units.get("mira", {})
		far_mira["cell"] = Vector2i(0, 2)
		far_pair_units["mira"] = far_mira
		far_pair_state["units"] = far_pair_units
		hud.set("_state", far_pair_state)
		hud.call("_refresh")
		hud.call("_open_radial_page", "skill")
		await process_frame
		await process_frame
		hud.call("_browse_radial_entry", {"id": "duo_pulse"})
		await create_timer(0.25).timeout
		error = root.get_texture().get_image().save_png(PAIRS_FAR_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL out-of-range pair-technique capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	if hud != null:
		mode_picker.select(3)
		mode_picker.item_selected.emit(3)
		await process_frame
		await process_frame
		var progression_state := hud.call("state_snapshot") as Dictionary
		var progression_units: Dictionary = progression_state.get("units", {})
		for raw_id in progression_units:
			var unit: Dictionary = progression_units[raw_id]
			if str(unit.get("team", "")) == "enemy" or str(raw_id) == "orik":
				unit["hp"] = 0
			progression_units[raw_id] = unit
		progression_state["units"] = progression_units
		hud.set("_authored_encounter", EncounterCatalog.definition("colored_crossing_demo"))
		hud.set("_state", progression_state)
		hud.call("_refresh")
		await process_frame
		await create_timer(0.25).timeout
		error = root.get_texture().get_image().save_png(PROGRESSION_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL combat progression capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	if hud != null:
		mode_picker.select(3)
		mode_picker.item_selected.emit(3)
		await process_frame
		await process_frame
		var approach_state := (hud.call("state_snapshot") as Dictionary).duplicate(true)
		var approach_units := approach_state.get("units", {}) as Dictionary
		for raw_id in approach_units:
			var approach_unit := approach_units[raw_id] as Dictionary
			var approach_id := str(raw_id)
			approach_unit["nextAt"] = 0.0 if approach_id == "mira" else 100.0
			if approach_id not in ["mira", "wisp"]:
				approach_unit["hp"] = 0
			if approach_id == "mira":
				approach_unit["cell"] = Vector2i(0, 2)
				approach_unit["moveRange"] = 2
			if approach_id == "wisp":
				approach_unit["cell"] = Vector2i(6, 2)
			approach_units[raw_id] = approach_unit
		approach_state["units"] = approach_units
		hud.set("_state", approach_state)
		hud.set("_pending_actor_id", "")
		hud.call("_refresh")
		await process_frame
		hud.call("_select_action", "strike")
		await process_frame
		hud.call("_preview_target_at", world.call("screen_position_for_cell", Vector2i(6, 2)))
		await create_timer(0.35).timeout
		error = root.get_texture().get_image().save_png(APPROACH_OUTPUT_PATH)
	if error != OK:
		printerr("FAIL combat auto-approach capture: ", error_string(error))
		lab.free()
		quit(1)
		return
	print("PASS Forward+ combat vertical capture: ", ProjectSettings.globalize_path(OUTPUT_PATH))
	print("PASS Forward+ low-angle capture: ", ProjectSettings.globalize_path(LOW_ANGLE_OUTPUT_PATH))
	print("PASS Forward+ lift/status capture: ", ProjectSettings.globalize_path(FEEDBACK_OUTPUT_PATH))
	print("PASS Forward+ combat rules capture: ", ProjectSettings.globalize_path(RULES_OUTPUT_PATH))
	print("PASS safe command-browse capture: ", ProjectSettings.globalize_path(COMMAND_BROWSE_OUTPUT_PATH))
	print("PASS confirmed command-target capture: ", ProjectSettings.globalize_path(COMMAND_TARGET_OUTPUT_PATH))
	print("PASS hostile auto-approach capture: ", ProjectSettings.globalize_path(APPROACH_OUTPUT_PATH))
	print("PASS Forward+ element-library capture: ", ProjectSettings.globalize_path(ELEMENTS_OUTPUT_PATH))
	print("PASS Forward+ personal-actions capture: ", ProjectSettings.globalize_path(PERSONAL_OUTPUT_PATH))
	print("PASS Forward+ combat items capture: ", ProjectSettings.globalize_path(ITEMS_OUTPUT_PATH))
	print("PASS Forward+ combat pair-technique capture: ", ProjectSettings.globalize_path(PAIRS_OUTPUT_PATH))
	print("PASS Forward+ out-of-range pair capture: ", ProjectSettings.globalize_path(PAIRS_FAR_OUTPUT_PATH))
	print("PASS Forward+ combat progression capture: ", ProjectSettings.globalize_path(PROGRESSION_OUTPUT_PATH))
	lab.free()
	quit(0)
