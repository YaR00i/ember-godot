extends SceneTree
## UI + native scene smoke for the isolated D1 Combat Lab.

const LAB_SCENE := preload("res://scenes/combat_lab.tscn")
const Grid3D = preload("res://scripts/prototypes/ember_combat_grid_3d_world.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")


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
	var timeline := lab.find_child("CombatTimeline", true, false) as VBoxContainer
	var timeline_panel := lab.find_child("CombatTimelinePanel", true, false) as PanelContainer
	var console_panel := lab.find_child("CombatConsolePanel", true, false) as PanelContainer
	var command_panel := lab.find_child("CombatCommandPanel", true, false) as PanelContainer
	var field_panel := lab.find_child("CombatFieldPanel", true, false) as PanelContainer
	var field := lab.find_child("CombatZoneField", true, false) as HBoxContainer
	var actions := lab.find_child("CombatActions", true, false) as VBoxContainer
	var preview := lab.find_child("CombatPreview", true, false) as RichTextLabel
	var ability_info := lab.find_child("CombatAbilityInfo", true, false) as RichTextLabel
	var enemy_info_panel := lab.find_child("CombatEnemyInfoPanel", true, false) as PanelContainer
	var enemy_info := lab.find_child("CombatEnemyInfo", true, false) as RichTextLabel
	var confirm := lab.find_child("CombatConfirm", true, false) as Button
	var console_input := lab.find_child("CombatConsoleInput", true, false) as LineEdit
	var pause_overlay := lab.find_child("CombatPauseOverlay", true, false) as ColorRect
	var mode_picker := lab.find_child("CombatEncounterMode", true, false) as OptionButton
	var view_picker := lab.find_child("CombatFieldViewMode", true, false) as OptionButton
	var camera_menu := lab.find_child("CombatCameraMenu", true, false) as MenuButton
	var grid_map := lab.find_child("CombatGridMap", true, false) as GridMap
	var camera := lab.find_child("CombatCamera3D", true, false) as Camera3D
	var camera_rig := lab.find_child("CameraRig", true, false) as Node3D
	var embedded := lab.find_child("CombatGrid3DField", true, false) as SubViewportContainer
	if world == null or hud == null or grid_map == null or camera == null or camera_rig == null:
		errors.append("Combat Lab is not a standard Node3D scene with GridMap, Camera3D and CanvasLayer HUD")
	if embedded != null:
		errors.append("main Combat Lab still embeds its world in a SubViewportContainer")
	if timeline == null or timeline.get_child_count() != 8:
		errors.append("Combat Lab did not render the visible eight-entry timeline")
	if (
		timeline_panel == null or console_panel == null or command_panel == null or field_panel == null
		or console_panel.position.x > 24.0 or console_panel.position.y < 650.0
		or timeline_panel.position.x > 24.0 or timeline_panel.position.y > 110.0
		or timeline_panel.size.x > 240.0 or timeline_panel.size.y < 450.0
		or field_panel.size.x < 1500.0 or field_panel.size.y < 850.0
	):
		errors.append("combat HUD is not split into fullscreen field, left turn column, bottom-left console and compact command card")
	if lab.find_child("HSplitContainer", true, false) != null:
		errors.append("legacy two-column laboratory overlay still owns the battle layout")
	if mode_picker == null or str(mode_picker.get_item_metadata(mode_picker.selected)) != "grid":
		errors.append("E2 grid is not the default comparison mode")
	if view_picker == null or str(view_picker.get_item_metadata(view_picker.selected)) != "3d":
		errors.append("native 3D projection is not the default grid view")
	var input_surface := lab.find_child("CombatFieldInputSurface", true, false) as Control
	if field == null or input_surface == null or field.get_child_count() != 1:
		errors.append("standard 3D mode did not expose one transparent input surface over the native world")
	if grid_map == null or grid_map.mesh_library == null or grid_map.get_used_cells().size() != 35:
		errors.append("Combat Lab did not render the 7x5 scene-owned GridMap")
	elif world != null:
		var d2_screen: Vector2 = world.call("screen_position_for_cell", Vector2i(3, 1))
		var picked_d2: Vector2i = world.call("pick_cell_at", d2_screen)
		if picked_d2 != Vector2i(3, 1):
			errors.append("main Camera3D ray did not resolve the visible D2 GridMap tile")
	if camera_rig != null and camera != null and input_surface != null:
		var initial_size := camera.size
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		input_surface.gui_input.emit(wheel)
		await process_frame
		if not is_equal_approx(camera.size, initial_size):
			errors.append("mouse wheel still changes combat zoom instead of remaining available to UI")
		if bool(camera_rig.get("mouse_wheel_zoom_enabled")):
			errors.append("combat scene did not disable runtime wheel zoom through its authored toggle")
		var initial_yaw := float(camera_rig.get("yaw_degrees"))
		var orbit := InputEventMouseMotion.new()
		orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
		orbit.relative = Vector2(60.0, -10.0)
		input_surface.gui_input.emit(orbit)
		await create_timer(0.4).timeout
		if is_equal_approx(float(camera_rig.get("yaw_degrees")), initial_yaw):
			errors.append("right mouse drag did not orbit the combat camera")
		var initial_target: Vector3 = camera_rig.get("target")
		var pan := InputEventMouseMotion.new()
		pan.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		pan.relative = Vector2(30.0, 12.0)
		input_surface.gui_input.emit(pan)
		await process_frame
		if (camera_rig.get("target") as Vector3).is_equal_approx(initial_target):
			errors.append("middle mouse drag did not pan the combat camera target")
		camera_rig.set("projection_mode", 1)
		camera_rig.set("fov", 55.0)
		camera_rig.call("apply_settings")
		if camera.projection != Camera3D.PROJECTION_PERSPECTIVE or not is_equal_approx(camera.fov, 55.0):
			errors.append("Inspector projection/FOV settings did not reach Camera3D")
		if camera_menu == null:
			errors.append("visible camera overview/settings controls are absent")
		else:
			camera_menu.get_popup().id_pressed.emit(0)
		await create_timer(0.5).timeout
		if camera.projection != Camera3D.PROJECTION_ORTHOGONAL or not is_equal_approx(camera.size, 9.2):
			errors.append("the visible overview button did not restore the authored combat camera view")
		var reset_screen: Vector2 = world.call("screen_position_for_cell", Vector2i(3, 1))
		if world.call("pick_cell_at", reset_screen) != Vector2i(3, 1):
			errors.append("camera reset did not restore ray-pick alignment")
	if actions == null or actions.get_child_count() != 12:
		errors.append("standalone lab did not expose six hero actions, three candidate element actions and three shared items")
	elif actions.visible:
		errors.append("3D HUD still shows the duplicate sidebar action list instead of radial commands")
	var radial := lab.find_child("CombatRadialMenu", true, false) as Control
	var drawer := lab.find_child("CombatCommandDrawer", true, false) as PanelContainer
	if radial == null or not radial.visible or radial.get_child_count() < 7:
		errors.append("active hero does not expose the radial movement/action shortcuts")
	if drawer == null:
		errors.append("adaptive command drawer is missing")
	if lab.find_child("CombatRadialActor", true, false) != null:
		errors.append("radial actor plate still covers the active combatant")
	if (
		lab.find_child("CombatRadial_skills", true, false) == null
		or lab.find_child("CombatRadial_magic", true, false) == null
		or lab.find_child("CombatRadial_items", true, false) == null
	):
		errors.append("root radial menu is not split into Skills, Magic and Items")
	if ability_info == null or "условия" not in ability_info.text.to_lower():
		errors.append("bottom action description does not explain hover/focus behavior")
	else:
		var magic_category := lab.find_child("CombatRadial_magic", true, false) as Button
		if magic_category != null:
			magic_category.grab_focus()
			magic_category.pressed.emit()
		else:
			hud.call("_open_radial_page", "magic")
		await process_frame
		await process_frame
		var radial_focus := root.gui_get_focus_owner()
		if radial_focus == null or drawer == null or not drawer.is_ancestor_of(radial_focus):
			errors.append("gamepad/keyboard focus did not enter the command drawer (focus=%s)" % str(radial_focus))
		if drawer == null or not drawer.visible or lab.find_child("CombatCommand_douse", true, false) == null:
			errors.append("Magic command drawer does not expose authored spells")
		if lab.find_child("CombatRadial_douse", true, false) != null:
			errors.append("a selected category still creates a second command ring")
		hud.call("_show_radial_entry_help", {"id": "douse"})
		if "Wet" not in ability_info.text or "MP: 4" not in ability_info.text:
			errors.append("hovered spell does not expose its effect, cost and conditions")
		hud.call("_open_radial_page", "skill")
		await process_frame
		if lab.find_child("CombatCommand_lift_throw", true, false) == null:
			errors.append("Skills command drawer does not expose authored techniques")
		hud.call("_open_radial_page", "item")
		await process_frame
		var herb_command := lab.find_child("CombatCommand_item_herb", true, false) as Button
		if herb_command == null:
			errors.append("Items command drawer does not expose the shared combat bag")
		elif not herb_command.disabled or "нет подходящей цели" not in herb_command.text:
			errors.append("an unavailable item row does not remain visible with its reason")
		var drawer_scroll := lab.find_child("CombatCommandDrawerScroll", true, false) as ScrollContainer
		if drawer_scroll == null or drawer_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			errors.append("command drawer still exposes horizontal scrolling for long labels")
		hud.call("_show_radial_entry_help", {"id": "item:qingxin_tea"})
		if "HP +12" not in ability_info.text or "MP +8" not in ability_info.text:
			errors.append("hovered combat item does not expose its deterministic effect")
		if drawer != null:
			radial.position = Vector2(8, 220)
			hud.call("_position_command_drawer")
			if drawer.position.x <= radial.position.x + radial.size.x:
				errors.append("command drawer did not move to the right of a left-edge actor")
			radial.position = Vector2(hud.size.x - radial.size.x - 8, 220)
			hud.call("_position_command_drawer")
			if drawer.position.x + drawer.size.x >= radial.position.x:
				errors.append("command drawer did not move to the left of a right-edge actor")
			hud.call("_position_radial_menu")
		var staged_actor_id := Combat.current_unit_id(hud.call("state_snapshot"))
		hud.set("_pending_actor_id", staged_actor_id)
		hud.set("_pending_cell", Vector2i(3, 1))
		hud.call("_open_radial_page", "magic")
		await process_frame
		await process_frame
		var staged_douse := lab.find_child("CombatCommand_douse", true, false) as Button
		if staged_douse == null or staged_douse.disabled:
			errors.append("staged command-selection test could not enable Douse")
		else:
			staged_douse.grab_focus()
			await process_frame
			if (
				str(hud.get("_browsed_command_id")) != "douse"
				or not str(hud.get("_selected_action")).is_empty()
				or bool(hud.get("_radial_targeting"))
				or str(world.get("_selected_action")) != "douse"
			):
				errors.append("focus did not stay in safe command browsing while projecting Douse range")
			staged_douse.pressed.emit()
			await process_frame
			if (
				str(hud.get("_selected_action")) != "douse"
				or not bool(hud.get("_radial_targeting"))
				or radial.visible
				or drawer.visible
			):
				errors.append("confirming a browsed command did not enter the separate target-planning stage")
			var cancel_targeting := InputEventAction.new()
			cancel_targeting.action = "ui_cancel"
			cancel_targeting.pressed = true
			hud.call("_unhandled_input", cancel_targeting)
			await process_frame
			await process_frame
			var restored_focus := root.gui_get_focus_owner()
			if (
				not str(hud.get("_selected_action")).is_empty()
				or bool(hud.get("_radial_targeting"))
				or str(hud.get("_radial_page")) != "magic"
				or not drawer.visible
				or restored_focus == null
				or restored_focus.name != "CombatCommand_douse"
				or str(world.get("_selected_action")) != "douse"
			):
				errors.append("Cancel did not clear targeting and restore the source command with safe field preview")
			var cancel_drawer := InputEventAction.new()
			cancel_drawer.action = "ui_cancel"
			cancel_drawer.pressed = true
			hud.call("_unhandled_input", cancel_drawer)
			await process_frame
			if str(hud.get("_radial_page")) != "root" or drawer.visible:
				errors.append("a second Cancel did not step back from the command drawer to the root ring")
		hud.call("_reset_lab")
		await process_frame
		await process_frame
		if drawer != null and drawer.visible:
			errors.append("returning to the main ring did not close the command drawer")
		var returned_focus := root.gui_get_focus_owner()
		if returned_focus == null or not radial.is_ancestor_of(returned_focus):
			errors.append("closing the command drawer did not return focus to the main ring")
	if not str(hud.get("_selected_action")).is_empty() or bool(hud.get("_radial_targeting")):
		errors.append("idle combat UI still arms an action before the player confirms a command")
	if preview != null and (preview.text.contains("бросок ") or preview.text.contains("ПРОМАХ") or preview.text.contains("КРИТ")):
		errors.append("pre-commit HUD leaks the resolver's locked random result")
	var pair_state := (hud.call("state_snapshot") as Dictionary).duplicate(true)
	var pair_units: Dictionary = pair_state.get("units", {})
	for raw_id in pair_units:
		var pair_unit: Dictionary = pair_units[raw_id]
		pair_unit["nextAt"] = 0.0 if str(raw_id) == "sena" else 100.0
		if str(raw_id) == "wisp":
			pair_unit["statuses"] = {"wet": 2}
			pair_unit["cell"] = Vector2i(2, 1)
		pair_units[raw_id] = pair_unit
	pair_state["units"] = pair_units
	hud.set("_state", pair_state)
	hud.call("_refresh")
	hud.call("_open_radial_page", "skill")
	await process_frame
	var wet_pair_button := lab.find_child("CombatCommand_duo_pulse", true, false) as Button
	if wet_pair_button == null or wet_pair_button.disabled or "8+6MP" not in wet_pair_button.text:
		errors.append("skill drawer does not expose the available Mira + Sena cost (button=%s, disabled=%s, text=%s)" % [
			str(wet_pair_button != null),
			str(wet_pair_button.disabled) if wet_pair_button != null else "n/a",
			wet_pair_button.text if wet_pair_button != null else "missing",
		])
	hud.call("_show_radial_entry_help", {"id": "duo_pulse"})
	await process_frame
	if (
		"Партнёр: Мира" not in ability_info.text
		or "дистанция 2/3 · В РАДИУСЕ" not in ability_info.text
		or "MP: 6" not in ability_info.text
	):
		errors.append("pair hover description does not explain its partner, radius and cost")
	var pair_badge := lab.find_child("CombatPairPartnerBadge_mira", true, false) as Label3D
	if (
		pair_badge == null
		or "СВЯЗКА · Мира" not in pair_badge.text
		or "В РАДИУСЕ · 2/3" not in pair_badge.text
		or lab.find_child("CombatPairRange_0_1", true, false) == null
	):
		errors.append("3D pair context does not identify the partner and visible radius")
	var in_range_pair_state := pair_state.duplicate(true)
	var distant_pair_state := in_range_pair_state.duplicate(true)
	var distant_units: Dictionary = distant_pair_state.get("units", {})
	var distant_mira: Dictionary = distant_units.get("mira", {})
	distant_mira["cell"] = Vector2i(6, 4)
	distant_units["mira"] = distant_mira
	distant_pair_state["units"] = distant_units
	hud.set("_state", distant_pair_state)
	hud.call("_refresh")
	hud.call("_open_radial_page", "skill")
	await process_frame
	wet_pair_button = lab.find_child("CombatCommand_duo_pulse", true, false) as Button
	if wet_pair_button != null:
		wet_pair_button.grab_focus()
	hud.call("_show_radial_entry_help", {"id": "duo_pulse"})
	await process_frame
	pair_badge = lab.find_child("CombatPairPartnerBadge_mira", true, false) as Label3D
	if (
		wet_pair_button == null
		or not wet_pair_button.disabled
		or "Мира вне радиуса: 9/3 клеток" not in wet_pair_button.text
		or "ВНЕ РАДИУСА" not in ability_info.text
		or pair_badge == null
		or "ВНЕ РАДИУСА · 9/3" not in pair_badge.text
	):
		errors.append("out-of-range partner is not explained consistently by HUD and 3D field (row=%s; help=%s; badge=%s)" % [
			wet_pair_button.text if wet_pair_button != null else "<missing>",
			ability_info.text if ability_info != null else "<missing>",
			pair_badge.text if pair_badge != null else "<missing>",
		])
	pair_state = in_range_pair_state.duplicate(true)
	pair_units = pair_state.get("units", {})
	var pair_mira: Dictionary = pair_units.get("mira", {})
	pair_mira["mp"] = 5
	pair_units["mira"] = pair_mira
	pair_state["units"] = pair_units
	hud.set("_state", pair_state)
	hud.call("_refresh")
	hud.call("_open_radial_page", "skill")
	await process_frame
	wet_pair_button = lab.find_child("CombatCommand_duo_pulse", true, false) as Button
	if wet_pair_button == null or not wet_pair_button.disabled or "Мира: нужно 6 MP" not in wet_pair_button.text:
		errors.append("pair row does not explain the partner's missing MP")
	hud.call("_reset_lab")
	await process_frame
	if enemy_info_panel == null or enemy_info == null:
		errors.append("top-right enemy study card is absent")
	else:
		hud.call("_inspect_unit_at", world.call("screen_position_for_cell", Vector2i(5, 1)))
		if (
			not enemy_info_panel.visible
			or "Болотный огонёк" not in enemy_info.text
			or "уровень 2" not in enemy_info.text
			or "Тип: Дух" not in enemy_info.text
			or "Frozen: сокр. на 1 ход" not in enemy_info.text
		):
			errors.append("enemy study card does not expose authored level, type and deterministic resistances")
		hud.call("_set_inspected_enemy", "")
		if enemy_info_panel.visible:
			errors.append("enemy study card did not clear away from an enemy")
	if confirm == null or confirm.visible or not confirm.disabled:
		errors.append("legacy F confirmation is still exposed in the combat HUD")
	var item_state := (hud.call("state_snapshot") as Dictionary).duplicate(true)
	var item_actor_id := Combat.current_unit_id(item_state)
	var item_units := item_state.get("units", {}) as Dictionary
	var item_actor := item_units.get(item_actor_id, {}) as Dictionary
	item_actor["hp"] = maxi(1, int(item_actor.get("maxHp", 1)) - 4)
	item_units[item_actor_id] = item_actor
	item_state["units"] = item_units
	hud.set("_state", item_state)
	hud.call("_refresh")
	var item_count_before := int((item_state.get("inventory", {}) as Dictionary).get("herb", 0))
	hud.call("_select_action", "item:herb")
	await process_frame
	if int(((hud.call("state_snapshot") as Dictionary).get("inventory", {}) as Dictionary).get("herb", 0)) != item_count_before:
		errors.append("opening a combat item target selection consumed it before commit")
	hud.call("_select_target", item_actor_id)
	await process_frame
	var item_committed := hud.call("state_snapshot") as Dictionary
	if int((item_committed.get("inventory", {}) as Dictionary).get("herb", 0)) != item_count_before - 1:
		errors.append("combat item target click did not consume exactly one shared stack")
	hud.call("_reset_lab")
	await process_frame
	var turn_before_defend := int((hud.call("state_snapshot") as Dictionary).get("turn", 0))
	hud.call("_select_action", "defend")
	await process_frame
	if int((hud.call("state_snapshot") as Dictionary).get("turn", 0)) <= turn_before_defend:
		errors.append("self-target defend did not commit immediately from the radial command")
	hud.call("_reset_lab")
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
	var far_strike := lab.find_child("CombatRadial_strike", true, false) as Button
	if far_strike == null or far_strike.disabled:
		var radial_names := PackedStringArray()
		for child in radial.get_children():
			radial_names.append(str(child.name))
		errors.append("Strike is disabled even though the distant enemy has an approach route (targets=%s, pending=%s, button=%s)" % [
			str(hud.call("_action_target_ids", "strike")), str(hud.get("_pending_cell")),
			"%s, radial=%s, targeting=%s, children=%s" % [
				str(far_strike), str(radial.visible), str(hud.get("_radial_targeting")), str(radial_names),
			],
		])
	else:
		hud.call("_select_action", "strike")
		await process_frame
		hud.call("_preview_target_at", world.call("screen_position_for_cell", Vector2i(6, 2)))
		await process_frame
		preview = lab.find_child("CombatPreview", true, false) as RichTextLabel
		var stop_label := lab.find_child("CombatApproachStopLabel", true, false) as Label3D
		var approach_preview := hud.get("_current_preview") as Dictionary
		var untouched_state := hud.call("state_snapshot") as Dictionary
		if (
			str(approach_preview.get("actionId", "")) != "defend"
			or not bool(approach_preview.get("approachFallbackDefend", false))
			or approach_preview.get("approachDestination", Combat.INVALID_CELL) != Vector2i(2, 2)
		):
			errors.append("far target hover did not plan the visible movement + Defend fallback")
		if (
			preview == null
			or "Остановка: C3" not in preview.text
			or "ЗАЩИТА" not in preview.text
			or "не расходует ресурсы" not in preview.text
		):
			errors.append("far target preview does not plainly explain stop cell and Defend fallback")
		if stop_label == null or "ЗАЩИТА" not in stop_label.text or "C3" not in stop_label.text:
			errors.append("3D field does not mark the exact fallback stop cell with a shield state")
		if (
			Combat.unit_definition(untouched_state, "mira").get("cell", Combat.INVALID_CELL)
			!= Vector2i(0, 2)
		):
			errors.append("far target hover committed its approach before target confirmation")
		hud.call("_cancel_radial_targeting")
		await process_frame
	hud.call("_reset_lab")
	await process_frame
	if hud == null or hud.size.x < 1500.0 or hud.size.y < 850.0:
		errors.append("Combat HUD did not fill its 1600x900 CanvasLayer")
	if hud != null and not bool(hud.get("request_fullscreen")):
		errors.append("Combat Lab no longer requests a fullscreen game window")
	var move_button := lab.find_child("CombatMoveMode", true, false) as Button
	if move_button == null:
		errors.append("grid movement command is absent")
	else:
		move_button.pressed.emit()
		await process_frame
		if radial.visible:
			errors.append("radial menu did not hide while choosing a movement cell")
		world.emit_signal("cell_chosen", Vector2i(3, 1), "")
		await create_timer(0.34).timeout
		if not radial.visible:
			errors.append("radial menu did not return after choosing a movement cell")
		var staged_state: Dictionary = hud.call("state_snapshot")
		var staged_mira: Dictionary = (staged_state.get("units", {}) as Dictionary).get("mira", {})
		var staged_unit := lab.find_child("CombatUnit_mira", true, false) as Node3D
		if staged_unit == null or not is_equal_approx(staged_unit.position.x, 4.2):
			errors.append("staged destination does not visibly project the active hero")
		if (
			str(world.call("projected_occupant_at", Vector2i(3, 1))) != "mira"
			or not str(world.call("projected_occupant_at", Vector2i(1, 2))).is_empty()
		):
			errors.append("3D hit projection disagrees with the staged hero position")
		if staged_mira.get("cell") != Vector2i(1, 2):
			errors.append("visual staged movement mutated state before confirmation")
		var douse := lab.find_child("CombatAction_douse", true, false) as Button
		if douse == null or douse.disabled:
			errors.append("movement did not unlock the ranged water action")
		else:
			var staged_roll_state := hud.call("_selection_state") as Dictionary
			_lock_hit_seed(staged_roll_state, "douse", "wisp")
			var source_roll_state := hud.call("state_snapshot") as Dictionary
			source_roll_state["rngSeed"] = staged_roll_state.get("rngSeed", 1)
			hud.set("_state", source_roll_state)
			hud.call("_refresh")
			douse.pressed.emit()
			await process_frame
			if radial.visible:
				errors.append("radial menu did not hide while choosing an action target")
			hud.call("_preview_target_at", world.call("screen_position_for_cell", Vector2i(5, 1)))
			await process_frame
			preview = lab.find_child("CombatPreview", true, false) as RichTextLabel
			var hover_state := hud.call("state_snapshot") as Dictionary
			var hover_mira := (hover_state.get("units", {}) as Dictionary).get("mira", {}) as Dictionary
			if preview == null or not preview.text.contains("Перемещение") or not preview.text.contains("Wet"):
				errors.append("hovering a valid target did not expose the compound action preview (%s, target=%s)" % [
				preview.text if preview != null else "<missing>", str(hud.get("_selected_target")),
			])
			if hover_mira.get("cell") != Vector2i(1, 2):
				errors.append("target hover mutated canonical movement before click")
			if preview != null and (preview.text.contains("Попадание ") or preview.text.contains("бросок ") or preview.text.contains("КРИТ") or preview.text.contains(" HP")):
				errors.append("target hover revealed hit, crit or damage before commit")
			world.emit_signal("cell_chosen", Vector2i(5, 1), "wisp")
			await process_frame
			if not radial.visible:
				errors.append("radial menu did not return for the next hero after immediate target commit")
		var state: Dictionary = hud.call("state_snapshot")
		var mira: Dictionary = (state.get("units", {}) as Dictionary).get("mira", {})
		var wisp: Dictionary = (state.get("units", {}) as Dictionary).get("wisp", {})
		if mira.get("cell") != Vector2i(3, 1):
			errors.append("choosing a valid target did not commit the staged hero movement")
		elif int((wisp.get("statuses", {}) as Dictionary).get("wet", 0)) <= 0:
			errors.append("choosing a valid target did not immediately commit the selected action")
		elif int(state.get("turn", 0)) < 3:
			errors.append("immediate target commit did not resolve deterministic enemy turns")
	if mode_picker != null:
		mode_picker.select(2)
		mode_picker.item_selected.emit(2)
		await process_frame
		# Keep this terrain assertion independent from authored deployment spacing:
		# place the active unit in range, then drive the same UI preview/commit path.
		var terrain_state := hud.call("state_snapshot") as Dictionary
		var terrain_units := terrain_state.get("units", {}) as Dictionary
		var terrain_orik := terrain_units.get("orik", {}) as Dictionary
		terrain_orik["cell"] = Vector2i(3, 2)
		terrain_units["orik"] = terrain_orik
		terrain_state["units"] = terrain_units
		_lock_hit_seed(terrain_state, "chill", "warden")
		hud.set("_state", terrain_state)
		hud.set("_pending_actor_id", "")
		hud.call("_refresh")
		await process_frame
		var chill := lab.find_child("CombatAction_chill", true, false) as Button
		if chill != null:
			chill.pressed.emit()
			await process_frame
			hud.call("_preview_target_at", world.call("screen_position_for_cell", Vector2i(5, 2)))
			await process_frame
			preview = lab.find_child("CombatPreview", true, false) as RichTextLabel
			var preview_field := hud.call("state_snapshot") as Dictionary
			var preview_d2 := (((preview_field.get("grid", {}) as Dictionary).get("cells", {}) as Dictionary).get("3:2", {})) as Dictionary
			if preview == null or not preview.text.contains("Frozen"):
				errors.append("E3 hover did not explain the linked Frozen change before click")
			if "frozen" in preview_d2.get("tags", []):
				errors.append("E3 hover preview mutated canonical field state")
			if int(world.call("projected_item_at", Vector2i(3, 2))) == Grid3D.ITEM_FROZEN:
				errors.append("E3 field projection leaked the hidden hit through a future cell change")
			world.emit_signal("cell_chosen", Vector2i(5, 2), "warden")
			await process_frame
		var after_field: Dictionary = hud.call("state_snapshot")
		var after_d2: Dictionary = (
			((after_field.get("grid", {}) as Dictionary).get("cells", {}) as Dictionary).get("3:2", {})
		)
		if (
			grid_map == null
			or grid_map.get_used_cells().size() != 63
			or int(world.call("projected_item_at", Vector2i(3, 2))) != Grid3D.ITEM_FROZEN
		):
			errors.append("E3 did not project the linked Frozen field after immediate target commit")
		if "frozen" not in after_d2.get("tags", []):
			errors.append("E3 target selection did not commit the Frozen field")
		if view_picker != null:
			view_picker.select(1)
			view_picker.item_selected.emit(1)
			await process_frame
			var diagnostic_grid := lab.find_child("CombatGridField", true, false) as GridContainer
			if world.visible or diagnostic_grid == null or diagnostic_grid.get_child_count() != 63:
				errors.append("2D diagnostic projection cannot replace and hide the standard 3D world")
		mode_picker.select(0)
		mode_picker.item_selected.emit(0)
		await process_frame
		await process_frame
		field = lab.find_child("CombatZoneField", true, false) as HBoxContainer
		if world.visible or field == null or field.get_child_count() != 4:
			errors.append("E1 four-area comparison cannot replace the standard 3D world")
		var zone_douse := lab.find_child("CombatAction_douse", true, false) as Button
		if zone_douse == null or zone_douse.disabled:
			errors.append("E1 action list cannot exercise the global staged command flow")
		else:
			zone_douse.grab_focus()
			await process_frame
			if str(hud.get("_browsed_command_id")) != "douse" or not str(hud.get("_selected_action")).is_empty():
				errors.append("E1 action-list focus arms a command instead of only previewing eligible targets")
			zone_douse.pressed.emit()
			await process_frame
			if str(hud.get("_selected_action")) != "douse" or not bool(hud.get("_radial_targeting")):
				errors.append("E1 action-list confirm did not enter target selection")
			var cancel_zone_targeting := InputEventAction.new()
			cancel_zone_targeting.action = "ui_cancel"
			cancel_zone_targeting.pressed = true
			hud.call("_unhandled_input", cancel_zone_targeting)
			await process_frame
			await process_frame
			var restored_zone_focus := root.gui_get_focus_owner()
			if (
				not str(hud.get("_selected_action")).is_empty()
				or restored_zone_focus == null
				or restored_zone_focus.name != "CombatAction_douse"
			):
				errors.append("E1 Cancel did not clear targeting and restore its source action row")
	if pause_overlay == null:
		errors.append("combat pause menu is absent")
	else:
		hud.call("_open_pause_menu")
		if not pause_overlay.visible or not paused:
			errors.append("opening the combat menu did not pause the scene tree")
		hud.call("_close_pause_menu")
		if pause_overlay.visible or paused:
			errors.append("closing the combat menu did not resume the battle")
	if console_input == null:
		errors.append("bottom-left combat console has no command input")
	else:
		hud.call("_submit_console_command", "units")
		hud.call("_submit_console_command", "victory")
		var result_overlay := lab.find_child("CombatResultOverlay", true, false) as ColorRect
		if result_overlay == null or not result_overlay.visible or Combat.outcome(hud.call("state_snapshot")) != "victory":
			errors.append("victory console command did not use the normal combat result state")
		hud.call("_submit_console_command", "reset")
		if Combat.outcome(hud.call("state_snapshot")) != "active":
			errors.append("reset console command did not restore the encounter snapshot")
	lab.free()
	if not errors.is_empty():
		printerr("FAIL combat lab")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat lab")
	print("  main scene is Node3D + scene-owned GridMap/Camera3D + CanvasLayer HUD")
	print("  CameraRig defaults to free horizontal orbit + locked pitch; orthogonal sides remain optional")
	print("  staged movement + target selection commit once through the shared enemy resolver")
	print("  distant hostile targets preview an exact stop cell and Defend fallback without mutation")
	print("  command focus previews range; confirm enters targeting; Cancel restores the source list")
	print("  root radial + adaptive Skills/Magic/Items drawer preserve hidden outcomes")
	print("  Esc/B step back through targeting and command menus before pause")
	print("  E3 projects elevation and Frozen changes; 2D remains a diagnostic view")
	quit(0)


func _lock_hit_seed(
	state: Dictionary,
	action_id: String,
	target_id: String,
	secondary_cell: Vector2i = Combat.INVALID_CELL,
) -> void:
	for seed in range(1, 1000):
		state["rngSeed"] = seed
		if bool(Combat.preview(state, action_id, target_id, secondary_cell).get("hit", false)):
			return
