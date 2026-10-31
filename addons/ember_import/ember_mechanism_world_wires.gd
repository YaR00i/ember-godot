@tool
extends HBoxContainer
signal editing_changed(enabled: bool)
signal component_chosen(circuit: Node3D, id: String)
signal logic_requested(circuit: Node3D, kind: String, source_id: String, world_position: Vector3)
## Editor-only projection of the existing circuit. No wire nodes enter the scene.
const Model = preload("res://scripts/ember_mechanism_graph.gd")
var active := false
var _scene: Node
var _actions: RefCounted
var _redraw := Callable()
var _properties := Callable()
var _camera: Camera3D
var _toggle: Button
var _picker: OptionButton
var _hint: Label
var _draft := ""
var _selected := ""
var _mouse := Vector2.ZERO
var _selection := Callable()
var _role_dialog: ConfirmationDialog
var _role: OptionButton
var _role_circuit: OptionButton
var _role_target: WeakRef
var _role_scene: WeakRef
var _role_message: Label
var _capture_click := false
var _inspector_mode := false
var _show_ports := true
var _logic_popup: PopupMenu
var _pending_circuit: WeakRef
var _pending_source := ""
var _pending_position := Vector3.ZERO
var _drag_root: WeakRef
var _drag_id := ""
var _drag_start := Vector2.ZERO
var _drag_origin := Vector3.ZERO
var _drag_world := Vector3.ZERO
var _drag_depth := 0.5
var _drag_moved := false
var _feedback := {}

func setup(actions: RefCounted, redraw: Callable, properties: Callable, selection: Callable = Callable()) -> void:
	_actions = actions; _redraw = redraw; _properties = properties
	_selection = selection
	_toggle = Button.new(); _toggle.text = "Провода"; _toggle.toggle_mode = true
	_toggle.tooltip_text = "Соединять компоненты механизма прямо в 3D"
	add_child(_toggle)
	_toggle.toggled.connect(func(on):
		_cancel_drag()
		_cancel_logic_menu()
		active = on and _show_ports; _draft = ""; _camera = null; _capture_click = false
		refresh_circuits()
		_picker.visible = on and (not _inspector_mode or _picker.item_count > 0)
		_request()
		editing_changed.emit(on)
	)
	_picker = OptionButton.new(); _picker.custom_minimum_size.x = 160; add_child(_picker)
	_picker.item_selected.connect(func(_i): _cancel_drag(); _draft = ""; _selected = ""; _feedback.clear(); _request())
	var role_button := Button.new(); role_button.text = "Роль объекта…"; role_button.name = "AssignMechanismRole"
	role_button.tooltip_text = "Выдели обычный предмет на карте и назначь ему роль без готового набора"
	add_child(role_button)
	role_button.pressed.connect(func():
		var target: Node3D = _selection.call() as Node3D if _selection.is_valid() else null
		open_role_dialog(target)
	)
	var properties_button := Button.new(); properties_button.text = "Свойства / схема"
	add_child(properties_button)
	properties_button.pressed.connect(func():
		if _properties.is_valid(): _properties.call(circuit(), _selected)
	)
	_hint = Label.new(); _hint.text = "Выход → вход · Shift+вход: снять · Esc: отмена"
	_hint.custom_minimum_size.x = 240; _hint.clip_text = true; _hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_hint); _picker.hide(); _hint.hide()
	_actions.scene_binding_changed.connect(func(): _cancel_drag(); refresh_circuits(); _refresh_feedback(); _request())

func use_inspector_mode() -> void:
	_inspector_mode = true; _toggle.text = "Механизмы"
	for child in get_children():
		if child != _toggle: child.hide()

func is_editing() -> bool:
	return _toggle.button_pressed if _inspector_mode else active

func set_ports_visible(on: bool) -> void:
	_cancel_drag()
	_cancel_logic_menu()
	_show_ports = on; active = is_editing() and on; _draft = ""; _request()

func set_scene(scene: Node) -> void:
	if _scene == scene and is_instance_valid(_scene): return
	_cancel_drag()
	_cancel_logic_menu()
	if is_instance_valid(_role_dialog): _role_dialog.hide()
	_role_target = null; _role_scene = null
	_scene = scene; _draft = ""; _selected = ""; active = false; _camera = null; _capture_click = false
	_toggle.set_pressed_no_signal(false); _picker.clear(); _picker.hide(); _hint.hide()
	refresh_circuits(); _request()

func open_role_dialog(target: Node3D) -> void:
	if not is_instance_valid(_role_dialog):
		_role_dialog = ConfirmationDialog.new(); _role_dialog.title = "Роль объекта в механизме"
		_role_dialog.dialog_hide_on_ok = false; _role_dialog.ok_button_text = "Назначить роль"
		_role_dialog.min_size = Vector2i(320, 180)
		add_child(_role_dialog)
		var scroll := ScrollContainer.new(); scroll.name = "RoleScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_role_dialog.add_child(scroll)
		var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(column)
		_role_message = Label.new()
		_role_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(_role_message)
		_role = OptionButton.new(); _role.name = "ObjectMechanismRole"
		_role.clip_text = true
		_role.add_item("Рычаг · переключение по F"); _role.set_item_metadata(0, "lever")
		_role.add_item("Лампа · меш или источник света"); _role.set_item_metadata(1, "lamp")
		_role.add_item("Дверь · тело и зона прохода автоматически"); _role.set_item_metadata(2, "door")
		_role.add_item("Нажимная плита · датчик автоматически"); _role.set_item_metadata(3, "plate")
		column.add_child(_role)
		_role_circuit = OptionButton.new(); _role_circuit.name = "ObjectMechanismCircuit"; _role_circuit.clip_text = true; column.add_child(_role_circuit)
		var hint := Label.new(); hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "Объект останется на месте и в своей группе.\nДля двери и плиты зоны рассчитываются по геометрии. Плита реагирует на персонажа или лежащий физический предмет.\nНастройки движения и зон можно изменить после назначения."
		column.add_child(hint)
		_role_dialog.confirmed.connect(_assign_role)
	_role_target = weakref(target) if is_instance_valid(target) else null
	_role_scene = weakref(_scene) if is_instance_valid(_scene) else null
	_role_message.text = "Объект: " + str(target.name) if is_instance_valid(target) else "Сначала выдели один обычный объект в3D или дереве сцены."
	_role_dialog.get_ok_button().disabled = not is_instance_valid(target)
	_role_circuit.clear(); _role_circuit.add_item("Новый пустой механизм"); _role_circuit.set_item_metadata(0, null)
	refresh_circuits()
	for i in _picker.item_count:
		_role_circuit.add_item(_picker.get_item_text(i)); _role_circuit.set_item_metadata(i + 1, _picker.get_item_metadata(i))
		if _picker.get_item_metadata(i).get_ref() == circuit(): _role_circuit.select(i + 1)
	_role_dialog.popup_centered_clamped(Vector2i(540, 340), 0.9)

func _assign_role() -> void:
	if _role_scene == null or not is_instance_valid(_scene) or _role_scene.get_ref() != _scene:
		_role_message.text = "Сцена сменилась. Выдели объект заново."; return
	var target: Node3D = _role_target.get_ref() as Node3D if _role_target != null else null
	var ref: WeakRef = _role_circuit.get_selected_metadata()
	var chosen := ref.get_ref() as Node3D if ref != null else null
	if ref != null and not is_instance_valid(chosen):
		_role_message.text = "Механизм удалён. Открой назначение заново."; return
	var answer: Dictionary = _actions.assign_mechanism_role(_scene as Node3D, target, str(_role.get_selected_metadata()), chosen)
	if not answer.ok: _role_message.text = str(answer.error); return
	refresh_circuits()
	for i in _picker.item_count:
		if _picker.get_item_metadata(i).get_ref() == answer.circuit: _picker.select(i); break
	_toggle.button_pressed = true
	_selected = str(answer.id); _draft = ""
	_hint.text = "Роль назначена · соедини выход и вход"
	_role_dialog.hide(); _request()

func refresh_circuits() -> void:
	var previous := circuit()
	_picker.clear()
	if not is_instance_valid(_scene): return
	var nodes: Array[Node] = [_scene]
	nodes.append_array(_scene.find_children("*", "Node3D", true, false))
	for node in nodes:
		if node.has_method("toggle_lever") and node.has_method("snapshot"):
			_picker.add_item(str(node.name)); _picker.set_item_metadata(_picker.item_count - 1, weakref(node))
			if node == previous: _picker.select(_picker.item_count - 1)
	if previous != circuit(): _draft = ""; _selected = ""

func circuit() -> Node3D:
	if _picker == null or _picker.selected < 0: return null
	var ref: WeakRef = _picker.get_selected_metadata()
	var node := ref.get_ref() as Node3D if ref != null else null
	if not is_instance_valid(node) or not node.is_inside_tree(): return null
	if not is_instance_valid(_scene) or not (_scene == node or _scene.is_ancestor_of(node)): return null
	return node

func _request() -> void:
	if _redraw.is_valid(): _redraw.call()

func ports(camera: Camera3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var root := circuit()
	if root == null or not is_instance_valid(camera): return result
	var index := 0
	var occupied: Array[Vector2] = []
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var columns := maxi(1, int((viewport_size.x - 24) / 180))
	var rows := maxi(1, int((viewport_size.y - 100) / 94))
	for row in root.snapshot().nodes:
		var target := root.get_node_or_null(NodePath(str(row.target))) as Node3D if not str(row.target).is_empty() else null
		var logical: bool = str(row.kind) in ["all", "any", "not", "hold", "latch"]
		var placed: bool = logical and row.has("world_position")
		var dragging: bool = _drag_id == str(row.id) and _drag_root != null and _drag_root.get_ref() == root and _drag_moved
		var world := root.to_global(Vector3(-35 + index * 30, 55, 0))
		if target != null:
			world = target.global_position + Vector3.UP * 12
			if target is MeshInstance3D and target.mesh:
				var bounds: AABB = target.mesh.get_aabb()
				world = target.to_global(bounds.get_center() + Vector3.UP * bounds.size.y * 0.5) + Vector3.UP * 4
		else:
			world = root.to_global(row.get("world_position", Vector3(-35 + index * 30, 55, 0)))
			index += 1
		if dragging: world = _drag_world
		if camera.is_position_behind(world): continue
		var anchor := camera.unproject_position(world)
		var center := Vector2.ZERO
		var best_distance := INF
		# Nearest vacant screen slot keeps sockets visible even in dense assemblies.
		# Thin tethers preserve the actual world anchor while labels avoid one another.
		for y in rows:
			for x in columns:
				var candidate := Vector2(96 + x * 180, 92 + y * 94)
				if candidate in occupied: continue
				var distance := candidate.distance_squared_to(anchor)
				if distance < best_distance: best_distance = distance; center = candidate
		if best_distance == INF and not (_inspector_mode and (placed or dragging)): continue
		if _inspector_mode and (placed or dragging): center = anchor - Vector2(0, 28)
		occupied.append(center)
		var count := Model.inputs(str(row.kind))
		for port in count:
			result.append({"id":str(row.id), "port":port, "output":false,
				"at":center + Vector2(-74, 28 + port * (32 if _inspector_mode else 22)), "center":center,
				"anchor":anchor, "world":world, "label":str(row.label), "kind":str(row.kind)})
		if Model.output(str(row.kind)):
			result.append({"id":str(row.id), "port":0, "output":true,
				"at":center + Vector2(74, 28), "center":center,
				"anchor":anchor, "world":world, "label":str(row.label), "kind":str(row.kind)})
	return result

func _hit(points: Array[Dictionary], at: Vector2) -> Dictionary:
	var best := {}; var distance := 14.0
	for point in points:
		var d: float = point.at.distance_to(at)
		if d < distance: best = point; distance = d
	return best

func forward_input(camera: Camera3D, event: InputEvent) -> int:
	if not active: return EditorPlugin.AFTER_GUI_INPUT_PASS
	_camera = camera
	if event is InputEventMouse:
		_mouse = event.position; _request()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not _drag_id.is_empty():
			_cancel_drag(); _hint.text = "Перемещение отменено"; _request()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		_cancel_logic_menu()
		_draft = ""; _hint.text = "Связь отменена · выход → вход"; _request()
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	if not _drag_id.is_empty():
		if event is InputEventMouseMotion:
			if _drag_root == null or _drag_root.get_ref() != circuit(): _cancel_drag()
			else:
				_drag_moved = _drag_moved or event.position.distance_to(_drag_start) >= 5.0
				_drag_world = _drag_origin + camera.project_position(event.position, _drag_depth) - camera.project_position(_drag_start, _drag_depth)
				_request()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed: _finish_drag()
			elif event.pressed: _cancel_drag()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.alt_pressed: return EditorPlugin.AFTER_GUI_INPUT_PASS
		if event.pressed:
			_capture_click = false
			var point := _hit(ports(camera), event.position)
			if not point.is_empty():
				_capture_click = true; use_port(point, event.shift_pressed)
			else:
				for candidate in ports(camera):
					var rectangle := Rect2(candidate.at + Vector2(-146 if candidate.output else 12, -14), Vector2(134, 28)) if _inspector_mode else Rect2(candidate.center + Vector2(-82, -16), Vector2(164, 82))
					if rectangle.has_point(event.position):
						_selected = candidate.id; _capture_click = true
						if _inspector_mode and str(candidate.kind) in ["all", "any", "not", "hold", "latch"]:
							_drag_root = weakref(circuit()); _drag_id = str(candidate.id); _drag_start = event.position
							_drag_depth = maxf(0.5, -camera.to_local(candidate.world).z)
							_drag_origin = camera.project_position(candidate.center + Vector2(0,28), _drag_depth)
							_drag_world = _drag_origin; _drag_moved = false
							_hint.text = "Перемести блок · отпусти мышь для сохранения · Esc: отмена"
						break
				if _capture_click: component_chosen.emit(circuit(), _selected)
				elif _inspector_mode and not _draft.is_empty() and open_logic_menu(camera, event.position):
					_capture_click = true
					return EditorPlugin.AFTER_GUI_INPUT_STOP
				_draft = ""
				_request()
			return EditorPlugin.AFTER_GUI_INPUT_STOP if _capture_click else EditorPlugin.AFTER_GUI_INPUT_PASS
		var captured := _capture_click; _capture_click = false
		return EditorPlugin.AFTER_GUI_INPUT_STOP if captured else EditorPlugin.AFTER_GUI_INPUT_PASS
	# Navigation is passed to Godot, but never forwarded to Ember painting tools.
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _cancel_drag() -> void:
	if not _drag_id.is_empty(): _capture_click = false
	_drag_root = null; _drag_id = ""; _drag_moved = false

func _finish_drag() -> void:
	var root := _drag_root.get_ref() as Node3D if _drag_root != null else null
	var id := _drag_id; var world := _drag_world; var moved := _drag_moved
	_cancel_drag()
	if not moved or root == null or root != circuit() or root.component(id) == null: _request(); return
	var document: Dictionary = root.snapshot().duplicate(true)
	for row in document.nodes:
		if str(row.id) == id: row["world_position"] = root.to_local(world)
	var answer: Dictionary = _actions.apply_mechanism_document(root, document)
	_hint.text = "Блок перемещён · отмена через Undo" if answer.ok else str(answer.error)
	_request()

func _refresh_feedback() -> void:
	_feedback.clear()
	var root := circuit()
	if root == null or _draft.is_empty(): return
	var document: Dictionary = root.snapshot()
	for row in document.nodes:
		for port in Model.inputs(str(row.kind)):
			var candidate := document.duplicate(true)
			candidate.links.append({"from":_draft, "to":str(row.id), "port":port})
			var errors := Model.errors(candidate)
			_feedback["%s:%d" % [row.id, port]] = "" if errors.is_empty() else errors[0]

func _cancel_logic_menu() -> void:
	if is_instance_valid(_logic_popup): _logic_popup.hide()
	_pending_source = ""; _pending_circuit = null

func open_logic_menu(camera: Camera3D, at: Vector2) -> bool:
	var root := circuit()
	if root == null or _draft.is_empty(): return false
	var source: Node = root.component(_draft)
	if source == null or not Model.output(str(source.kind)): return false
	var found := false; var world := Vector3.ZERO
	for point in ports(camera):
		if point.id == _draft and point.output: found = true; world = point.world; break
	if not found: return false
	if not is_instance_valid(_logic_popup):
		_logic_popup = PopupMenu.new(); _logic_popup.name = "MechanismWireAdd"
		_logic_popup.max_size = Vector2i(360, 340); add_child(_logic_popup)
		for kind in ["all", "any", "not", "hold", "latch"]:
			_logic_popup.add_item(str(Model.LABELS[kind])); _logic_popup.set_item_metadata(_logic_popup.item_count - 1, kind)
		_logic_popup.id_pressed.connect(_choose_logic)
		# PopupMenu hides before id_pressed. Let the selection consume its draft first.
		_logic_popup.popup_hide.connect(func(): _finish_logic_menu.call_deferred())
	_pending_circuit = weakref(root); _pending_source = _draft
	var depth := maxf(0.5, -camera.to_local(world).z)
	_pending_position = root.to_local(camera.project_position(at, depth))
	_logic_popup.position = get_window().position + Vector2i(get_global_mouse_position())
	_logic_popup.popup(); _hint.text = "Выбери блок: провод подключится автоматически"; _request()
	return true

func _finish_logic_menu() -> void:
	if is_instance_valid(_logic_popup) and _logic_popup.visible: return
	if _draft == _pending_source: _draft = ""
	_pending_source = ""; _pending_circuit = null; _request()

func _choose_logic(index: int) -> void:
	var root := _pending_circuit.get_ref() as Node3D if _pending_circuit != null else null
	var source := _pending_source; var at := _pending_position
	_pending_circuit = null; _pending_source = ""; _draft = ""
	_logic_popup.hide()
	if not active or root == null or root != circuit() or root.component(source) == null: return
	if not Model.output(str(root.component(source).kind)): return
	logic_requested.emit(root, str(_logic_popup.get_item_metadata(index)), source, at)

func continue_from(root: Node3D, id: String) -> void:
	if not active or root != circuit() or root.component(id) == null: return
	_selected = id; _draft = id
	_refresh_feedback()
	_hint.text = "Блок добавлен · выбери следующий вход или нажми Esc"; _request()

func use_port(point: Dictionary, remove := false) -> void:
	var root := circuit()
	if root == null: return
	_selected = str(point.id)
	component_chosen.emit(root, _selected)
	if bool(point.output):
		_draft = str(point.id)
		_refresh_feedback()
		_hint.text = "Выбери вход или пустое место для нового блока · Esc: отмена" if _inspector_mode else "Теперь выбери вход · Esc: отмена"
		_request(); return
	var doc: Dictionary = root.snapshot().duplicate(true)
	if remove:
		for i in range(doc.links.size() - 1, -1, -1):
			if str(doc.links[i].to) == str(point.id) and int(doc.links[i].port) == int(point.port): doc.links.remove_at(i)
	elif not _draft.is_empty():
		doc.links.append({"from":_draft, "to":str(point.id), "port":int(point.port)})
	else:
		_hint.text = "Сначала выбери выход · свойства выбранного: «Свойства / схема»"; return
	var answer: Dictionary = _actions.apply_mechanism_document(root, doc)
	_hint.text = "Провод снят" if remove and answer.ok else ("Соединено · выход → вход" if answer.ok else str(answer.error))
	if answer.ok: _draft = ""
	_request()

func draw_overlay(overlay: Control) -> void:
	if not active or not is_instance_valid(_camera): return
	var points := ports(_camera)
	var root := circuit()
	if root == null: return
	var font := ThemeDB.fallback_font
	var footer := overlay.size.y - 60
	overlay.draw_style_box(_box(false), Rect2(Vector2(12, footer), Vector2(minf(overlay.size.x - 24, 760), 46)))
	overlay.draw_string(font, Vector2(24, footer + 20), _hint.text, HORIZONTAL_ALIGNMENT_LEFT, overlay.size.x - 48, 14, Color.WHITE)
	var help := "Порты: выход → вход · Подпись блока: перетащить · Shift+вход: снять · Esc: отмена" if _inspector_mode else "Выход → вход · Shift+вход: снять · Esc: отмена"
	overlay.draw_string(font, Vector2(24, footer + 37), help, HORIZONTAL_ALIGNMENT_LEFT, overlay.size.x - 48, 12, Color("a7bdce"))
	var scale := maxf(1.0, ThemeDB.fallback_font_size / 16.0)
	for link in root.snapshot().links:
		var from := {}; var to := {}
		for point in points:
			if point.output and point.id == str(link.from): from = point
			if not point.output and point.id == str(link.to) and point.port == int(link.port): to = point
		if not from.is_empty() and not to.is_empty(): _wire(overlay, from.at, to.at, Color("77d9c2"))
	if _inspector_mode:
		for point in points:
			overlay.draw_line(point.anchor, point.at, Color(0.5, 0.7, 0.8, 0.4), 1, true)
			var color := Color("77d9c2") if point.output else Color("92bde6")
			if not point.output and not _draft.is_empty():
				color = Color("77d9a2") if str(_feedback.get("%s:%d" % [point.id, point.port], "")).is_empty() else Color("f38a8a")
				overlay.draw_arc(point.at, 10, 0, TAU, 24, color, 2, true)
			overlay.draw_circle(point.at, 6, color)
			var at: Vector2 = point.at + Vector2(-146 if point.output else 12, -14)
			var name_box := _box(str(point.id) == _selected)
			var text_value := str(point.label)
			if not point.output and Model.inputs(str(point.kind)) > 1: text_value = Model.input_label(str(point.kind), int(point.port))
			overlay.draw_style_box(name_box, Rect2(at, Vector2(134, 28)))
			overlay.draw_string(font, at + Vector2(6, 20), text_value, HORIZONTAL_ALIGNMENT_LEFT, 122, 13, Color.WHITE)
			if point.output and point.id == _draft: _wire(overlay, point.at, _mouse, Color("ffe49b"))
		if not _draft.is_empty():
			var hovered := _hit(points, _mouse)
			if not hovered.is_empty() and not hovered.output:
				var error := str(_feedback.get("%s:%d" % [hovered.id, hovered.port], ""))
				if not error.is_empty():
					var width := minf(420, overlay.size.x - 24)
					var height := font.get_multiline_string_size(error, HORIZONTAL_ALIGNMENT_LEFT, width - 20, 13).y + 18
					var at := (_mouse + Vector2(18,18)).clamp(Vector2(12,12), (overlay.size - Vector2(width,height) - Vector2(12,12)).max(Vector2(12,12)))
					overlay.draw_style_box(_box(false), Rect2(at, Vector2(width,height)))
					overlay.draw_multiline_string(font, at + Vector2(10,20), error, HORIZONTAL_ALIGNMENT_LEFT, width - 20, 13, -1, Color("ffb6b6"))
		return
	var shown := {}
	for point in points:
		if not shown.has(point.id):
			shown[point.id] = true
			overlay.draw_line(point.anchor, point.center + Vector2(0, 20), Color("607e92"), 1, true)
			var rectangle := Rect2(point.center + Vector2(-82, -16), Vector2(164, 82))
			overlay.draw_style_box(_box(str(point.id) == _selected), rectangle)
			overlay.draw_string(font, point.center + Vector2(-74, 0), str(point.label).left(19), HORIZONTAL_ALIGNMENT_LEFT, 150, int(14 * scale), Color.WHITE)
			overlay.draw_string(font, point.center + Vector2(-74, 17), str(Model.LABELS[point.kind]), HORIZONTAL_ALIGNMENT_LEFT, 150, int(11 * scale), Color("a7bdce"))
	for point in points:
		var color := Color("77d9c2") if point.output else Color("92bde6")
		overlay.draw_circle(point.at, 7, color)
		var port_text := "→" if point.output else Model.input_label(str(point.kind), int(point.port)) if point.kind == "latch" else str(point.port + 1)
		overlay.draw_string(font, point.at + Vector2(-40 if point.output else 12, 5), port_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		if point.output and point.id == _draft: _wire(overlay, point.at, _mouse, Color("ffe49b"))

func _box(selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color = Color(0.035, 0.06, 0.09, 0.94)
	box.set_corner_radius_all(6); box.set_border_width_all(2 if selected else 1)
	box.border_color = Color("ffe49b") if selected else Color("496579")
	return box

func _wire(overlay: Control, from: Vector2, to: Vector2, color: Color) -> void:
	var curve := Curve2D.new()
	var tangent := maxf(45, absf(to.x - from.x) * 0.4)
	curve.add_point(from, Vector2.ZERO, Vector2(tangent, 0))
	curve.add_point(to, Vector2(-tangent, 0))
	var line := curve.tessellate()
	overlay.draw_polyline(line, Color(0.01, 0.02, 0.03, 0.8), 5, true)
	overlay.draw_polyline(line, color, 2, true)
