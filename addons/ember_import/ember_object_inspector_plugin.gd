@tool
class_name EmberObjectInspectorPlugin
extends EditorInspectorPlugin
## Routes supported Ember nodes into one read-only native Inspector block.

const InspectorPanel = preload("res://addons/ember_import/ember_object_inspector_panel.gd")

var _rebuild_callback: Callable
var _interact_save_callback: Callable
var _interact_remove_callback: Callable
var _chain_save_callback: Callable
var _chain_remove_callback: Callable
var _standalone_save_callback: Callable
var _standalone_remove_callback: Callable
var _standalone_chain_save_callback: Callable
var _standalone_chain_remove_callback: Callable
var _standalone_bounds_save_callback: Callable
var _dialogue_save_callback: Callable
var _shop_save_callback: Callable
var _shop_migrate_callback: Callable
var _item_save_callback: Callable
var _item_migrate_callback: Callable
var _quest_save_callback: Callable


func configure(
	rebuild_callback: Callable,
	interact_save_callback: Callable = Callable(),
	interact_remove_callback: Callable = Callable(),
	chain_save_callback: Callable = Callable(),
	chain_remove_callback: Callable = Callable(),
	standalone_save_callback: Callable = Callable(),
	standalone_remove_callback: Callable = Callable(),
	standalone_chain_save_callback: Callable = Callable(),
	standalone_chain_remove_callback: Callable = Callable(),
	standalone_bounds_save_callback: Callable = Callable(),
	dialogue_save_callback: Callable = Callable(),
	shop_save_callback: Callable = Callable(),
	shop_migrate_callback: Callable = Callable(),
	item_save_callback: Callable = Callable(),
	item_migrate_callback: Callable = Callable(),
	quest_save_callback: Callable = Callable(),
) -> void:
	_rebuild_callback = rebuild_callback
	_interact_save_callback = interact_save_callback
	_interact_remove_callback = interact_remove_callback
	_chain_save_callback = chain_save_callback
	_chain_remove_callback = chain_remove_callback
	_standalone_save_callback = standalone_save_callback
	_standalone_remove_callback = standalone_remove_callback
	_standalone_chain_save_callback = standalone_chain_save_callback
	_standalone_chain_remove_callback = standalone_chain_remove_callback
	_standalone_bounds_save_callback = standalone_bounds_save_callback
	_dialogue_save_callback = dialogue_save_callback
	_shop_save_callback = shop_save_callback
	_shop_migrate_callback = shop_migrate_callback
	_item_save_callback = item_save_callback
	_item_migrate_callback = item_migrate_callback
	_quest_save_callback = quest_save_callback


func _can_handle(object: Object) -> bool:
	return EmberObjectInspectorModel.supports(object)


func _parse_begin(object: Object) -> void:
	add_custom_control(build_panel(object))


func build_panel(object: Object) -> EmberObjectInspectorPanel:
	var panel := InspectorPanel.new() as EmberObjectInspectorPanel
	panel.setup(object, EmberObjectInspectorModel.snapshot(object))
	if _rebuild_callback.is_valid():
		panel.rebuild_requested.connect(_on_rebuild_requested)
	if _interact_save_callback.is_valid():
		panel.interact_save_requested.connect(_on_interact_save_requested)
	if _interact_remove_callback.is_valid():
		panel.interact_remove_requested.connect(_on_interact_remove_requested)
	if _chain_save_callback.is_valid():
		panel.chain_save_requested.connect(_on_chain_save_requested)
	if _chain_remove_callback.is_valid():
		panel.chain_remove_requested.connect(_on_chain_remove_requested)
	if _standalone_save_callback.is_valid():
		panel.standalone_save_requested.connect(_on_standalone_save_requested)
	if _standalone_remove_callback.is_valid():
		panel.standalone_remove_requested.connect(_on_standalone_remove_requested)
	if _standalone_chain_save_callback.is_valid():
		panel.standalone_chain_save_requested.connect(_on_standalone_chain_save_requested)
	if _standalone_chain_remove_callback.is_valid():
		panel.standalone_chain_remove_requested.connect(_on_standalone_chain_remove_requested)
	if _standalone_bounds_save_callback.is_valid():
		panel.standalone_bounds_save_requested.connect(_on_standalone_bounds_save_requested)
	if _dialogue_save_callback.is_valid():
		panel.dialogue_save_requested.connect(_on_dialogue_save_requested)
	if _shop_save_callback.is_valid():
		panel.shop_save_requested.connect(_on_shop_save_requested)
	if _shop_migrate_callback.is_valid():
		panel.shop_migrate_requested.connect(_on_shop_migrate_requested)
	if _item_save_callback.is_valid():
		panel.item_save_requested.connect(_on_item_save_requested)
	if _item_migrate_callback.is_valid():
		panel.item_migrate_requested.connect(_on_item_migrate_requested)
	if _quest_save_callback.is_valid():
		panel.quest_save_requested.connect(_on_quest_save_requested)
	return panel


func _on_rebuild_requested(prop: EmberVoxelProp) -> void:
	if _rebuild_callback.is_valid():
		_rebuild_callback.call(prop)


func _on_interact_save_requested(prop: EmberVoxelProp, values: Dictionary) -> void:
	if _interact_save_callback.is_valid():
		_interact_save_callback.call(prop, values)


func _on_interact_remove_requested(prop: EmberVoxelProp) -> void:
	if _interact_remove_callback.is_valid():
		_interact_remove_callback.call(prop)


func _on_chain_save_requested(prop: EmberVoxelProp, document: Dictionary) -> void:
	if _chain_save_callback.is_valid():
		_chain_save_callback.call(prop, document)


func _on_chain_remove_requested(prop: EmberVoxelProp) -> void:
	if _chain_remove_callback.is_valid():
		_chain_remove_callback.call(prop)


func _on_standalone_save_requested(interact: EmberInteract, values: Dictionary) -> void:
	if _standalone_save_callback.is_valid():
		_standalone_save_callback.call(interact, values)


func _on_standalone_remove_requested(interact: EmberInteract) -> void:
	if _standalone_remove_callback.is_valid():
		_standalone_remove_callback.call(interact)


func _on_standalone_chain_save_requested(interact: EmberInteract, document: Dictionary) -> void:
	if _standalone_chain_save_callback.is_valid():
		_standalone_chain_save_callback.call(interact, document)


func _on_standalone_chain_remove_requested(interact: EmberInteract) -> void:
	if _standalone_chain_remove_callback.is_valid():
		_standalone_chain_remove_callback.call(interact)


func _on_standalone_bounds_save_requested(interact: EmberInteract, size: Vector3) -> void:
	if _standalone_bounds_save_callback.is_valid():
		_standalone_bounds_save_callback.call(interact, size)


func _on_dialogue_save_requested(document: Dictionary) -> void:
	if _dialogue_save_callback.is_valid():
		_dialogue_save_callback.call(document)


func _on_shop_save_requested(document: Dictionary) -> void:
	if _shop_save_callback.is_valid():
		_shop_save_callback.call(document)


func _on_shop_migrate_requested(shop_id: String) -> void:
	if _shop_migrate_callback.is_valid():
		_shop_migrate_callback.call(shop_id)


func _on_item_save_requested(document: Dictionary) -> void:
	if _item_save_callback.is_valid():
		_item_save_callback.call(document)


func _on_item_migrate_requested(item_id: String) -> void:
	if _item_migrate_callback.is_valid():
		_item_migrate_callback.call(item_id)


func _on_quest_save_requested(interact: EmberInteract, document: Dictionary) -> void:
	if _quest_save_callback.is_valid():
		_quest_save_callback.call(interact, document)
