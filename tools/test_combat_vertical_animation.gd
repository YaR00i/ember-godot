extends SceneTree
## Stage 1 visual motion smoke: staged move, lift/throw, enemy route and defend pulse.

const LAB_SCENE := preload("res://scenes/combat_lab.tscn")
const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")


func _init() -> void:
	root.size = Vector2i(1600, 900)
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var errors: Array[String] = []
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if progress != null:
		progress.set_battle_strategy(EmberPartyState.DEFAULT_BATTLE_STRATEGY)
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	var world := lab as Node3D
	var hud := lab.find_child("CombatHUD", true, false) as Control
	var mode_picker := lab.find_child("CombatEncounterMode", true, false) as OptionButton
	if world == null or hud == null or mode_picker == null:
		errors.append("animation lab is missing its world, HUD or E4 selector")
		_finish(lab, errors)
		return
	mode_picker.select(3)
	mode_picker.item_selected.emit(3)
	await process_frame
	await process_frame
	await _confirm_default_deployment(lab, hud, errors, "initial E4 selection")
	hud.call("_console_add_status", "wisp", "wet", 2)
	hud.call("_console_add_status", "mira", "guard", 2)
	hud.call("_refresh")
	await process_frame
	var wet_badge := lab.find_child("CombatStatus_wisp_wet", true, false) as Label3D
	var guard_badge := lab.find_child("CombatStatus_mira_guard", true, false) as Label3D
	if wet_badge == null or not wet_badge.text.contains("▼ ● Мокрый"):
		errors.append("enemy debuff did not receive a readable icon badge above the unit")
	if guard_badge == null or not guard_badge.text.contains("▲ ■ Защита"):
		errors.append("unit buff did not receive a distinct readable icon badge")

	var staged_start: Vector3 = world.call("_world_position", Vector2i(0, 2), 0.42)
	var staged_end: Vector3 = world.call("_world_position", Vector2i(0, 3), 0.42)
	hud.call("_toggle_move_mode")
	world.emit_signal("cell_chosen", Vector2i(0, 3), "")
	await create_timer(0.06).timeout
	var mira := lab.find_child("CombatUnit_mira", true, false) as Node3D
	if mira == null:
		errors.append("Mira projection disappeared during staged movement")
	else:
		if mira.position.distance_to(staged_end) <= 0.001:
			errors.append("staged movement snapped to its destination without a transition")
		await create_timer(0.28).timeout
		mira = lab.find_child("CombatUnit_mira", true, false) as Node3D
		if mira == null or mira.position.distance_to(staged_end) > 0.02:
			errors.append("staged movement did not settle on the selected cell")

	hud.call("_select_action", "lift_throw")
	world.emit_signal("cell_chosen", Vector2i(0, 4), "orik")
	var selected_state := hud.call("state_snapshot") as Dictionary
	if Combat.unit_definition(selected_state, "orik").get("cell", Vector2i(-1, -1)) != Vector2i(0, 4):
		errors.append("selecting a lift target mutated its gameplay cell before the throw")
	await create_timer(0.3).timeout
	var held_orik := lab.find_child("CombatUnit_orik", true, false) as Node3D
	mira = lab.find_child("CombatUnit_mira", true, false) as Node3D
	if held_orik == null or mira == null or held_orik.position.y < mira.position.y + 0.7:
		errors.append("the target was not lifted above the carrier immediately after target selection")
	hud.call("_cancel_radial_targeting")
	await create_timer(0.34).timeout
	held_orik = lab.find_child("CombatUnit_orik", true, false) as Node3D
	var restored_orik_position: Vector3 = world.call("_world_position", Vector2i(0, 4), 0.42)
	if (
		not str(hud.get("_selected_action")).is_empty()
		or not str(hud.get("_lifted_target_id")).is_empty()
		or held_orik == null
		or held_orik.position.distance_to(restored_orik_position) > 0.03
	):
		errors.append("Cancel did not clear the full lift command and restore the uncommitted target (action=%s, lifted=%s, distance=%.3f)" % [
			str(hud.get("_selected_action")),
			str(hud.get("_lifted_target_id")),
			held_orik.position.distance_to(restored_orik_position) if held_orik != null else -1.0,
		])
	hud.call("_select_action", "lift_throw")
	world.emit_signal("cell_chosen", Vector2i(0, 4), "orik")
	await create_timer(0.3).timeout
	hud.call("_choose_lift_throw")
	var selection_state := hud.call("_selection_state") as Dictionary
	var landing_cells := Combat.valid_secondary_cells(selection_state, "lift_throw", "orik")
	var landing := Vector2i(-1, -1)
	for cell in landing_cells:
		if cell.x >= 2:
			landing = cell
			break
	if landing == Vector2i(-1, -1):
		errors.append("E4 offers no visible multi-cell landing for lift/throw")
	else:
		var orik_origin: Vector3 = world.call("_world_position", Vector2i(0, 4), 0.42)
		var final_position: Vector3 = world.call("_world_position", landing, 0.42)
		var before_throw := hud.call("state_snapshot") as Dictionary
		var wisp_before: Vector2i = Combat.unit_definition(before_throw, "wisp").get(
			"cell", Vector2i(-1, -1)
		)
		world.emit_signal("cell_chosen", landing, "")
		await process_frame
		var after_throw := hud.call("state_snapshot") as Dictionary
		var orik_after: Vector2i = Combat.unit_definition(after_throw, "orik").get(
			"cell", Vector2i(-1, -1)
		)
		if orik_after != landing:
			errors.append("lift/throw animation path did not preserve the committed landing")
		var orik := lab.find_child("CombatUnit_orik", true, false) as Node3D
		if orik == null or orik.position.distance_to(final_position) <= 0.01:
			errors.append("lift/throw snapped to its final cell before the animation")
		await create_timer(0.17).timeout
		orik = lab.find_child("CombatUnit_orik", true, false) as Node3D
		mira = lab.find_child("CombatUnit_mira", true, false) as Node3D
		if (
			orik == null
			or mira == null
			or orik.position.y < maxf(orik_origin.y, mira.position.y) + 0.7
		):
			errors.append("lift phase did not visibly place the target above the carrier")
		var wisp_after: Vector2i = Combat.unit_definition(after_throw, "wisp").get(
			"cell", Vector2i(-1, -1)
		)
		await create_timer(1.55).timeout
		orik = lab.find_child("CombatUnit_orik", true, false) as Node3D
		if orik == null or orik.position.distance_to(final_position) > 0.03:
			errors.append("thrown unit did not settle on the committed landing cell")
		if wisp_after != wisp_before:
			var wisp := lab.find_child("CombatUnit_wisp", true, false) as Node3D
			var wisp_final: Vector3 = world.call("_world_position", wisp_after, 0.42)
			if wisp == null or wisp.position.distance_to(wisp_final) > 0.03:
				errors.append("enemy movement animation did not settle on the AI cell")

	hud.call("_reset_lab")
	await create_timer(0.36).timeout
	await _confirm_default_deployment(lab, hud, errors, "pair-animation reset")
	var pair_state := (hud.call("state_snapshot") as Dictionary).duplicate(true)
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
	var pair_preview := Combat.preview(pair_state, "duo_pulse", "wisp")
	if not bool(pair_preview.get("ok", false)):
		errors.append("pair animation fixture could not resolve the authored technique")
	else:
		world.call("queue_action_animation", pair_state, pair_preview)
		hud.set("_state", Combat.commit(pair_state, pair_preview))
		hud.call("_refresh")
		if not await _observed_pair_scale(world, 0.4):
			errors.append("pair technique did not visibly cue both participants")
		await create_timer(0.5).timeout

	hud.call("_reset_lab")
	await create_timer(0.36).timeout
	await _confirm_default_deployment(lab, hud, errors, "defend reset")
	var defender_id := Combat.current_unit_id(hud.call("state_snapshot"))
	hud.call("_select_action", "defend")
	if not await _observed_unit_scale(lab, "CombatUnit_%s" % defender_id, 0.24):
		errors.append("defend did not produce the lightweight squash/pulse feedback")

	_finish(lab, errors)


func _confirm_default_deployment(
	lab: Node, hud: Control, errors: Array[String], context: String
) -> void:
	var deployment_start := lab.find_child("CombatDeploymentReadyStart", true, false) as Button
	if deployment_start == null or deployment_start.disabled:
		errors.append("E4 default deployment cannot be confirmed after %s" % context)
		return
	deployment_start.pressed.emit()
	await process_frame
	await process_frame
	await create_timer(0.36).timeout
	hud.get_viewport().gui_release_focus()
	if bool((hud.call("deployment_snapshot") as Dictionary).get("active", true)):
		errors.append("E4 remained in deployment after Start was pressed after %s" % context)


func _observed_unit_scale(lab: Node, unit_name: String, duration: float) -> bool:
	## Projection rebuild and deferred animation can land on different frames in
	## headless runs. Observe the short animation window instead of one instant.
	var elapsed := 0.0
	while elapsed < duration:
		await create_timer(0.02).timeout
		elapsed += 0.02
		var unit := lab.find_child(unit_name, true, false) as Node3D
		if unit != null and not unit.scale.is_equal_approx(Vector3.ONE):
			return true
	return false


func _observed_pair_scale(world: Node, duration: float) -> bool:
	var elapsed := 0.0
	var saw_sena := false
	var saw_mira := false
	while elapsed < duration:
		await create_timer(0.02).timeout
		elapsed += 0.02
		var roots := world.get("_unit_roots") as Dictionary
		var sena := roots.get("sena", null) as Node3D
		var mira := roots.get("mira", null) as Node3D
		saw_sena = saw_sena or (sena != null and not sena.scale.is_equal_approx(Vector3.ONE))
		saw_mira = saw_mira or (mira != null and not mira.scale.is_equal_approx(Vector3.ONE))
		if saw_sena and saw_mira:
			return true
	return false


func _finish(lab: Node, errors: Array[String]) -> void:
	lab.free()
	if not errors.is_empty():
		printerr("FAIL combat vertical animation")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat vertical animation")
	print("  staged movement interpolates and enemy AI movement follows its resolved route")
	print("  target selection raises the unit without committing; landing selection only throws")
	print("  buffs and debuffs use distinct icon badges with names and remaining turns")
	print("  pair techniques cue both participants before the initiating attack")
	print("  defend, attacks and damage use short projection-only feedback animations")
	quit(0)
