@tool
extends RefCounted
## Authoring adapter. The saved owner is a plain StaticBody3D + BoxShape3D,
## not a gameplay script or a second terrain renderer.
const MARKER := "ember_walk_surface"
const THICKNESS := 0.02

static func is_surface(node: Node) -> bool:
	return node is StaticBody3D and bool(node.get_meta(MARKER, false))

static func shape_node(node: Node) -> CollisionShape3D:
	return node.get_node_or_null("Shape") as CollisionShape3D

static func dimensions(node: Node) -> Vector2:
	var collider := shape_node(node)
	if collider != null and collider.shape is BoxShape3D:
		return Vector2(collider.shape.size.x, collider.shape.size.z)
	return Vector2.ZERO

static func make_node(size: Vector2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "WalkSurface"
	body.set_meta(MARKER, true)
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	set_size(body, size)
	return body

static func set_size(node: Node, size: Vector2) -> void:
	var collider := shape_node(node)
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, THICKNESS, size.y)
	collider.shape = box
	collider.position = Vector3(0, -THICKNESS * 0.5, 0)
	if node is Node3D:
		node.update_gizmos()

static func grid_lines(size: Vector2) -> PackedVector3Array:
	var lines := PackedVector3Array()
	# Bounded at 66 lines regardless of physical extent.
	var nx := mini(32, maxi(1, ceili(size.x / 4.0)))
	var nz := mini(32, maxi(1, ceili(size.y / 4.0)))
	for x in nx + 1:
		var p := -size.x * 0.5 + size.x * x / nx
		lines.append(Vector3(p, 0, -size.y * 0.5))
		lines.append(Vector3(p, 0, size.y * 0.5))
	for z in nz + 1:
		var p := -size.y * 0.5 + size.y * z / nz
		lines.append(Vector3(-size.x * 0.5, 0, p))
		lines.append(Vector3(size.x * 0.5, 0, p))
	return lines

static func visual_mesh(size: Vector2) -> PlaneMesh:
	var mesh := PlaneMesh.new()
	mesh.size = size
	return mesh

static func orthogonal(pose: Transform3D) -> bool:
	if not pose.origin.is_finite() or not pose.basis.x.is_finite() or not pose.basis.y.is_finite() or not pose.basis.z.is_finite():
		return false
	if pose.basis.determinant() <= 0.000001:
		return false
	var x := pose.basis.x.normalized()
	var y := pose.basis.y.normalized()
	var z := pose.basis.z.normalized()
	return absf(x.dot(y)) < 0.0001 and absf(x.dot(z)) < 0.0001 and absf(y.dot(z)) < 0.0001
