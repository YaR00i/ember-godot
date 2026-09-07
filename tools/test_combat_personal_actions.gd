extends SceneTree
## Stage 3.6 gate: all four canonical heroes own exactly three personal actions,
## and the six newly completed abilities use the same preview/commit resolver.

const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid := preload("res://scripts/prototypes/ember_combat_grid.gd")
const Terrain := preload("res://scripts/prototypes/ember_combat_terrain.gd")
const UnitCatalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")


func _init() -> void:
	var errors: Array[String] = []
	_test_assignments(errors)
	_test_forge_leap(errors)
	_test_overheat(errors)
	_test_mira_mend(errors)
	_test_ice_wall(errors)
	_test_remote_relay(errors)
	_test_overload(errors)
	if not errors.is_empty():
		printerr("FAIL combat personal actions")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat personal actions")
	print("  each hero owns three GDD personal actions plus shared and pair commands")
	print("  leap, healing, ice wall and remote focus activation share preview/commit")
	print("  Overheat has an explicit damage bonus and incoming-risk contract")
	print("  Overload keeps hit, critical and damage hidden before commit")
	quit(0)


func _test_assignments(errors: Array[String]) -> void:
	var expected := {
		"protagonist": ["kindle", "forge_leap", "overheat"],
		"mira": ["douse", "gust", "mira_mend"],
		"orik": ["chill", "guard", "ice_wall"],
		"sena": ["spark", "remote_relay", "overload"],
	}
	for unit_id in expected:
		var unit := UnitCatalog.resource(unit_id)
		if unit == null:
			errors.append("missing canonical hero %s" % unit_id)
			continue
		for action_id in expected[unit_id]:
			if action_id not in unit.action_ids:
				errors.append("%s is missing personal action %s" % [unit_id, action_id])
	if "kindle" in UnitCatalog.resource("sena").action_ids:
		errors.append("Sena still duplicates the protagonist's personal Fire spell")


func _test_forge_leap(errors: Array[String]) -> void:
	var state := _grid_state("protagonist")
	var target := Vector2i(3, 1)
	var cells: Dictionary = (state.get("grid", {}) as Dictionary).get("cells", {})
	var target_definition: Dictionary = (cells[Terrain.cell_key(target)] as Dictionary).duplicate(true)
	target_definition["elevation"] = 3
	cells[Terrain.cell_key(target)] = target_definition
	(state["grid"] as Dictionary)["cells"] = cells
	if target not in Combat.valid_target_cells(state, "forge_leap"):
		errors.append("Forge Leap does not expose a free h3 destination")
		return
	var preview := Combat.preview(state, "forge_leap", "", Combat.INVALID_CELL, target)
	if (
		not bool(preview.get("ok", false))
		or (preview.get("moves", {}) as Dictionary).get("protagonist") != target
		or preview.get("movementPath", []) != [Vector2i(1, 1), target]
	):
		errors.append("Forge Leap did not lock its movement in preview")
		return
	if Combat.unit_definition(state, "protagonist").get("cell") != Vector2i(1, 1):
		errors.append("Forge Leap preview mutated the source position")
	var committed := Combat.commit(state, preview)
	if Combat.unit_definition(committed, "protagonist").get("cell") != target:
		errors.append("Forge Leap commit did not move the protagonist")
	var compound_state := _grid_state("protagonist")
	var compound := Grid.command_preview(
		compound_state,
		"forge_leap",
		"",
		Vector2i(2, 1),
		Combat.INVALID_CELL,
		Vector2i(4, 1),
	)
	var compound_path: Array = compound.get("movementPath", [])
	if (
		not bool(compound.get("ok", false))
		or (compound.get("moves", {}) as Dictionary).get("protagonist") != Vector2i(4, 1)
		or compound_path.is_empty()
		or compound_path[0] != Vector2i(1, 1)
		or compound_path[-1] != Vector2i(4, 1)
	):
		errors.append("staged movement overwrote Forge Leap's final destination")


func _test_overheat(errors: Array[String]) -> void:
	var state := _grid_state("protagonist")
	var self_preview := Combat.preview(state, "overheat", "protagonist")
	var committed := Combat.commit(state, self_preview)
	if int(Combat.unit_definition(committed, "protagonist").get("statuses", {}).get("overheated", 0)) != 2:
		errors.append("Overheat did not persist for the next two actions")

	var hot_attack := _grid_state("protagonist")
	var hot_units: Dictionary = hot_attack.get("units", {})
	var hot_actor: Dictionary = hot_units["protagonist"]
	hot_actor["statuses"] = {"overheated": 2}
	hot_units["protagonist"] = hot_actor
	var hot_target: Dictionary = hot_units["wisp"]
	hot_target["cell"] = Vector2i(2, 1)
	hot_units["wisp"] = hot_target
	hot_attack["units"] = hot_units
	var normal_attack := hot_attack.duplicate(true)
	var normal_units: Dictionary = normal_attack.get("units", {})
	var normal_actor: Dictionary = normal_units["protagonist"]
	normal_actor["statuses"] = {}
	normal_units["protagonist"] = normal_actor
	normal_attack["units"] = normal_units
	var seed := _shared_hit_seed(hot_attack, normal_attack, "strike", "wisp")
	if seed < 0:
		errors.append("could not lock a shared hit for Overheat offense test")
	else:
		hot_attack["rngSeed"] = seed
		normal_attack["rngSeed"] = seed
		var hot_preview := Combat.preview(hot_attack, "strike", "wisp")
		var normal_preview := Combat.preview(normal_attack, "strike", "wisp")
		if int(hot_preview.get("damage", {}).get("wisp", 0)) <= int(normal_preview.get("damage", {}).get("wisp", 0)):
			errors.append("Overheat does not increase outgoing attack damage")

	var risky := _grid_state("wisp")
	var risky_units: Dictionary = risky.get("units", {})
	var risky_target: Dictionary = risky_units["protagonist"]
	risky_target["statuses"] = {"overheated": 2}
	risky_target["cell"] = Vector2i(2, 2)
	risky_units["protagonist"] = risky_target
	var enemy: Dictionary = risky_units["wisp"]
	enemy["cell"] = Vector2i(3, 2)
	risky_units["wisp"] = enemy
	risky["units"] = risky_units
	var safe := risky.duplicate(true)
	var safe_units: Dictionary = safe.get("units", {})
	var safe_target: Dictionary = safe_units["protagonist"]
	safe_target["statuses"] = {}
	safe_units["protagonist"] = safe_target
	safe["units"] = safe_units
	seed = _shared_hit_seed(risky, safe, "enemy_strike", "protagonist")
	if seed < 0:
		errors.append("could not lock a shared hit for Overheat risk test")
	else:
		risky["rngSeed"] = seed
		safe["rngSeed"] = seed
		var risky_preview := Combat.preview(risky, "enemy_strike", "protagonist")
		var safe_preview := Combat.preview(safe, "enemy_strike", "protagonist")
		if int(risky_preview.get("damage", {}).get("protagonist", 0)) <= int(safe_preview.get("damage", {}).get("protagonist", 0)):
			errors.append("Overheat does not increase incoming damage")


func _test_mira_mend(errors: Array[String]) -> void:
	var state := _grid_state("mira")
	var units: Dictionary = state.get("units", {})
	var target: Dictionary = units["orik"]
	target["hp"] = 5
	units["orik"] = target
	state["units"] = units
	if "orik" not in Combat.valid_target_ids(state, "mira_mend"):
		errors.append("Mira cannot target a wounded living ally")
		return
	var preview := Combat.preview(state, "mira_mend", "orik")
	if int((preview.get("restoreHp", {}) as Dictionary).get("orik", 0)) != 17:
		errors.append("Mira's heal does not restore the authored 12 HP")
	var committed := Combat.commit(state, preview)
	if (
		int(Combat.unit_definition(committed, "orik").get("hp", 0)) != 17
		or int(Combat.unit_definition(committed, "mira").get("mp", 0))
		!= int(Combat.unit_definition(state, "mira").get("mp", 0)) - 10
	):
		errors.append("Mira's heal did not commit HP and MP exactly once")
	var full_state := _grid_state("mira")
	if "orik" in Combat.valid_target_ids(full_state, "mira_mend"):
		errors.append("Mira can waste the expensive heal on a full-HP ally")


func _test_ice_wall(errors: Array[String]) -> void:
	var state := _grid_state("orik")
	var target := Vector2i(2, 3)
	var preview := Combat.preview(state, "ice_wall", "", Combat.INVALID_CELL, target)
	var patch: Dictionary = (preview.get("cellChanges", {}) as Dictionary).get(
		Terrain.cell_key(target), {}
	)
	if not bool(patch.get("blocked", false)) or "frozen" not in patch.get("tags", []):
		errors.append("Ice Wall preview is not a Frozen blocking cell patch")
		return
	var committed := Combat.commit(state, preview)
	if not Grid.is_blocked(committed, target) or "frozen" not in Grid.cell_definition(committed, target).get("tags", []):
		errors.append("Ice Wall commit did not reach canonical terrain")


func _test_remote_relay(errors: Array[String]) -> void:
	var state := _grid_state("sena")
	var focus := Vector2i(5, 3)
	if focus not in Combat.valid_target_cells(state, "remote_relay"):
		errors.append("Sena cannot target the authored focus from range")
		return
	var preview := Combat.preview(state, "remote_relay", "", Combat.INVALID_CELL, focus)
	var patch: Dictionary = (preview.get("cellChanges", {}) as Dictionary).get(
		Terrain.cell_key(focus), {}
	)
	if "activated" not in patch.get("tags", []):
		errors.append("remote activation preview did not mark the focus active")
		return
	var committed := Combat.commit(state, preview)
	if "activated" not in Grid.cell_definition(committed, focus).get("tags", []):
		errors.append("remote activation did not commit to battle state")
	if focus in Combat.valid_target_cells(committed, "remote_relay"):
		errors.append("an activated focus can be triggered repeatedly")


func _test_overload(errors: Array[String]) -> void:
	var state := _grid_state("sena")
	var intent := Combat.describe_intent(state, "overload", "wisp")
	if " HP" in intent or "КРИТ" in intent or "%" in intent:
		errors.append("Overload intent reveals a hidden combat outcome")
	var preview := _first_hit_preview(state, "overload", "wisp")
	if not bool(preview.get("ok", false)) or int(preview.get("damage", {}).get("wisp", 0)) <= 0:
		errors.append("Overload could not resolve through the hostile RNG path")
		return
	var committed := Combat.commit(state, preview)
	if (
		int(Combat.unit_definition(committed, "sena").get("mp", 0))
		!= int(Combat.unit_definition(state, "sena").get("mp", 0)) - 10
	):
		errors.append("Overload did not spend its authored MP once")


func _grid_state(actor_id: String) -> Dictionary:
	var state := Combat.initial_state(17)
	var cells := {}
	for y in 6:
		for x in 8:
			var cell := Vector2i(x, y)
			cells[Terrain.cell_key(cell)] = {
				"cell": cell, "terrain": 0, "elevation": 0,
				"blocked": false, "group": "", "tags": [],
			}
	state["grid"] = {
		"width": 8,
		"height": 6,
		"cells": cells,
		"focus": {"cell": Vector2i(5, 3), "effect": "", "bonus": 0},
	}
	var positions := {
		"protagonist": Vector2i(1, 1),
		"mira": Vector2i(1, 2),
		"orik": Vector2i(1, 3),
		"sena": Vector2i(1, 4),
		"wisp": Vector2i(3, 2),
		"raider": Vector2i(7, 4),
	}
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit_id := str(raw_id)
		var unit: Dictionary = units[unit_id]
		unit["nextAt"] = 0.0 if unit_id == actor_id else 100.0
		unit["hp"] = int(unit.get("maxHp", 1)) if positions.has(unit_id) else 0
		unit["mp"] = int(unit.get("maxMp", 0))
		unit["cell"] = positions.get(unit_id, Vector2i(7, 5))
		units[unit_id] = unit
	state["units"] = units
	return state


func _first_hit_preview(state: Dictionary, action_id: String, target_id: String) -> Dictionary:
	for seed in range(1, 1000):
		state["rngSeed"] = seed
		var preview := Combat.preview(state, action_id, target_id)
		if bool(preview.get("ok", false)) and bool(preview.get("hit", false)):
			return preview
	return {}


func _shared_hit_seed(
	left: Dictionary,
	right: Dictionary,
	action_id: String,
	target_id: String,
) -> int:
	for seed in range(1, 1000):
		left["rngSeed"] = seed
		right["rngSeed"] = seed
		if (
			bool(Combat.preview(left, action_id, target_id).get("hit", false))
			and bool(Combat.preview(right, action_id, target_id).get("hit", false))
		):
			return seed
	return -1
