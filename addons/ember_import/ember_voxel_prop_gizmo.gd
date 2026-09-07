@tool
extends EditorNode3DGizmoPlugin
## Compact selection bounds for EmberVoxelProp. The child Omni range is intentionally ignored.


func _init() -> void:
	create_material("bounds", Color(1.0, 0.62, 0.12), false, true)


func _get_gizmo_name() -> String:
	return "Ember voxel prop bounds"


func _has_gizmo(node: Node3D) -> bool:
	return node is EmberVoxelProp


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var prop := gizmo.get_node_3d() as EmberVoxelProp
	if prop == null or not _is_selected(prop):
		return
	var visual := prop.get_node_or_null("Mesh") as MeshInstance3D
	if visual == null or visual.mesh == null:
		return
	var lines := _box_lines(visual.mesh.get_aabb(), visual.transform)
	gizmo.add_lines(lines, get_material("bounds", gizmo))
	gizmo.add_collision_segments(lines)


func _is_selected(prop: EmberVoxelProp) -> bool:
	var selection := EditorInterface.get_selection()
	if selection == null:
		return false
	for selected in selection.get_selected_nodes():
		var current := selected as Node
		while current:
			if current == prop:
				return true
			current = current.get_parent()
	return false


func _box_lines(box: AABB, local_transform: Transform3D) -> PackedVector3Array:
	var p := PackedVector3Array()
	for index in range(8):
		p.append(local_transform * box.get_endpoint(index))
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
		lines.append(p[edges[index]])
		lines.append(p[edges[index + 1]])
	return lines
