@tool
extends ConfirmationDialog
## Small native preview for the prepared terrain Resource.

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")

signal created(scene_path: String)

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


func _init() -> void:
	title = "Новая компактная карта"
	size = Vector2i(520, 560)
	dialog_hide_on_ok = false
	get_ok_button().text = "Создать и открыть карту"
	get_ok_button().disabled = true
	get_cancel_button().text = "Отмена"
	var box := VBoxContainer.new()
	add_child(box)
	var heading := Label.new()
	heading.text = "Участок 24×24 блока · блок 16×16"
	box.add_child(heading)
	_preset = OptionButton.new()
	_preset.add_item("Ровная земля")
	_preset.add_item("Берег · рельеф, песок, трава, вода")
	box.add_child(_preset)
	_id_field = LineEdit.new()
	_id_field.placeholder_text = "ID карты: например, new_island"
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
	var preview_button := Button.new()
	preview_button.text = "Обновить предпросмотр"
	preview_button.pressed.connect(_prepare)
	box.add_child(preview_button)
	var preview_frame := CenterContainer.new()
	preview_frame.custom_minimum_size = Vector2(300, 135)
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
	box.add_child(_preview_label)
	_status = Label.new()
	box.add_child(_status)
	_status.text = "До нажатия «Создать» сцена и Resource не меняются."
	_id_field.text_changed.connect(_invalidate.unbind(1))
	_preset.item_selected.connect(_preset_changed)
	for field in [_width, _depth, _height, _water, _relief, _seed]:
		field.value_changed.connect(_invalidate.unbind(1))
	confirmed.connect(_commit)


func open_for() -> void:
	popup_centered_clamped(Vector2i(520, 560), 0.9)


func _preset_changed(index: int) -> void:
	_set_coast_fields(index == 1)
	_height.value = 32 if index == 1 else 8
	_invalidate()


func _set_coast_fields(enabled: bool) -> void:
	for field in [_water, _relief, _seed]:
		field.get_parent().visible = enabled


func _number(parent: Node, caption: String, initial: int, minimum: int, maximum: int) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.value = initial
	number.custom_minimum_size.x = 110
	row.add_child(number)
	return number


func _invalidate() -> void:
	get_ok_button().disabled = true
	creation.source = null
	_swatch.visible = false
	_texture.visible = false
	_texture.texture = null
	_preview_label.text = ""
	_status.text = "Параметры изменены.\nОбновите предпросмотр перед созданием."


func _prepare() -> void:
	var coast := _preset.selected == 1
	var okay := creation.prepare_coast_sections(_id_field.text, int(_width.value), int(_depth.value), int(_height.value), int(_water.value), int(_relief.value), int(_seed.value)) if coast else creation.prepare_sections(_id_field.text, int(_width.value), int(_depth.value), int(_height.value))
	get_ok_button().disabled = not okay
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
	_preview_label.text = "Вид сверху: %d×%d участка · %d×%d ячеек\n%s\nСцена: %s.tscn\nЗемля: %s.res" % [int(_width.value), int(_depth.value), source.width, source.depth, "Берег · высота %d · вода %d · seed %d" % [creation.height, int(_water.value), int(_seed.value)] if coast else "Ровная высота %d · без воды" % creation.height, _id_field.text, _id_field.text]
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
		get_ok_button().disabled = true
		_status.text = creation.error
		return
	hide()
	created.emit(path)
