@tool
extends RefCounted
## Authoring adapter. The saved owner is a plain StaticBody3D + BoxShape3D,
## not a gameplay script or a second terrain renderer.
const MARKER := "ember_walk_surface"
const THICKNESS := 0.02
const Mask = preload("res://addons/ember_import/ember_walk_surface_mask.gd")
const MASK_KEY := "ember_walk_mask"

static func is_surface(node: Node) -> bool:
	return node is StaticBody3D and bool(node.get_meta(MARKER, false))

static func shape_node(node: Node) -> CollisionShape3D:
	return node.get_node_or_null("Shape") as CollisionShape3D

static func dimensions(node: Node) -> Vector2:
	if node.has_meta(MASK_KEY) and Mask.valid(node.get_meta(MASK_KEY)):
		return Mask.size(node.get_meta(MASK_KEY))
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
	node.remove_meta(MASK_KEY)
	for child in node.get_children():
		if child.name != &"Shape":
			node.remove_child(child)
			child.free()
	if shape_node(node) == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		node.add_child(shape)
		shape.owner = node.owner
	var collider := shape_node(node)
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, THICKNESS, size.y)
	collider.shape = box
	collider.position = Vector3(0, -THICKNESS * 0.5, 0)
	if node is Node3D:
		node.update_gizmos()

static func set_mask(node: Node, data: Dictionary) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.free()
	node.set_meta(MASK_KEY, data.duplicate(true))
	for rect in Mask.rectangles(data):
		var collider := CollisionShape3D.new()
		collider.name = "Shape" if node.get_child_count() == 0 else "Shape%d" % node.get_child_count()
		var box := BoxShape3D.new()
		var extent: Vector2 = Vector2(rect.size)*data.cell
		box.size = Vector3(extent.x,THICKNESS,extent.y)
		collider.shape = box
		collider.position = Mask.rect_pose(rect,data)+Vector3(0,-THICKNESS*0.5,0)
		node.add_child(collider)
		collider.owner = node.owner
	if node is Node3D:
		node.update_gizmos()

static func node_lines(node: Node) -> PackedVector3Array:
	if node.has_meta(MASK_KEY) and Mask.valid(node.get_meta(MASK_KEY)):
		var data: Dictionary = node.get_meta(MASK_KEY)
		# Saved gizmos show occupied rectangles, not empty grid as solid support.
		var lines := PackedVector3Array()
		for rect in Mask.rectangles(data):
			var extent: Vector2 = Vector2(rect.size)*data.cell
			var center := Mask.rect_pose(rect,data)
			var a := center+Vector3(-extent.x/2,0,-extent.y/2)
			var b := center+Vector3(extent.x/2,0,-extent.y/2)
			var c := center+Vector3(extent.x/2,0,extent.y/2)
			var d := center+Vector3(-extent.x/2,0,extent.y/2)
			lines.append_array(PackedVector3Array([a,b,b,c,c,d,d,a]))
		return lines
	return grid_lines(dimensions(node))

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
