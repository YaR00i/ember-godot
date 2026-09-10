@tool
extends EditorPlugin
## Thin main-screen adapter. The workspace, actions and canonical Resource
## remain owned by ember_import; this plugin only gives that UI a proper Godot
## workspace tab beside 2D/3D/Script.

const SurfaceWorkspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const EditorViewStore = preload("res://addons/ember_import/ember_surface_editor_view_store.gd")
const LAYOUT_SECTION := "EmberSurfaceCanvas"
const LAYOUT_VIEW_STATES := "surface_view_states"

var _workspace: EmberVoxelSculptWorkspace
var _view_store: RefCounted = EditorViewStore.new()


func _enter_tree() -> void:
	_workspace = SurfaceWorkspace.new() as EmberVoxelSculptWorkspace
	_workspace.name = "EmberSurfaceCanvasWorkspace"
	_workspace.setup(get_editor_interface(), get_undo_redo(), _view_store)
	_workspace.create_object_callback = func():
		var importer := get_parent().get_node_or_null("EmberImportPlugin")
		if importer != null:
			importer.call("_new_voxel_shape")
	EditorInterface.get_editor_main_screen().add_child(_workspace)
	_make_visible(false)


func _exit_tree() -> void:
	if is_instance_valid(_workspace):
		_workspace.export_editor_view_data()
		_workspace.queue_free()
	_workspace = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if not is_instance_valid(_workspace):
		return
	if visible:
		_workspace.cancel_navigation_request()
		_workspace.visible = true
		_workspace.ensure_ui()
		if _workspace.get("_resource") == null:
			_workspace.open_pilot()
		else:
			_workspace.show_current_status()
	elif _workspace.visible:
		_workspace.request_close(_finish_hiding, _return_to_canvas)


func _finish_hiding() -> void:
	if is_instance_valid(_workspace):
		_workspace.visible = false


func _return_to_canvas() -> void:
	if is_instance_valid(_workspace):
		_workspace.visible = true
	get_editor_interface().set_main_screen_editor("Surface Canvas")


func _get_unsaved_status(for_scene: String) -> String:
	if not for_scene.is_empty() or not is_instance_valid(_workspace):
		return ""
	return _workspace.unsaved_status()


func _save_external_data() -> void:
	if is_instance_valid(_workspace) and _workspace.has_unsaved_changes():
		_workspace.save_changes()


func _get_window_layout(configuration: ConfigFile) -> void:
	var data := (
		_workspace.export_editor_view_data()
		if is_instance_valid(_workspace)
		else _view_store.call("export_data") as Dictionary
	)
	configuration.set_value(LAYOUT_SECTION, LAYOUT_VIEW_STATES, data)


func _set_window_layout(configuration: ConfigFile) -> void:
	var data: Variant = configuration.get_value(LAYOUT_SECTION, LAYOUT_VIEW_STATES, {})
	if data is Dictionary:
		_view_store.call("import_data", data as Dictionary)


func _get_plugin_name() -> String:
	return "Surface Canvas"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GridMap", "EditorIcons")
