@tool
class_name EmberVoxelSurfaceInspectorPlugin
extends EditorInspectorPlugin

const SurfacePanel := preload("res://addons/ember_import/ember_voxel_surface_inspector_panel.gd")

var _editor_interface: EditorInterface
var _open_surface_callback: Callable


func configure(
	editor_interface: EditorInterface,
	open_surface_callback := Callable(),
) -> void:
	_editor_interface = editor_interface
	_open_surface_callback = open_surface_callback


func _can_handle(object: Object) -> bool:
	return object is EmberVoxelModelResource and "surface" in (object as EmberVoxelModelResource).tags


func _parse_begin(object: Object) -> void:
	var surface := object as EmberVoxelModelResource
	if surface == null:
		return
	var panel := SurfacePanel.new()
	panel.setup(surface, _editor_interface, _open_surface_callback)
	add_custom_control(panel)
