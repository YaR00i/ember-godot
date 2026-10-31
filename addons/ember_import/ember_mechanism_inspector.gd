@tool
extends VBoxContainer
## Context view over the existing Workspace property editor and scene commands.
const Model = preload("res://scripts/ember_mechanism_graph.gd")
const Geometry = preload("res://scripts/ember_mechanism_role_geometry.gd")
var _scene: Node3D
var _actions: RefCounted
var _workspace: Window
var _wires: HBoxContainer
var _selection := Callable()
var _object: Node3D
var _title: Label
var _role: Label
var _palette: GridContainer
var _fields: VBoxContainer
var _logic_picker: OptionButton
var _message: Label
var _logic_menu: MenuButton
var _roles := {}
var _new_circuit: CheckBox
var _focus_circuit: WeakRef
var _focus_id := ""

func setup(scene: Node3D, actions: RefCounted, workspace: Window, wires: HBoxContainer, selection: Callable) -> void:
	_scene = scene; _actions = actions; _workspace = workspace; _wires = wires; _selection = selection
	add_theme_constant_override("separation", 8)
	_title = Label.new(); _title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(_title)
	var picker: OptionButton = wires._picker
	picker.get_parent().remove_child(picker); picker.custom_minimum_size.x = 0; picker.fit_to_longest_item = false; picker.clip_text = true
	add_child(picker); picker.show()
	picker.item_selected.connect(_on_circuit_selected)
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	var content := VBoxContainer.new(); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(content)
	_new_circuit = CheckBox.new(); _new_circuit.text = "В новом механизме"; content.add_child(_new_circuit)
	_palette = GridContainer.new(); _palette.columns = 2; content.add_child(_palette)
	for entry in [["plate", "Плита", "Area3D"], ["door", "Дверь", "AnimatableBody3D"], ["lever", "Рычаг", "Node3D"], ["lamp", "Лампа", "OmniLight3D"]]:
		var kind := str(entry[0]); var button := Button.new(); button.text = str(entry[1])
		button.custom_minimum_size = Vector2(94, 52); button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if Engine.is_editor_hint():
			var theme := EditorInterface.get_editor_theme()
			if theme.has_icon(str(entry[2]), "EditorIcons"): button.icon = theme.get_icon(str(entry[2]), "EditorIcons")
		button.pressed.connect(assign_role.bind(kind)); _palette.add_child(button); _roles[kind] = button
	_role = Label.new(); _role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; content.add_child(_role)
	_fields = workspace.take_property_editor(); content.add_child(_fields)
	var ports := CheckButton.new(); ports.name = "MechanismPorts"; ports.text = "Показать провода"; ports.button_pressed = wires._show_ports
	ports.toggled.connect(wires.set_ports_visible); content.add_child(ports)
	_logic_menu = MenuButton.new(); _logic_menu.text = "+ Логический блок"; content.add_child(_logic_menu)
	for kind in ["all", "any", "not", "hold", "latch"]:
		_logic_menu.get_popup().add_item(str(Model.LABELS[kind]))
		_logic_menu.get_popup().set_item_metadata(_logic_menu.get_popup().item_count - 1, kind)
	_logic_menu.get_popup().id_pressed.connect(func(id):
		if _available(): workspace.add_logic(str(_logic_menu.get_popup().get_item_metadata(id)))
	)
	_logic_picker = OptionButton.new(); _logic_picker.fit_to_longest_item = false; _logic_picker.clip_text = true; content.add_child(_logic_picker)
	_logic_picker.item_selected.connect(func(i): focus_component(wires.circuit(), str(_logic_picker.get_item_metadata(i))))
	var graph := Button.new(); graph.text = "Полная схема…"; content.add_child(graph)
	graph.pressed.connect(func():
		if _available(): workspace.popup_centered_clamped(Vector2i(1100, 680), 0.9)
	)
	_message = Label.new(); _message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(_message)
	var history := HBoxContainer.new(); add_child(history)
	for entry in [["Отменить", false], ["Повторить", true]]:
		var button := Button.new(); button.text = str(entry[0]); button.pressed.connect(workspace._undo.bind(bool(entry[1]))); history.add_child(button)
	var save := Button.new(); save.text = "Сохранить сцену"; add_child(save)
	save.pressed.connect(func(): if _available() and workspace._save.is_valid(): workspace._save.call())
	workspace.component_selected.connect(_show_component)
	workspace.document_result.connect(_set_message)
	wires.component_chosen.connect(focus_component)
	wires.logic_requested.connect(_add_wired_logic)
	actions.scene_binding_changed.connect(refresh)
	refresh()

func _available() -> bool:
	return is_instance_valid(_scene) and _scene.is_inside_tree() and _workspace._available()

func release_view() -> void:
	if is_instance_valid(_wires) and is_instance_valid(_wires._picker) and _wires._picker.item_selected.is_connected(_on_circuit_selected):
		_wires._picker.item_selected.disconnect(_on_circuit_selected)
	if is_instance_valid(_wires) and is_instance_valid(_wires._picker) and _wires._picker.get_parent() == self:
		remove_child(_wires._picker); _wires.add_child(_wires._picker); _wires._picker.hide()

func _on_circuit_selected(_index: int) -> void:
	_focus_id = ""; _object = null
	_wires._selected = ""; _wires._draft = ""
	var circuit: Node3D = _wires.circuit()
	if circuit == null: refresh(); return
	_workspace.focus_component(circuit, "")
	_palette.hide(); _new_circuit.hide(); _fields.hide(); _role.hide()
	_title.text = str(circuit.name)
	_logic_menu.disabled = false; _logic_picker.clear()
	for row in circuit.snapshot().nodes:
		if str(row.kind) in ["all", "any", "not", "hold", "latch"]:
			_logic_picker.add_item(str(row.label)); _logic_picker.set_item_metadata(_logic_picker.item_count - 1, str(row.id))
	_logic_picker.visible = _logic_picker.item_count > 0
	_set_message("Выбери предмет в3D или логический блок.")

func refresh() -> void:
	if not _available(): return
	_wires._picker.visible = _wires._picker.item_count > 0
	if _focus_circuit != null and not _focus_id.is_empty():
		var focused := _focus_circuit.get_ref() as Node3D
		if focused != null and focused.is_inside_tree() and _scene.is_ancestor_of(focused) and focused.component(_focus_id) != null:
			focus_component(focused, _focus_id); return
		_focus_id = ""
	var object: Node3D = _selection.call() as Node3D if _selection.is_valid() else null
	if object != null and object != _scene and _scene.is_ancestor_of(object):
		_object = object
		var parent: Node = object
		while parent != null and parent != _scene:
			if parent.has_meta("mechanism_role_id"): _object = parent.get_parent() as Node3D; break
			parent = parent.get_parent()
	else: _object = null
	if is_instance_valid(_object) and _object.has_method("snapshot") and _object.has_method("toggle_lever"):
		_wires.refresh_circuits()
		for i in _wires._picker.item_count:
			if _wires._picker.get_item_metadata(i).get_ref() == _object:
				_wires._picker.select(i); _on_circuit_selected(i); return
	var circuit: Node3D = _wires.circuit()
	var id := ""
	if is_instance_valid(_object):
		for owner_node in _scene.find_children("*", "Node3D", true, false):
			if not owner_node.has_method("snapshot") or not owner_node.has_method("toggle_lever"): continue
			for row in owner_node.snapshot().nodes:
				if str(row.target).is_empty(): continue
				var bound := Geometry.object_for(owner_node.get_node_or_null(NodePath(str(row.target))) as Node3D)
				if bound == _object:
					circuit = owner_node; id = str(row.id); break
			if not id.is_empty(): break
	_logic_menu.disabled = circuit == null
	_logic_picker.clear()
	if circuit != null:
		for row in circuit.snapshot().nodes:
			if str(row.kind) in ["all", "any", "not", "hold", "latch"]:
				_logic_picker.add_item(str(row.label)); _logic_picker.set_item_metadata(_logic_picker.item_count - 1, str(row.id))
	_logic_picker.visible = _logic_picker.item_count > 0
	if not id.is_empty(): focus_component(circuit, id); return
	_title.text = str(_object.name) if is_instance_valid(_object) else "Выбери объект в3D"
	_palette.visible = is_instance_valid(_object); _new_circuit.visible = _palette.visible and _wires._picker.item_count > 0; _fields.hide(); _role.hide()
	_set_message("Выбери роль предмета" if is_instance_valid(_object) else "Или выбери логический блок в списке.")
	for kind in _roles: _roles[kind].disabled = not is_instance_valid(_object)

func focus_component(circuit: Node3D, id: String) -> void:
	if not _available() or circuit == null or not _scene.is_ancestor_of(circuit) or circuit.component(id) == null: return
	_focus_circuit = weakref(circuit); _focus_id = id
	_wires._picker.show()
	for i in _wires._picker.item_count:
		if _wires._picker.get_item_metadata(i).get_ref() == circuit: _wires._picker.select(i); break
	_wires._selected = id; _workspace.focus_component(circuit, id)

func _show_component(circuit: Node3D, id: String) -> void:
	if not _available(): return
	var component: Node = circuit.component(id) if circuit != null else null
	if component == null: return
	_focus_circuit = weakref(circuit); _focus_id = id
	_logic_menu.disabled = false
	for i in _wires._picker.item_count:
		if _wires._picker.get_item_metadata(i).get_ref() == circuit: _wires._picker.select(i); break
	_logic_picker.clear()
	for row in circuit.snapshot().nodes:
		if str(row.kind) in ["all", "any", "not", "hold", "latch"]:
			_logic_picker.add_item(str(row.label)); _logic_picker.set_item_metadata(_logic_picker.item_count - 1, str(row.id))
	_logic_picker.visible = _logic_picker.item_count > 0
	_title.text = str(component.label); _role.text = str(Model.LABELS[component.kind]); _role.show()
	_palette.hide(); _new_circuit.hide(); _fields.show(); _set_message("")
	_wires._selected = id

func select_native_object() -> void:
	_focus_id = ""; refresh()

func _set_message(message: String) -> void:
	_message.text = message; _message.visible = not message.is_empty()

func assign_role(kind: String) -> void:
	if not _available(): return
	var result: Dictionary = _actions.assign_mechanism_role(_scene, _object, kind, null if _new_circuit.button_pressed else _wires.circuit())
	if not result.ok: _set_message(str(result.error)); return
	_new_circuit.button_pressed = false
	_wires.refresh_circuits(); focus_component(result.circuit, str(result.id))

func _add_wired_logic(circuit: Node3D, kind: String, source_id: String, world_position: Vector3) -> void:
	if not _available() or circuit != _wires.circuit(): return
	_workspace.focus_component(circuit, "")
	var id: String = _workspace.add_logic(kind, source_id, world_position)
	if not id.is_empty():
		focus_component(circuit, id); _wires.continue_from(circuit, id)
