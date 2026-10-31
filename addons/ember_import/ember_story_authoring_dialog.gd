@tool
extends ConfirmationDialog
signal create_requested(values: Dictionary)
const Authoring = preload("res://addons/ember_import/ember_story_authoring.gd")
var _scene: WeakRef
var _nodes: Array[Node3D] = []
var _pickers: Dictionary = {}
var _title: LineEdit
var _duration: SpinBox
var _movement: Array[SpinBox] = []
var _talks: VBoxContainer
var _error: Label
var _shot: OptionButton


func setup(scene: Node3D) -> void:
	_scene = weakref(scene)
	_nodes = Authoring.candidates(scene)
	title = "Создать сценку"
	size = Vector2i(720, 700)
	dialog_hide_on_ok = false
	get_ok_button().text = "Создать и открыть шкалу"
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_bottom = -52
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 9)
	scroll.add_child(column)
	_title = LineEdit.new()
	_title.name = "StoryTitle"
	_title.placeholder_text = "Название, например: Встреча у посылки"
	column.add_child(_title)
	for pair in [["primary", "Первый участник"], ["secondary", "Второй участник"], ["item", "Перемещаемый предмет"]]:
		var label := Label.new()
		label.text = pair[1]
		column.add_child(label)
		var selection_row := HBoxContainer.new()
		column.add_child(selection_row)
		var filter := LineEdit.new()
		filter.name = "StoryFilter_" + pair[0]
		filter.placeholder_text = "Фильтр по имени"
		filter.custom_minimum_size.x = 190
		selection_row.add_child(filter)
		var picker := OptionButton.new()
		picker.name = "StoryTarget_" + pair[0]
		picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.fit_to_longest_item = false
		selection_row.add_child(picker)
		_pickers[pair[0]] = picker
		_fill_targets(picker, "")
		filter.text_changed.connect(func(text: String): _fill_targets(picker, text))
	var movement_label := Label.new()
	movement_label.text = "Смещение предмета по осям мира"
	column.add_child(movement_label)
	var row := HBoxContainer.new()
	column.add_child(row)
	for axis in ["X", "Y", "Z"]:
		var label := Label.new()
		label.text = axis
		row.add_child(label)
		var value := SpinBox.new()
		value.name = "StoryMove" + axis
		value.min_value = -10000
		value.max_value = 10000
		value.step = 0.1
		value.value = 0.8 if axis == "X" else 0.0
		row.add_child(value)
		_movement.append(value)
	var timing := HBoxContainer.new()
	column.add_child(timing)
	var timing_label := Label.new()
	timing_label.text = "Длительность, сек."
	timing.add_child(timing_label)
	_duration = SpinBox.new()
	_duration.name = "StoryDuration"
	_duration.min_value = 0.5
	_duration.max_value = 120
	_duration.step = 0.1
	_duration.value = 4.0
	timing.add_child(_duration)
	_shot = OptionButton.new()
	_shot.name = "StoryInitialShot"
	for shot in ["Общий план", "Средний", "Крупный", "Через плечо", "Обратное плечо", "Предмет"]:
		_shot.add_item(shot)
	timing.add_child(_shot)
	var talk_label := Label.new()
	talk_label.text = "Разговорные остановки · время не учитывает чтение реплик"
	column.add_child(talk_label)
	_talks = VBoxContainer.new()
	column.add_child(_talks)
	var add := Button.new()
	add.name = "StoryAddDialogue"
	add.text = "+ Добавить разговор"
	add.pressed.connect(add_dialogue)
	column.add_child(add)
	_error = Label.new()
	_error.name = "StoryError"
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.modulate = Color(1, 0.65, 0.45)
	column.add_child(_error)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "Предмет — визуальный Node3D/меш без динамической физики. После создания сохрани карту (Ctrl+S). Движение и ракурсы меняются в AnimationPlayer → story; разговоры — в Presentation → Dialogue Cues. Для квеста добавь действие «Показать сценку»."
	column.add_child(help)
	confirmed.connect(func(): create_requested.emit(values()))


func _fill_targets(picker: OptionButton, filter: String) -> void:
	var current := str(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""
	picker.clear()
	picker.add_item("— выбери объект на карте —")
	picker.set_item_metadata(0, "")
	var scene := _scene.get_ref() as Node
	for node in _nodes:
		if not is_instance_valid(node) or scene == null or not scene.is_ancestor_of(node):
			continue
		var path := str(scene.get_path_to(node))
		if not filter.is_empty() and not path.to_lower().contains(filter.to_lower()):
			continue
		picker.add_item(path)
		picker.set_item_metadata(picker.item_count - 1, path)
		if path == current:
			picker.select(picker.item_count - 1)


func add_dialogue() -> void:
	var row := HBoxContainer.new()
	var time := SpinBox.new()
	time.name = "Time"
	time.min_value = 0
	time.max_value = 119.9
	time.step = 0.1
	time.value = minf(1.0 + _talks.get_child_count(), _duration.value - 0.1)
	row.add_child(time)
	var picker := OptionButton.new()
	picker.name = "Dialogue"
	picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	picker.fit_to_longest_item = false
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("— выбери диалог —")
	picker.set_item_metadata(0, "")
	for id in EmberDialogueCatalog.ids():
		picker.add_item(str(EmberDialogueCatalog.document(id).get("nameRu", id)))
		picker.set_item_metadata(picker.item_count - 1, id)
	row.add_child(picker)
	var remove := Button.new()
	remove.text = "Убрать"
	remove.pressed.connect(func():
		_talks.remove_child(row)
		row.queue_free())
	row.add_child(remove)
	_talks.add_child(row)


func show_error(message: String) -> void:
	_error.text = message


func values() -> Dictionary:
	var data := {"title": _title.text, "duration": _duration.value,
		"movement": Vector3(_movement[0].value, _movement[1].value, _movement[2].value),
		"shot": _shot.selected, "dialogues": []}
	for field in _pickers:
		var picker: OptionButton = _pickers[field]
		data[field] = str(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else ""
	for row in _talks.get_children():
		var picker := row.get_node("Dialogue") as OptionButton
		data.dialogues.append({"time": row.get_node("Time").value, "dialogueId": str(picker.get_item_metadata(picker.selected))})
	return data
