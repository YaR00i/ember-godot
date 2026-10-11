@tool
extends VBoxContainer
## Dock UI for the existing prepared terrain Resource; no writes until Create.

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")

signal created(scene_path: String)
signal cancel_requested

var creation := Creation.new()
var _id_field: LineEdit
var _preset: OptionButton
var _width: SpinBox
var _depth: SpinBox
var _height: SpinBox
var _water: SpinBox
var _relief: SpinBox
var _seed: SpinBox
var _swatch: ColorRect
var _texture: TextureRect
var _preview_label: Label
var _status: Label
var _create_button: Button
var _preview_button: Button
var _scroll: ScrollContainer
var _initial_values: Array = []


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := Label.new(); title.text = "Новая карта"; add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	var box := VBoxContainer.new(); box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(box)
	var heading := Label.new()
	heading.text = "Участок — 24×24 м.\n16 вокселей высоты — 1 метр."
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(heading)
	_preset = OptionButton.new()
	_preset.add_item("Ровная земля")
	_preset.add_item("Берег с водой")
	_preset.tooltip_text = "Берег: рельеф, песок, трава и вода"
	box.add_child(_preset)
	_id_field = LineEdit.new()
	_id_field.placeholder_text = "Имя карты: new_island"
	_id_field.tooltip_text = "3–48 знаков: латинские буквы, цифры и _. Начните с буквы. Файл получит имя в нижнем регистре."
	_id_field.text = "new_landscape"
	box.add_child(_id_field)
	_width = _number(box, "Ширина · участки", 1, 1, Creation.MAX_INITIAL_SECTIONS)
	_depth = _number(box, "Длина · участки", 1, 1, Creation.MAX_INITIAL_SECTIONS)
	_height = _number(box, "Высота земли · воксели (шаг 4)", 8, 4, 128)
	_height.step = 4
	_water = _number(box, "Уровень воды · воксели", 16, 4, 124)
	_water.step = 4
	_relief = _number(box, "Неровность суши · воксели", 16, 0, 48)
	_relief.step = 4
	_seed = _number(box, "Рисунок · seed", 371, 0, 999999)
	_set_coast_fields(false)
	var preview_frame := CenterContainer.new()
	preview_frame.custom_minimum_size = Vector2(0, 135)
	box.add_child(preview_frame)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(120, 120)
	_swatch.visible = false
	preview_frame.add_child(_swatch)
	_texture = TextureRect.new()
	_texture.custom_minimum_size = Vector2(120, 120)
	_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_texture.visible = false
	preview_frame.add_child(_texture)
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_preview_label)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_button = Button.new(); _preview_button.text = "Обновить предпросмотр"
	_preview_button.pressed.connect(_prepare); add_child(_preview_button)
	add_child(_status)
	var actions := HBoxContainer.new(); add_child(actions)
	_create_button = Button.new(); _create_button.text = "Создать карту"
	_create_button.tooltip_text = "Создать файлы и открыть отдельную карту"
	_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_button.disabled = true; _create_button.pressed.connect(_commit); actions.add_child(_create_button)
	var cancel := Button.new(); cancel.text = "Отмена"
	cancel.pressed.connect(func(): cancel_requested.emit()); actions.add_child(cancel)
	_status.text = "Карта появится после нажатия «Создать». Текущая карта сохранит свои правки."
	_id_field.text_changed.connect(_invalidate.unbind(1))
	_preset.item_selected.connect(_preset_changed)
	for field in [_width, _depth, _height, _water, _relief, _seed]:
		field.value_changed.connect(_invalidate.unbind(1))
	_initial_values = _parameter_values()


func _parameter_values() -> Array:
	return [_id_field.text, _preset.selected, _width.value, _depth.value, _height.value, _water.value, _relief.value, _seed.value]


func is_dirty() -> bool:
	return creation.source != null or _parameter_values() != _initial_values


func open_for() -> void:
	show()


func _preset_changed(index: int) -> void:
	_set_coast_fields(index == 1)
	_height.value = 32 if index == 1 else 8
	_invalidate()


func _set_coast_fields(enabled: bool) -> void:
	for field in [_water, _relief, _seed]:
		field.get_parent().visible = enabled


func _number(parent: Node, caption: String, initial: int, minimum: int, maximum: int) -> SpinBox:
	var row := VBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.value = initial
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(number)
	return number


func _invalidate() -> void:
	get_create_button().disabled = true
	creation.source = null
	_swatch.visible = false
	_texture.visible = false
	_texture.texture = null
	_preview_label.text = ""
	_status.text = "Параметры изменены.\nОбновите предпросмотр перед созданием."


func _prepare() -> void:
	var coast := _preset.selected == 1
	var okay := creation.prepare_coast_sections(_id_field.text, int(_width.value), int(_depth.value), int(_height.value), int(_water.value), int(_relief.value), int(_seed.value)) if coast else creation.prepare_sections(_id_field.text, int(_width.value), int(_depth.value), int(_height.value))
	get_create_button().disabled = not okay
	_swatch.visible = okay and not coast
	_texture.visible = okay and coast
	_preview_label.text = ""
	_status.text = creation.error
	if not okay:
		return
	var source := creation.source
	_swatch.color = source.palette[int(source.top_materials[0])]
	var longest := maxf(float(source.width), float(source.depth))
	var preview_size := Vector2(120.0 * source.width / longest, 120.0 * source.depth / longest)
	_swatch.custom_minimum_size = preview_size
	_texture.custom_minimum_size = preview_size
	if coast:
		_texture.texture = ImageTexture.create_from_image(_coast_preview(source))
	_preview_label.text = "Вид сверху: %d×%d участка · %d×%d ячеек\n%s\nСцена: %s.tscn\nЗемля: %s.res" % [int(_width.value), int(_depth.value), source.width, source.depth, "Берег · высота %d · вода %d · seed %d" % [creation.height, int(_water.value), int(_seed.value)] if coast else "Ровная высота %d · без воды" % creation.height, creation.map_id, creation.map_id]
	_status.text = "Предпросмотр готов. Файлы появятся после создания."


func _coast_preview(source: TerrainResource) -> Image:
	var image := Image.create(120, 120, false, Image.FORMAT_RGBA8)
	var tops: PackedByteArray = source.top_materials
	var waters: PackedInt32Array = source.water_levels
	var colors: PackedByteArray = source.water_materials
	for py in 120:
		var z := mini(source.depth - 1, py * source.depth / 120)
		for px in 120:
			var x := mini(source.width - 1, px * source.width / 120)
			var index := x + z * source.width
			var material: int = colors[index] if waters[index] > source.heights[index] else tops[index]
			image.set_pixel(px, py, source.palette[material])
	return image


func _commit() -> void:
	var path := creation.commit()
	if path.is_empty():
		get_create_button().disabled = true
		_status.text = creation.error
		return
	hide()
	created.emit(path)


func get_create_button() -> Button:
	return _create_button

func clear_preview() -> void:
	_invalidate()
