@tool
extends ConfirmationDialog
## One-section growth on the four sides of the current compact map.

signal requested(direction: String, mode: String)
signal preview_requested(direction: String, mode: String)

const Extension = preload("res://addons/ember_import/ember_compact_map_extension.gd")

var _direction: OptionButton
var _mode: OptionButton
var _size: Label
var _status: Label


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
	_mode.item_selected.connect(_request_preview.unbind(1))
	_direction.item_selected.connect(_request_preview.unbind(1))
	confirmed.connect(_submit)


func open_for(map: EmberMapLoader) -> void:
	_size.text = "Сейчас: %d×%d блоков" % [map.authored_size_blocks.x, map.authored_size_blocks.y]
	_status.text = "Показываю новый участок в 3D…"
	get_ok_button().disabled = true
	popup_centered_clamped(Vector2i(450, 320), 0.9)
	call_deferred("_request_preview")


func _request_preview() -> void:
	get_ok_button().disabled = true
	_status.text = "Показываю новый участок в 3D…"
	preview_requested.emit(["east", "west", "south", "north"][_direction.selected], Extension.MODE_FLAT if _mode.selected == 0 else Extension.MODE_CONTINUE)


func show_preview_ready() -> void:
	_status.text = "Предпросмотр готов. Добавить — одно Ctrl+Z.\nОтмена удалит только предпросмотр."
	get_ok_button().disabled = false


func show_error(message: String) -> void:
	_status.text = message
	get_ok_button().disabled = true


func _submit() -> void:
	requested.emit(["east", "west", "south", "north"][_direction.selected], Extension.MODE_FLAT if _mode.selected == 0 else Extension.MODE_CONTINUE)
