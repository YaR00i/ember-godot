class_name EmberCombatTerrain
extends RefCounted
## Pure semantic terrain helpers shared by movement, elemental resolution and
## future 3D projection. Geometry never becomes the combat rules owner.

const MAX_STEP_HEIGHT := 1
const SAFE_FALL_HEIGHT := 1
const FALL_DAMAGE_PER_LEVEL := 2


static func cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


static func world_edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		return cell_key(b) + "|" + cell_key(a)
	return cell_key(a) + "|" + cell_key(b)


static func world_edge_blocked(state: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var edges: Dictionary = state.get("fieldGeometry", {}).get("edges", {})
	if edges.is_empty():
		return false
	if from_cell.x == to_cell.x or from_cell.y == to_cell.y:
		return edges.has(world_edge_key(from_cell, to_cell))
	var cross_x := Vector2i(to_cell.x, from_cell.y)
	var cross_z := Vector2i(from_cell.x, to_cell.y)
	return edges.has(world_edge_key(from_cell, cross_x)) or edges.has(world_edge_key(cross_x, to_cell)) \
		or edges.has(world_edge_key(from_cell, cross_z)) or edges.has(world_edge_key(cross_z, to_cell))


static func cell_definition(state: Dictionary, cell: Vector2i) -> Dictionary:
	var definition := (((state.get("grid", {}) as Dictionary).get("cells", {}) as Dictionary).get(
		cell_key(cell), {}
	) as Dictionary).duplicate(true)
	var gate: Dictionary = state.get("pressureGate", {})
	if not definition.is_empty() and gate.get("gateCell") == cell:
		definition["blocked"] = not preload("res://scripts/ember_combat_world_items.gd").pressure_gate_open(state)
	if state.get("fieldGeometry", {}).get("blocked", {}).has(cell):
		definition["blocked"] = true
	var levels: Dictionary = state.get("fieldGeometry", {}).get("levels", {})
	if levels.has(cell):
		definition["elevation"] = levels[cell]
	return definition


static func elevation(state: Dictionary, cell: Vector2i) -> int:
	return int(cell_definition(state, cell).get("elevation", 0))


static func can_step(
	state: Dictionary,
	from_cell: Vector2i,
	to_cell: Vector2i,
	jump_height: int = MAX_STEP_HEIGHT,
) -> bool:
	## Going up is limited by the unit's Jump. A downward step remains legal so
	## the same path can preview a fall instead of silently making cliffs walls.
	return not world_edge_blocked(state, from_cell, to_cell) and (
		elevation(state, to_cell) - elevation(state, from_cell) <= maxi(0, jump_height)
		or state.get("fieldGeometry", {}).get("walkEdges", {}).has(world_edge_key(from_cell, to_cell))
	)


static func can_force_move(state: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	## Pushes and throws can cross a ledge downward, but never shove a target up a
	## vertical wall. Occupancy and map bounds stay with the grid owner.
	return not world_edge_blocked(state, from_cell, to_cell) and elevation(state, to_cell) <= elevation(state, from_cell)


static func fall_height(state: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> int:
	if state.get("fieldGeometry", {}).get("walkEdges", {}).has(world_edge_key(from_cell, to_cell)):
		return 0
	return maxi(0, elevation(state, from_cell) - elevation(state, to_cell))


static func fall_damage(state: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> int:
	return maxi(0, fall_height(state, from_cell, to_cell) - SAFE_FALL_HEIGHT) * FALL_DAMAGE_PER_LEVEL


static func path_fall_damage(state: Dictionary, path: Array[Vector2i]) -> int:
	var result := 0
	for index in range(1, path.size()):
		result += fall_damage(state, path[index - 1], path[index])
	return result


static func action_distance(state: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> int:
	var planar := absi(from_cell.x - to_cell.x) + absi(from_cell.y - to_cell.y)
	## One elevation level is the normal height of an adjacent step. Larger
	## differences consume range and therefore remain visible in exact preview.
	return planar + maxi(0, absi(elevation(state, from_cell) - elevation(state, to_cell)) - 1)


static func has_line_of_sight(state: Dictionary, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if from_cell == to_cell:
		return true
	var cells := line_cells(from_cell, to_cell)
	if not state.get("fieldGeometry", {}).get("edges", {}).is_empty():
		for index in range(1, cells.size()):
			if world_edge_blocked(state, cells[index - 1], cells[index]):
				return false
	if cells.size() <= 2:
		return true
	var start_eye := float(elevation(state, from_cell)) + 1.0
	var end_eye := float(elevation(state, to_cell)) + 1.0
	for index in range(1, cells.size() - 1):
		var cell := cells[index]
		var ratio := float(index) / float(cells.size() - 1)
		var sight_height := lerpf(start_eye, end_eye, ratio)
		var definition := cell_definition(state, cell)
		var obstacle_height := float(definition.get("elevation", 0))
		if bool(definition.get("blocked", false)):
			obstacle_height += 2.0
		if obstacle_height >= sight_height - 0.001:
			return false
	return true


static func line_cells(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	## Deterministic grid DDA. This is shared by player preview and AI rather than
	## consulting rendered meshes or PhysicsServer state.
	var result: Array[Vector2i] = []
	var steps := maxi(absi(to_cell.x - from_cell.x), absi(to_cell.y - from_cell.y))
	if steps <= 0:
		return [from_cell]
	for index in range(steps + 1):
		var ratio := float(index) / float(steps)
		var cell := Vector2i(
			roundi(lerpf(float(from_cell.x), float(to_cell.x), ratio)),
			roundi(lerpf(float(from_cell.y), float(to_cell.y), ratio)),
		)
		if result.is_empty() or result[-1] != cell:
			result.append(cell)
	return result


static func tags_after(
	state: Dictionary,
	cell: Vector2i,
	add_tags: Array[String],
	remove_tags: Array[String] = [],
) -> Array[String]:
	var result: Array[String] = []
	for raw_tag in cell_definition(state, cell).get("tags", []):
		var tag := str(raw_tag)
		if tag not in remove_tags and tag not in result:
			result.append(tag)
	for tag in add_tags:
		if tag not in result:
			result.append(tag)
	return result


static func apply_cell_changes(state: Dictionary, raw_changes: Variant) -> Dictionary:
	var result := state.duplicate(true)
	if typeof(raw_changes) != TYPE_DICTIONARY or not result.has("grid"):
		return result
	var grid: Dictionary = result.get("grid", {}).duplicate(true)
	var cells: Dictionary = grid.get("cells", {}).duplicate(true)
	for raw_key in raw_changes:
		var key := str(raw_key)
		var patch: Dictionary = (raw_changes as Dictionary).get(raw_key, {})
		if not cells.has(key) or patch.is_empty():
			continue
		var definition: Dictionary = (cells.get(key, {}) as Dictionary).duplicate(true)
		for raw_field in patch:
			var field := str(raw_field)
			if field == "cell":
				continue
			definition[field] = patch[raw_field]
		cells[key] = definition
	grid["cells"] = cells
	result["grid"] = grid
	return result
