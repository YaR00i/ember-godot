@tool
class_name EmberObjectInspectorPlugin
extends EditorInspectorPlugin
## Routes supported Ember nodes into one read-only native Inspector block.

const InspectorPanel = preload("res://addons/ember_import/ember_object_inspector_panel.gd")

var _rebuild_callback: Callable
var canvas_callback: Callable
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
var _item_save_callback: Callable
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
	item_save_callback: Callable = Callable(),
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
	_item_save_callback = item_save_callback
	_quest_save_callback = quest_save_callback


func _can_handle(object: Object) -> bool:
	return EmberObjectInspectorModel.supports(object)


func _parse_begin(object: Object) -> void:
	add_custom_control(build_panel(object))


class PatternSizeProperty extends EditorProperty:
	var value:=SpinBox.new()
	func _init()->void:
		value.min_value=0.125;value.max_value=16.0;value.step=0.025;value.suffix="×"
		value.tooltip_text="1 — масштаб материала земли. Больше — крупнее рисунок только выбранного объекта; глубина и форма прежние."
		add_child(value);add_focusable(value.get_line_edit())
		value.value_changed.connect(func(number:float):emit_changed(get_edited_property(),number))
	func _update_property()->void:
		if get_edited_object()==null:return
		value.set_block_signals(true);value.value=get_edited_object().get(get_edited_property());value.set_block_signals(false)
	func _set_read_only(readonly:bool)->void:
		value.editable=not readonly


class NpcModelProperty extends EditorProperty:
	var _choice := OptionButton.new()
	var _models: Array[PackedScene] = []

	func _init() -> void:
		_models = EmberMapLoader.WorldPresets.npc_models.duplicate()
		_choice.add_item("Модель из сцены NPC")
		for model: PackedScene in _models:
			var caption := model.resource_name
			if caption.is_empty(): caption = model.resource_path.get_file().get_basename()
			_choice.add_item(caption)
		add_child(_choice)
		add_focusable(_choice)
		_choice.item_selected.connect(func(index: int):
			emit_changed(get_edited_property(), null if index == 0 else _models[index - 1]))

	func _update_property() -> void:
		var object := get_edited_object()
		if object == null: return
		var model := object.get(get_edited_property()) as PackedScene
		var index := _models.find(model)
		if model != null and index < 0:
			_models.append(model)
			_choice.add_item(model.resource_path.get_file().get_basename())
			index = _models.size() - 1
		_choice.select(index + 1)

	func _set_read_only(readonly: bool) -> void:
		_choice.disabled = readonly


func _parse_property(object:Object,_type:Variant.Type,property:String,_hint:PropertyHint,_hint_text:String,_usage:int,_wide:bool)->bool:
	if object is EmberInteract and property == "model_preset":
		add_property_editor(property, NpcModelProperty.new(), false, "Модель NPC из библиотеки")
		return true
	if object is EmberVoxelProp and property=="material_pattern_scale":
		var visual:=object.get_node_or_null("Mesh") as MeshInstance3D
		if visual==null or visual.mesh==null or not visual.mesh.has_meta("solid_surface_material_ids"):return true
		var editor:=PatternSizeProperty.new()
		if visual.material_override!=null and not visual.material_override.get_meta("ember_derived_solid_material",false):
			editor.read_only=true
			editor.tooltip_text="У объекта собственный материал. Регулятор относится к общему генерируемому покрытию."
		add_property_editor(property,editor,false,"Размер рисунка")
		return true
	return false


func build_panel(object: Object) -> EmberObjectInspectorPanel:
	var panel := InspectorPanel.new() as EmberObjectInspectorPanel
	panel.setup(object, EmberObjectInspectorModel.snapshot(object))
	if canvas_callback.is_valid():
		panel.canvas_action_requested.connect(canvas_callback)
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
	if _item_save_callback.is_valid():
		panel.item_save_requested.connect(_on_item_save_requested)
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


func _on_item_save_requested(document: Dictionary) -> void:
	if _item_save_callback.is_valid():
		_item_save_callback.call(document)


func _on_quest_save_requested(interact: EmberInteract, document: Dictionary) -> void:
	if _quest_save_callback.is_valid():
		_quest_save_callback.call(interact, document)
