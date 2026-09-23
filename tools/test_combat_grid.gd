extends SceneTree
## E2 grid gate: staged movement and colored-panel rules reuse D1 resolver.

const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Terrain = preload("res://scripts/prototypes/ember_combat_terrain.gd")


func _init() -> void:
	var errors: Array[String] = []
	_test_reachability(errors)
	_test_staged_command(errors)
	_test_auto_approach(errors)
	_test_non_hostile_approach(errors)
	_test_held_target_lifecycle(errors)
	_test_held_ai(errors)
	_test_grid_conduction(errors)
	_test_focus_and_push(errors)
	_test_height_rules(errors)
	_test_field_mutation(errors)
	if not errors.is_empty():
		printerr("FAIL combat grid")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat grid")
	print("  7x5 movement respects range, blockers and occupied cells")
	print("  move + action stays a pure staged preview until one commit")
	print("  hostile melee/ranged commands approach, or stop and defend when MOVE is insufficient")
	print("  support, item, cell and lift commands reuse the same approach planner")
	print("  held targets leave the grid and release through synthetic carrier commands")
	print("  AI carriers use the same synthetic legality without moving")
	print("  connected wet panels conduct; focus-linked ember panels boost fire")
	print("  grid forced movement resolves through the shared combat result")
	print("  elevation and linked Frozen/Wet cellChanges share preview and commit")
	quit(0)


func _test_reachability(errors: Array[String]) -> void:
	var state := Grid.initial_state()
	var reachable := Grid.reachable_cells(state, "mira")
	if Vector2i(1, 2) not in reachable or Vector2i(4, 2) not in reachable:
		errors.append("three-cell movement did not include origin and reachable wet panel")
	if Vector2i(5, 2) in reachable or Vector2i(3, 0) in reachable:
		errors.append("movement crossed its range or a blocked cell")
	if Vector2i(0, 1) in reachable:
		errors.append("movement allowed entering an occupied hero cell")


func _test_staged_command(errors: Array[String]) -> void:
	var state := Grid.initial_state()
	var original := state.duplicate(true)
	var destination := Vector2i(4, 2)
	var staged := Grid.stage_move(state, destination)
	if state != original:
		errors.append("staged grid movement mutated the source snapshot")
	if Combat.unit_definition(staged, "mira").get("cell") != destination:
		errors.append("staged snapshot did not move the active hero")
	if "wisp" not in Combat.valid_target_ids(staged, "douse"):
		errors.append("movement did not make the ranged water target available")
	var preview := Grid.command_preview(state, "douse", "wisp", destination)
	if not preview.get("ok", false) or (preview.get("moves", {}) as Dictionary).get("mira") != destination:
		errors.append("compound move + action preview lost staged movement")
	var committed := Combat.commit(state, preview)
	if Combat.unit_definition(committed, "mira").get("cell") != destination:
		errors.append("shared commit did not apply previewed grid movement")
	if int((Combat.unit_definition(committed, "wisp").get("statuses", {}) as Dictionary).get("wet", 0)) != 2:
		errors.append("compound grid command did not apply its elemental action")


func _test_auto_approach(errors: Array[String]) -> void:
	var state := Grid.initial_state()
	_keep_alive(state, PackedStringArray(["mira", "wisp"]))
	_set_cell(state, "mira", Vector2i(0, 2))
	_set_cell(state, "wisp", Vector2i(4, 2))
	_set_unit_value(state, "mira", "moveRange", 3)
	_force_turn(state, "mira")
	var original := state.duplicate(true)
	var melee_plan := Grid.approach_plan(state, "strike", "wisp")
	if (
		not bool(melee_plan.get("willExecute", false))
		or melee_plan.get("destination", Combat.INVALID_CELL) != Vector2i(3, 2)
	):
		errors.append("melee approach did not choose the nearest legal attack cell")
	var melee := Grid.approach_command_preview(state, "strike", "wisp")
	if (
		not bool(melee.get("ok", false))
		or str(melee.get("actionId", "")) != "strike"
		or (melee.get("moves", {}) as Dictionary).get("mira") != Vector2i(3, 2)
		or bool(melee.get("approachFallbackDefend", true))
	):
		errors.append("reachable melee target did not produce one move + strike preview")
	if state != original:
		errors.append("approach preview mutated its source snapshot")

	_set_cell(state, "wisp", Vector2i(6, 2))
	_set_unit_value(state, "mira", "moveRange", 3)
	var ranged := Grid.approach_command_preview(state, "douse", "wisp")
	if (
		not bool(ranged.get("ok", false))
		or str(ranged.get("actionId", "")) != "douse"
		or ranged.get("approachDestination", Combat.INVALID_CELL) != Vector2i(3, 2)
		or not bool(ranged.get("approachWillExecute", false))
	):
		errors.append("ranged action did not reuse movement + range + LOS approach rules")

	_set_unit_value(state, "mira", "moveRange", 2)
	var far_targets := Grid.approach_target_ids(state, "strike")
	if "wisp" not in far_targets:
		errors.append("path-connected target beyond this turn is not selectable for approach")
	var fallback := Grid.approach_command_preview(state, "strike", "wisp")
	if (
		not bool(fallback.get("ok", false))
		or str(fallback.get("actionId", "")) != "defend"
		or str(fallback.get("requestedActionId", "")) != "strike"
		or not bool(fallback.get("approachFallbackDefend", false))
		or fallback.get("approachDestination", Combat.INVALID_CELL) != Vector2i(2, 2)
		or not (fallback.get("damage", {}) as Dictionary).is_empty()
		or int(fallback.get("mpCost", -1)) != 0
	):
		errors.append("insufficient MOVE did not stop at the route frontier and substitute Defend")
	var committed := Combat.commit(state, fallback)
	if (
		Combat.unit_definition(committed, "mira").get("cell", Combat.INVALID_CELL) != Vector2i(2, 2)
		or int((Combat.unit_definition(committed, "mira").get("statuses", {}) as Dictionary).get("guard", 0)) != 1
		or int(Combat.unit_definition(committed, "wisp").get("hp", 0))
		!= int(Combat.unit_definition(state, "wisp").get("hp", 0))
	):
		errors.append("approach fallback commit did not move once and apply canonical guard")

	_set_unit_value(state, "mira", "mp", 0)
	if "wisp" in Grid.approach_target_ids(state, "douse"):
		errors.append("auto approach hid a non-positional MP requirement")


func _test_non_hostile_approach(errors: Array[String]) -> void:
	var state := Grid.initial_state()
	_keep_alive(state, PackedStringArray(["mira", "orik", "raider"]))
	_set_cell(state, "mira", Vector2i(0, 2))
	_set_cell(state, "orik", Vector2i(6, 2))
	_set_cell(state, "raider", Vector2i(5, 2))
	_set_unit_value(state, "orik", "hp", 1)
	_set_unit_value(state, "mira", "moveRange", 2)
	_force_turn(state, "mira")
	var heal_fallback := Grid.approach_command_preview(state, "mira_mend", "orik")
	if (
		not bool(heal_fallback.get("approachFallbackDefend", false))
		or int(heal_fallback.get("mpCost", -1)) != 0
		or not (heal_fallback.get("restoreHp", {}) as Dictionary).is_empty()
	):
		errors.append("out-of-MOVE healing did not stop and defend without spending the action")
	_set_unit_value(state, "mira", "moveRange", 4)
	var heal := Grid.approach_command_preview(state, "mira_mend", "orik")
	if not bool(heal.get("ok", false)) or bool(heal.get("approachFallbackDefend", true)):
		errors.append("reachable healing did not approach and execute")
	_set_unit_value(state, "mira", "hp", 1)
	var self_heal := Grid.approach_command_preview(state, "mira_mend", "mira")
	if (
		not bool(self_heal.get("ok", false))
		or bool(self_heal.get("approachFallbackDefend", true))
		or self_heal.get("approachDestination", Combat.INVALID_CELL) != Vector2i(0, 2)
	):
		errors.append("self healing moved away from the actor or fell back to Defend")

	var item_state := Combat.with_inventory(state, {"test_tonic": 1}, {
		"test_tonic": {
			"id": "test_tonic", "nameRu": "Тоник", "kind": "consumable",
			"useIn": "arena", "hpRestore": 5, "combatRange": 1, "combatDelay": 100,
		},
	})
	_set_unit_value(item_state, "mira", "moveRange", 1)
	var item_fallback := Grid.approach_command_preview(item_state, "item:test_tonic", "orik")
	if (
		not bool(item_fallback.get("approachFallbackDefend", false))
		or not (item_fallback.get("inventoryCost", {}) as Dictionary).is_empty()
	):
		errors.append("out-of-MOVE item command consumed or retained an inventory cost")
	var self_item := Grid.approach_command_preview(item_state, "item:test_tonic", "mira")
	if (
		not bool(self_item.get("ok", false))
		or bool(self_item.get("approachFallbackDefend", true))
		or self_item.get("approachDestination", Combat.INVALID_CELL) != Vector2i(0, 2)
	):
		errors.append("self item use moved away from the actor or fell back to Defend")

	var guard_state := Grid.initial_state()
	_keep_alive(guard_state, PackedStringArray(["orik", "mira", "wisp"]))
	_set_cell(guard_state, "orik", Vector2i(2, 2))
	_force_turn(guard_state, "orik")
	var self_guard := Grid.approach_command_preview(guard_state, "guard", "orik")
	if (
		not bool(self_guard.get("ok", false))
		or bool(self_guard.get("approachFallbackDefend", true))
		or self_guard.get("approachDestination", Combat.INVALID_CELL) != Vector2i(2, 2)
	):
		errors.append("self guard moved away from the actor or fell back to Defend")

	var cell_state := Grid.initial_state()
	_keep_alive(cell_state, PackedStringArray(["orik", "wisp"]))
	_set_cell(cell_state, "orik", Vector2i(0, 2))
	_set_unit_value(cell_state, "orik", "moveRange", 1)
	_force_turn(cell_state, "orik")
	var edge_cell := Vector2i(4, 2)
	var far_cell := Vector2i(6, 4)
	var cell_targets := Grid.approach_target_cells(cell_state, "ice_wall")
	if edge_cell not in cell_targets:
		errors.append("cell command did not include the MOVE + authored range frontier")
	if edge_cell not in Grid.approach_target_cells(cell_state, "ice_wall", Vector2i(0, 2)):
		errors.append("current actor cell was mistaken for a locked manual destination")
	if far_cell in cell_targets:
		errors.append("cell command exposed a remote cell beyond MOVE + authored range")
	var edge_preview := Grid.approach_cell_command_preview(cell_state, "ice_wall", edge_cell)
	if (
		not bool(edge_preview.get("ok", false))
		or bool(edge_preview.get("approachFallbackDefend", true))
		or edge_preview.get("approachDestination", Combat.INVALID_CELL) != Vector2i(1, 2)
	):
		errors.append("cell command frontier did not preview its exact one-cell approach")
	if bool(Grid.approach_cell_command_preview(cell_state, "ice_wall", far_cell).get("ok", false)):
		errors.append("remote cell command produced a misleading fallback preview")

	var lift_state := Grid.initial_state()
	_keep_alive(lift_state, PackedStringArray(["mira", "wisp"]))
	_set_cell(lift_state, "mira", Vector2i(0, 2))
	_set_cell(lift_state, "wisp", Vector2i(4, 2))
	_set_unit_value(lift_state, "mira", "moveRange", 1)
	_force_turn(lift_state, "mira")
	var lift_fallback := Grid.approach_command_preview(lift_state, "lift_throw", "wisp")
	if (
		not bool(lift_fallback.get("approachFallbackDefend", false))
		or lift_fallback.get("approachDestination", Combat.INVALID_CELL) != Vector2i(1, 2)
		or lift_fallback.get("approachPath", []).size() != 2
	):
		errors.append("lift did not expose its exact stop-and-defend approach route")
	_set_unit_value(lift_state, "mira", "moveRange", 3)
	var lift_plan := Grid.approach_plan(lift_state, "lift_throw", "wisp")
	if (
		not bool(lift_plan.get("willExecute", false))
		or lift_plan.get("destination", Combat.INVALID_CELL) != Vector2i(3, 2)
		or lift_plan.get("movementPath", []).size() != 4
	):
		errors.append("reachable lift did not stop adjacent after using at most MOVE")
	var lift_approach := Grid.approach_command_preview(
		lift_state, "lift_throw", "wisp", Combat.INVALID_CELL, Combat.INVALID_CELL, "hold"
	)
	if (
		not bool(lift_approach.get("ok", false))
		or bool(lift_approach.get("approachFallbackDefend", true))
		or (lift_approach.get("moves", {}) as Dictionary).get("mira") != Vector2i(3, 2)
	):
		errors.append("reachable lift preview lost the carrier movement before pickup")


func _test_held_target_lifecycle(errors: Array[String]) -> void:
	var state := Grid.initial_state()
	_keep_alive(state, PackedStringArray(["mira", "sena", "wisp", "raider"]))
	_set_cell(state, "mira", Vector2i(2, 2))
	_set_cell(state, "wisp", Vector2i(3, 2))
	_set_cell(state, "raider", Vector2i(5, 2))
	_set_cell(state, "sena", Vector2i(4, 2))
	_force_turn(state, "mira")
	_lock_hit_seed(state, "lift_throw", "wisp")
	var hold_preview := Combat.preview(
		state, "lift_throw", "wisp", Combat.INVALID_CELL, Combat.INVALID_CELL, "hold"
	)
	if not bool(hold_preview.get("ok", false)) or (hold_preview.get("setHold", {}) as Dictionary).is_empty():
		errors.append("lift hold choice produced no battle-only hold transition")
		return
	state = Combat.commit(state, hold_preview)
	if (
		Combat.held_target_id(state, "mira") != "wisp"
		or Combat.unit_definition(state, "wisp").has("cell")
		or "wisp" in Combat.valid_target_ids(state, "spark")
		or Grid.reachable_cells(state, "mira").size() != 1
		or Combat.command_ids_for_current_actor(state, false) != [
			Combat.HELD_THROW_COMMAND, Combat.HELD_LOWER_COMMAND, Combat.HELD_GUARD_COMMAND,
		]
	):
		errors.append("held target occupancy, targeting or carrier command lock is inconsistent")
	var queued_ids: Array[String] = []
	for row in Combat.timeline(state, 12):
		queued_ids.append(str(row.get("unitId", "")))
	if "wisp" in queued_ids:
		errors.append("held target remained in the visible/acting timeline")

	var throw_state := state.duplicate(true)
	_force_turn(throw_state, "mira")
	var throw_cells := Combat.valid_target_cells(throw_state, Combat.HELD_THROW_COMMAND)
	if throw_cells.is_empty():
		errors.append("held throw exposed no legal landing cells")
	else:
		var throw_cell: Vector2i = throw_cells[0]
		var delayed_throw := Combat.preview(
			throw_state, Combat.HELD_THROW_COMMAND, "", Combat.INVALID_CELL, throw_cell
		)
		var thrown := Combat.commit(throw_state, delayed_throw)
		var thrown_target := Combat.unit_definition(thrown, "wisp")
		var landed_or_defeated: bool = (
			(
				int(thrown_target.get("hp", 0)) > 0
				and thrown_target.get("cell", Combat.INVALID_CELL) == throw_cell
			)
			or (int(thrown_target.get("hp", 0)) <= 0 and not thrown_target.has("cell"))
		)
		if (
			not bool(delayed_throw.get("ok", false))
			or not Combat.held_target_id(thrown, "mira").is_empty()
			or not landed_or_defeated
			or Combat.unit_definition(thrown, "mira").get("cell", Combat.INVALID_CELL) != Vector2i(2, 2)
		):
			errors.append("delayed held throw did not release onto the selected cell")

	_force_turn(state, "sena")
	var units := state.get("units", {}) as Dictionary
	var held_wisp := units.get("wisp", {}) as Dictionary
	held_wisp["statuses"] = {"wet": 2}
	held_wisp["zone"] = int((units.get("raider", {}) as Dictionary).get("zone", 1))
	units["wisp"] = held_wisp
	var chain_target := units.get("raider", {}) as Dictionary
	chain_target["statuses"] = {"wet": 2}
	units["raider"] = chain_target
	state["units"] = units
	_lock_hit_seed(state, "spark", "wisp")
	var chain := Combat.preview(state, "spark", "raider")
	if (chain.get("damage", {}) as Dictionary).has("wisp") or (chain.get("setStatuses", {}) as Dictionary).has("wisp"):
		errors.append("ordinary AOE/status effects reached a held target")

	_force_turn(state, "mira")
	var guard := Combat.preview(state, Combat.HELD_GUARD_COMMAND, "mira")
	state = Combat.commit(state, guard)
	if Combat.held_target_id(state, "mira") != "wisp":
		errors.append("hold-and-defend released its target")
	_force_turn(state, "mira")
	var lower := Combat.preview(state, Combat.HELD_LOWER_COMMAND, "mira")
	var lowered := Combat.commit(state, lower)
	if not Combat.held_target_id(lowered, "mira").is_empty() or not Combat.unit_definition(lowered, "wisp").has("cell"):
		errors.append("lower command did not deterministically free the held target")

	var stale_state := state.duplicate(true)
	var stale_lower := Combat.preview(stale_state, Combat.HELD_LOWER_COMMAND, "mira")
	stale_state["holds"] = {}
	if Combat.commit(stale_state, stale_lower) != stale_state:
		errors.append("same-turn stale hold preview still applied after the snapshot changed")

	_force_turn(state, "raider")
	_set_unit_value(state, "mira", "hp", 1)
	_set_cell(state, "raider", Vector2i(2, 1))
	_lock_hit_seed(state, "enemy_strike", "mira")
	var lethal := Combat.preview(state, "enemy_strike", "mira")
	var released := Combat.commit(state, lethal)
	if (
		int(Combat.unit_definition(released, "mira").get("hp", 1)) > 0
		or not Combat.held_target_id(released, "mira").is_empty()
		or not Combat.unit_definition(released, "wisp").has("cell")
	):
		errors.append("carrier death did not deterministically release the held target")


func _test_held_ai(errors: Array[String]) -> void:
	var state := Grid.initial_state()
	_keep_alive(state, PackedStringArray(["warden", "protagonist"]))
	_set_cell(state, "warden", Vector2i(4, 2))
	_set_cell(state, "protagonist", Vector2i(3, 2))
	_force_turn(state, "warden")
	state["holds"] = {"warden": "protagonist"}
	var units := state.get("units", {}) as Dictionary
	var held := units.get("protagonist", {}) as Dictionary
	held.erase("cell")
	units["protagonist"] = held
	state["units"] = units
	var command := Grid.enemy_command(state)
	if (
		not bool(command.get("ok", false))
		or str(command.get("actionId", "")) not in [
			Combat.HELD_THROW_COMMAND, Combat.HELD_LOWER_COMMAND, Combat.HELD_GUARD_COMMAND,
		]
		or (command.get("moves", {}) as Dictionary).get("warden", Vector2i(4, 2)) != Vector2i(4, 2)
	):
		errors.append("AI carrier bypassed shared synthetic commands or moved while holding")


func _test_grid_conduction(errors: Array[String]) -> void:
	var state := Grid.initial_state()
	_set_cell(state, "sena", Vector2i(3, 1))
	_set_cell(state, "wisp", Vector2i(4, 1))
	_set_cell(state, "raider", Vector2i(4, 2))
	_force_turn(state, "sena")
	var preview := Combat.preview(state, "spark", "wisp")
	var damage: Dictionary = preview.get("damage", {})
	if str(preview.get("reaction", "")) != "Проводящая цепь":
		errors.append("grid wet panels did not trigger conduction")
	if not damage.has("wisp") or not damage.has("raider") or damage.has("warden"):
		errors.append("conduction did not follow the connected wet panel group")


func _test_focus_and_push(errors: Array[String]) -> void:
	var state := Grid.initial_state()
	_set_cell(state, "protagonist", Vector2i(3, 3))
	_set_cell(state, "raider", Vector2i(4, 3))
	_force_turn(state, "protagonist")
	var units: Dictionary = state.get("units", {})
	var raider: Dictionary = units.get("raider", {})
	raider["statuses"] = {"frozen": 1}
	units["raider"] = raider
	state["units"] = units
	var no_focus := state.duplicate(true)
	var no_focus_grid: Dictionary = no_focus.get("grid", {})
	no_focus_grid["focus"] = {}
	no_focus["grid"] = no_focus_grid
	_lock_hit_seed(state, "kindle", "raider")
	no_focus["rngSeed"] = state.get("rngSeed", 1)
	var preview := Combat.preview(state, "kindle", "raider")
	var without_bonus := Combat.preview(no_focus, "kindle", "raider")
	if (
		int((preview.get("damage", {}) as Dictionary).get("raider", 0))
		<= int((without_bonus.get("damage", {}) as Dictionary).get("raider", 0))
	):
		errors.append("ember focus did not add +2 before Steam Break bonus")
	if (preview.get("moves", {}) as Dictionary).get("raider") != Vector2i(5, 3):
		errors.append("grid Steam Break did not push along the attacker-target axis")
	if not str(preview.get("summary", "")).contains("Жар-фокус"):
		errors.append("field rule bonus is absent from consequence preview")


func _test_height_rules(errors: Array[String]) -> void:
	var state := Grid.initial_state()
	_set_elevation(state, Vector2i(0, 0), 2)
	_set_elevation(state, Vector2i(1, 0), 0)
	_set_elevation(state, Vector2i(2, 0), 0)
	_set_elevation(state, Vector2i(4, 1), 1)
	_set_cell(state, "mira", Vector2i(1, 1))
	var units: Dictionary = state.get("units", {})
	var mira: Dictionary = units.get("mira", {})
	mira["jumpHeight"] = 1
	units["mira"] = mira
	state["units"] = units
	var reachable := Grid.reachable_cells(state, "mira")
	if Vector2i(4, 1) not in reachable:
		errors.append("movement could not climb the one-level terrace")
	if Vector2i(0, 0) in reachable:
		errors.append("Jump 1 climbed a two-level cliff in one step")
	mira["jumpHeight"] = 2
	units["mira"] = mira
	state["units"] = units
	if Vector2i(0, 0) not in Grid.reachable_cells(state, "mira"):
		errors.append("Jump 2 did not unlock the two-level cliff")
	if Terrain.elevation(state, Vector2i(4, 1)) != 1 or Terrain.elevation(state, Vector2i(0, 0)) != 2:
		errors.append("semantic elevation fixture is absent from grid cells")
	_set_cell(state, "mira", Vector2i(2, 0))
	_set_cell(state, "wisp", Vector2i(1, 0))
	_force_turn(state, "mira")
	var push := Combat.preview(state, "gust", "wisp")
	if (push.get("moves", {}) as Dictionary).has("wisp"):
		errors.append("forced movement ignored the shared two-level cliff rule")


func _test_field_mutation(errors: Array[String]) -> void:
	var state := Grid.field_mutation_state()
	# The authored 9x7 E3 deployments intentionally begin outside immediate
	# spell range. Position the actors for this pure resolver gate; movement/UI
	# legality is covered separately by Combat Lab.
	_set_cell(state, "orik", Vector2i(3, 2))
	_set_cell(state, "warden", Vector2i(5, 2))
	_force_turn(state, "orik")
	_lock_hit_seed(state, "chill", "warden")
	var original := state.duplicate(true)
	var freeze := Combat.preview(state, "chill", "warden")
	var frozen_changes: Dictionary = freeze.get("cellChanges", {})
	if state != original:
		errors.append("field mutation preview changed its source snapshot")
	var wet_count := 0
	for definition in (state.get("grid", {}) as Dictionary).get("cells", {}).values():
		if "wet" in (definition as Dictionary).get("tags", []):
			wet_count += 1
	if frozen_changes.size() != wet_count:
		errors.append("cold did not preview every panel in the linked wet group")
	if not str(freeze.get("summary", "")).contains("Frozen"):
		errors.append("field mutation is absent from the consequence preview")
	state = Combat.commit(state, freeze)
	var frozen_cell := Grid.cell_definition(state, Vector2i(3, 2))
	if "frozen" not in frozen_cell.get("tags", []) or "wet" in frozen_cell.get("tags", []):
		errors.append("confirm did not atomically replace Wet with Frozen")
	_force_turn(state, "protagonist")
	_set_cell(state, "protagonist", Vector2i(3, 3))
	_lock_hit_seed(state, "kindle", "warden")
	var thaw := Combat.preview(state, "kindle", "warden")
	if not str(thaw.get("summary", "")).contains("Wet"):
		errors.append("fire did not preview thawing the linked Frozen panels")
	state = Combat.commit(state, thaw)
	var thawed_cell := Grid.cell_definition(state, Vector2i(3, 2))
	if "wet" not in thawed_cell.get("tags", []) or "frozen" in thawed_cell.get("tags", []):
		errors.append("thaw commit did not restore the linked panels to Wet")


func _set_cell(state: Dictionary, unit_id: String, cell: Vector2i) -> void:
	var units: Dictionary = state.get("units", {})
	var unit: Dictionary = units.get(unit_id, {})
	unit["cell"] = cell
	units[unit_id] = unit
	state["units"] = units


func _set_unit_value(state: Dictionary, unit_id: String, key: String, value: Variant) -> void:
	var units: Dictionary = state.get("units", {})
	var unit: Dictionary = units.get(unit_id, {})
	unit[key] = value
	units[unit_id] = unit
	state["units"] = units


func _keep_alive(state: Dictionary, unit_ids: PackedStringArray) -> void:
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit_id := str(raw_id)
		var unit: Dictionary = units[raw_id]
		if unit_id not in unit_ids:
			unit["hp"] = 0
		units[raw_id] = unit
	state["units"] = units


func _set_elevation(state: Dictionary, cell: Vector2i, elevation: int) -> void:
	var grid: Dictionary = state.get("grid", {})
	var cells: Dictionary = grid.get("cells", {})
	var definition: Dictionary = cells.get(Grid.cell_key(cell), {})
	definition["elevation"] = elevation
	cells[Grid.cell_key(cell)] = definition
	grid["cells"] = cells
	state["grid"] = grid


func _force_turn(state: Dictionary, active_id: String) -> void:
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit: Dictionary = units[raw_id]
		unit["nextAt"] = 0.0 if str(raw_id) == active_id else 100.0
		units[raw_id] = unit
	state["units"] = units


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
