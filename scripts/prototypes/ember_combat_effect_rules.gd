extends RefCounted
## Internal pure rules for reusable effect steps and battlefield mutations.
## EmberCombatPrototype remains the only public preview/commit resolver.

const Terrain := preload("res://scripts/prototypes/ember_combat_terrain.gd")
const StatusRules := preload("res://scripts/prototypes/ember_combat_status_rules.gd")
const DamageRules := preload("res://scripts/prototypes/ember_combat_damage_rules.gd")
const INVALID_CELL := Vector2i(-999999, -999999)


static func set_push(
	state: Dictionary,
	resolved: Dictionary,
	actor: Dictionary,
	target: Dictionary,
	force: int,
) -> void:
	if force <= int(target.get("pushResistance", 0)):
		(resolved.get("notes", []) as Array).append("Устойчивость цели блокирует отбрасывание.")
		return
	if state.has("grid") and actor.has("cell") and target.has("cell"):
		var actor_cell: Vector2i = actor.get("cell", Vector2i.ZERO)
		var target_cell: Vector2i = target.get("cell", Vector2i.ZERO)
		var delta := target_cell - actor_cell
		var direction := Vector2i.ZERO
		if absi(delta.x) >= absi(delta.y) and delta.x != 0:
			direction.x = signi(delta.x)
		elif delta.y != 0:
			direction.y = signi(delta.y)
		var destination := target_cell + direction
		if (
			direction != Vector2i.ZERO
			and _grid_inside(state, destination)
			and not bool(_grid_cell_definition(state, destination).get("blocked", true))
			and Terrain.can_force_move(state, target_cell, destination)
			and _grid_occupant(state, destination).is_empty()
		):
			var moves: Dictionary = resolved.get("moves", {})
			moves[str(target.get("id", ""))] = destination
			resolved["moves"] = moves
			var fall := Terrain.fall_damage(state, target_cell, destination)
			if fall > 0:
				DamageRules.add_damage(resolved, str(target.get("id", "")), fall)
				resolved["fallDamage"] = int(resolved.get("fallDamage", 0)) + fall
				(resolved.get("notes", []) as Array).append(
					"Столкновение с края наносит %d HP." % fall
				)
		return
	var actor_zone := int(actor.get("zone", 0))
	var target_zone := int(target.get("zone", 0))
	var direction := 1 if target_zone >= actor_zone else -1
	var zone_count := maxi(1, (state.get("zones", []) as Array).size())
	var destination := clampi(target_zone + direction, 0, zone_count - 1)
	if destination != target_zone:
		var moves: Dictionary = resolved.get("moves", {})
		moves[str(target.get("id", ""))] = destination
		resolved["moves"] = moves


static func shares_conduction_area(state: Dictionary, first: Dictionary, second: Dictionary) -> bool:
	if state.has("grid") and first.has("cell") and second.has("cell"):
		var first_group := str(_grid_cell_definition(state, first.get("cell", Vector2i.ZERO)).get("group", ""))
		var second_group := str(_grid_cell_definition(state, second.get("cell", Vector2i.ZERO)).get("group", ""))
		return not first_group.is_empty() and first_group == second_group
	return int(first.get("zone", -1)) == int(second.get("zone", -2))


static func field_power_bonus(state: Dictionary, actor: Dictionary, element: String) -> int:
	if element != "fire" or not state.has("grid") or not actor.has("cell"):
		return 0
	var grid: Dictionary = state.get("grid", {})
	var focus: Dictionary = grid.get("focus", {})
	if str(focus.get("effect", "")) != "fire_power":
		return 0
	var focus_group := str(_grid_cell_definition(
		state, focus.get("cell", Vector2i(-1, -1))
	).get("group", ""))
	var actor_group := str(_grid_cell_definition(
		state, actor.get("cell", Vector2i(-1, -1))
	).get("group", ""))
	if focus_group.is_empty() or focus_group != actor_group:
		return 0
	return maxi(0, int(focus.get("bonus", 0)))


static func linked_surface_cells(state: Dictionary, origin: Vector2i) -> Array[Vector2i]:
	var origin_group := str(_grid_cell_definition(state, origin).get("group", ""))
	var affected: Array[Vector2i] = []
	if origin_group.is_empty():
		affected.append(origin)
	else:
		var grid: Dictionary = state.get("grid", {})
		for raw_key in (grid.get("cells", {}) as Dictionary):
			var definition: Dictionary = (grid.get("cells", {}) as Dictionary).get(raw_key, {})
			if str(definition.get("group", "")) != origin_group:
				continue
			var parts := str(raw_key).split(":")
			if parts.size() == 2:
				affected.append(Vector2i(int(parts[0]), int(parts[1])))
	return affected


static func set_cell_tags(
	state: Dictionary,
	resolved: Dictionary,
	cell: Vector2i,
	add_tags: Array[String],
	remove_tags: Array[String],
) -> void:
	var changes: Dictionary = resolved.get("cellChanges", {})
	var key := Terrain.cell_key(cell)
	var patch: Dictionary = (changes.get(key, {}) as Dictionary).duplicate(true)
	var tags: Array[String] = []
	var source_tags: Array = patch.get("tags", _grid_cell_definition(state, cell).get("tags", []))
	for raw_tag in source_tags:
		var tag := str(raw_tag)
		if tag not in remove_tags and tag not in tags:
			tags.append(tag)
	for tag in add_tags:
		if tag not in tags:
			tags.append(tag)
	patch["cell"] = cell
	patch["tags"] = tags
	changes[key] = patch
	resolved["cellChanges"] = changes


static func change_linked_surface(
	state: Dictionary,
	resolved: Dictionary,
	origin: Vector2i,
	add_tags: Array[String],
	remove_tags: Array[String],
) -> void:
	for cell in linked_surface_cells(state, origin):
		set_cell_tags(state, resolved, cell, add_tags, remove_tags)


static func effect_steps_apply_to_cell(state: Dictionary, action: Dictionary, cell: Vector2i) -> bool:
	var effects: Array = action.get("effects", [])
	if effects.is_empty() or not _grid_inside(state, cell):
		return false
	var definition := _grid_cell_definition(state, cell)
	var occupant_id := _grid_occupant(state, cell)
	for raw_effect in effects:
		var effect := raw_effect as Dictionary
		match str(effect.get("operation", "")):
			"apply_status", "push":
				if occupant_id.is_empty():
					return false
			"remove_status":
				if occupant_id.is_empty():
					return false
				var occupant := _unit_definition(state, occupant_id)
				var has_removable := false
				for raw_status in effect.get("removeStatusIds", []):
					if StatusRules.has(occupant, str(raw_status)):
						has_removable = true
						break
				if not has_removable:
					return false
			"cell_patch":
				if _is_grid_focus_cell(state, cell):
					return false
				var block_mode := str(effect.get("blockMode", "keep"))
				if block_mode == "block" and (bool(definition.get("blocked", false)) or not occupant_id.is_empty()):
					return false
				if block_mode == "open" and not bool(definition.get("blocked", false)):
					return false
				var next_elevation := int(definition.get("elevation", 0)) + int(effect.get("elevationDelta", 0))
				if next_elevation < 0 or next_elevation > 16:
					return false
			"spread":
				if not _spread_source_available(state, cell, effect):
					return false
			"move_actor":
				var actor := _unit_definition(state, _current_unit_id(state))
				var actor_cell: Vector2i = actor.get("cell", INVALID_CELL)
				if (
					bool(definition.get("blocked", false))
					or not occupant_id.is_empty()
					or _is_grid_focus_cell(state, cell)
					or cell == actor_cell
					or absi(int(definition.get("elevation", 0)) - int(_grid_cell_definition(state, actor_cell).get("elevation", 0))) > int(effect.get("moveMaxHeightDelta", 0))
				):
					return false
			"activate_focus":
				if not _is_grid_focus_cell(state, cell) or "activated" in definition.get("tags", []):
					return false
	return true


static func apply_authored_effects(
	state: Dictionary,
	resolved: Dictionary,
	actor: Dictionary,
	target: Dictionary,
	action: Dictionary,
	target_cell: Vector2i,
) -> void:
	var cell := target_cell
	if cell == INVALID_CELL and not target.is_empty():
		cell = target.get("cell", INVALID_CELL)
	for raw_effect in action.get("effects", []):
		var effect := raw_effect as Dictionary
		var effect_name := str(effect.get("name", effect.get("id", "Эффект")))
		match str(effect.get("operation", "")):
			"apply_status":
				if not target.is_empty():
					StatusRules.set_hostile_status(resolved, target, str(effect.get("statusId", "")), int(effect.get("statusDuration", 1)))
			"remove_status":
				if not target.is_empty():
					for raw_status in effect.get("removeStatusIds", []):
						StatusRules.remove_status(resolved, str(target.get("id", "")), str(raw_status))
			"push":
				if not target.is_empty():
					set_push(state, resolved, actor, target, int(effect.get("force", 0)))
			"cell_patch":
				_apply_cell_patch_effect(state, resolved, cell, effect)
			"spread":
				_apply_spread_effect(state, resolved, cell, effect)
			"restore_hp":
				if not target.is_empty():
					var target_id := str(target.get("id", ""))
					var healed := mini(int(target.get("maxHp", 1)), int(target.get("hp", 0)) + int(effect.get("restoreHpAmount", 0)))
					(resolved["restoreHp"] as Dictionary)[target_id] = healed
			"move_actor":
				_apply_actor_move_effect(state, resolved, actor, cell)
			"activate_focus":
				set_cell_tags(state, resolved, cell, ["activated"], [])
				(resolved.get("notes", []) as Array).append("Узел %s активирован дистанционно." % _cell_label(cell))
		if str(resolved.get("reaction", "")).is_empty():
			resolved["reaction"] = effect_name


static func authored_effects_allow_unit_target(action: Dictionary, target: Dictionary) -> bool:
	for raw_effect in action.get("effects", []):
		var effect := raw_effect as Dictionary
		if str(effect.get("operation", "")) == "restore_hp" and int(target.get("hp", 0)) >= int(target.get("maxHp", 1)):
			return false
	return true


static func _apply_actor_move_effect(state: Dictionary, resolved: Dictionary, actor: Dictionary, destination: Vector2i) -> void:
	if destination == INVALID_CELL:
		return
	var actor_id := str(actor.get("id", ""))
	var origin: Vector2i = actor.get("cell", INVALID_CELL)
	var moves: Dictionary = resolved.get("moves", {})
	moves[actor_id] = destination
	resolved["moves"] = moves
	resolved["movementPath"] = [origin, destination]
	var fall := Terrain.fall_damage(state, origin, destination)
	if fall > 0:
		DamageRules.add_fixed_damage(resolved, actor_id, fall)
		resolved["fallDamage"] = int(resolved.get("fallDamage", 0)) + fall
		(resolved.get("notes", []) as Array).append("Приземление ниже наносит %d HP." % fall)


static func _apply_cell_patch_effect(state: Dictionary, resolved: Dictionary, cell: Vector2i, effect: Dictionary) -> void:
	if cell == INVALID_CELL or not _grid_inside(state, cell):
		return
	var changes: Dictionary = resolved.get("cellChanges", {})
	var key := Terrain.cell_key(cell)
	var patch: Dictionary = (changes.get(key, {}) as Dictionary).duplicate(true)
	var definition := _grid_cell_definition(state, cell)
	patch["cell"] = cell
	var elevation_delta := int(effect.get("elevationDelta", 0))
	if elevation_delta != 0:
		patch["elevation"] = clampi(int(patch.get("elevation", definition.get("elevation", 0))) + elevation_delta, 0, 16)
	var block_mode := str(effect.get("blockMode", "keep"))
	if block_mode != "keep":
		patch["blocked"] = block_mode == "block"
	var tags: Array[String] = []
	for raw_tag in patch.get("tags", definition.get("tags", [])):
		var tag := str(raw_tag)
		if tag not in effect.get("removeCellTags", []) and tag not in tags:
			tags.append(tag)
	for raw_tag in effect.get("addCellTags", []):
		var tag := str(raw_tag)
		if tag not in tags:
			tags.append(tag)
	if not effect.get("addCellTags", []).is_empty() or not effect.get("removeCellTags", []).is_empty():
		patch["tags"] = tags
	changes[key] = patch
	resolved["cellChanges"] = changes
	(resolved.get("notes", []) as Array).append("%s изменяет клетку %s до конца боя." % [str(effect.get("name", "Эффект земли")), _cell_label(cell)])


static func _apply_spread_effect(state: Dictionary, resolved: Dictionary, source_cell: Vector2i, effect: Dictionary) -> void:
	if source_cell == INVALID_CELL or not _grid_inside(state, source_cell):
		return
	var source_statuses := _spread_source_statuses(state, resolved, source_cell, effect)
	var source_tags := _spread_source_tags(state, resolved, source_cell, effect)
	if source_statuses.is_empty() and source_tags.is_empty():
		return
	var radius := maxi(1, int(effect.get("spreadRadius", 1)))
	var affected_cells := 0
	var affected_units := 0
	var grid: Dictionary = state.get("grid", {})
	for y in int(grid.get("height", 0)):
		for x in int(grid.get("width", 0)):
			var cell := Vector2i(x, y)
			if cell == source_cell or Terrain.action_distance(state, source_cell, cell) > radius:
				continue
			if bool(effect.get("spreadToCells", true)) and not source_tags.is_empty() and not bool(_grid_cell_definition(state, cell).get("blocked", false)):
				set_cell_tags(state, resolved, cell, source_tags, [])
				affected_cells += 1
			if not bool(effect.get("spreadToUnits", true)):
				continue
			var target_id := _grid_occupant(state, cell)
			if target_id.is_empty():
				continue
			var target := _unit_definition(state, target_id)
			for status_id in source_statuses:
				var duration := _spread_source_duration(state, resolved, source_cell, status_id, int(effect.get("spreadStatusDuration", 2)))
				if StatusRules.duration_after_preview(state, resolved, target_id, status_id) >= duration:
					continue
				if StatusRules.set_hostile_status(resolved, target, status_id, duration):
					affected_units += 1
	(resolved.get("notes", []) as Array).append("Ветер распространяет стихию: %d клеток, %d наложений на бойцов." % [affected_cells, affected_units])


static func _spread_source_available(state: Dictionary, cell: Vector2i, effect: Dictionary) -> bool:
	return not _spread_source_statuses(state, {}, cell, effect).is_empty() or not _spread_source_tags(state, {}, cell, effect).is_empty()


static func _spread_source_statuses(state: Dictionary, resolved: Dictionary, cell: Vector2i, effect: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var occupant_id := _grid_occupant(state, cell)
	if occupant_id.is_empty():
		return result
	for raw_status in effect.get("spreadStatusIds", []):
		var status_id := str(raw_status)
		if StatusRules.duration_after_preview(state, resolved, occupant_id, status_id) > 0:
			result.append(status_id)
	return result


static func _spread_source_tags(state: Dictionary, resolved: Dictionary, cell: Vector2i, effect: Dictionary) -> Array[String]:
	var current: Array = _grid_cell_definition(state, cell).get("tags", [])
	var patch: Dictionary = (resolved.get("cellChanges", {}) as Dictionary).get(Terrain.cell_key(cell), {})
	var tags: Array = patch.get("tags", current)
	var result: Array[String] = []
	for raw_tag in effect.get("spreadCellTags", []):
		var tag := str(raw_tag)
		if tag in tags:
			result.append(tag)
	return result


static func _spread_source_duration(state: Dictionary, resolved: Dictionary, cell: Vector2i, status_id: String, fallback: int) -> int:
	var occupant_id := _grid_occupant(state, cell)
	var copied := StatusRules.duration_after_preview(state, resolved, occupant_id, status_id) if not occupant_id.is_empty() else 0
	return maxi(1, copied if copied > 0 else fallback)


static func _unit_definition(state: Dictionary, unit_id: String) -> Dictionary:
	return ((state.get("units", {}) as Dictionary).get(unit_id, {}) as Dictionary).duplicate(true)


static func _current_unit_id(state: Dictionary) -> String:
	var best_id := ""
	var best_at := INF
	var holds: Dictionary = state.get("holds", {})
	var held_ids: Array = holds.values()
	for raw_id in state.get("units", {}):
		var unit_id := str(raw_id)
		var unit := _unit_definition(state, unit_id)
		if int(unit.get("hp", 0)) <= 0 or unit_id in held_ids:
			continue
		var next_at := float(unit.get("nextAt", 0.0))
		if next_at < best_at or (is_equal_approx(next_at, best_at) and unit_id < best_id):
			best_at = next_at
			best_id = unit_id
	return best_id


static func _grid_cell_definition(state: Dictionary, cell: Vector2i) -> Dictionary:
	return Terrain.cell_definition(state, cell)


static func _grid_inside(state: Dictionary, cell: Vector2i) -> bool:
	var grid: Dictionary = state.get("grid", {})
	return cell.x >= 0 and cell.y >= 0 and cell.x < int(grid.get("width", 0)) and cell.y < int(grid.get("height", 0))


static func _grid_occupant(state: Dictionary, cell: Vector2i) -> String:
	for raw_id in state.get("units", {}):
		var unit := _unit_definition(state, str(raw_id))
		if int(unit.get("hp", 0)) > 0 and unit.get("cell", Vector2i(-1, -1)) == cell:
			return str(raw_id)
	return ""


static func _is_grid_focus_cell(state: Dictionary, cell: Vector2i) -> bool:
	return ((state.get("grid", {}) as Dictionary).get("focus", {}) as Dictionary).get("cell", INVALID_CELL) == cell


static func _cell_label(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), cell.y + 1]
