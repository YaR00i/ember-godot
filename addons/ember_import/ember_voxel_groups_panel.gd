@tool
extends VBoxContainer
## UI for canonical named groups; mutations remain in workspace/Undo owner.
const Groups = preload("res://addons/ember_import/ember_voxel_groups.gd")
signal operation_requested(operation: Dictionary)
signal select_requested(indices: PackedInt32Array, color: Color)
signal isolate_requested(indices: PackedInt32Array, enabled: bool)
signal visibility_requested(hidden_indices: PackedInt32Array)
var _groups: Array[Dictionary] = []
var _selected_id := ""
var _list: OptionButton
var _lock: CheckButton
var _isolate: CheckButton
var _visible: CheckButton
var _color: ColorPickerButton
var _create: Button
var _replace: Button
var _delete: Button
var _dialog: ConfirmationDialog
var _name: LineEdit
var _pending_kind := ""
var _hidden_ids: Dictionary = {}
var _color_before := Color.WHITE


func _init() -> void:
	name = "VoxelGroupsPanel"
	var heading := Label.new()
	heading.text = "ГРУППЫ ВОКСЕЛЕЙ"
	add_child(heading)
	_list = OptionButton.new()
	_list.name = "VoxelGroupList"
	_list.item_selected.connect(_on_selected)
	add_child(_list)
	var row := HBoxContainer.new()
	add_child(row)
	_create = _button(row, "+ Из выделения", _ask_name.bind("create"))
	_create.name = "VoxelGroupCreate"
	var rename := _button(row, "Имя…", _ask_name.bind("rename"))
	rename.name = "VoxelGroupRename"
	_replace = _button(self, "Заменить состав выделением", _replace_members)
	var select := _button(self, "Выделить группу", _select_group)
	select.name = "VoxelGroupSelect"
	_lock = CheckButton.new()
	_lock.name = "VoxelGroupLock"
	_lock.text = "Защитить воксели от кистей"
	_lock.toggled.connect(_toggle_lock)
	add_child(_lock)
	var color_row := HBoxContainer.new()
	add_child(color_row)
	var color_label := Label.new()
	color_label.text = "Цвет группы"
	color_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(color_label)
	_color = ColorPickerButton.new()
	_color.name = "VoxelGroupColor"
	_color.custom_minimum_size = Vector2(72, 30)
	_color.edit_alpha = false
	_color.pressed.connect(_begin_color_edit)
	_color.popup_closed.connect(_commit_color_edit)
	color_row.add_child(_color)
	_visible = CheckButton.new()
	_visible.name = "VoxelGroupVisible"
	_visible.text = "Показывать в просмотре"
	_visible.set_pressed_no_signal(true)
	_visible.toggled.connect(_toggle_visible)
	add_child(_visible)
	_isolate = CheckButton.new()
	_isolate.name = "VoxelGroupIsolate"
	_isolate.text = "Изолировать в просмотре"
	_isolate.toggled.connect(_toggle_isolate)
	add_child(_isolate)
	_delete = _button(self, "Удалить группу", _delete_group)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "Координаты и цвет подписи хранятся в .tres; цвет не перекрашивает модель. Видимость и изоляция — только текущий вид редактора. Защита блокирует форму, цвет вокселей и материал."
	add_child(help)
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Имя группы"
	_dialog.ok_button_text = "Применить"
	_dialog.get_label().hide()
	add_child(_dialog)
	_name = LineEdit.new()
	_name.name = "VoxelGroupName"
	_name.custom_minimum_size.x = 320
	_name.max_length = 64
	_dialog.add_child(_name)
	_dialog.confirmed.connect(_confirm_name)
	_dialog.canceled.connect(func() -> void: _pending_kind = "")
	sync([], "")


func sync(groups: Array, preferred_id := "") -> void:
	if groups != _groups:
		_dialog.hide()
		_pending_kind = ""
	var isolation_id := _selected_id if _isolate.button_pressed else ""
	_groups.clear()
	var existing_ids := {}
	for group in groups:
		var copy := (group as Dictionary).duplicate(true)
		_groups.append(copy)
		existing_ids[str(copy.get("id", ""))] = true
	for id in _hidden_ids.keys():
		if not existing_ids.has(id):
			_hidden_ids.erase(id)
	_selected_id = preferred_id if not preferred_id.is_empty() else _selected_id
	_list.clear()
	for group in _groups:
		var suffix := " · 🔒" if bool(group.get("locked", false)) else ""
		if _hidden_ids.has(str(group.get("id", ""))):
			suffix += " · скрыта"
		_list.add_item("%s · %d vox%s" % [group.get("name", "Группа"), group.get("indices", PackedInt32Array()).size(), suffix])
		_list.set_item_metadata(_list.item_count - 1, str(group.get("id", "")))
	var position := _position(_selected_id)
	if position < 0 and not _groups.is_empty():
		position = 0
		_selected_id = str(_groups[0].get("id", ""))
	elif _groups.is_empty():
		_selected_id = ""
	if position >= 0:
		_list.select(position)
	var group := current_group()
	_lock.set_pressed_no_signal(bool(group.get("locked", false)))
	_color.color = group.get("color", Groups.default_color(maxi(0, position)))
	_visible.set_pressed_no_signal(not _hidden_ids.has(_selected_id))
	var available := not group.is_empty()
	for control in [_replace, _delete, _lock, _color, _visible, _isolate]:
		control.disabled = not available
	if _isolate.button_pressed and isolation_id != _selected_id:
		_isolate.set_pressed_no_signal(false)
		isolate_requested.emit(PackedInt32Array(), false)


func set_can_create(available: bool) -> void:
	_create.disabled = not available


func current_group() -> Dictionary:
	var position := _position(_selected_id)
	return _groups[position] if position >= 0 else {}


func selected_id() -> String:
	return _selected_id


func hidden_indices() -> PackedInt32Array:
	var hidden := {}
	for group in _groups:
		if _hidden_ids.has(str(group.get("id", ""))):
			for index in group.get("indices", PackedInt32Array()):
				hidden[int(index)] = true
	var result := PackedInt32Array(hidden.keys())
	result.sort()
	return result


func isolation_enabled() -> bool:
	return _isolate.button_pressed


func cancel_isolation() -> void:
	if _isolate.button_pressed:
		_isolate.set_pressed_no_signal(false)
		isolate_requested.emit(PackedInt32Array(), false)


func clear_view_filters(notify := true) -> void:
	if _isolate.button_pressed:
		_isolate.set_pressed_no_signal(false)
		if notify:
			isolate_requested.emit(PackedInt32Array(), false)
	_hidden_ids.clear()
	_visible.set_pressed_no_signal(true)
	if notify:
		visibility_requested.emit(PackedInt32Array())


func _on_selected(index: int) -> void:
	if index < 0:
		return
	_selected_id = str(_list.get_item_metadata(index))
	var group := current_group()
	_lock.set_pressed_no_signal(bool(group.get("locked", false)))
	_color.color = group.get("color", Groups.default_color(index))
	_visible.set_pressed_no_signal(not _hidden_ids.has(_selected_id))
	if _isolate.button_pressed:
		isolate_requested.emit(group.get("indices", PackedInt32Array()), true)


func _ask_name(kind: String) -> void:
	_pending_kind = kind
	_name.text = str(current_group().get("name", "Группа")) if kind == "rename" else "Новая группа"
	_dialog.popup_centered(Vector2i(380, 110))
	_name.grab_focus()
	_name.select_all()


func _confirm_name() -> void:
	if _pending_kind.is_empty():
		return
	operation_requested.emit({
		"kind": _pending_kind,
		"id": _selected_id if _pending_kind == "rename" else "",
		"name": _name.text,
	})
	_pending_kind = ""


func _replace_members() -> void:
	operation_requested.emit({"kind": "replace", "id": _selected_id})


func _delete_group() -> void:
	operation_requested.emit({"kind": "delete", "id": _selected_id})


func _toggle_lock(locked: bool) -> void:
	if not _selected_id.is_empty():
		operation_requested.emit({"kind": "lock", "id": _selected_id, "locked": locked})


func _select_group() -> void:
	var group := current_group()
	select_requested.emit(
		group.get("indices", PackedInt32Array()),
		group.get("color", Groups.default_color(maxi(0, _position(_selected_id))))
	)


func _toggle_isolate(enabled: bool) -> void:
	if enabled and _hidden_ids.erase(_selected_id):
		_visible.set_pressed_no_signal(true)
		visibility_requested.emit(hidden_indices())
	isolate_requested.emit(current_group().get("indices", PackedInt32Array()), enabled)


func _toggle_visible(visible: bool) -> void:
	if _selected_id.is_empty():
		return
	if visible:
		_hidden_ids.erase(_selected_id)
	else:
		_hidden_ids[_selected_id] = true
		if _isolate.button_pressed:
			_isolate.set_pressed_no_signal(false)
			isolate_requested.emit(PackedInt32Array(), false)
	sync(_groups.duplicate(true), _selected_id)
	visibility_requested.emit(hidden_indices())


func _begin_color_edit() -> void:
	_color_before = current_group().get("color", _color.color)


func _commit_color_edit() -> void:
	if _selected_id.is_empty() or _color.color.is_equal_approx(_color_before):
		return
	operation_requested.emit({"kind": "color", "id": _selected_id, "color": _color.color})


func _position(id: String) -> int:
	for index in _groups.size():
		if str(_groups[index].get("id", "")) == id:
			return index
	return -1


func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(action)
	parent.add_child(button)
	return button
