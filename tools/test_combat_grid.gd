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
