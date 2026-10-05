@tool
extends ConfirmationDialog
## Parameters route to the existing WorldEditor selection and authoring session.

signal preview_requested(parameters: Dictionary)
signal settings_changed
signal select_area_requested

const Math = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
var _fields := {}
var _profile: OptionButton
var _status: Label
var _area: Label
var _preview_button: Button
var _help: Label
var _back_button: Button


func _ready() -> void:
	title = "Рельеф выбранной области"
	# AcceptDialog normally hides before emitting confirmed. Hiding clears the
	# private candidate, so the owner must close only after a successful commit.
	dialog_hide_on_ok = false
	# Wrapped labels can report a tall minimum during the first native layout,
	# before the scroll area's width is assigned. Keep that layout inside a
	# bounded window; the parameter scroll absorbs content, not the window.
	wrap_controls = false
	ok_button_text = "Применить рельеф"
	cancel_button_text = "Отмена"
	var content := VBoxContainer.new()
	add_child(content)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_area = Label.new()
	box.add_child(_area)
	var units := Label.new()
	units.text = "Высоты и размеры — в метрах; море отсчитывается от основания карты."
	units.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(units)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var label := Label.new()
	label.text = "Рисунок рельефа"
	grid.add_child(label)
	_profile = OptionButton.new()
	for name in ["Мягкие холмы", "Горные хребты", "Изрезанные склоны"]: _profile.add_item(name)
	grid.add_child(_profile)
	_profile.item_selected.connect(_changed.unbind(1))
	for spec in [["sea_m", "Уровень моря", 0.5, 16.0, 0.25],
		["land_m", "Подъём суши над морем", 0.25, 8.0, 0.25],
		["relief_m", "Высота холмов / хребтов", 0.0, 24.0, 0.25],
		["feature_m", "Ширина крупных форм", 2.0, 96.0, 1.0],
		["shore_m", "Ширина перехода берега", 0.5, 24.0, 0.5],
		["land_fraction", "Размер острова в области", 0.3, 0.9, 0.05],
		["seed", "Номер рисунка", 0.0, 1000000.0, 1.0]]:
		var name_label := Label.new()
		name_label.text = spec[1]
		grid.add_child(name_label)
		var value := SpinBox.new()
		value.min_value = spec[2]
		value.max_value = spec[3]
		value.step = spec[4]
		value.value = Math.DEFAULTS[spec[0]]
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
		_fields[spec[0]] = value
		value.value_changed.connect(_changed.unbind(1))
	_help = Label.new()
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_help)
	_back_button = Button.new()
	_back_button.text = "← Изменить выделение"
	_back_button.pressed.connect(func(): hide(); select_area_requested.emit())
	content.add_child(_back_button)
	_preview_button = Button.new()
	_preview_button.text = "Показать предпросмотр"
	_preview_button.pressed.connect(func(): set_pending("Подготавливаю землю…"); preview_requested.emit(parameters()))
	content.add_child(_preview_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	get_ok_button().disabled = true


func open_for(bounds_blocks: Rect2i, new_sections_count := 0) -> void:
	title = "Новые участки · рельеф и вода" if new_sections_count > 0 else "Рельеф выбранной области"
	ok_button_text = "Добавить участки" if new_sections_count > 0 else "Применить рельеф"
	_back_button.visible = new_sections_count > 0
	_help.text = "Добавится новых участков: %d. Уже созданная земля и объекты сохранятся. На стыке будет плавный переход." % new_sections_count if new_sections_count > 0 else "Склоны имитируют следы эрозии. На границе с существующей землёй будет плавный переход.\nПрименение заменяет землю, покрытия и воду внутри области. Объекты остаются на своих местах."
	_area.text = "Область: %d×%d м · начало (%d, %d)" % [bounds_blocks.size.x, bounds_blocks.size.y, bounds_blocks.position.x, bounds_blocks.position.y]
	set_pending("Настройте форму и нажмите «Показать предпросмотр».")
	var available := EditorInterface.get_base_control().size
	var requested := Vector2i(mini(550, int(available.x * 0.9)), mini(600, int(available.y * 0.85)))
	max_size = requested
	popup_centered(requested)
	call_deferred("child_controls_changed")


func parameters() -> Dictionary:
	var values := {"profile": Math.PROFILES[_profile.selected]}
	for key in _fields: values[key] = int(_fields[key].value) if key == "seed" else float(_fields[key].value)
	return values


func _changed() -> void:
	set_pending("Параметры изменены. Обновите предпросмотр.")
	settings_changed.emit()


func set_pending(message: String) -> void:
	get_ok_button().disabled = true
	_status.text = message


func set_ready(message: String) -> void:
	get_ok_button().disabled = false
	_status.text = message
