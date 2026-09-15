extends RefCounted
## Pure shoreline spawn choice for the W04 gameplay gate.
## Reads EmberVoxelSurfaceMesher.build_water_shore_field and does not own water.

const SurfaceMesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const CANONICAL_SURFACE_PATH := "res://content/world_surfaces/agent_sandbox_surface.tres"
const INLAND_OFFSETS := [8, 6, 12, 4]


static func canonical_surface_path() -> String:
	return CANONICAL_SURFACE_PATH


static func select_shore_spawn(surface: EmberVoxelModelResource) -> Dictionary:
	var empty := _failure("surface is missing", {}, Vector3i.ZERO)
	if surface == null:
		return empty
	var size := surface.grid_size()
	var field: Dictionary = SurfaceMesher.build_water_shore_field(surface)
	var stats := _field_stats(field, size)
	if field.is_empty() or stats.get("field_size", Vector2i.ZERO) == Vector2i.ZERO:
		return _failure(
			"build_water_shore_field returned no usable field",
			stats,
			size
		)
	var heights := field.get("heights", PackedInt32Array()) as PackedInt32Array
	var direction_codes := field.get("direction_codes", PackedByteArray()) as PackedByteArray
	var walls := field.get("walls", PackedByteArray()) as PackedByteArray
	if (
		heights.size() != size.x * size.z
		or direction_codes.size() != heights.size()
		or walls.size() != heights.size()
	):
		return _failure("shore field arrays do not match Surface grid_size", stats, size)
	var beach_spawns: Array[Dictionary] = []
	var wall_spawns: Array[Dictionary] = []
	for z in size.z:
		for x in size.x:
			var cell := Vector2i(x, z)
			if not _is_wet_shore_candidate(cell, size, heights, direction_codes):
				continue
			var index := x + z * size.x
			var spawn := _spawn_from_candidate(
				surface,
				cell,
				int(direction_codes[index]),
				int(walls[index]) == 0,
				int(heights[index]),
				heights,
				size
			)
			if not bool(spawn.get("ok", false)):
				continue
			if bool(spawn.get("is_beach", false)):
				beach_spawns.append(spawn)
			else:
				wall_spawns.append(spawn)
	stats["valid_beach_spawns"] = beach_spawns.size()
	stats["valid_wall_spawns"] = wall_spawns.size()
	var chosen: Dictionary = {}
	if not beach_spawns.is_empty():
		chosen = beach_spawns[0]
	elif not wall_spawns.is_empty():
		chosen = wall_spawns[0]
	else:
		return _failure(
			"no wet shoreline cell has a dry passable inland side",
			stats,
			size
		)
	chosen["stats"] = stats
	chosen["grid_size"] = size
	return chosen


static func _spawn_from_candidate(
	surface: EmberVoxelModelResource,
	wet_cell: Vector2i,
	direction_code: int,
	is_beach: bool,
	wet_height: int,
	heights: PackedInt32Array,
	size: Vector3i,
) -> Dictionary:
	var waterward: Vector2 = SurfaceMesher._decode_shore_direction(direction_code)
	var step := _landward_step(waterward)
	if step == Vector2i.ZERO:
		return {"ok": false}
	var dry_cell := _first_dry_neighbor(wet_cell, step, heights, size)
	if dry_cell == Vector2i(-1, -1):
		return {"ok": false}
	for offset in INLAND_OFFSETS:
		var inland: Vector2i = wet_cell + step * int(offset)
		if not _in_bounds(inland, size):
			continue
		var inland_index := inland.x + inland.y * size.x
		if int(heights[inland_index]) >= 0:
			continue
		var solid_height := SurfaceMesher.solid_height_at(surface, inland)
		if solid_height < 0:
			continue
		if SurfaceMesher.water_height_at(surface, inland) >= 0:
			continue
		return {
			"ok": true,
			"reason": "",
			"wet_cell": wet_cell,
			"dry_cell": dry_cell,
			"inland_cell": inland,
			"inland_voxels": int(offset),
			"waterward": waterward,
			"direction_code": direction_code,
			"is_beach": is_beach,
			"wet_water_height": wet_height,
			"dry_solid_height": solid_height,
		}
	return {"ok": false}


static func _is_wet_shore_candidate(
	cell: Vector2i,
	size: Vector3i,
	heights: PackedInt32Array,
	direction_codes: PackedByteArray,
) -> bool:
	if _is_resource_border(cell, size):
		return false
	var index := cell.x + cell.y * size.x
	return int(heights[index]) >= 0 and int(direction_codes[index]) > 0


static func _is_resource_border(cell: Vector2i, size: Vector3i) -> bool:
	return cell.x <= 0 or cell.y <= 0 or cell.x >= size.x - 1 or cell.y >= size.z - 1


static func _in_bounds(cell: Vector2i, size: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.z


static func _landward_step(waterward: Vector2) -> Vector2i:
	var step := Vector2i.ZERO
	if absf(waterward.x) >= 0.38:
		step.x = -1 if waterward.x > 0.0 else 1
	if absf(waterward.y) >= 0.38:
		step.y = -1 if waterward.y > 0.0 else 1
	return step


static func _first_dry_neighbor(
	wet_cell: Vector2i,
	step: Vector2i,
	heights: PackedInt32Array,
	size: Vector3i,
) -> Vector2i:
	var tries: Array[Vector2i] = [step]
	if step.x != 0:
		tries.append(Vector2i(step.x, 0))
	if step.y != 0:
		tries.append(Vector2i(0, step.y))
	for raw in tries:
		var neighbor: Vector2i = wet_cell + raw
		if not _in_bounds(neighbor, size):
			continue
		if int(heights[neighbor.x + neighbor.y * size.x]) < 0:
			return neighbor
	return Vector2i(-1, -1)


static func _field_stats(field: Dictionary, size: Vector3i) -> Dictionary:
	var heights := field.get("heights", PackedInt32Array()) as PackedInt32Array
	var direction_codes := field.get("direction_codes", PackedByteArray()) as PackedByteArray
	var walls := field.get("walls", PackedByteArray()) as PackedByteArray
	var wet_columns := 0
	var shore_candidates := 0
	var beach_candidates := 0
	var wall_candidates := 0
	if heights.size() == size.x * size.z and direction_codes.size() == heights.size():
		for z in size.z:
			for x in size.x:
				var index := x + z * size.x
				if int(heights[index]) < 0:
					continue
				wet_columns += 1
				if int(direction_codes[index]) <= 0:
					continue
				if _is_resource_border(Vector2i(x, z), size):
					continue
				shore_candidates += 1
				if walls.size() == heights.size() and int(walls[index]) == 0:
					beach_candidates += 1
				else:
					wall_candidates += 1
	return {
		"field_size": field.get("size", Vector2i.ZERO),
		"grid_size": size,
		"wet_columns": wet_columns,
		"shore_candidates": shore_candidates,
		"beach_candidates": beach_candidates,
		"wall_candidates": wall_candidates,
		"maximum_steps": int(field.get("maximum_steps", 0)),
	}


static func _failure(reason: String, stats: Dictionary, size: Vector3i) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"stats": stats,
		"grid_size": size,
		"wet_cell": Vector2i(-1, -1),
		"dry_cell": Vector2i(-1, -1),
		"inland_cell": Vector2i(-1, -1),
		"inland_voxels": 0,
		"waterward": Vector2.ZERO,
		"direction_code": 0,
		"is_beach": false,
		"wet_water_height": -1,
		"dry_solid_height": -1,
	}


static func format_failure(result: Dictionary) -> String:
	var stats: Dictionary = result.get("stats", {})
	return "%s · grid=%s field=%s wet_columns=%s shore=%s beach=%s wall=%s valid_beach=%s valid_wall=%s" % [
		str(result.get("reason", "unknown shoreline failure")),
		str(result.get("grid_size", stats.get("grid_size", Vector3i.ZERO))),
		str(stats.get("field_size", Vector2i.ZERO)),
		str(stats.get("wet_columns", 0)),
		str(stats.get("shore_candidates", 0)),
		str(stats.get("beach_candidates", 0)),
		str(stats.get("wall_candidates", 0)),
		str(stats.get("valid_beach_spawns", 0)),
		str(stats.get("valid_wall_spawns", 0)),
	]
