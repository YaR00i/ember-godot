extends SceneTree
## Stage 1 gate: full vertical rules and the large-field profile remain in the
## existing Battlefield/Grid/Combat owners.

const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid := preload("res://scripts/prototypes/ember_combat_grid.gd")
const Terrain := preload("res://scripts/prototypes/ember_combat_terrain.gd")
const FIELD_10 := preload("res://content/combat/battlefields/vertical_forge_10x8.tres")
const FIELD_16 := preload("res://content/combat/battlefields/vertical_forge_16x12.tres")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	_test_field_resources(errors)
	_test_jump_and_fall(errors)
	_test_height_range_and_los(errors)
	_test_push_from_ledge(errors)
	_test_lift_throw(errors)
	_test_ai_throw(errors)
	var profile := _profile_large_field(errors)
	if not errors.is_empty():
		printerr("FAIL combat vertical profile")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS combat vertical profile")
	print("  10x8 and 16x12 use the existing dense one-height Battlefield Resource")
	print("  Jump, height-aware range, LOS, falls, push and lift/throw share preview/commit")
	print("  enemy AI evaluates the same movement paths and lift/throw previews")
	print("  16x12 average: reachable %.2f ms · path %.2f ms · approach %.2f ms · cells %.2f ms · AI %.2f ms" % [
		float(profile.get("reachableUsec", 0.0)) / 1000.0,
		float(profile.get("pathUsec", 0.0)) / 1000.0,
		float(profile.get("approachUsec", 0.0)) / 1000.0,
		float(profile.get("cellTargetUsec", 0.0)) / 1000.0,
		float(profile.get("aiUsec", 0.0)) / 1000.0,
	])
	return 0


func _test_field_resources(errors: Array[String]) -> void:
	for raw_field in [FIELD_10, FIELD_16]:
		var field := raw_field as EmberBattlefieldResource
		if field == null:
			errors.append("vertical field Resource is missing")
			continue
		var expected: int = field.width * field.height
		if (
			field.terrain_kinds.size() != expected
			or field.elevations.size() != expected
			or field.blocked.size() != expected
			or field.groups.size() != expected
		):
			errors.append("%s does not keep one dense definition per column" % field.field_id)
		var validation: Array[String] = field.validation_errors()
		if not validation.is_empty():
			errors.append("%s is invalid: %s" % [field.field_id, " | ".join(validation)])
	if FIELD_10.width != 10 or FIELD_10.height != 8:
		errors.append("regular vertical laboratory field is not 10x8")
	if FIELD_16.width != 16 or FIELD_16.height != 12:
		errors.append("large vertical laboratory field is not 16x12")


func _test_jump_and_fall(errors: Array[String]) -> void:
	var state := Grid.initial_state(FIELD_10)
	_force_turn(state, "mira")
	_keep_alive(state, PackedStringArray(["mira", "wisp"]))
	_set_unit_cell(state, "mira", Vector2i(1, 1))
	_set_unit_cell(state, "wisp", Vector2i(8, 7))
	_set_unit_value(state, "mira", "moveRange", 1)
	_set_cell(state, Vector2i(1, 1), {"elevation": 0, "blocked": false})
	_set_cell(state, Vector2i(2, 1), {"elevation": 2, "blocked": false})
	_set_unit_value(state, "mira", "jumpHeight", 1)
	if Vector2i(2, 1) in Grid.reachable_cells(state, "mira"):
		errors.append("Jump 1 crossed a two-level rise")
	_set_unit_value(state, "mira", "jumpHeight", 2)
	if Vector2i(2, 1) not in Grid.reachable_cells(state, "mira"):
		errors.append("Jump 2 could not cross a two-level rise")
	_set_unit_cell(state, "mira", Vector2i(2, 1))
	_set_cell(state, Vector2i(2, 1), {"elevation": 3, "blocked": false})
	_set_cell(state, Vector2i(3, 1), {"elevation": 0, "blocked": false})
	var before := state.duplicate(true)
	var preview := Grid.command_preview(state, "defend", "mira", Vector2i(3, 1))
	if (
		not bool(preview.get("ok", false))
		or int((preview.get("damage", {}) as Dictionary).get("mira", 0)) != 4
		or preview.get("movementPath", []) != [Vector2i(2, 1), Vector2i(3, 1)]
	):
		errors.append("movement fall did not produce an exact staged path and 4 HP preview")
	if state != before:
		errors.append("movement/fall preview mutated the source snapshot")
	var committed := Combat.commit(state, preview)
	if (
		int(Combat.unit_definition(committed, "mira").get("hp", 0))
		!= int(Combat.unit_definition(state, "mira").get("hp", 0)) - 4
	):
		errors.append("fall commit did not apply the previewed damage exactly")


func _test_height_range_and_los(errors: Array[String]) -> void:
	var state := Grid.initial_state(FIELD_10)
	_force_turn(state, "mira")
	_keep_alive(state, PackedStringArray(["mira", "wisp"]))
	_set_unit_cell(state, "mira", Vector2i(1, 1))
	_set_unit_cell(state, "wisp", Vector2i(3, 1))
	_set_cell(state, Vector2i(1, 1), {"elevation": 0, "blocked": false})
	_set_cell(state, Vector2i(2, 1), {"elevation": 0, "blocked": false})
	_set_cell(state, Vector2i(3, 1), {"elevation": 3, "blocked": false})
	if "wisp" in Combat.valid_target_ids(state, "douse"):
		errors.append("height-aware range ignored the three-level difference")
	_set_cell(state, Vector2i(3, 1), {"elevation": 1, "blocked": false})
	if "wisp" not in Combat.valid_target_ids(state, "douse"):
		errors.append("height-aware range rejected a visible reachable target")
	_set_cell(state, Vector2i(2, 1), {"elevation": 0, "blocked": true})
	if "wisp" in Combat.valid_target_ids(state, "douse"):
		errors.append("blocked intermediate cell did not stop line of sight")
	_set_cell(state, Vector2i(2, 1), {"elevation": 3, "blocked": false})
	if Terrain.has_line_of_sight(state, Vector2i(1, 1), Vector2i(3, 1)):
		errors.append("high terrain ridge did not stop line of sight")


func _test_push_from_ledge(errors: Array[String]) -> void:
	var state := Grid.initial_state(FIELD_10)
	_force_turn(state, "mira")
	_keep_alive(state, PackedStringArray(["mira", "wisp"]))
	_set_unit_cell(state, "mira", Vector2i(1, 1))
	_set_unit_cell(state, "wisp", Vector2i(2, 1))
	_set_cell(state, Vector2i(1, 1), {"elevation": 3, "blocked": false})
	_set_cell(state, Vector2i(2, 1), {"elevation": 3, "blocked": false})
	_set_cell(state, Vector2i(3, 1), {"elevation": 0, "blocked": false})
	_lock_hit_seed(state, "gust", "wisp")
	var preview := Combat.preview(state, "gust", "wisp")
	if (
		not bool(preview.get("ok", false))
		or (preview.get("moves", {}) as Dictionary).get("wisp", Vector2i(-1, -1)) != Vector2i(3, 1)
		or int(preview.get("fallDamage", 0)) != 4
		or int((preview.get("damage", {}) as Dictionary).get("wisp", 0)) < 4
	):
		errors.append("push from ledge did not preview movement plus 4 fall damage")


func _test_lift_throw(errors: Array[String]) -> void:
	var state := Grid.initial_state(FIELD_10)
	_force_turn(state, "mira")
	_keep_alive(state, PackedStringArray(["mira", "orik", "wisp", "warden"]))
	_set_unit_cell(state, "mira", Vector2i(1, 1))
	_set_unit_cell(state, "orik", Vector2i(2, 1))
	_set_unit_cell(state, "wisp", Vector2i(1, 2))
	_set_unit_cell(state, "warden", Vector2i(2, 2))
	for cell in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		_set_cell(state, cell, {"elevation": 3, "blocked": false})
	_set_cell(state, Vector2i(3, 1), {"elevation": 0, "blocked": false})
	if "warden" in Combat.valid_target_ids(state, "lift_throw"):
		errors.append("heavy unit can be lifted despite the authored weight limit")
	var destinations := Combat.valid_secondary_cells(state, "lift_throw", "orik")
	if Vector2i(3, 1) not in destinations:
		errors.append("lift/throw did not expose the valid landing cell")
	var before := state.duplicate(true)
	var preview := Combat.preview(state, "lift_throw", "orik", Vector2i(3, 1))
	if (
		not bool(preview.get("ok", false))
		or (preview.get("moves", {}) as Dictionary).get("orik", Vector2i(-1, -1)) != Vector2i(3, 1)
		or int((preview.get("damage", {}) as Dictionary).get("orik", 0)) != 4
	):
		errors.append("ally lift/throw did not preview exact landing and fall damage")
	if state != before:
		errors.append("lift/throw preview mutated its source state")
	var committed := Combat.commit(state, preview)
	if (
		Combat.unit_definition(committed, "orik").get("cell", Vector2i(-1, -1)) != Vector2i(3, 1)
		or int(Combat.unit_definition(committed, "orik").get("hp", 0))
		!= int(Combat.unit_definition(state, "orik").get("hp", 0)) - 4
	):
		errors.append("lift/throw commit drifted from preview")


func _test_ai_throw(errors: Array[String]) -> void:
	var state := Grid.initial_state(FIELD_10)
	_force_turn(state, "warden")
	_keep_alive(state, PackedStringArray(["mira", "warden"]))
	_set_unit_cell(state, "warden", Vector2i(2, 1))
	_set_unit_cell(state, "mira", Vector2i(3, 1))
	_set_cell(state, Vector2i(2, 1), {"elevation": 3, "blocked": false})
	_set_cell(state, Vector2i(3, 1), {"elevation": 3, "blocked": false})
	var command := Grid.enemy_command(state)
	if (
		not bool(command.get("ok", false))
		or str(command.get("actionId", "")) != "lift_throw"
		or command.get("secondaryCell", Combat.INVALID_CELL) == Combat.INVALID_CELL
	):
		errors.append("enemy AI did not evaluate lift/throw through the shared preview")
		return
	var committed := Combat.commit(state, command)
	if (
		Combat.unit_definition(committed, "mira").get("cell", Combat.INVALID_CELL)
		!= command.get("secondaryCell", Combat.INVALID_CELL)
	):
		errors.append("AI lift/throw commit did not use its previewed landing cell")


func _profile_large_field(errors: Array[String]) -> Dictionary:
	var state := Grid.initial_state(FIELD_16)
	_force_turn(state, "mira")
	var reachable_iterations := 300
	var started := Time.get_ticks_usec()
	var reachable: Array[Vector2i] = []
	for _index in reachable_iterations:
		reachable = Grid.reachable_cells(state, "mira")
	var reachable_usec := float(Time.get_ticks_usec() - started) / float(reachable_iterations)
	var destination := reachable[-1] if not reachable.is_empty() else Vector2i.ZERO
	var path_iterations := 300
	started = Time.get_ticks_usec()
	for _index in path_iterations:
		Grid.movement_path(state, "mira", destination)
	var path_usec := float(Time.get_ticks_usec() - started) / float(path_iterations)
	var approach_iterations := 120
	started = Time.get_ticks_usec()
	for _index in approach_iterations:
		Grid.approach_target_ids(state, "strike")
	var approach_usec := float(Time.get_ticks_usec() - started) / float(approach_iterations)
	var cell_state := state.duplicate(true)
	_force_turn(cell_state, "orik")
	var cell_iterations := 60
	started = Time.get_ticks_usec()
	for _index in cell_iterations:
		Grid.approach_target_cells(cell_state, "ice_wall")
	var cell_target_usec := float(Time.get_ticks_usec() - started) / float(cell_iterations)
	var ai_state := state.duplicate(true)
	_force_turn(ai_state, "warden")
	_keep_alive(ai_state, PackedStringArray(["mira", "warden"]))
	_set_unit_cell(ai_state, "warden", Vector2i(9, 6))
	_set_unit_cell(ai_state, "mira", Vector2i(10, 6))
	_set_cell(ai_state, Vector2i(9, 6), {"elevation": 3, "blocked": false})
	_set_cell(ai_state, Vector2i(10, 6), {"elevation": 2, "blocked": false})
	var ai_iterations := 40
	started = Time.get_ticks_usec()
	for _index in ai_iterations:
		var command := Grid.enemy_command(ai_state)
		if not bool(command.get("ok", false)):
			errors.append("16x12 AI profile could not produce a command")
			break
	var ai_usec := float(Time.get_ticks_usec() - started) / float(ai_iterations)
	if reachable_usec > 5000.0:
		errors.append("16x12 reachable query exceeded 5 ms average: %.1f us" % reachable_usec)
	if path_usec > 5000.0:
		errors.append("16x12 path query exceeded 5 ms average: %.1f us" % path_usec)
	if approach_usec > 10000.0:
		errors.append("16x12 approach query exceeded 10 ms average: %.1f us" % approach_usec)
	if cell_target_usec > 20000.0:
		errors.append("16x12 cell target query exceeded 20 ms average: %.1f us" % cell_target_usec)
	if ai_usec > 50000.0:
		errors.append("16x12 AI query exceeded 50 ms average: %.1f us" % ai_usec)
	return {
		"reachableUsec": reachable_usec,
		"pathUsec": path_usec,
		"approachUsec": approach_usec,
		"cellTargetUsec": cell_target_usec,
		"aiUsec": ai_usec,
	}


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


func _keep_alive(state: Dictionary, alive_ids: PackedStringArray) -> void:
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit: Dictionary = units[raw_id]
		unit["hp"] = int(unit.get("maxHp", 1)) if str(raw_id) in alive_ids else 0
		units[raw_id] = unit
	state["units"] = units


func _set_unit_cell(state: Dictionary, unit_id: String, cell: Vector2i) -> void:
	_set_unit_value(state, unit_id, "cell", cell)


func _set_unit_value(state: Dictionary, unit_id: String, key: String, value: Variant) -> void:
	var units: Dictionary = state.get("units", {})
	var unit: Dictionary = units.get(unit_id, {})
	unit[key] = value
	units[unit_id] = unit
	state["units"] = units


func _set_cell(state: Dictionary, cell: Vector2i, patch: Dictionary) -> void:
	var grid: Dictionary = state.get("grid", {})
	var cells: Dictionary = grid.get("cells", {})
	var definition: Dictionary = cells.get(Grid.cell_key(cell), {}).duplicate(true)
	for key in patch:
		definition[key] = patch[key]
	cells[Grid.cell_key(cell)] = definition
	grid["cells"] = cells
	state["grid"] = grid
