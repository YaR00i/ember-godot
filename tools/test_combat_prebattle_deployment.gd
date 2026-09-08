extends SceneTree
## Narrow gate for process-local pre-battle party deployment.

const LAB_SCENE := preload("res://scenes/combat_lab.tscn")
const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid := preload("res://scripts/prototypes/ember_combat_grid.gd")
const E2_FIELD := preload("res://content/combat/battlefields/colored_crossing.tres")
const E4_FIELD := preload("res://content/combat/battlefields/vertical_forge_10x8.tres")


func _init() -> void:
	root.size = Vector2i(1600, 900)
	_run.call_deferred()


func _run() -> void:
	var errors: Array[String] = []
	_test_pure_deployment(errors)
	await _test_lab_lifecycle(errors)
	if not errors.is_empty():
		printerr("FAIL combat prebattle deployment")
		for message in errors:
			printerr(" - ", message)
		quit(1)
		return
	print("PASS combat prebattle deployment")
	print("  exact-N authored cells ignore strategy; extra cells open strategy-ready setup")
	print("  ready has two actions; edit keeps move/swap/reset pure in CombatGrid")
	print("  mouse/grid cursor and 3D first-hero projection block combat until confirmation")
	print("  defeat Retry keeps confirmed cells with a new seed and does not reopen setup")
	print("  ordinary Lab Reset restores persisted strategy and reopens ready")
	quit(0)


func _test_pure_deployment(errors: Array[String]) -> void:
	var exact_state := Grid.initial_state(E2_FIELD, 41)
	var exact_allowed: Array[Vector2i] = []
	exact_allowed.assign(E2_FIELD.party_deployment_cells)
	if Grid.deployment_enabled(exact_state, exact_allowed):
		errors.append("exact-N colored crossing unexpectedly enables deployment")
	var exact_defaults := Grid.deployment_default_placement(exact_state, exact_allowed)
	_assert_first_n_defaults(exact_state, exact_allowed, exact_defaults, errors)

	var state := Grid.initial_state(E4_FIELD, 43)
	var allowed: Array[Vector2i] = []
	allowed.assign(E4_FIELD.party_deployment_cells)
	var heroes := Grid.deployment_hero_ids(state)
	var defaults := Grid.deployment_default_placement(state, allowed)
	if not Grid.deployment_enabled(state, allowed):
		errors.append("extra E4 party cells did not enable deployment")
	if heroes.size() != 4 or allowed.size() <= heroes.size():
		errors.append("E4 fixture does not expose four heroes plus a wider authored zone")
	_assert_first_n_defaults(state, allowed, defaults, errors)
	if not Grid.deployment_validation_errors(state, allowed, defaults).is_empty():
		errors.append("authored first-N E4 defaults are not a valid placement")
	if heroes.is_empty():
		return
	var moved := Grid.deployment_move(state, allowed, defaults, heroes[0], Vector2i(1, 2))
	if not bool(moved.get("ok", false)) or (moved.get("placement", {}) as Dictionary).get(heroes[0]) != Vector2i(1, 2):
		errors.append("pure deployment move rejected a free authored cell")
	var swapped := Grid.deployment_move(state, allowed, defaults, heroes[0], defaults[heroes[1]])
	var swapped_placement := swapped.get("placement", {}) as Dictionary
	if (
		not bool(swapped.get("ok", false))
		or str(swapped.get("swappedHeroId", "")) != heroes[1]
		or swapped_placement.get(heroes[0]) != defaults[heroes[1]]
		or swapped_placement.get(heroes[1]) != defaults[heroes[0]]
	):
		errors.append("occupied hero cell did not produce a pure two-hero swap")

	_assert_rejected(state, allowed, defaults, heroes[0], Vector2i(3, 0), "outside authored zone", errors)
	var permissive := allowed.duplicate()
	permissive.append(Vector2i(-1, 0))
	_assert_rejected(state, permissive, defaults, heroes[0], Vector2i(-1, 0), "outside battlefield", errors)
	permissive = allowed.duplicate()
	permissive.append(Vector2i(4, 2))
	_assert_rejected(state, permissive, defaults, heroes[0], Vector2i(4, 2), "blocked cell", errors)
	permissive = allowed.duplicate()
	permissive.append(E4_FIELD.focus_cell)
	_assert_rejected(state, permissive, defaults, heroes[0], E4_FIELD.focus_cell, "focus cell", errors)
	var enemy_cell: Vector2i = E4_FIELD.enemy_deployment_cells[0]
	permissive = allowed.duplicate()
	permissive.append(enemy_cell)
	_assert_rejected(state, permissive, defaults, heroes[0], enemy_cell, "enemy cell", errors)
	var duplicate := defaults.duplicate(true)
	duplicate[heroes[1]] = duplicate[heroes[0]]
	if Grid.deployment_validation_errors(state, allowed, duplicate).is_empty():
		errors.append("duplicate hero placement passed validation")


func _test_lab_lifecycle(errors: Array[String]) -> void:
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	var previous_strategy := progress.combat_strategy_snapshot() if progress != null else []
	var saved_strategy: Array[String] = ["mira", "protagonist", "orik", "sena"]
	if progress != null:
		progress.set_battle_strategy(saved_strategy)
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	var hud := lab.find_child("CombatHUD", true, false)
	var world := lab as Node3D
	if hud == null or world == null:
		errors.append("Combat Lab fixture is missing its HUD or 3D world")
		lab.queue_free()
		return
	var initial_setup := hud.call("deployment_snapshot") as Dictionary
	if bool(initial_setup.get("active", true)):
		errors.append("default exact-N E2 Lab did not auto-skip deployment")
	var exact_state := hud.call("state_snapshot") as Dictionary
	var exact_allowed: Array[Vector2i] = []
	exact_allowed.assign(E2_FIELD.party_deployment_cells)
	if (initial_setup.get("placement", {}) as Dictionary) != Grid.deployment_default_placement(exact_state, exact_allowed):
		errors.append("exact-N E2 did not ignore the persisted strategy")
	if lab.find_child("CombatDeploymentPanel", true, false) == null:
		errors.append("functional deployment panel is missing")

	hud.call("_select_encounter_mode", 3)
	await process_frame
	await process_frame
	var setup := hud.call("deployment_snapshot") as Dictionary
	var heroes := Grid.deployment_hero_ids(hud.call("state_snapshot"))
	if not heroes.is_empty() and heroes[0] != Combat.current_unit_id(hud.call("state_snapshot")):
		errors.append("3D regression fixture no longer moves the first/current combat hero")
	var defaults := Grid.deployment_default_placement(
		hud.call("state_snapshot"), setup.get("allowedCells", [])
	)
	var panel := lab.find_child("CombatDeploymentPanel", true, false) as Control
	var ready_panel := lab.find_child("CombatDeploymentReadyPanel", true, false) as Control
	var timeline := lab.find_child("CombatTimelinePanel", true, false) as Control
	var command := lab.find_child("CombatCommandPanel", true, false) as Control
	var radial := lab.find_child("CombatRadialMenu", true, false) as Control
	var start := lab.find_child("CombatDeploymentStart", true, false) as Button
	var ready_start := lab.find_child("CombatDeploymentReadyStart", true, false) as Button
	var ready_edit := lab.find_child("CombatDeploymentReadyEdit", true, false) as Button
	if (
		not bool(setup.get("active", false))
		or not bool(setup.get("ready", false))
		or bool(setup.get("editing", true))
		or ready_panel == null
		or not ready_panel.visible
		or panel == null
		or panel.visible
	):
		errors.append("E4 extra cells did not open the compact ready phase")
	if (
		ready_panel == null
		or ready_panel.find_children("*", "Button", true, false).size() != 2
		or ready_start == null
		or ready_edit == null
	):
		errors.append("ready window does not expose exactly Start and Edit strategy")
	var expected_strategy := Grid.deployment_strategy_placement(
		hud.call("state_snapshot"), setup.get("allowedCells", []), saved_strategy
	)
	if (setup.get("placement", {}) as Dictionary) != expected_strategy:
		errors.append("direct Combat Lab did not apply persisted strategy before ready UI")
	if timeline == null or timeline.visible or command == null or command.visible or radial == null or radial.visible:
		errors.append("timeline or combat commands remain visible during ready")
	if start == null or ready_start == null or ready_start.disabled:
		errors.append("valid strategy does not enable ready Start battle")
	if bool(world.get("_deployment_active")) or lab.find_children("CombatDeployment_*", "Node3D", true, false).size() != 0:
		errors.append("ready mode obscures the field with detailed deployment markers")
	for hero_id in heroes:
		if lab.find_child("CombatUnit_%s" % hero_id, true, false) == null:
			errors.append("ready field does not visibly project ally %s" % hero_id)
	var ready_state_before := hud.call("state_snapshot") as Dictionary
	var ready_seed_before := int(ready_state_before.get("rngSeed", 0))
	hud.call("_select_action", "strike")
	hud.call("_confirm_action")
	hud.call("_advance_enemy_turns")
	if hud.call("state_snapshot") != ready_state_before or int((hud.call("state_snapshot") as Dictionary).get("rngSeed", 0)) != ready_seed_before:
		errors.append("ready phase allowed combat or RNG advancement")
	if not bool(hud.call("_confirm_deployment")):
		errors.append("ready Start battle did not confirm the applied strategy")
	elif (hud.call("deployment_snapshot") as Dictionary).get("confirmedPlacement", {}) != expected_strategy:
		errors.append("ready Start battle did not preserve the applied strategy")
	await create_timer(0.45).timeout
	var ready_confirmed_state := hud.call("state_snapshot") as Dictionary
	var ready_actor_id := Combat.current_unit_id(ready_confirmed_state)
	var ready_actor_cell: Vector2i = Combat.unit_definition(ready_confirmed_state, ready_actor_id).get("cell", Combat.INVALID_CELL)
	var ready_actor_root := lab.find_child("CombatUnit_%s" % ready_actor_id, true, false) as Node3D
	var ready_expected_position: Vector3 = world.call("_world_position", ready_actor_cell, 0.42)
	if (
		hud.get("_pending_actor_id") != ready_actor_id
		or hud.get("_pending_cell") != ready_actor_cell
		or bool(hud.get("_manual_move_selected"))
		or ready_actor_root == null
		or not ready_actor_root.position.is_equal_approx(ready_expected_position)
	):
		errors.append("ready Start left a staged path instead of anchoring the confirmed strategy")
	hud.call("_reset_lab")
	await process_frame
	setup = hud.call("deployment_snapshot")

	ready_edit.pressed.emit()
	await process_frame
	setup = hud.call("deployment_snapshot")
	if not bool(setup.get("editing", false)) or panel == null or not panel.visible or ready_panel.visible:
		errors.append("Edit strategy did not enter detailed deployment")
	if heroes.size() != 4 or lab.find_children("CombatDeploymentHero_*", "Button", true, false).size() != 4:
		errors.append("detailed deployment panel does not expose four hero controls")
	if start == null or start.disabled:
		errors.append("valid strategy does not enable detailed Start battle")
	elif heroes.size() > 1:
		var duplicate_ui := (setup.get("placement", {}) as Dictionary).duplicate(true)
		duplicate_ui[heroes[1]] = duplicate_ui[heroes[0]]
		hud.set("_deployment_placement", duplicate_ui)
		hud.call("_refresh")
		if not start.disabled:
			errors.append("Start battle remains enabled for duplicate placement")
		hud.call("_reset_deployment")
	if not bool(world.get("_deployment_active")) or lab.find_children("CombatDeployment_*", "Node3D", true, false).size() < E4_FIELD.party_deployment_cells.size():
		errors.append("3D world does not show the full phase-specific cyan zone")

	var before_block := hud.call("state_snapshot") as Dictionary
	var before_seed := int(before_block.get("rngSeed", 0))
	var before_timeline := Combat.timeline(before_block, 8)
	hud.call("_select_action", "strike")
	hud.call("_confirm_action")
	hud.call("_advance_enemy_turns")
	var after_block := hud.call("state_snapshot") as Dictionary
	if after_block != before_block or int(after_block.get("rngSeed", 0)) != before_seed or Combat.timeline(after_block, 8) != before_timeline:
		errors.append("combat input, timeline or RNG changed before deployment confirmation")

	if heroes.is_empty():
		lab.queue_free()
		return
	# Mouse-facing controller path: click a hero on the field, then a legal cell.
	hud.call("_on_grid_cell_chosen", defaults[heroes[0]], heroes[0])
	if str((hud.call("deployment_snapshot") as Dictionary).get("selectedHeroId", "")) != heroes[0]:
		errors.append("field hero click did not enter placement selection")
	hud.call("_on_grid_cell_chosen", Vector2i(1, 2), "")
	await process_frame
	await create_timer(0.45).timeout
	setup = hud.call("deployment_snapshot")
	if (setup.get("placement", {}) as Dictionary).get(heroes[0]) != Vector2i(1, 2):
		errors.append("field cell click did not move the selected hero")
	var first_root := lab.find_child("CombatUnit_%s" % heroes[0], true, false) as Node3D
	var expected_position: Vector3 = world.call("_world_position", Vector2i(1, 2), 0.42)
	if first_root == null or not first_root.position.is_equal_approx(expected_position):
		errors.append("first/current hero still projects at its stale staged combat cell in 3D")
	if int((hud.call("state_snapshot") as Dictionary).get("rngSeed", 0)) != before_seed:
		errors.append("deployment movement consumed RNG")

	# Controller path: a card arms the existing grid cursor; arrows + Accept place.
	hud.call("_reset_deployment")
	hud.call("_select_deployment_hero", heroes[0])
	var projection_generation := int(world.get("_animation_generation"))
	var right := InputEventAction.new()
	right.action = "ui_right"
	right.pressed = true
	hud.call("_unhandled_input", right)
	if hud.get("_hover_cell") != Vector2i(1, 2):
		errors.append("deployment did not reuse the grid cursor for ui_right")
	var cursor_snapshot := world.call("deployment_cursor_snapshot") as Dictionary
	if (
		cursor_snapshot.get("cell", Combat.INVALID_CELL) != Vector2i(1, 2)
		or not bool(cursor_snapshot.get("visible", false))
		or lab.find_child("CombatDeploymentCursor", true, false) == null
	):
		errors.append("ui_right did not update the public 3D deployment cursor marker")
	if int(world.get("_animation_generation")) != projection_generation:
		errors.append("deployment cursor rebuilt the full 3D field")
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	hud.call("_unhandled_input", accept)
	if ((hud.call("deployment_snapshot") as Dictionary).get("placement", {}) as Dictionary).get(heroes[0]) != Vector2i(1, 2):
		errors.append("ui_accept did not place the selected hero")
	hud.call("_on_grid_cell_hovered", Vector2i(2, 2))
	cursor_snapshot = world.call("deployment_cursor_snapshot")
	if cursor_snapshot.get("cell", Combat.INVALID_CELL) != Vector2i(2, 2) or not bool(cursor_snapshot.get("visible", false)):
		errors.append("mouse-facing hover did not move the public 3D deployment cursor")
	hud.call("_select_field_view_mode", 1)
	await process_frame
	var diagnostic := lab.find_child("CombatGridField", true, false) as Control
	hud.call("_on_grid_cell_hovered", Vector2i(2, 3))
	var diagnostic_cell := lab.find_child("CombatCell_2_3", true, false) as Button
	if (
		diagnostic == null
		or diagnostic.call("deployment_cursor_cell") != Vector2i(2, 3)
		or diagnostic_cell == null
		or "КУРСОР" not in diagnostic_cell.text
	):
		errors.append("2D diagnostic does not distinguish the current deployment cursor cell")
	hud.call("_select_field_view_mode", 0)
	await process_frame
	hud.call("_select_deployment_hero", heroes[1])
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	hud.call("_unhandled_input", cancel)
	await process_frame
	var pause := lab.find_child("CombatPauseOverlay", true, false) as Control
	cursor_snapshot = world.call("deployment_cursor_snapshot")
	if (
		bool((hud.call("deployment_snapshot") as Dictionary).get("selectingCell", true))
		or (pause != null and pause.visible)
		or bool(cursor_snapshot.get("visible", true))
	):
		errors.append("ui_cancel did not return from the grid to the hero panel without pause")

	hud.call("_reset_deployment")
	if (hud.call("deployment_snapshot") as Dictionary).get("placement", {}) != expected_strategy:
		errors.append("deployment Reset did not restore the persisted strategy")
	hud.call("_select_deployment_hero", heroes[0])
	hud.call("_place_selected_hero", Vector2i(1, 2))
	var confirmed: Dictionary = ((hud.call("deployment_snapshot") as Dictionary).get(
		"placement", {}
	) as Dictionary).duplicate(true)
	if not bool(hud.call("_confirm_deployment")):
		errors.append("valid complete placement could not be confirmed")
	await process_frame
	await create_timer(0.45).timeout
	setup = hud.call("deployment_snapshot")
	if bool(setup.get("active", true)) or panel.visible or not timeline.visible or not command.visible or not radial.visible:
		errors.append("confirmation did not replace setup UI with normal combat UI")
	if bool(world.get("_deployment_active")) or lab.find_children("CombatDeployment_*", "Node3D", true, false).size() != 0:
		errors.append("deployment markers leaked into active combat")
	var confirmed_state := hud.call("state_snapshot") as Dictionary
	var confirmed_actor_id := Combat.current_unit_id(confirmed_state)
	var confirmed_actor_cell: Vector2i = Combat.unit_definition(confirmed_state, confirmed_actor_id).get("cell", Combat.INVALID_CELL)
	var confirmed_actor_root := lab.find_child("CombatUnit_%s" % confirmed_actor_id, true, false) as Node3D
	var confirmed_expected_position: Vector3 = world.call("_world_position", confirmed_actor_cell, 0.42)
	if (
		confirmed_actor_cell != confirmed.get(confirmed_actor_id, Combat.INVALID_CELL)
		or hud.get("_pending_actor_id") != confirmed_actor_id
		or hud.get("_pending_cell") != confirmed_actor_cell
		or bool(hud.get("_manual_move_selected"))
		or confirmed_actor_root == null
		or not confirmed_actor_root.position.is_equal_approx(confirmed_expected_position)
	):
		errors.append("edit Start projected a staged path back to the saved strategy cell")
	if confirmed_state.has("deployment") or confirmed_state.has("confirmedPlacement") or EmberExploreState.SAVE_VERSION != 2:
		errors.append("process-local deployment leaked into combat/save schema")

	var defeated := confirmed_state.duplicate(true)
	var defeated_units := defeated.get("units", {}) as Dictionary
	for hero_id in heroes:
		var unit := defeated_units.get(hero_id, {}) as Dictionary
		unit["hp"] = 0
		defeated_units[hero_id] = unit
	defeated["units"] = defeated_units
	hud.set("_state", defeated)
	hud.call("_refresh")
	var defeated_seed := int(defeated.get("rngSeed", 0))
	hud.call("_retry_encounter")
	await process_frame
	var retried := hud.call("state_snapshot") as Dictionary
	setup = hud.call("deployment_snapshot")
	if bool(setup.get("active", true)) or int(retried.get("rngSeed", 0)) == defeated_seed:
		errors.append("defeat Retry reopened setup or reused its RNG seed")
	for hero_id in heroes:
		if Combat.unit_definition(retried, hero_id).get("cell", Combat.INVALID_CELL) != confirmed.get(hero_id, Combat.INVALID_CELL):
			errors.append("defeat Retry lost confirmed placement for %s" % hero_id)

	hud.call("_reset_lab")
	await process_frame
	setup = hud.call("deployment_snapshot")
	var reset_state := hud.call("state_snapshot") as Dictionary
	if (
		not bool(setup.get("active", false))
		or not bool(setup.get("ready", false))
		or (setup.get("placement", {}) as Dictionary) != Grid.deployment_strategy_placement(reset_state, setup.get("allowedCells", []), saved_strategy)
	):
		errors.append("ordinary active-battle Lab Reset did not reopen persisted-strategy ready")
	if progress != null:
		progress.set_battle_strategy(previous_strategy)
	lab.queue_free()
	await process_frame


func _assert_first_n_defaults(
	state: Dictionary,
	allowed: Array[Vector2i],
	placement: Dictionary,
	errors: Array[String],
) -> void:
	var heroes := Grid.deployment_hero_ids(state)
	for index in heroes.size():
		if placement.get(heroes[index], Combat.INVALID_CELL) != allowed[index]:
			errors.append("default placement does not use authored cell %d" % index)


func _assert_rejected(
	state: Dictionary,
	allowed: Array[Vector2i],
	placement: Dictionary,
	hero_id: String,
	cell: Vector2i,
	label: String,
	errors: Array[String],
) -> void:
	if bool(Grid.deployment_move(state, allowed, placement, hero_id, cell).get("ok", false)):
		errors.append("deployment accepted %s" % label)
