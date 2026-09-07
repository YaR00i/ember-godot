class_name EmberCombatGrid
extends RefCounted
## Pure semantic grid adapter. Movement is staged until the shared combat
## preview is confirmed, so move + action remain one reversible lab command.

const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Terrain = preload("res://scripts/prototypes/ember_combat_terrain.gd")
const DEFAULT_E2_FIELD := preload("res://content/combat/battlefields/colored_crossing.tres")
const DEFAULT_E3_FIELD := preload("res://content/combat/battlefields/thaw_keeper.tres")
const VERTICAL_10X8_FIELD := preload("res://content/combat/battlefields/vertical_forge_10x8.tres")
const STRESS_16X12_FIELD := preload("res://content/combat/battlefields/vertical_forge_16x12.tres")
const WIDTH := 7
const HEIGHT := 5


static func initial_state(
	field: EmberBattlefieldResource = DEFAULT_E2_FIELD,
	rng_seed: int = 1,
) -> Dictionary:
	var state := Combat.initial_state(rng_seed)
	var active_field := field if field != null else DEFAULT_E2_FIELD
	state["encounterId"] = active_field.field_id
	state["log"] = [active_field.preview_intro]
	state["grid"] = active_field.to_grid_dictionary()
	var units: Dictionary = state.get("units", {})
	var party_index := 0
	var enemy_index := 0
	for raw_id in units:
		var unit_id := str(raw_id)
		var unit: Dictionary = units[unit_id]
		if str(unit.get("team", "")) == "hero":
			if party_index < active_field.party_deployment_cells.size():
				unit["cell"] = active_field.party_deployment_cells[party_index]
			party_index += 1
		else:
			if enemy_index < active_field.enemy_deployment_cells.size():
				unit["cell"] = active_field.enemy_deployment_cells[enemy_index]
			enemy_index += 1
		units[unit_id] = unit
	state["units"] = units
	return state


static func field_mutation_state(
	field: EmberBattlefieldResource = DEFAULT_E3_FIELD,
	rng_seed: int = 1,
) -> Dictionary:
	var state := initial_state(field if field != null else DEFAULT_E3_FIELD, rng_seed)
	var next_at := {
		"orik": 0.0,
		"wisp": 8.0,
		"sena": 16.0,
		"raider": 24.0,
		"mira": 32.0,
		"warden": 40.0,
	}
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit_id := str(raw_id)
		var unit: Dictionary = units[unit_id]
		unit["nextAt"] = float(next_at.get(unit_id, unit.get("nextAt", 0.0)))
		units[unit_id] = unit
	state["units"] = units
	return state


static func reachable_cells(state: Dictionary, unit_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for raw_cell in reachable_cell_costs(state, unit_id):
		if raw_cell is Vector2i:
			result.append(raw_cell as Vector2i)
	return result


static func reachable_cell_costs(state: Dictionary, unit_id: String) -> Dictionary:
	return (movement_field(state, unit_id).get("costs", {}) as Dictionary).duplicate()


static func movement_field(state: Dictionary, unit_id: String) -> Dictionary:
	var unit := Combat.unit_definition(state, unit_id)
	if unit.is_empty() or not unit.has("cell"):
		return {"costs": {}, "previous": {}}
	var max_distance := maxi(0, int(unit.get("moveRange", 0)))
	return _navigation_field(state, unit_id, max_distance)


static func _navigation_field(
	state: Dictionary,
	unit_id: String,
	max_distance: int = -1,
) -> Dictionary:
	var unit := Combat.unit_definition(state, unit_id)
	if unit.is_empty() or not unit.has("cell"):
		return {"costs": {}, "previous": {}}
	var start: Vector2i = unit.get("cell", Vector2i.ZERO)
	var result := {start: 0}
	var previous := {}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var visited := {cell_key(start): true}
	var jump_height := maxi(0, int(unit.get("jumpHeight", Terrain.MAX_STEP_HEIGHT)))
	# This field is also used for long approach routes on 16x12 arenas. Resolve
	# dense cell/occupancy lookups once instead of duplicating Resources and unit
	# dictionaries for every neighbor expansion.
	var grid := state.get("grid", {}) as Dictionary
	var width := int(grid.get("width", WIDTH))
	var height := int(grid.get("height", HEIGHT))
	var cells := grid.get("cells", {}) as Dictionary
	var focus_cell: Vector2i = (grid.get("focus", {}) as Dictionary).get(
		"cell", Combat.INVALID_CELL
	)
	var occupied := {}
	for raw_id in state.get("units", {}):
		var other_id := str(raw_id)
		if other_id == unit_id:
			continue
		var other := Combat.unit_definition(state, other_id)
		if int(other.get("hp", 0)) > 0 and other.has("cell"):
			occupied[cell_key(other.get("cell", Combat.INVALID_CELL))] = true
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var distance := int(result.get(cell, 0))
		if max_distance >= 0 and distance >= max_distance:
			continue
		var cell_height := int((cells.get(cell_key(cell), {}) as Dictionary).get("elevation", 0))
		for neighbor in _neighbors(cell):
			var key := cell_key(neighbor)
			if (
				visited.has(key)
				or neighbor.x < 0
				or neighbor.y < 0
				or neighbor.x >= width
				or neighbor.y >= height
			):
				continue
			visited[key] = true
			var definition := cells.get(key, {}) as Dictionary
			if (
				bool(definition.get("blocked", true))
				or neighbor == focus_cell
				or int(definition.get("elevation", 0)) - cell_height > jump_height
				or occupied.has(key)
			):
				continue
			result[neighbor] = distance + 1
			previous[neighbor] = cell
			queue.append(neighbor)
	return {"costs": result, "previous": previous}


static func movement_path(state: Dictionary, unit_id: String, destination: Vector2i) -> Array[Vector2i]:
	var unit := Combat.unit_definition(state, unit_id)
	if unit.is_empty() or not unit.has("cell"):
		return []
	var start: Vector2i = unit.get("cell", Vector2i.ZERO)
	var field := movement_field(state, unit_id)
	return _path_from_field(start, destination, field)


static func _path_from_field(
	start: Vector2i,
	destination: Vector2i,
	field: Dictionary,
) -> Array[Vector2i]:
	if not (field.get("costs", {}) as Dictionary).has(destination):
		return []
	var previous: Dictionary = field.get("previous", {})
	var reversed: Array[Vector2i] = [destination]
	var cursor := destination
	while cursor != start:
		if not previous.has(cursor):
			return []
		cursor = previous[cursor]
		reversed.append(cursor)
	reversed.reverse()
	return reversed


static func enemy_command(state: Dictionary) -> Dictionary:
	var actor_id := Combat.current_unit_id(state)
	var actor := Combat.unit_definition(state, actor_id)
	if str(actor.get("team", "")) != "enemy" or not actor.has("cell"):
		return Combat.enemy_command(state)
	var options: Array[Dictionary] = []
	var costs := reachable_cell_costs(state, actor_id)
	for raw_cell in costs:
		if not raw_cell is Vector2i:
			continue
		var cell := raw_cell as Vector2i
		var staged := stage_move(state, cell)
		if staged.is_empty():
			continue
		var path := movement_path(state, actor_id, cell)
		options.append({
			"state": staged,
			"destination": cell,
			"movementCost": int(costs.get(cell, 0)),
			"movementPath": path,
			"fallDamage": Terrain.path_fall_damage(state, path),
		})
	return Combat.enemy_command(state, options)


static func stage_move(state: Dictionary, destination: Vector2i) -> Dictionary:
	var actor_id := Combat.current_unit_id(state)
	if destination not in reachable_cells(state, actor_id):
		return {}
	var result := state.duplicate(true)
	var units: Dictionary = result.get("units", {})
	var actor: Dictionary = units.get(actor_id, {})
	actor["cell"] = destination
	units[actor_id] = actor
	result["units"] = units
	return result


static func command_preview(
	state: Dictionary,
	action_id: String,
	target_id: String,
	destination: Vector2i,
	secondary_cell: Vector2i = Combat.INVALID_CELL,
	target_cell: Vector2i = Combat.INVALID_CELL,
) -> Dictionary:
	var actor_id := Combat.current_unit_id(state)
	var actor := Combat.unit_definition(state, actor_id)
	var origin: Vector2i = actor.get("cell", Vector2i.ZERO)
	var staged := stage_move(state, destination)
	if staged.is_empty():
		return {"ok": false, "error": "Клетка недоступна для перемещения.", "summary": "Клетка недоступна для перемещения."}
	var resolved := Combat.preview(staged, action_id, target_id, secondary_cell, target_cell)
	if not bool(resolved.get("ok", false)):
		return resolved
	if destination != origin:
		var path := movement_path(state, actor_id, destination)
		var moves: Dictionary = resolved.get("moves", {})
		var action_moves_actor := moves.has(actor_id)
		if not action_moves_actor:
			moves[actor_id] = destination
		resolved["moves"] = moves
		var combined_path := path.duplicate()
		if action_moves_actor:
			for raw_cell in resolved.get("movementPath", []):
				if raw_cell is Vector2i and (
					combined_path.is_empty() or combined_path[-1] != raw_cell
				):
					combined_path.append(raw_cell)
		resolved["movementPath"] = combined_path
		_apply_fall_preview(state, resolved, actor_id, path)
		resolved["summary"] = Combat.describe_preview(staged, resolved)
		resolved["summary"] = "Перемещение: %s\n%s" % [
			_format_path(combined_path), str(resolved.get("summary", "")),
		]
	return resolved


static func supports_auto_approach(state: Dictionary, action_id: String) -> bool:
	var action := Combat.command_definition(state, action_id)
	return (
		state.has("grid")
		and not action.is_empty()
		and str(action.get("target", "")) == "enemy"
		and str(action.get("effect", "")) != "lift_throw"
		and str(action.get("partnerId", "")).is_empty()
		and not Combat.is_item_command(action_id)
	)


static func approach_target_ids(
	state: Dictionary,
	action_id: String,
	preferred_destination: Vector2i = Combat.INVALID_CELL,
) -> Array[String]:
	if not supports_auto_approach(state, action_id):
		var staged := stage_move(state, preferred_destination)
		return Combat.valid_target_ids(state if staged.is_empty() else staged, action_id)
	var result: Array[String] = []
	var actor_id := Combat.current_unit_id(state)
	var field := _navigation_field(state, actor_id)
	for raw_target_id in Combat.eligible_target_ids(state, action_id):
		var target_id := str(raw_target_id)
		if not _approach_plan_with_field(
			state, action_id, target_id, preferred_destination, field
		).is_empty():
			result.append(target_id)
	return result


static func approach_plan(
	state: Dictionary,
	action_id: String,
	target_id: String,
	preferred_destination: Vector2i = Combat.INVALID_CELL,
) -> Dictionary:
	if not supports_auto_approach(state, action_id):
		return {}
	if target_id not in Combat.eligible_target_ids(state, action_id):
		return {}
	var actor_id := Combat.current_unit_id(state)
	return _approach_plan_with_field(
		state, action_id, target_id, preferred_destination,
		_navigation_field(state, actor_id),
	)


static func _approach_plan_with_field(
	state: Dictionary,
	action_id: String,
	target_id: String,
	preferred_destination: Vector2i,
	field: Dictionary,
) -> Dictionary:
	var actor_id := Combat.current_unit_id(state)
	var actor := Combat.unit_definition(state, actor_id)
	var target := Combat.unit_definition(state, target_id)
	if actor.is_empty() or target.is_empty() or not actor.has("cell") or not target.has("cell"):
		return {}
	var origin: Vector2i = actor.get("cell", Vector2i.ZERO)
	var target_cell: Vector2i = target.get("cell", Combat.INVALID_CELL)
	var action := Combat.command_definition(state, action_id)
	var action_range := maxi(0, int(action.get("range", 0)))
	var costs: Dictionary = field.get("costs", {})
	var best_cell := Combat.INVALID_CELL
	var best_path: Array[Vector2i] = []
	var best_cost := 2147483647
	var best_fall := 2147483647
	for raw_cell in costs:
		if not raw_cell is Vector2i:
			continue
		var cell := raw_cell as Vector2i
		if (
			Terrain.action_distance(state, cell, target_cell) > action_range
			or not Terrain.has_line_of_sight(state, cell, target_cell)
		):
			continue
		var path := _path_from_field(origin, cell, field)
		if path.is_empty():
			continue
		var cost := int(costs.get(cell, 0))
		var fall := Terrain.path_fall_damage(state, path)
		var better := (
			cost < best_cost
			or (cost == best_cost and fall < best_fall)
			or (
				cost == best_cost
				and fall == best_fall
				and (best_cell == Combat.INVALID_CELL or cell_key(cell) < cell_key(best_cell))
			)
		)
		if better:
			best_cell = cell
			best_path = path
			best_cost = cost
			best_fall = fall
	if best_cell == Combat.INVALID_CELL or best_path.is_empty():
		return {}
	var move_range := maxi(0, int(actor.get("moveRange", 0)))
	var manual_destination := (
		preferred_destination != Combat.INVALID_CELL
		and preferred_destination != origin
	)
	var destination := best_cell
	var planned_path := best_path.duplicate()
	var will_execute := best_cost <= move_range
	if manual_destination:
		var manual_path := movement_path(state, actor_id, preferred_destination)
		if manual_path.is_empty():
			return {}
		destination = preferred_destination
		planned_path = manual_path
		var staged := stage_move(state, destination)
		will_execute = (
			not staged.is_empty()
			and target_id in Combat.valid_target_ids(staged, action_id)
		)
	elif not will_execute:
		var stop_index := mini(move_range, best_path.size() - 1)
		destination = best_path[stop_index]
		planned_path = best_path.slice(0, stop_index + 1)
	if not will_execute and _defend_action_id(state, actor_id).is_empty():
		return {}
	return {
		"ok": true,
		"actorId": actor_id,
		"targetId": target_id,
		"requestedActionId": action_id,
		"destination": destination,
		"attackPosition": best_cell,
		"movementPath": planned_path,
		"willExecute": will_execute,
		"fallbackDefend": not will_execute,
		"manualDestination": manual_destination,
		"fullDistance": best_cost,
		"moveRange": move_range,
	}


static func approach_command_preview(
	state: Dictionary,
	action_id: String,
	target_id: String,
	preferred_destination: Vector2i = Combat.INVALID_CELL,
) -> Dictionary:
	var plan := approach_plan(state, action_id, target_id, preferred_destination)
	if plan.is_empty():
		return {
			"ok": false,
			"error": "До подходящей позиции нет маршрута.",
			"summary": "До подходящей позиции нет маршрута.",
		}
	var actor_id := str(plan.get("actorId", ""))
	var destination: Vector2i = plan.get("destination", Combat.INVALID_CELL)
	var will_execute := bool(plan.get("willExecute", false))
	var resolved := (
		command_preview(state, action_id, target_id, destination)
		if will_execute
		else command_preview(state, _defend_action_id(state, actor_id), actor_id, destination)
	)
	if not bool(resolved.get("ok", false)):
		return resolved
	resolved["requestedActionId"] = action_id
	resolved["approachTargetId"] = target_id
	resolved["approachDestination"] = destination
	resolved["approachAttackPosition"] = plan.get("attackPosition", destination)
	resolved["approachPath"] = plan.get("movementPath", []).duplicate()
	resolved["approachWillExecute"] = will_execute
	resolved["approachFallbackDefend"] = not will_execute
	if not will_execute:
		var action_name := str(Combat.command_definition(state, action_id).get("name", action_id))
		var target_name := str(Combat.unit_definition(state, target_id).get("name", target_id))
		resolved["summary"] = (
			"Подход к %s: остановка %s. %s не достигает цели; применяется Защита.\n%s"
			% [target_name, cell_label(destination), action_name, str(resolved.get("summary", ""))]
		)
	return resolved


static func _defend_action_id(state: Dictionary, actor_id: String) -> String:
	var actor := Combat.unit_definition(state, actor_id)
	for raw_action_id in actor.get("actions", []):
		var candidate := str(raw_action_id)
		if str(Combat.command_definition(state, candidate).get("effect", "")) == "defend":
			return candidate
	return ""


static func occupant_id(state: Dictionary, cell: Vector2i, except_id: String = "") -> String:
	for raw_id in state.get("units", {}):
		var unit_id := str(raw_id)
		if unit_id == except_id:
			continue
		var unit := Combat.unit_definition(state, unit_id)
		if int(unit.get("hp", 0)) > 0 and unit.get("cell", Vector2i(-1, -1)) == cell:
			return unit_id
	return ""


static func cell_definition(state: Dictionary, cell: Vector2i) -> Dictionary:
	return Terrain.cell_definition(state, cell)


static func elevation(state: Dictionary, cell: Vector2i) -> int:
	return Terrain.elevation(state, cell)


static func focus_definition(state: Dictionary) -> Dictionary:
	return ((state.get("grid", {}) as Dictionary).get("focus", {}) as Dictionary).duplicate(true)


static func is_focus_cell(state: Dictionary, cell: Vector2i) -> bool:
	return focus_definition(state).get("cell", Vector2i(-1, -1)) == cell


static func active_focus_group(state: Dictionary) -> String:
	var focus := focus_definition(state)
	var cell: Vector2i = focus.get("cell", Vector2i(-1, -1))
	return str(cell_definition(state, cell).get("group", ""))


static func is_inside(state: Dictionary, cell: Vector2i) -> bool:
	var grid: Dictionary = state.get("grid", {})
	return (
		cell.x >= 0 and cell.y >= 0
		and cell.x < int(grid.get("width", WIDTH))
		and cell.y < int(grid.get("height", HEIGHT))
	)


static func is_blocked(state: Dictionary, cell: Vector2i) -> bool:
	return bool(cell_definition(state, cell).get("blocked", true))


static func cell_key(cell: Vector2i) -> String:
	return Terrain.cell_key(cell)


static func cell_label(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), cell.y + 1]


static func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i.LEFT,
		cell + Vector2i.RIGHT,
		cell + Vector2i.UP,
		cell + Vector2i.DOWN,
	]


static func _apply_fall_preview(
	state: Dictionary,
	resolved: Dictionary,
	unit_id: String,
	path: Array[Vector2i],
) -> void:
	var amount := Terrain.path_fall_damage(state, path)
	if amount <= 0:
		return
	var damage: Dictionary = resolved.get("damage", {})
	damage[unit_id] = int(damage.get(unit_id, 0)) + amount
	resolved["damage"] = damage
	resolved["fallDamage"] = amount
	(resolved.get("notes", []) as Array).append("Падение по пути наносит %d HP." % amount)


static func _format_path(path: Array[Vector2i]) -> String:
	var labels := PackedStringArray()
	for cell in path:
		labels.append(cell_label(cell))
	return " → ".join(labels)
