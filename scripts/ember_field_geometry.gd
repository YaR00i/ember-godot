extends RefCounted
## A bounded snapshot of exploration collision for a single in-place encounter.

const TILE_SIZE := 16.0
const FLOOR_TOLERANCE := 2.0
const HEIGHT_BAND := 24.0
const LEVEL_HEIGHT := 0.52 * TILE_SIZE / 1.2
const Terrain = preload("res://scripts/prototypes/ember_combat_terrain.gd")


static func find_placement(
	space: PhysicsDirectSpaceState3D, origin: Vector3, field: EmberBattlefieldResource,
	footprint: CapsuleShape3D, excluded: Array[RID], enemy_cells: Array[Vector2i],
	party_count: int, fixed: bool,
) -> Dictionary:
	var candidates := [Vector3.ZERO]
	if not fixed:
		candidates.append_array([Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK])
	var size := Vector2i(field.width, field.height)
	for offset: Vector3 in candidates:
		var corner := origin + offset * TILE_SIZE
		var geometry := sample(space, corner, size, footprint, excluded)
		var slots := Array(field.party_deployment_cells).filter(
			func(cell): return not geometry.blocked.has(cell)
		)
		if slots.size() < party_count:
			continue
		if enemy_cells.any(func(cell): return geometry.blocked.has(cell)):
			continue
		return {"corner": corner, "geometry": geometry, "partySlots": slots}
	return {}


static func sample(
	space: PhysicsDirectSpaceState3D, corner: Vector3, size: Vector2i,
	footprint: CapsuleShape3D, excluded: Array[RID],
) -> Dictionary:
	var open_centers := {}
	var blocked := {}
	var edges := {}
	var walk_edges := {}
	var floors := {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = footprint
	query.collision_mask = 1
	query.exclude = excluded
	var footprint_sample := footprint.radius * 0.7
	var samples := [Vector3.ZERO, Vector3.LEFT * footprint_sample, Vector3.RIGHT * footprint_sample,
		Vector3.FORWARD * footprint_sample, Vector3.BACK * footprint_sample]
	for z in size.y:
		for x in size.x:
			var cell := Vector2i(x, z)
			var center := corner + Vector3(x + 0.5, 0, z + 0.5) * TILE_SIZE
			var floor_y := center.y
			var supported := true
			for offset: Vector3 in samples:
				var point := center + offset
				var hit := _support(space, point, corner.y, excluded)
				if hit.is_empty():
					supported = false
					break
				if offset == Vector3.ZERO:
					floor_y = hit.position.y
				elif absf(float(hit.position.y) - floor_y) > 2.5:
					supported = false
					break
			center.y = floor_y + footprint.height * 0.5 + 0.45
			query.transform = Transform3D(Basis.IDENTITY, center)
			if supported and space.intersect_shape(query, 1).is_empty():
				open_centers[cell] = center
				floors[cell] = floor_y
			else:
				blocked[cell] = true
	for cell: Vector2i in open_centers:
		var center: Vector3 = open_centers[cell]
		for offset in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + offset
			if not open_centers.has(neighbor):
				continue
			query.transform = Transform3D(Basis.IDENTITY, center)
			var next: Vector3 = open_centers[neighbor]
			var middle := (center + next) * 0.5
			var hit := _support(space, middle, corner.y, excluded)
			if hit.is_empty() or float(hit.position.y) < minf(floors[cell], floors[neighbor]) - 0.5 \
					or float(hit.position.y) > maxf(floors[cell], floors[neighbor]) + 0.5:
				edges[Terrain.world_edge_key(cell, neighbor)] = true
				continue
			if absf(center.y - next.y) > 2.5:
				# Check the air above the lip, then the vertical space at the landing.
				var high_y := maxf(center.y, next.y)
				var low := next if next.y < center.y else center
				query.transform = Transform3D(Basis.IDENTITY, Vector3(low.x, high_y, low.z))
				if not space.intersect_shape(query, 1).is_empty():
					edges[Terrain.world_edge_key(cell, neighbor)] = true
					continue
				query.motion = Vector3.DOWN * (high_y - low.y)
				var drop := space.cast_motion(query)
				if drop.size() < 2 or drop[0] < 0.999:
					edges[Terrain.world_edge_key(cell, neighbor)] = true
					continue
				query.transform = Transform3D(Basis.IDENTITY, Vector3(center.x, high_y, center.z))
				query.motion = Vector3(next.x - center.x, 0, next.z - center.z)
			else:
				query.motion = next - center
			var motion := space.cast_motion(query)
			if motion.size() < 2 or motion[0] < 0.999:
				edges[Terrain.world_edge_key(cell, neighbor)] = true
			elif absf(float(hit.position.y) - (float(floors[cell]) + float(floors[neighbor])) * 0.5) <= 0.75:
				walk_edges[Terrain.world_edge_key(cell, neighbor)] = true
	var ground := corner.y
	var levels := {}
	var offsets := {}
	if not floors.is_empty():
		var heights := floors.values()
		ground = float(heights.min())
		for cell in floors:
			offsets[cell] = float(floors[cell]) - ground
			levels[cell] = roundi(float(offsets[cell]) / LEVEL_HEIGHT)
	return {"blocked": blocked, "edges": edges, "walkEdges": walk_edges,
		"ground": ground, "levels": levels, "offsets": offsets}


static func _support(space: PhysicsDirectSpaceState3D, point: Vector3, baseline: float, excluded: Array[RID]) -> Dictionary:
	var column := Vector3(point.x, baseline, point.z)
	var ray := PhysicsRayQueryParameters3D.create(
		column + Vector3.UP * HEIGHT_BAND, column - Vector3.UP * HEIGHT_BAND, 1, excluded
	)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.82:
		return {}
	var collider := hit.collider as Node
	if absf(float(hit.position.y) - baseline) > FLOOR_TOLERANCE \
			and (collider == null or not collider.is_in_group("ember_battle_walkable")):
		return {}
	return hit
