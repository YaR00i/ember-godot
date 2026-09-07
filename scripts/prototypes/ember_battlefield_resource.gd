@tool
class_name EmberBattlefieldResource
extends Resource
## Authored semantic cell data for one battle arena. Rendering and combat
## resolver both consume to_grid_dictionary(); GridMap never owns legality.

const SurfaceMesher := preload("res://scripts/ember_voxel_surface_mesher.gd")
const BattleSurfaceProjection := preload("res://scripts/ember_battle_surface_projection.gd")

enum TerrainKind {
	NEUTRAL,
	WET,
	EMBER,
	FROZEN,
}

enum PaintTool {
	NEUTRAL,
	WET,
	EMBER,
	FROZEN,
	BLOCKED,
	HEIGHT_UP,
	HEIGHT_DOWN,
	FOCUS,
	PARTY_DEPLOYMENT,
	ENEMY_DEPLOYMENT,
}

enum ResizeAnchor {
	TOP_LEFT,
	TOP_CENTER,
	TOP_RIGHT,
	MIDDLE_LEFT,
	CENTER,
	MIDDLE_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_CENTER,
	BOTTOM_RIGHT,
}

@export_group("Поле боя")
@export var field_id := "battlefield"
@export var display_name := "Новое поле боя"
@export_multiline var preview_intro := ""
@export_range(1, 64, 1) var width := 7
@export_range(1, 64, 1) var height := 5
## Optional authored art surface. Gameplay legality and pathfinding remain in
## the semantic arrays below; small sculpted chips never alter battle rules.
@export var visual_surface: EmberVoxelModelResource

@export_group("Данные клеток · построчно")
## TerrainKind for each cell, ordered left-to-right and top-to-bottom.
@export var terrain_kinds := PackedByteArray()
## Integer gameplay elevation for each cell in the same order.
@export var elevations := PackedInt32Array()
## 0 = walkable, 1 = blocked, in the same order.
@export var blocked := PackedByteArray()
## Optional linked-panel group ID for each cell in the same order.
@export var groups := PackedStringArray()

@export_group("Фокус поля")
@export var focus_id := "ember_focus"
@export var focus_name := "Жар-фокус"
@export var focus_cell := Vector2i(3, 3)
@export var focus_effect := "fire_power"
@export var focus_bonus := 2

@export_group("Расстановка")
## Ordered start cells. The current lab assigns hero/enemy definitions in their
## canonical order; the future Encounter Resource will bind explicit unit slots.
@export var party_deployment_cells: Array[Vector2i] = []
@export var enemy_deployment_cells: Array[Vector2i] = []


func cell_count() -> int:
	return maxi(0, width) * maxi(0, height)


func cell_index(cell: Vector2i) -> int:
	return cell.y * width + cell.x


func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func visual_surface_matches_field() -> bool:
	return (
		visual_surface != null
		and visual_surface.size_blocks.x == width
		and visual_surface.size_blocks.z == height
	)


func cell_definition(cell: Vector2i) -> Dictionary:
	if not contains(cell):
		return {"blocked": true, "elevation": 0, "group": "", "tags": []}
	var index := cell_index(cell)
	var terrain := int(terrain_kinds[index]) if index < terrain_kinds.size() else TerrainKind.NEUTRAL
	var tags: Array[String] = []
	if terrain == TerrainKind.WET:
		tags.append("wet")
	elif terrain == TerrainKind.FROZEN:
		tags.append("frozen")
	return {
		"terrain": terrain,
		"group": str(groups[index]) if index < groups.size() else "",
		"tags": tags,
		"blocked": index < blocked.size() and int(blocked[index]) != 0,
		"elevation": int(elevations[index]) if index < elevations.size() else 0,
	}


func to_grid_dictionary() -> Dictionary:
	var cells := {}
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			cells[cell_key(cell)] = cell_definition(cell)
	return {
		"width": width,
		"height": height,
		"cells": cells,
		"focus": {
			"id": focus_id,
			"name": focus_name,
			"cell": focus_cell,
			"effect": focus_effect,
			"bonus": focus_bonus,
		},
		"deployment": {
			"party": party_deployment_cells.duplicate(),
			"enemy": enemy_deployment_cells.duplicate(),
		},
	}


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if field_id.strip_edges().is_empty():
		errors.append("У поля нет устойчивого ID.")
	if width <= 0 or height <= 0:
		errors.append("Размер поля должен быть положительным.")
	var expected := cell_count()
	_validate_array_size("Типы поверхности", terrain_kinds.size(), expected, errors)
	_validate_array_size("Высоты", elevations.size(), expected, errors)
	_validate_array_size("Преграды", blocked.size(), expected, errors)
	_validate_array_size("Группы панелей", groups.size(), expected, errors)
	for index in mini(terrain_kinds.size(), expected):
		var kind := int(terrain_kinds[index])
		if kind < TerrainKind.NEUTRAL or kind > TerrainKind.FROZEN:
			errors.append("Клетка %d содержит неизвестный тип поверхности %d." % [index, kind])
	for index in mini(elevations.size(), expected):
		if int(elevations[index]) < 0:
			errors.append("Клетка %d имеет отрицательную высоту." % index)
	for index in mini(blocked.size(), expected):
		if int(blocked[index]) != 0 and int(blocked[index]) != 1:
			errors.append("Клетка %d: преграда должна быть 0 или 1." % index)
	if not contains(focus_cell):
		errors.append("Фокус поля находится за границей карты.")
	elif bool(cell_definition(focus_cell).get("blocked", false)):
		errors.append("Фокус поля не может стоять на преграде.")
	_validate_deployments("Герои", party_deployment_cells, errors)
	_validate_deployments("Враги", enemy_deployment_cells, errors)
	for cell in party_deployment_cells:
		if cell in enemy_deployment_cells:
			errors.append("Клетка %s одновременно занята точкой героев и врагов." % cell_label(cell))
	return errors


func content_signature() -> String:
	return "%s|%dx%d|%s|%s|%s|%s|%s|%s|%s|%d|%s|%s" % [
		field_id, width, height, terrain_kinds, elevations, blocked, groups,
		focus_id, focus_cell, focus_effect, focus_bonus,
		party_deployment_cells, enemy_deployment_cells,
	]


func terrain_count(kind: int) -> int:
	var count := 0
	for value in terrain_kinds:
		if int(value) == kind:
			count += 1
	return count


func authoring_snapshot() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"terrain_kinds": terrain_kinds.duplicate(),
		"elevations": elevations.duplicate(),
		"blocked": blocked.duplicate(),
		"groups": groups.duplicate(),
		"focus_cell": focus_cell,
		"party_deployment_cells": party_deployment_cells.duplicate(),
		"enemy_deployment_cells": enemy_deployment_cells.duplicate(),
	}


func surface_water_sync_preview(minimum_coverage := 0.25) -> Dictionary:
	## Visual water is an authoring suggestion, never a second runtime rule owner.
	## One battle cell covers density² art columns; an explicit editor action may
	## copy the thresholded result into canonical terrain_kinds.
	if visual_surface == null:
		return {"ok": false, "error": "У поля не назначена Visual Surface."}
	if terrain_kinds.size() != cell_count() or groups.size() != cell_count():
		return {"ok": false, "error": "Сначала исправьте массивы клеток Battlefield Resource."}
	if not visual_surface_matches_field():
		return {
			"ok": false,
			"error": "Размер Visual Surface не совпадает с полем %dx%d." % [width, height],
		}
	var density := visual_surface.normalized_density()
	var art_size := visual_surface.grid_size()
	var coverage_counts := PackedInt32Array()
	coverage_counts.resize(cell_count())
	coverage_counts.fill(0)
	for art_z in art_size.z:
		for art_x in art_size.x:
			if SurfaceMesher.water_height_at(visual_surface, Vector2i(art_x, art_z)) < 0:
				continue
			var battle_x := mini(width - 1, floori(float(art_x) / float(density)))
			var battle_y := mini(height - 1, floori(float(art_z) / float(density)))
			coverage_counts[cell_index(Vector2i(battle_x, battle_y))] += 1
	var threshold := clampf(minimum_coverage, 0.01, 1.0)
	var columns_per_cell := density * density
	var after := authoring_snapshot()
	var next_terrain: PackedByteArray = after["terrain_kinds"]
	var next_groups: PackedStringArray = after["groups"]
	var wet_cells: Array[Vector2i] = []
	var changed_cells: Array[Vector2i] = []
	var protected_cells: Array[Vector2i] = []
	var coverage := PackedFloat32Array()
	coverage.resize(cell_count())
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			var index := cell_index(cell)
			var ratio := float(coverage_counts[index]) / float(columns_per_cell)
			coverage[index] = ratio
			var should_be_wet := ratio >= threshold
			var current := int(next_terrain[index])
			if should_be_wet:
				wet_cells.append(cell)
				if current in [TerrainKind.EMBER, TerrainKind.FROZEN]:
					protected_cells.append(cell)
					continue
				if current != TerrainKind.WET:
					next_terrain[index] = TerrainKind.WET
					if next_groups[index].strip_edges().is_empty():
						next_groups[index] = "tide"
					changed_cells.append(cell)
			elif current == TerrainKind.WET:
				next_terrain[index] = TerrainKind.NEUTRAL
				next_groups[index] = ""
				changed_cells.append(cell)
	after["terrain_kinds"] = next_terrain
	after["groups"] = next_groups
	return {
		"ok": true,
		"snapshot": after,
		"threshold": threshold,
		"coverage": coverage,
		"wet_cells": wet_cells,
		"changed_cells": changed_cells,
		"protected_cells": protected_cells,
	}


func surface_height_sync_preview() -> Dictionary:
	## Fine sculpt remains visual until the author confirms this quantized coarse
	## projection. Median top height ignores isolated pebbles and small chips.
	var report := BattleSurfaceProjection.height_preview(
		visual_surface, width, height, elevations
	)
	if not bool(report.get("ok", false)):
		return report
	var snapshot := authoring_snapshot()
	snapshot["elevations"] = report["elevations"]
	report["snapshot"] = snapshot
	return report


func resize_preview(new_width: int, new_height: int, anchor: int) -> Dictionary:
	if new_width < 1 or new_width > 64 or new_height < 1 or new_height > 64:
		return {"ok": false, "errors": ["Размер должен быть от 1 до 64 клеток."]}
	if terrain_kinds.size() != cell_count() or elevations.size() != cell_count():
		return {"ok": false, "errors": ["Сначала исправьте длину массивов клеток."]}
	if blocked.size() != cell_count() or groups.size() != cell_count():
		return {"ok": false, "errors": ["Сначала исправьте длину массивов клеток."]}
	var offset := _resize_offset(new_width, new_height, anchor)
	var after := _resized_authoring_snapshot(new_width, new_height, offset)
	var kept_cells := 0
	for y in height:
		for x in width:
			var mapped := Vector2i(x, y) + offset
			if mapped.x >= 0 and mapped.y >= 0 and mapped.x < new_width and mapped.y < new_height:
				kept_cells += 1
	var party_after: Array[Vector2i] = after.get("party_deployment_cells", [])
	var enemy_after: Array[Vector2i] = after.get("enemy_deployment_cells", [])
	var errors: Array[String] = []
	if party_after.is_empty():
		errors.append("После обрезки не останется ни одной точки героев.")
	if enemy_after.is_empty():
		errors.append("После обрезки не останется ни одной точки врагов.")
	if after.get("focus_cell", Vector2i(-1, -1)) == Vector2i(-1, -1):
		errors.append("После обрезки не осталось клетки для фокуса.")
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"snapshot": after,
		"offset": offset,
		"kept_cells": kept_cells,
		"lost_cells": cell_count() - kept_cells,
		"new_cells": new_width * new_height - kept_cells,
		"party_lost": party_deployment_cells.size() - party_after.size(),
		"enemy_lost": enemy_deployment_cells.size() - enemy_after.size(),
		"focus_moved": after.get("focus_cell", focus_cell) != focus_cell,
	}


func edited_cell_snapshot(cell: Vector2i, tool: int, requested_group := "") -> Dictionary:
	return edited_cells_snapshot([cell], tool, requested_group)


func edited_cells_snapshot(cells: Array[Vector2i], tool: int, requested_group := "") -> Dictionary:
	if cells.is_empty() or not validation_errors().is_empty():
		return {}
	var snapshot := authoring_snapshot()
	var changed := false
	for cell in cells:
		if not contains(cell):
			continue
		changed = _edit_snapshot_cell(snapshot, cell, tool, requested_group) or changed
	return snapshot if changed else {}


func rectangle_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not contains(from) or not contains(to):
		return cells
	for y in range(mini(from.y, to.y), maxi(from.y, to.y) + 1):
		for x in range(mini(from.x, to.x), maxi(from.x, to.x) + 1):
			cells.append(Vector2i(x, y))
	return cells


func connected_matching_cells(start: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not contains(start) or not validation_errors().is_empty():
		return cells
	var target: String = _paint_region_signature(cell_definition(start))
	var pending: Array[Vector2i] = [start]
	var visited: Dictionary = {}
	var pending_index := 0
	while pending_index < pending.size():
		var cell: Vector2i = pending[pending_index]
		pending_index += 1
		if visited.has(cell):
			continue
		visited[cell] = true
		if _paint_region_signature(cell_definition(cell)) != target:
			continue
		cells.append(cell)
		var neighbors: Array[Vector2i] = [
			cell + Vector2i.LEFT,
			cell + Vector2i.RIGHT,
			cell + Vector2i.UP,
			cell + Vector2i.DOWN,
		]
		for neighbor: Vector2i in neighbors:
			if contains(neighbor) and not visited.has(neighbor):
				pending.append(neighbor)
	return cells


func _paint_region_signature(definition: Dictionary) -> String:
	return "%d|%s|%d|%s" % [
		int(definition.get("terrain", TerrainKind.NEUTRAL)),
		bool(definition.get("blocked", false)),
		int(definition.get("elevation", 0)),
		str(definition.get("group", "")),
	]


func _edit_snapshot_cell(
	snapshot: Dictionary,
	cell: Vector2i,
	tool: int,
	requested_group: String,
) -> bool:
	var next_terrain: PackedByteArray = snapshot["terrain_kinds"]
	var next_elevations: PackedInt32Array = snapshot["elevations"]
	var next_blocked: PackedByteArray = snapshot["blocked"]
	var next_groups: PackedStringArray = snapshot["groups"]
	var index := cell_index(cell)
	if tool == PaintTool.BLOCKED and cell == snapshot.get("focus_cell", focus_cell):
		return false
	if tool in [PaintTool.BLOCKED, PaintTool.FOCUS] and _is_last_deployment(snapshot, cell):
		return false
	match tool:
		PaintTool.NEUTRAL:
			next_terrain[index] = TerrainKind.NEUTRAL
			next_blocked[index] = 0
			next_groups[index] = ""
		PaintTool.WET:
			next_terrain[index] = TerrainKind.WET
			next_blocked[index] = 0
			next_groups[index] = requested_group.strip_edges() if not requested_group.strip_edges().is_empty() else "tide"
		PaintTool.EMBER:
			next_terrain[index] = TerrainKind.EMBER
			next_blocked[index] = 0
			next_groups[index] = requested_group.strip_edges() if not requested_group.strip_edges().is_empty() else "ember"
		PaintTool.FROZEN:
			next_terrain[index] = TerrainKind.FROZEN
			next_blocked[index] = 0
			next_groups[index] = requested_group.strip_edges()
		PaintTool.BLOCKED:
			next_terrain[index] = TerrainKind.NEUTRAL
			next_blocked[index] = 1
			next_groups[index] = ""
			_remove_deployment(snapshot, cell)
		PaintTool.HEIGHT_UP:
			next_elevations[index] = mini(16, next_elevations[index] + 1)
		PaintTool.HEIGHT_DOWN:
			next_elevations[index] = maxi(0, next_elevations[index] - 1)
		PaintTool.FOCUS:
			snapshot["focus_cell"] = cell
			_remove_deployment(snapshot, cell)
		PaintTool.PARTY_DEPLOYMENT:
			if cell == snapshot.get("focus_cell", focus_cell) or int(next_blocked[index]) != 0:
				return false
			if not _toggle_deployment(snapshot, cell, true):
				return false
		PaintTool.ENEMY_DEPLOYMENT:
			if cell == snapshot.get("focus_cell", focus_cell) or int(next_blocked[index]) != 0:
				return false
			if not _toggle_deployment(snapshot, cell, false):
				return false
		_:
			return false
	snapshot["terrain_kinds"] = next_terrain
	snapshot["elevations"] = next_elevations
	snapshot["blocked"] = next_blocked
	snapshot["groups"] = next_groups
	return true


func notify_authoring_changed() -> void:
	emit_changed()


static func cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


static func cell_label(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), cell.y + 1]


func _resized_authoring_snapshot(new_width: int, new_height: int, offset: Vector2i) -> Dictionary:
	var next_terrain := PackedByteArray()
	var next_elevations := PackedInt32Array()
	var next_blocked := PackedByteArray()
	var next_groups := PackedStringArray()
	var next_count := new_width * new_height
	next_terrain.resize(next_count)
	next_elevations.resize(next_count)
	next_blocked.resize(next_count)
	next_groups.resize(next_count)
	for old_y in height:
		for old_x in width:
			var old_cell := Vector2i(old_x, old_y)
			var new_cell := old_cell + offset
			if new_cell.x < 0 or new_cell.y < 0 or new_cell.x >= new_width or new_cell.y >= new_height:
				continue
			var old_index := cell_index(old_cell)
			var new_index := new_cell.y * new_width + new_cell.x
			next_terrain[new_index] = terrain_kinds[old_index]
			next_elevations[new_index] = elevations[old_index]
			next_blocked[new_index] = blocked[old_index]
			next_groups[new_index] = groups[old_index]
	var next_focus := focus_cell + offset
	if not _snapshot_cell_available(next_focus, new_width, new_height, next_blocked):
		next_focus = _nearest_available_cell(next_focus, new_width, new_height, next_blocked)
	var next_party := _remap_deployments(
		party_deployment_cells, offset, new_width, new_height, next_blocked, next_focus
	)
	var next_enemy := _remap_deployments(
		enemy_deployment_cells, offset, new_width, new_height, next_blocked, next_focus
	)
	return {
		"width": new_width,
		"height": new_height,
		"terrain_kinds": next_terrain,
		"elevations": next_elevations,
		"blocked": next_blocked,
		"groups": next_groups,
		"focus_cell": next_focus,
		"party_deployment_cells": next_party,
		"enemy_deployment_cells": next_enemy,
	}


func _resize_offset(new_width: int, new_height: int, anchor: int) -> Vector2i:
	var column := clampi(anchor % 3, 0, 2)
	var row := clampi(anchor / 3, 0, 2)
	var dx := 0 if column == 0 else (new_width - width if column == 2 else floori(float(new_width - width) * 0.5))
	var dy := 0 if row == 0 else (new_height - height if row == 2 else floori(float(new_height - height) * 0.5))
	return Vector2i(dx, dy)


func _remap_deployments(
	source: Array[Vector2i],
	offset: Vector2i,
	new_width: int,
	new_height: int,
	next_blocked: PackedByteArray,
	next_focus: Vector2i,
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for old_cell in source:
		var cell := old_cell + offset
		if cell == next_focus or not _snapshot_cell_available(cell, new_width, new_height, next_blocked):
			continue
		if cell not in result:
			result.append(cell)
	return result


func _snapshot_cell_available(
	cell: Vector2i,
	new_width: int,
	new_height: int,
	next_blocked: PackedByteArray,
) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= new_width or cell.y >= new_height:
		return false
	return int(next_blocked[cell.y * new_width + cell.x]) == 0


func _nearest_available_cell(
	from: Vector2i,
	new_width: int,
	new_height: int,
	next_blocked: PackedByteArray,
) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := 1 << 30
	for y in new_height:
		for x in new_width:
			var cell := Vector2i(x, y)
			if not _snapshot_cell_available(cell, new_width, new_height, next_blocked):
				continue
			var distance := absi(cell.x - from.x) + absi(cell.y - from.y)
			if distance < best_distance:
				best = cell
				best_distance = distance
	return best


func _toggle_deployment(snapshot: Dictionary, cell: Vector2i, party: bool) -> bool:
	var own_name := "party_deployment_cells" if party else "enemy_deployment_cells"
	var other_name := "enemy_deployment_cells" if party else "party_deployment_cells"
	var own: Array[Vector2i] = snapshot.get(own_name, []).duplicate()
	var other: Array[Vector2i] = snapshot.get(other_name, []).duplicate()
	if cell in own:
		if own.size() <= 1:
			return false
		own.erase(cell)
	else:
		if cell in other and other.size() <= 1:
			return false
		other.erase(cell)
		own.append(cell)
	snapshot[own_name] = own
	snapshot[other_name] = other
	return true


func _remove_deployment(snapshot: Dictionary, cell: Vector2i) -> void:
	for property_name in ["party_deployment_cells", "enemy_deployment_cells"]:
		var cells: Array[Vector2i] = snapshot.get(property_name, []).duplicate()
		cells.erase(cell)
		snapshot[property_name] = cells


func _is_last_deployment(snapshot: Dictionary, cell: Vector2i) -> bool:
	for property_name in ["party_deployment_cells", "enemy_deployment_cells"]:
		var cells: Array[Vector2i] = snapshot.get(property_name, [])
		if cell in cells and cells.size() <= 1:
			return true
	return false


func _validate_deployments(
	label: String,
	cells: Array[Vector2i],
	errors: Array[String],
) -> void:
	if cells.is_empty():
		errors.append("Добавьте хотя бы одну точку: %s." % label.to_lower())
		return
	var seen: Dictionary = {}
	for cell in cells:
		if seen.has(cell):
			errors.append("%s: точка %s повторяется." % [label, cell_label(cell)])
			continue
		seen[cell] = true
		if not contains(cell):
			errors.append("%s: точка %s находится за границей поля." % [label, cell_label(cell)])
		elif bool(cell_definition(cell).get("blocked", false)):
			errors.append("%s: точка %s стоит на преграде." % [label, cell_label(cell)])
		elif cell == focus_cell:
			errors.append("%s: точка %s занята фокусом поля." % [label, cell_label(cell)])


func _validate_array_size(
	label: String,
	actual: int,
	expected: int,
	errors: Array[String],
) -> void:
	if actual != expected:
		errors.append("%s: ожидалось %d значений, найдено %d." % [label, expected, actual])
