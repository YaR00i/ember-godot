extends RefCounted
## Shared, pure body containment/settle eligibility; no progress writes.

static func accepts_body(zone: Area3D, body: Node3D, pickup_id: String) -> bool:
	if pickup_id.is_empty() or not is_instance_valid(body) or not body is RigidBody3D:
		return false
	if not body.is_in_group("ember_world_item_bodies") or str(body.get("pickup_id")) != pickup_id:
		return false
	if body.has_method("is_carried") and body.call("is_carried"):
		return false
	if (body as RigidBody3D).linear_velocity.length() > 1.0 or (body as RigidBody3D).angular_velocity.length() > 0.15:
		return false
	var zone_shape := zone.get_node_or_null("Shape") as CollisionShape3D
	var body_shape := body.get_node_or_null("BodyShape") as CollisionShape3D
	if zone_shape == null or body_shape == null or not zone_shape.shape is BoxShape3D or not body_shape.shape is BoxShape3D:
		return false
	var half: Vector3 = (zone_shape.shape as BoxShape3D).size * 0.5
	var bounds := AABB(-(body_shape.shape as BoxShape3D).size * 0.5, (body_shape.shape as BoxShape3D).size)
	var to_zone := zone_shape.global_transform.affine_inverse() * body_shape.global_transform
	for index in 8:
		var corner: Vector3 = to_zone * bounds.get_endpoint(index)
		# Physics contact recovery can leave a small penetration at the floor.
		if absf(corner.x) > half.x + 0.15 or absf(corner.y) > half.y + 0.15 or absf(corner.z) > half.z + 0.15:
			return false
	return true
