@tool
class_name EmberBattlefieldInspectorPlugin
extends EditorInspectorPlugin

const BattlefieldPanel = preload("res://addons/ember_import/ember_battlefield_inspector_panel.gd")
const BattlefieldActions = preload("res://addons/ember_import/ember_battlefield_editor_actions.gd")

var _actions: EmberBattlefieldEditorActions


func configure(undo_redo: Object) -> void:
	_actions = BattlefieldActions.new() as EmberBattlefieldEditorActions
	_actions.configure(undo_redo)


func _can_handle(object: Object) -> bool:
	return object is EmberBattlefieldResource


func _parse_begin(object: Object) -> void:
	var field := object as EmberBattlefieldResource
	if field == null:
		return
	var panel := BattlefieldPanel.new() as EmberBattlefieldInspectorPanel
	panel.setup(
		field,
		_actions.paint_cell if _actions != null else Callable(),
		_actions.resize_field if _actions != null else Callable(),
		_actions.sync_surface_water if _actions != null else Callable(),
		_actions.sync_surface_heights if _actions != null else Callable(),
	)
	add_custom_control(panel)


func _parse_property(
	_object: Object,
	_type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool,
) -> bool:
	# These properties have atomic, validated authoring above. Showing the raw
	# values below would let a single Inspector edit desynchronise row-major data.
	return name in [
		"width", "height", "party_deployment_cells", "enemy_deployment_cells",
	]
