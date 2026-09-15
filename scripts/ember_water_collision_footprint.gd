class_name EmberWaterCollisionFootprint
extends RefCounted
## Pure collision-to-waterline projection. The runtime contact owner decides
## which water surface is active; this module only describes collider bounds.


static func collect(root: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if root == null:
		return result
	_collect_recursive(root, result)
	return result


static func from_collision(collision: CollisionShape3D) -> Dictionary:
	if collision == null or collision.disabled or collision.shape == null:
		return {}
	var local_bounds := _local_bounds(collision.shape)
	if local_bounds.is_empty():
		return {}
	var local_half: Vector3 = local_bounds["half_extent"]
	var local_center: Vector3 = local_bounds.get("center", Vector3.ZERO)
	var transform := collision.global_transform
	var world_center := transform * local_center
	var basis := transform.basis
	var scaled_x := basis.x * local_half.x
	var scaled_y := basis.y * local_half.y
	var scaled_z := basis.z * local_half.z
	var vertical_radius := absf(scaled_x.y) + absf(scaled_y.y) + absf(scaled_z.y)
	var upright := (
		absf(basis.y.normalized().dot(Vector3.UP)) >= 0.92
		and absf(basis.x.normalized().dot(Vector3.UP)) <= 0.08
		and absf(basis.z.normalized().dot(Vector3.UP)) <= 0.08
	)
	var half_extent: Vector2
	var yaw := 0.0
	if upright:
		half_extent = Vector2(
			maxf(Vector2(scaled_x.x, scaled_x.z).length(), 0.001),
			maxf(Vector2(scaled_z.x, scaled_z.z).length(), 0.001),
		)
		var axis_x := Vector2(basis.x.x, basis.x.z).normalized()
		yaw = atan2(-axis_x.y, axis_x.x)
	else:
		# Tilted or irregular shapes use a conservative world-aligned rectangle.
		# This prevents a water response from being clipped even when an exact
		# waterline polygon is not available.
		half_extent = Vector2(
			absf(scaled_x.x) + absf(scaled_y.x) + absf(scaled_z.x),
			absf(scaled_x.z) + absf(scaled_y.z) + absf(scaled_z.z),
		)
	var roundness_world := 0.0
	if collision.shape is SphereShape3D or collision.shape is CylinderShape3D:
		roundness_world = minf(half_extent.x, half_extent.y)
	elif collision.shape is CapsuleShape3D and upright:
		roundness_world = minf(half_extent.x, half_extent.y)
	return {
		"collision": collision,
		"id": collision.get_instance_id(),
		"center": world_center,
		"half_extent": half_extent,
		"min_y": world_center.y - vertical_radius,
		"max_y": world_center.y + vertical_radius,
		"yaw": yaw,
		"roundness_world": roundness_world,
	}


static func intersects_height(footprint: Dictionary, water_y: float, tolerance := 0.001) -> bool:
	return (
		water_y >= float(footprint.get("min_y", INF)) - tolerance
		and water_y <= float(footprint.get("max_y", -INF)) + tolerance
	)


static func _collect_recursive(node: Node, result: Array[Dictionary]) -> void:
	if node is CollisionShape3D:
		var footprint := from_collision(node as CollisionShape3D)
		if not footprint.is_empty():
			result.append(footprint)
	for child in node.get_children():
		_collect_recursive(child, result)


static func _local_bounds(shape: Shape3D) -> Dictionary:
	if shape is BoxShape3D:
		return {"center": Vector3.ZERO, "half_extent": (shape as BoxShape3D).size * 0.5}
	if shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		return {"center": Vector3.ZERO, "half_extent": Vector3.ONE * radius}
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return {
			"center": Vector3.ZERO,
			"half_extent": Vector3(capsule.radius, capsule.height * 0.5, capsule.radius),
		}
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return {
			"center": Vector3.ZERO,
			"half_extent": Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius),
		}
	if shape is ConvexPolygonShape3D:
		return _points_bounds((shape as ConvexPolygonShape3D).points)
	if shape is ConcavePolygonShape3D:
		return _points_bounds((shape as ConcavePolygonShape3D).segments)
	var debug_mesh := shape.get_debug_mesh()
	if debug_mesh != null:
		var aabb := debug_mesh.get_aabb()
		return {"center": aabb.get_center(), "half_extent": aabb.size * 0.5}
	return {}


static func _points_bounds(points: PackedVector3Array) -> Dictionary:
	if points.is_empty():
		return {}
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return {
		"center": (minimum + maximum) * 0.5,
		"half_extent": (maximum - minimum) * 0.5,
	}
