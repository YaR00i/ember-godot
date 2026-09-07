@tool
extends EditorNode3DGizmoPlugin
## Editor-only wire bounds for scene-owned standalone EmberInteract volumes.


func _init() -> void:
	create_material("trigger_bounds", Color(0.18, 0.9, 1.0), false, true)


func _get_gizmo_name() -> String:
	return "Ember standalone trigger bounds"


func _has_gizmo(node: Node3D) -> bool:
	return node is EmberInteract and EmberObjectInspectorModel.voxel_owner(node) == null


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var interact := gizmo.get_node_3d() as EmberInteract
	if interact == null or not _is_selected(interact):
		return
	var shape_node := interact.get_node_or_null("Shape") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D if shape_node != null else null
	if box == null:
		return
	var bounds := AABB(-box.size * 0.5, box.size)
	var lines := _box_lines(bounds, shape_node.transform)
	gizmo.add_lines(lines, get_material("trigger_bounds", gizmo))
	gizmo.add_collision_segments(lines)


func _is_selected(interact: EmberInteract) -> bool:
	var selection := EditorInterface.get_selection()
	if selection == null:
		return false
	for selected in selection.get_selected_nodes():
		if selected == interact or (selected is Node and interact.is_ancestor_of(selected)):
			return true
	return false


func _box_lines(box: AABB, local_transform: Transform3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in range(8):
		points.append(local_transform * box.get_endpoint(index))
	var edges := [
		0, 1, 0, 2, 0, 4,
		1, 3, 1, 5,
		2, 3, 2, 6,
		3, 7,
		4, 5, 4, 6,
		5, 7,
		6, 7,
	]
	var lines := PackedVector3Array()
	for index in range(0, edges.size(), 2):
		lines.append(points[edges[index]])
		lines.append(points[edges[index + 1]])
	return lines
