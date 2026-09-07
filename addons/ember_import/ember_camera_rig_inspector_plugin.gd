@tool
class_name EmberCameraRigInspectorPlugin
extends EditorInspectorPlugin
## Adds the child Camera3D view to the Inspector of its author-facing rig.

const CameraRigPreview = preload("res://addons/ember_import/ember_camera_rig_preview.gd")

var _editor_interface: EditorInterface


func configure(editor_interface: EditorInterface) -> void:
	_editor_interface = editor_interface


func _can_handle(object: Object) -> bool:
	return object is OrbitCamera


func _parse_begin(object: Object) -> void:
	var rig := object as OrbitCamera
	if rig == null:
		return
	var preview := CameraRigPreview.new() as EmberCameraRigPreview
	preview.setup(rig, _editor_interface)
	add_custom_control(preview)
