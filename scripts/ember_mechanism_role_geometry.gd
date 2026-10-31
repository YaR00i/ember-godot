extends RefCounted
## Shared authored helper geometry, not another mechanism controller.
static func object_for(target: Node3D) -> Node3D:
	if target != null and target.has_meta("mechanism_object_path"):
		return target.get_node_or_null(target.get_meta("mechanism_object_path")) as Node3D
	return target

static func bounds(target: Node3D) -> AABB:
	var result := AABB(); var started := false
	var nodes: Array[Node] = [target]; nodes.append_array(target.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		if not node is MeshInstance3D or node.mesh == null: continue
		var box: AABB = (target.global_transform.affine_inverse() * node.global_transform) * node.mesh.get_aabb()
		result = result.merge(box) if started else box; started = true
	return result

static func helper_for(target: Node3D, id: String) -> Node3D:
	var object := object_for(target)
	if object == null: return null
	for child in object.get_children():
		if child.get_meta("mechanism_role_id", "") == id: return child as Node3D
	return null

static func shape(parent: Node3D, size: Vector3, center: Vector3) -> void:
	var node := CollisionShape3D.new(); node.name = "Shape"; node.shape = BoxShape3D.new()
	node.shape.size = size.max(Vector3.ONE * 0.1); node.position = center; parent.add_child(node)

static func build(target: Node3D, kind: String, id: String) -> Node3D:
	var box := bounds(target)
	var helper := Node3D.new(); helper.name = "MechanismRole_" + id
	helper.set_meta("mechanism_role_id", id); helper.set_meta("mechanism_role_kind", kind)
	var body: StaticBody3D = AnimatableBody3D.new() if kind == "door" else StaticBody3D.new()
	body.name = "Body"; body.collision_layer = 1; body.collision_mask = 0
	if body is AnimatableBody3D: body.sync_to_physics = false
	helper.add_child(body); shape(body, box.size, box.get_center())
	var area := Area3D.new(); area.name = "Clearance" if kind == "door" else "PlateZone"
	area.collision_layer = 0; area.collision_mask = 2 | 4 if kind == "plate" else 1 | 2 | 4
	helper.add_child(area)
	if kind == "door":
		shape(area, box.size * Vector3(0.9, 0.95, 1.0) + Vector3(0, 0, 6), box.get_center())
	else:
		var height := maxf(12, box.size.y)
		shape(area, Vector3(box.size.x, height, box.size.z), Vector3(box.get_center().x, box.end.y + height * 0.5 - 0.05, box.get_center().z))
		area.set_meta("mechanism_object_path", NodePath("../.."))
	return helper
