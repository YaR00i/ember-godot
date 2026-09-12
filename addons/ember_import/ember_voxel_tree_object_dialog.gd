@tool
extends ConfirmationDialog

const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")

signal created(prop: EmberVoxelProp)

var creation: RefCounted
var _root: Node
var _parent: Node3D
var _undo: Object
var _position: Vector3
var _world_size := 16.0
var _title: LineEdit
var _height: SpinBox
var _trunk_width: SpinBox
var _crown_spread: SpinBox
var _branchiness: SpinBox
var _irregularity: SpinBox
var _leaf_density: SpinBox
var _density: OptionButton
var _bark: ColorPickerButton
var _foliage: ColorPickerButton
var _seed := 1
var _seed_label: Label
var _status: Label
var _world: Node3D
var _camera: Camera3D
var _preview: Node3D
var _style: OptionButton
var _shape: OptionButton
var _shape_numbers: Dictionary = {}


func _init() -> void:
	title = "Большое процедурное дерево"
	size = Vector2i(980, 660)
	get_ok_button().text = "Создать и поставить в сцену"
	get_ok_button().disabled = true
	get_cancel_button().text = "Отмена"
	dialog_hide_on_ok = false
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(preview_column)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 7)
	scroll.add_child(box)
	var intro := Label.new()
	intro.text = "Обычный объект Ember высотой 64–256 vox. Ствол и крупные ветви имеют коллизию; листья — нет."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 360
	box.add_child(intro)
	_title = LineEdit.new()
	_title.text = "Большое лиственное дерево"
	_title.placeholder_text = "Название объекта"
	box.add_child(_title)
	_style = OptionButton.new()
	_style.add_item("Крупные формы", 2)
	_style.add_item("Классический · прежний", 1)
	box.add_child(_style)
	_shape = OptionButton.new()
	_shape.add_item("Крона: широкая", 0)
	_shape.add_item("Крона: вытянутая", 1)
	_shape.add_item("Крона: ярусная", 2)
	box.add_child(_shape)
	_height = _number(box, "Высота · vox", 64, 256, 96)
	_trunk_width = _number(box, "Толщина ствола · vox", 3, 24, 10)
	_crown_spread = _number(box, "Размах кроны · %", 25, 85, 65)
	_branchiness = _number(box, "Ветвистость · %", 0, 100, 62)
	_irregularity = _number(box, "Неровность силуэта · %", 0, 100, 42)
	_leaf_density = _number(box, "Плотность листвы · %", 20, 100, 62)
	for field in [
		["branch_thickness", "Толщина ветвей · % ствола", 25, 100, 75],
		["branch_taper", "Сужение ветвей · %", 0, 100, 60],
		["branch_curve", "Изгиб ствола и ветвей · %", 0, 100, 55],
		["branch_start", "Начало ветвления · % высоты", 20, 55, 34],
		["cluster_size", "Размер пучков · %", 65, 180, 130],
		["cluster_flatten", "Приплюснутость листвы · %", 0, 100, 60],
		["canopy_cohesion", "Сомкнутость кроны · %", 0, 100, 55],
		["root_flare", "Корневые выступы · %", 0, 100, 65],
	]:
		_shape_numbers[field[0]] = _number(box, field[1], field[2], field[3], field[4])
	_density = OptionButton.new()
	_density.add_item("16 vox/block", 16)
	_density.add_item("32 vox/block", 32)
	box.add_child(_density)
	_bark = ColorPickerButton.new()
	_bark.text = "Цвет коры"
	_bark.color = Color("765039")
	_bark.edit_alpha = false
	box.add_child(_bark)
	_foliage = ColorPickerButton.new()
	_foliage.text = "Цвет листвы"
	_foliage.color = Color("4f8f50")
	_foliage.edit_alpha = false
	box.add_child(_foliage)
	var seed_row := HBoxContainer.new()
	_seed_label = Label.new()
	_seed_label.text = "Вариант: %d" % _seed
	_seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_label)
	var next_seed := Button.new()
	next_seed.text = "Другой вариант"
	next_seed.pressed.connect(_next_seed)
	seed_row.add_child(next_seed)
	preview_column.add_child(seed_row)
	var prepare := Button.new()
	prepare.name = "VoxelLargeTreePrepare"
	prepare.text = "Собрать точный предпросмотр"
	prepare.tooltip_text = "Генерация запускается только явно. Созданный объект использует ровно эту геометрию."
	prepare.pressed.connect(_prepare)
	preview_column.add_child(prepare)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 420
	preview_column.add_child(_status)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(420, 340)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	_world = Node3D.new()
	viewport.add_child(_world)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_world.add_child(_camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.shadow_enabled = true
	_world.add_child(light)
	_title.text_changed.connect(_invalidate.unbind(1))
	_density.item_selected.connect(_invalidate.unbind(1))
	_bark.color_changed.connect(_invalidate.unbind(1))
	_foliage.color_changed.connect(_invalidate.unbind(1))
	confirmed.connect(_commit)
	_style.item_selected.connect(_style_changed.unbind(1))
	_shape.item_selected.connect(_invalidate.unbind(1))
	_style_changed()


func open_for(
	root: Node,
	parent: Node3D,
	undo: Object,
	position: Vector3,
	world_size := 16.0,
	base_recipe: Resource = null,
) -> void:
	_root = root
	_parent = parent
	_undo = undo
	_position = position
	_world_size = world_size
	if base_recipe != null and str(base_recipe.get("generator_id")) == Generator.LARGE_TREE:
		var settings := Generator.normalized_parameters(Generator.LARGE_TREE, base_recipe.get("parameters"))
		_seed = int(base_recipe.get("seed"))
		_apply_settings(settings)
		_title.text += " · вариант"
		_seed_label.text = "Вариант: %d" % _seed
	_status.text = "Изменения параметров ничего не сохраняют. Нажмите «Собрать точный предпросмотр»; на 256 vox это может занять несколько секунд."
	popup_centered(Vector2i(980, 660))


func _number(parent: Node, label: String, minimum: int, maximum: int, value: int) -> SpinBox:
	var row := HBoxContainer.new()
	var heading := Label.new()
	heading.text = label
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.step = 1
	number.value = value
	number.value_changed.connect(_invalidate.unbind(1))
	row.add_child(number)
	parent.add_child(row)
	return number


func _settings() -> Dictionary:
	var settings := {
		"generation_version": _style.get_selected_id(),
		"crown_shape": _shape.get_selected_id(),
		"height": int(_height.value),
		"trunk_width": int(_trunk_width.value),
		"crown_spread": int(_crown_spread.value),
		"branchiness": int(_branchiness.value),
		"irregularity": int(_irregularity.value),
		"leaf_density": int(_leaf_density.value),
		"density": _density.get_selected_id(),
		"bark_color": _bark.color,
		"foliage_color": _foliage.color,
	}
	for field in _shape_numbers:
		settings[field] = int(_shape_numbers[field].value)
	return settings


func _apply_settings(settings: Dictionary) -> void:
	_style.select(_style.get_item_index(int(settings.generation_version)))
	_shape.select(int(settings.crown_shape))
	for field in _shape_numbers:
		_shape_numbers[field].value = settings[field]
	_style_changed()
	_height.value = settings.height
	_trunk_width.value = settings.trunk_width
	_crown_spread.value = settings.crown_spread
	_branchiness.value = settings.branchiness
	_irregularity.value = settings.irregularity
	_leaf_density.value = settings.leaf_density
	_density.select(_density.get_item_index(int(settings.density)))
	_bark.color = settings.bark_color
	_foliage.color = settings.foliage_color


func _style_changed() -> void:
	var sculpted := _style.get_selected_id() == 2
	_shape.visible = sculpted
	_leaf_density.get_parent().visible = not sculpted
	for number in _shape_numbers.values():
		number.get_parent().visible = sculpted
	_invalidate()


func _next_seed() -> void:
	_seed += 1
	_seed_label.text = "Вариант: %d" % _seed
	_invalidate()


func _invalidate() -> void:
	get_ok_button().disabled = true
	if _status != null:
		_status.text = "Параметры изменены. Соберите новый точный предпросмотр перед созданием."


func _prepare() -> void:
	if not is_instance_valid(_root) or not is_instance_valid(_parent):
		_status.text = "Сцена закрыта. Откройте создание дерева заново."
		return
	_status.text = "Собираю дерево…"
	creation = Creation.new()
	creation.world_size = _world_size
	if not creation.prepare(_settings(), _seed, _title.text):
		_status.text = creation.error
		get_ok_button().disabled = true
		return
	if is_instance_valid(_preview):
		_preview.free()
	_preview = creation.packed.instantiate()
	_preview.configure_voxel_scale(creation.source.normalized_density(), _world_size)
	_world.add_child(_preview)
	var grid: Vector3i = creation.report.grid
	var extent: Vector3 = Vector3(grid) * (_world_size / creation.source.normalized_density())
	_camera.size = maxf(extent.x, maxf(extent.y, extent.z)) * 1.45
	var center := Vector3(0.0, extent.y * 0.48, 0.0)
	_camera.position = center + Vector3(1.25, 0.55, 1.25).normalized() * _camera.size * 2.0
	_camera.look_at(center)
	_status.text = "%s · %d vox высотой · %s в сетке · %d видимых · %d физических · %.0f мс.\nЭто точная подготовленная геометрия: создание не перебросит seed и не изменит силуэт." % [
		creation.source.display_name,
		creation.source.height_voxels,
		grid,
		int(creation.report.occupied),
		int(creation.report.colliding),
		float(creation.report.elapsed_usec) / 1000.0,
	]
	get_ok_button().disabled = false


func _commit() -> void:
	var prop: EmberVoxelProp = creation.commit(_root, _parent, _undo, _position)
	if prop == null:
		_status.text = creation.error
		return
	hide()
	created.emit(prop)
