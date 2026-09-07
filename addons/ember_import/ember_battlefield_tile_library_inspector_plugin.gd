@tool
class_name EmberBattlefieldTileLibraryInspectorPlugin
extends EditorInspectorPlugin

const Contract := preload("res://scripts/prototypes/ember_battlefield_tile_library.gd")
const PreviewPanel := preload("res://addons/ember_import/ember_battlefield_tile_library_panel.gd")


func _can_handle(object: Object) -> bool:
	return object is MeshLibrary and (object as MeshLibrary).resource_path == Contract.RESOURCE_PATH


func _parse_begin(object: Object) -> void:
	var library := object as MeshLibrary
	if library == null:
		return
	var panel := PreviewPanel.new() as EmberBattlefieldTileLibraryPanel
	panel.setup(library)
	add_custom_control(panel)
