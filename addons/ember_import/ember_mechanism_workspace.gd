@tool
extends Window
signal component_selected(circuit: Node3D, id: String)
signal document_result(message: String)
## Native scene authoring view. All changes use InspectorActions and the scene history.
const Model = preload("res://scripts/ember_mechanism_graph.gd")
var _scene: WeakRef
var _circuit: WeakRef
var _actions: RefCounted
var _current_scene := Callable()
var _create := Callable()
var _save := Callable()
var _picker: OptionButton
var _graph: GraphEdit
var _message: Label
var _kind: OptionButton
var _name: LineEdit
var _target: OptionButton
var _crate: OptionButton
var _clearance: OptionButton
var _seconds: SpinBox
var _settle: SpinBox
var _weight: SpinBox
var _actor_weight: SpinBox
var _hold: SpinBox
var _lift: SpinBox
var _selected := ""
var _document := {}
var _signature := ""
var _property_fields: VBoxContainer
var _context_properties := false
var _remove_button: Button
func _init() -> void:
	visible = false

func setup(scene: Node3D, actions: RefCounted, current_scene: Callable = Callable(), create: Callable = Callable(), save: Callable = Callable()) -> void:
	_scene = weakref(scene)
	_actions = actions
	_current_scene = current_scene
	_create = create
	_save = save
	title = "Ember · Механизмы"
	min_size = Vector2i(980, 680)
	_build()
	_refresh()
	close_requested.connect(hide)
	if not _actions.scene_binding_changed.is_connected(_refresh): _actions.scene_binding_changed.connect(_refresh)
func root_circuit() -> Node3D:
	return _circuit.get_ref() as Node3D if _circuit != null else null
func focus_component(circuit: Node3D, id: String) -> void:
	if circuit == null: return
	_circuit = weakref(circuit)
	_selected = id
	_refresh()
func _available() -> bool:
	return _scene != null and is_instance_valid(_scene.get_ref()) and (not _current_scene.is_valid() or _current_scene.call())
func _build() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	_picker = OptionButton.new()
	_picker.name = "MechanismCircuit"
	_picker.custom_minimum_size.x = 240
	_picker.item_selected.connect(func(_index):
		_circuit = weakref(_picker.get_selected_metadata())
		_selected = ""
		_render()
	)
	toolbar.add_child(_picker)
	_button(toolbar, "Создать набор", func():
		if not _available(): _message.text = "Карта сменилась. Открой окно заново."; return
		if _create.is_valid(): _create.call(); _refresh()
		else: _message.text = "Создание набора доступно в редакторе Godot."
	)
	_button(toolbar, "Отменить", _undo.bind(false))
	_button(toolbar, "Повторить", _undo.bind(true))
	_button(toolbar, "Сохранить сцену", func():
		if not _available(): _message.text = "Карта сменилась. Открой окно заново."; return
		if _save.is_valid(): _save.call()
		else: _message.text = "В F6 изменения временные. Для сохранения открой механизм в редакторе."
	)
	_message = Label.new()
	_message.name = "MechanismMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(split)
	_graph = GraphEdit.new()
	_graph.name = "MechanismGraph"
	_graph.custom_minimum_size.x = 640
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.right_disconnects = true
	_graph.connection_request.connect(connect_wire)
	_graph.disconnection_request.connect(disconnect_wire)
	_graph.delete_nodes_request.connect(_delete_nodes)
	_graph.node_selected.connect(func(node: Node): _select(str(node.name)))
	_graph.end_node_move.connect(_move_nodes)
	split.add_child(_graph)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300
	split.add_child(scroll)
	var fields := VBoxContainer.new()
	_property_fields = fields
	fields.custom_minimum_size.x = 280
	scroll.add_child(fields)
	var hint := Label.new()
	hint.text = "Проведи провод от выхода справа к входу слева.\nСнять провод — потянуть за подключённый вход.\nПеремещение карточки не двигает объект на карте."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(hint)
	_kind = OptionButton.new()
	_kind.name = "MechanismKind"
	for key in Model.LABELS:
		_kind.add_item(str(Model.LABELS[key])); _kind.set_item_metadata(_kind.item_count - 1, key)
	_kind.select(2)
	_kind.item_selected.connect(func(_i): _fill_bindings())
	fields.add_child(_kind)
	_name = LineEdit.new()
	_name.name = "MechanismLabel"
	_name.placeholder_text = "Название компонента"
	fields.add_child(_name)
	_target = _field_picker(fields, "Объект на карте", "MechanismTarget")
	_crate = _field_picker(fields, "Ящик для плиты", "MechanismCrate")
	_clearance = _field_picker(fields, "Зона безопасности двери", "MechanismClearance")
	_seconds = _number(fields, "Движение, секунд", "MechanismSeconds", 0.1, 3.0, 0.6)
	_settle = _number(fields, "Покой на плите, секунд", "MechanismSettle", 0.0, 3.0, 0.35)
	_weight = _number(fields, "Нужный вес (0 — любой груз)", "MechanismWeight", 0.0, 1000.0, 0.0)
	_actor_weight = _number(fields, "Вес персонажа (0 — не учитывать)", "MechanismActorWeight", 0.0, 1000.0, 1.0)
	_hold = _number(fields, "После выключения входа, секунд", "MechanismHold", 0.05, 120.0, 3.0)
	_lift = _number(fields, "Подъём двери (Y)", "MechanismLift", 1.0, 256.0, 40.0)
	_lift.allow_greater = true; _lift.allow_lesser = true
	_seconds.allow_greater = true; _settle.allow_greater = true
	_button(fields, "Добавить компонент", _add_component).name = "AddComponent"
	_button(fields, "Применить параметры", _apply_fields)
	_remove_button = _button(fields, "Удалить выбранный", func():
		if not _selected.is_empty(): _delete_nodes([StringName(_selected)])
	)
func _button(parent: Node, label: String, callback: Callable) -> Button:
	var button := Button.new(); button.text = label
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
func _field_picker(parent: Node, title_text: String, node_name: String) -> OptionButton:
	var label := Label.new(); label.text = title_text; parent.add_child(label)
	var picker := OptionButton.new(); picker.name = node_name
	picker.set_meta("field_label", label)
	picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	picker.fit_to_longest_item = false
	parent.add_child(picker)
	return picker
func _number(parent: Node, text: String, node_name: String, minimum: float, maximum: float, value: float) -> SpinBox:
	var label := Label.new(); label.text = text; parent.add_child(label)
	var number := SpinBox.new(); number.name = node_name
	number.set_meta("field_label", label)
	number.min_value = minimum; number.max_value = maximum; number.step = 0.05; number.value = value
	parent.add_child(number)
	return number
func _refresh() -> void:
	if not is_instance_valid(_picker) or not _available(): return
	var selected := root_circuit()
	_picker.clear()
	var scene := _scene.get_ref() as Node3D
	var nodes: Array[Node] = [scene]
	nodes.append_array(scene.find_children("*", "Node3D", true, false))
	for node in nodes:
		if node.has_method("toggle_lever") and node.has_method("snapshot"):
			_picker.add_item(str(node.name))
			_picker.set_item_metadata(_picker.item_count - 1, node)
			if node == selected: _picker.select(_picker.item_count - 1)
	_circuit = weakref(_picker.get_selected_metadata()) if _picker.item_count > 0 else null
	_render()
func _render() -> void:
	for node in _graph.get_children():
		if node is GraphNode: _graph.remove_child(node); node.queue_free()
	_graph.clear_connections()
	var circuit := root_circuit()
	if circuit == null:
		_document = {}; _message.text = "В сцене нет механизма. Нажми «Создать набор»."; return
	_document = circuit.snapshot()
	var errors: Array[String] = circuit.document_errors(_document)
	_message.text = errors[0] if not errors.is_empty() else "Схема сцены · изменения отменяются через Undo и сохраняются вместе с .tscn"
	for row in _document.nodes:
		var node := GraphNode.new()
		node.name = str(row.id)
		node.title = str(row.label) + " · " + str(Model.LABELS.get(str(row.kind), row.kind))
		node.position_offset = row.get("position", Vector2.ZERO)
		node.custom_minimum_size.x = 210
		_graph.add_child(node)
		for port in maxi(1, Model.inputs(str(row.kind))):
			var slot := HBoxContainer.new()
			slot.name = "Signal%d" % port
			var input_label := Label.new()
			input_label.name = "Input"
			input_label.text = Model.input_label(str(row.kind), port) if Model.inputs(str(row.kind)) > 0 else ""
			slot.add_child(input_label)
			var output_label := Label.new()
			output_label.name = "Output"
			output_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			output_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			output_label.text = "Выход →" if port == 0 and Model.output(str(row.kind)) else ""
			slot.add_child(output_label)
			node.add_child(slot)
			node.set_slot(port, port < Model.inputs(str(row.kind)), 0, Color("74b8db"), port == 0 and Model.output(str(row.kind)), 0, Color("67d6bd"))
	for link in _document.links:
		if _graph.has_node(NodePath(str(link.from))) and _graph.has_node(NodePath(str(link.to))): _graph.connect_node(str(link.from), 0, str(link.to), int(link.port))
	if not _selected.is_empty(): _select(_selected)
	else: _fill_bindings()
	_signature = ""
func _select(id: String) -> void:
	_selected = id
	for row in _document.get("nodes", []):
		if str(row.id) != id: continue
		_name.text = str(row.label)
		for i in _kind.item_count:
			if str(_kind.get_item_metadata(i)) == str(row.kind): _kind.select(i)
		_fill_bindings(row)
		_seconds.value = float(row.get("seconds", 0.6))
		_settle.value = float(row.get("settle", 0.35))
		_weight.value = float(row.get("required_weight", 0.0))
		_actor_weight.value = float(row.get("character_weight", 1.0))
		_hold.value = float(row.get("hold_seconds", 3.0))
		var offset: Vector3 = row.get("offset", Vector3(0, 40, 0))
		_lift.value = offset.y
		component_selected.emit(root_circuit(), id)
		return
func _fill_bindings(row: Dictionary = {}) -> void:
	var circuit := root_circuit()
	var kind := str(_kind.get_selected_metadata())
	var candidates: Array[Node] = []
	if circuit != null: candidates = circuit.binding_scene().find_children("*", "Node3D", true, false)
	for pair in [[_target, "target"], [_crate, "crate"], [_clearance, "clearance"]]:
		var picker: OptionButton = pair[0]
		picker.clear(); picker.add_item("— выбери объект —"); picker.set_item_metadata(0, "")
		if _context_properties and pair[1] == "crate": picker.set_item_text(0, "Любой персонаж / предмет")
		var current := str(row.get(pair[1], ""))
		for node in candidates:
			if not circuit.owns_target(node): continue
			var accepted := node is RigidBody3D and node.get("pickup_id") != null if pair[1] == "crate" else node is Area3D and not node is EmberInteract if pair[1] == "clearance" else (node is Area3D and not node is EmberInteract) if kind == "plate" else (node is AnimatableBody3D or preload("res://scripts/ember_mechanism_role_geometry.gd").helper_for(node, _selected) != null) if kind == "door" else (node is MeshInstance3D or node is Light3D) if kind == "lamp" else node is Node3D if kind == "lever" else false
			if not accepted: continue
			var path := str(circuit.get_path_to(node))
			picker.add_item(str(node.name) if _context_properties else path); picker.set_item_metadata(picker.item_count - 1, path)
			picker.get_popup().set_item_tooltip(picker.item_count - 1, path)
			if path == current: picker.select(picker.item_count - 1)
		if picker.selected == 0 and not current.is_empty():
			picker.add_item("Сохранено · " + current); picker.set_item_metadata(picker.item_count - 1, current); picker.select(picker.item_count - 1)
		picker.disabled = (pair[1] == "crate" and kind != "plate") or (pair[1] == "clearance" and kind != "door") or (pair[1] == "target" and kind in ["all", "any", "not", "hold", "latch"])
		picker.visible = not picker.disabled
		picker.get_meta("field_label").visible = picker.visible
		if _context_properties and pair[1] == "target":
			picker.hide(); picker.get_meta("field_label").hide()
		if _context_properties and pair[1] == "clearance" and circuit != null:
			var area := circuit.get_node_or_null(NodePath(current)) if not current.is_empty() else null
			if area != null and area.get_parent().has_meta("mechanism_role_id"):
				picker.hide(); picker.get_meta("field_label").hide()
	for pair in [[_seconds, kind == "door"], [_lift, kind == "door"], [_settle, kind == "plate"], [_weight, kind == "plate"], [_actor_weight, kind == "plate"], [_hold, kind == "hold"]]:
		pair[0].visible = pair[1]
		pair[0].get_meta("field_label").visible = pair[1]
func take_property_editor() -> VBoxContainer:
	_context_properties = true
	_remove_button.text = "Убрать из механизма"
	_lift.get_meta("field_label").text = "Высота подъёма"
	_seconds.get_meta("field_label").text = "Время движения, с"
	_settle.get_meta("field_label").text = "Задержка срабатывания, с"
	_hold.get_meta("field_label").text = "Удержание после выключения, с"
	_property_fields.custom_minimum_size.x = 0
	for control in _property_fields.get_children():
		if control is Label: control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if control is OptionButton: control.clip_text = true; control.fit_to_longest_item = false
	_property_fields.get_child(0).hide()
	_kind.hide(); _property_fields.get_node("AddComponent").hide()
	_property_fields.get_parent().hide()
	_property_fields.get_parent().remove_child(_property_fields)
	_fill_bindings(_row(_selected))
	return _property_fields

func add_logic(kind: String, source_id: String = "", world_position: Variant = null) -> String:
	if kind not in ["all", "any", "not", "hold", "latch"] or not _available() or root_circuit() == null: return ""
	for i in _kind.item_count:
		if str(_kind.get_item_metadata(i)) == kind: _kind.select(i); break
	_name.text = str(Model.LABELS[kind]); _fill_bindings()
	var id := "node_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var document := _document.duplicate(true)
	var row := _fields(id)
	if world_position != null: row["world_position"] = world_position
	document.nodes.append(row)
	if not source_id.is_empty(): document.links.append({"from": source_id, "to": id, "port": 0})
	_selected = id; _apply(document)
	return id if root_circuit().component(id) != null else ""

func _row(id: String) -> Dictionary:
	for row in _document.get("nodes", []):
		if str(row.id) == id: return row.duplicate(true)
	return {}
func _fields(id: String) -> Dictionary:
	var row := _row(id)
	row["id"] = id; row["kind"] = str(_kind.get_selected_metadata())
	row["label"] = _name.text.strip_edges() if not _name.text.strip_edges().is_empty() else str(Model.LABELS.get(row.kind, row.kind))
	for pair in [["target", _target], ["crate", _crate], ["clearance", _clearance]]: row[pair[0]] = str(pair[1].get_selected_metadata())
	row["seconds"] = _seconds.value; row["settle"] = _settle.value
	row["hold_seconds"] = _hold.value
	row["required_weight"] = _weight.value
	row["character_weight"] = _actor_weight.value
	var offset: Vector3 = row.get("offset", Vector3(0, 40, 0)); offset.y = _lift.value; row["offset"] = offset
	row["position"] = row.get("position", _free_position())
	return row
func _free_position() -> Vector2:
	var origin := _graph.scroll_offset / _graph.zoom
	for y in 20:
		for x in 3:
			var at := origin + Vector2(40 + x * 310, 40 + y * 170)
			var occupied := false
			for row in _document.get("nodes", []):
				var node := _graph.get_node_or_null(NodePath(str(row.id))) as GraphNode
				var size := node.size.max(Vector2(240, 110)) if node else Vector2(240, 110)
				if Rect2(row.get("position", Vector2.ZERO) - Vector2(10, 10), size + Vector2(20, 20)).intersects(Rect2(at, Vector2(240, 110))): occupied = true; break
			if not occupied: return at
	return origin + Vector2(100, 100)
func _add_component() -> void:
	if root_circuit() == null: return
	var id := "node_" + Crypto.new().generate_random_bytes(8).hex_encode()
	var document := _document.duplicate(true)
	document.nodes.append(_fields(id))
	_selected = id
	_apply(document)
	var node := _graph.get_node_or_null(NodePath(id)) as GraphNode
	if node:
		_graph.set_selected(node)
		_graph.scroll_offset = node.position_offset * _graph.zoom - Vector2(120, 120)
func _apply_fields() -> void:
	if _selected.is_empty(): _message.text = "Выбери карточку в схеме."; return
	var document := _document.duplicate(true)
	for index in document.nodes.size():
		if str(document.nodes[index].id) == _selected: document.nodes[index] = _fields(_selected)
	_apply(document)
func connect_wire(source: StringName, _source_port: int, target: StringName, target_port: int) -> void:
	if _document.is_empty(): return
	var document := _document.duplicate(true)
	document.links.append({"from": str(source), "to": str(target), "port": target_port})
	_apply(document)
func disconnect_wire(source: StringName, _source_port: int, target: StringName, target_port: int) -> void:
	if _document.is_empty(): return
	var document := _document.duplicate(true)
	for index in range(document.links.size() - 1, -1, -1):
		var link: Dictionary = document.links[index]
		if str(link.from) == str(source) and str(link.to) == str(target) and int(link.port) == target_port: document.links.remove_at(index)
	_apply(document)
func _delete_nodes(names: Array[StringName]) -> void:
	var document := _document.duplicate(true)
	for index in range(document.nodes.size() - 1, -1, -1):
		if StringName(str(document.nodes[index].id)) in names: document.nodes.remove_at(index)
	for index in range(document.links.size() - 1, -1, -1):
		if StringName(str(document.links[index].from)) in names or StringName(str(document.links[index].to)) in names: document.links.remove_at(index)
	_selected = ""
	_apply(document)
func _move_nodes() -> void:
	var document := _document.duplicate(true)
	for row in document.nodes:
		var node := _graph.get_node_or_null(NodePath(str(row.id))) as GraphNode
		if node: row["position"] = node.position_offset
	_apply(document)
func _apply(document: Dictionary) -> void:
	if not _available() or root_circuit() == null: _message.text = "Карта сменилась. Открой окно заново."; return
	var result: Dictionary = _actions.apply_mechanism_document(root_circuit(), document)
	if not result.ok: _message.text = str(result.error)
	else: _render()
	document_result.emit(str(result.error) if not result.ok else "Изменения применены")
func _undo(redo: bool) -> void:
	if not _available() or root_circuit() == null: return
	var history: Object = _actions.get("_undo_redo")
	if history.has_method("get_history_undo_redo"): history = history.get_history_undo_redo(history.get_object_history_id(root_circuit()))
	if redo: history.redo()
	else: history.undo()
	_refresh()
func _process(_delta: float) -> void:
	var circuit := root_circuit()
	if not visible or circuit == null or Engine.is_editor_hint(): return
	var signature := str(circuit.values)
	if signature == _signature: return
	_signature = signature
	for row in _document.get("nodes", []):
		var node := _graph.get_node_or_null(NodePath(str(row.id))) as GraphNode
		if node:
			var on := bool(circuit.values.get(str(row.id), false))
			node.self_modulate = Color(0.7, 1.0, 0.85) if on else Color.WHITE
			for port in maxi(1, Model.inputs(str(row.kind))):
				var input_label := node.get_node("Signal%d/Input" % port) as Label
				var output_label := node.get_node("Signal%d/Output" % port) as Label
				if port < Model.inputs(str(row.kind)):
					var input_on := false
					for wire in _document.links:
						if str(wire.to) == str(row.id) and int(wire.port) == port: input_on = bool(circuit.values.get(str(wire.from), false))
					input_label.text = Model.input_label(str(row.kind), port) + ": " + ("ДА" if input_on else "НЕТ")
				if port == 0 and Model.output(str(row.kind)): output_label.text = "Выход: " + ("ДА" if on else "НЕТ")
	for link in _document.get("links", []):
		if _graph.has_method("set_connection_activity"): _graph.call("set_connection_activity", str(link.from), 0, str(link.to), int(link.port), 1.0 if bool(circuit.values.get(str(link.from), false)) else 0.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed: return
	if event.keycode == KEY_ESCAPE:
		hide(); get_viewport().set_input_as_handled()
	elif event.ctrl_pressed or event.meta_pressed:
		if event.keycode == KEY_Z:
			_undo(event.shift_pressed); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Y:
			_undo(true); get_viewport().set_input_as_handled()
