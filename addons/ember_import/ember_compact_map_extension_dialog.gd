@tool
extends ConfirmationDialog
## One-section growth on the four sides of the current compact map.

signal requested(direction: String, mode: String)
signal preview_requested(direction: String, mode: String)
signal extent_repair_requested

const Extension = preload("res://addons/ember_import/ember_compact_map_extension.gd")

var _direction: OptionButton
var _mode: OptionButton
var _size: Label
var _status: Label
var _coverage: OptionButton
var _along: SpinBox
var _address_x: SpinBox
var _address_z: SpinBox
var _blocks := Vector2i.ZERO
var _preview_delay: Timer
var _repair_button: Button


func _init() -> void:
	title = "Расширить компактную карту"
	size = Vector2i(450, 270)
	dialog_hide_on_ok = false
	get_ok_button().text = "Добавить участок"
	get_ok_button().disabled = true
	var box := VBoxContainer.new()
	add_child(box)
	_size = Label.new()
	box.add_child(_size)
	var hint := Label.new()
	hint.text = "Один участок = 24×24 блока.\nВыберите форму новой земли и посмотрите её в 3D."
	box.add_child(hint)
	_coverage = OptionButton.new()
	for item in ["Один участок у части края", "Весь край · прежний режим", "По адресу · в том числе пустое место"]: _coverage.add_item(item)
	box.add_child(_coverage)
	_along = _number(box, "Номер участка вдоль края · от 1", 1, 1, Extension.MAX_SECTION_AXIS)
	_address_x = _number(box, "Адрес X · от 0", 0, 0, Extension.MAX_SECTION_AXIS - 1)
	_address_z = _number(box, "Адрес Z · от 0", 0, 0, Extension.MAX_SECTION_AXIS - 1)
	_mode = OptionButton.new()
	_mode.add_item("Ровный · короткий переход")
	_mode.add_item("Продолжить край")
	box.add_child(_mode)
	_direction = OptionButton.new()
	for item in ["Справа (+X)", "Слева (−X)", "Снизу (+Z)", "Сверху (−Z)"]:
		_direction.add_item(item)
	box.add_child(_direction)
	var liquid := Label.new()
	liquid.text = "Жидкость · тип: вода (пока единственный)\nУровень: от соседнего края"
	box.add_child(liquid)
	_status = Label.new()
	box.add_child(_status)
	_repair_button = Button.new()
	_repair_button.text = "Исправить размер сцены"
	_repair_button.tooltip_text = "Согласовать размер сцены с текущей землёй одной Undo-командой. Объекты не перемещаются; файлы не сохраняются."
	_repair_button.hide()
	_repair_button.pressed.connect(func(): extent_repair_requested.emit())
	box.add_child(_repair_button)
	_preview_delay = Timer.new()
	_preview_delay.one_shot = true
	_preview_delay.wait_time = 0.25
	add_child(_preview_delay)
	_preview_delay.timeout.connect(_request_preview)
	_mode.item_selected.connect(_schedule_preview.unbind(1))
	_direction.item_selected.connect(_schedule_preview.unbind(1))
	_coverage.item_selected.connect(_schedule_preview.unbind(1))
	for number in [_along, _address_x, _address_z]: number.value_changed.connect(_schedule_preview.unbind(1))
	confirmed.connect(_submit)


func open_for(map: EmberMapLoader) -> void:
	_blocks = map.authored_size_blocks
	_size.text = "Сейчас: %d×%d блоков" % [map.authored_size_blocks.x, map.authored_size_blocks.y]
	_status.text = "Показываю новый участок в 3D…"
	_repair_button.hide()
	get_ok_button().disabled = true
	popup_centered_clamped(Vector2i(500, 480), 0.9)
	call_deferred("_request_preview")


func _schedule_preview() -> void:
	get_ok_button().disabled = true
	_status.text = "Обновляю предпросмотр…"
	_preview_delay.start()


func _request_preview() -> void:
	var by_address := _coverage.selected == 2
	_along.get_parent().visible = _coverage.selected == 0
	_address_x.get_parent().visible = by_address
	_address_z.get_parent().visible = by_address
	_direction.disabled = by_address
	_mode.disabled = by_address
	if by_address: _mode.select(0)
	var length := _blocks.y if _direction.selected in [0, 1] else _blocks.x
	_along.set_value_no_signal(clampf(_along.value, 1, ceili(float(length) / Extension.Creation.SECTION_BLOCKS)))
	_along.max_value = maxi(1, ceili(float(length) / Extension.Creation.SECTION_BLOCKS))
	get_ok_button().disabled = true
	_status.text = "Показываю новый участок в 3D…"
	preview_requested.emit(["east", "west", "south", "north"][_direction.selected], Extension.MODE_FLAT if _mode.selected == 0 else Extension.MODE_CONTINUE)


func section_index() -> int:
	return int(_along.value) - 1 if _coverage.selected == 0 else -1


func section_address() -> Vector2i:
	return Vector2i(int(_address_x.value), int(_address_z.value)) if _coverage.selected == 2 else Vector2i(-1, -1)


func _number(box: VBoxContainer, text: String, value: int, minimum: int, maximum: int) -> SpinBox:
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.value = value
	row.add_child(number)
	return number


func show_preview_ready() -> void:
	if not _preview_delay.is_stopped(): return
	_status.text = "Предпросмотр готов. Добавить — одно Ctrl+Z.\nОтмена удалит только предпросмотр."
	get_ok_button().disabled = false


func show_error(message: String, extent_repair_available := false) -> void:
	_repair_button.visible = extent_repair_available
	_status.text = message
	get_ok_button().disabled = true


func _submit() -> void:
	requested.emit(["east", "west", "south", "north"][_direction.selected], Extension.MODE_FLAT if _mode.selected == 0 else Extension.MODE_CONTINUE)
