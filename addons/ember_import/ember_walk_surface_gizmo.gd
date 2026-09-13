@tool
extends EditorNode3DGizmoPlugin
const Surface = preload("res://addons/ember_import/ember_walk_surface.gd")
var show_surfaces := true

func _init() -> void:
	create_material("grid", Color(0.2, 0.95, 0.85, 0.8), false, true)

func _get_gizmo_name() -> String:
	return "Ember поверхности прохода"

func _has_gizmo(node: Node3D) -> bool:
	return Surface.is_surface(node)

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	if not show_surfaces or (gizmo.get_node_3d().collision_layer & 1) == 0:
		return
	var size := Surface.dimensions(gizmo.get_node_3d())
	if size.x <= 0 or size.y <= 0:
		return
	var lines := Surface.node_lines(gizmo.get_node_3d())
	gizmo.add_lines(lines, get_material("grid", gizmo))
	gizmo.add_collision_segments(lines)
