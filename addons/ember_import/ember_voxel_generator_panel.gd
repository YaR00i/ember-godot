@tool
extends VBoxContainer
## Common recipe UI lifecycle. Provider descriptors supply the editable fields.
## Canonical source and scene remain untouched until explicit variant creation.

const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")

signal preview_changed(packed: PackedScene, source: EmberVoxelModelResource)
signal variant_created(prop: EmberVoxelProp)
signal assets_changed(model_id: String)

var recipe_directory := "res://content/editor/voxel_generators"
var recipe: Resource
var creation: RefCounted
var context := {}
var controls := {}
var history := UndoRedo.new()
var _baseline: Resource
var _source: EmberVoxelModelResource
var _fields: VBoxContainer
var _info: Label
var _preview_button: Button
var _save_button: Button
var _syncing := false
var _save_mode: OptionButton
var _variation_name: LineEdit
var _source_id := ""


func _exit_tree() -> void:
	history.clear_history()
	history.free()


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	_save_mode = OptionButton.new()
	_save_mode.add_item("Новая вариация", 0)
	_save_mode.add_item("Обновить выбранную вариацию", 1)
	_save_mode.add_item("Отдельный объект", 2)
	_save_mode.item_selected.connect(_save_mode_changed)
	add_child(_save_mode)
	_variation_name = LineEdit.new()
	_variation_name.placeholder_text = "Имя вариации, например Осенний"
	_variation_name.max_length = 80
	_variation_name.text_changed.connect(func(_text: String): _clear_preview())
	add_child(_variation_name)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fields)
	var history_row := HBoxContainer.new()
	add_child(history_row)
	_button(history_row, "↶ Параметры", undo_parameters)
	_button(history_row, "↷", redo_parameters)
	_button(history_row, "Сбросить", discard)
	_preview_button = _button(self, "Собрать предпросмотр", prepare)
	_save_button = _button(self, "Сохранить вариацию и поставить", save_variant)
	_save_button.disabled = true
	history.version_changed.connect(_sync_controls)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func open_source(source: EmberVoxelModelResource, next_context := {}) -> bool:
	_clear_preview()
	history.clear_history()
	context = next_context
	_source = source
	recipe = null
	_baseline = null
	controls.clear()
	for child in _fields.get_children():
		child.free()
	if source == null:
		return false
	var source_id := str(context.get("source_id", source.model_id))
	_source_id = source_id
	var loaded := Creation.load_recipe(source_id, recipe_directory)
	if loaded == null or Generator.editing_fields(loaded).is_empty():
		_info.text = "Для модели нет поддерживаемого редактора рецепта."
		return false
	# Loading never regenerates geometry or modifies the saved recipe.
	recipe = loaded.duplicate(true)
	recipe.parameters = Generator.normalized_parameters(recipe.generator_id, recipe.parameters)
	_baseline = recipe.duplicate(true)
	_save_mode.select(0)
	_variation_name.text = "Новая вариация"
	_save_button.text = "Сохранить вариацию и поставить"
	_info.text = "Структура закреплена. Настройки меняют её оформление.\nПредпросмотр — только рецепт; ручная лепка не переносится. Исходник не изменится."
	var section := ""
	_syncing = true
	for field in Generator.editing_fields(recipe):
		if str(field.group) != section:
			section = str(field.group)
			var heading := Label.new()
			heading.text = section.to_upper()
			_fields.add_child(heading)
		var label := Label.new()
		label.text = field.label
		_fields.add_child(label)
		if str(field.get("type", "number")) == "bool":
			var toggle := CheckButton.new()
			toggle.button_pressed = bool(recipe.parameters[field.key])
			toggle.toggled.connect(func(value: bool): set_parameter(field.key, value))
			_fields.add_child(toggle)
			controls[field.key] = toggle
		elif field.has("options"):
			var option := OptionButton.new()
			for title in field.options: option.add_item(title)
			option.select(int(recipe.parameters[field.key]))
			option.item_selected.connect(func(value: int): set_parameter(field.key, value))
			_fields.add_child(option)
			controls[field.key] = option
		elif str(field.get("type", "number")) == "color":
			var picker := ColorPickerButton.new()
			picker.edit_alpha = false
			picker.color = recipe.parameters[field.key]
			picker.color_changed.connect(func(value: Color): set_parameter(field.key, value))
			_fields.add_child(picker)
			controls[field.key] = picker
		else:
			var value := SpinBox.new()
			value.min_value = field.min
			value.max_value = field.max
			value.step = 1
			value.value = recipe.parameters[field.key]
			value.value_changed.connect(func(number: float): set_parameter(field.key, int(number)))
			_fields.add_child(value)
			controls[field.key] = value
	_syncing = false
	_preview_button.disabled = false
	return true


func set_parameter(key: String, value: Variant) -> void:
	if _syncing or recipe == null or not controls.has(key) or recipe.parameters[key] == value:
		return
	var before: Variant = recipe.parameters[key]
	history.create_action("Параметр генератора: " + key)
	history.add_do_method(_assign.bind(key, value))
	history.add_undo_method(_assign.bind(key, before))
	if key == "bark_pattern" and bool(value):
		history.add_do_method(_assign.bind("bark_pattern_version", 2))
		history.add_undo_method(_assign.bind("bark_pattern_version", recipe.parameters.get("bark_pattern_version", 1)))
	history.commit_action()


func _assign(key: String, value: Variant) -> void:
	recipe.parameters[key] = value
	_clear_preview()
	_info.text = "Параметры изменены. Соберите новый точный предпросмотр. Исходник не меняется."
	_sync_controls()


func _sync_controls() -> void:
	if recipe == null:
		return
	_syncing = true
	for key in controls:
		if controls[key] is ColorPickerButton:
			controls[key].color = recipe.parameters[key]
		elif controls[key] is CheckButton:
			controls[key].button_pressed = bool(recipe.parameters[key])
		elif controls[key] is OptionButton:
			controls[key].select(int(recipe.parameters[key]))
		else:
			controls[key].value = recipe.parameters[key]
	_syncing = false


func undo_parameters() -> void:
	history.undo()


func redo_parameters() -> void:
	history.redo()


func discard() -> void:
	_clear_preview()
	if _baseline != null:
		recipe = _baseline.duplicate(true)
	history.clear_history()
	_sync_controls()
	_info.text = "Параметры возвращены к исходному рецепту. Предпросмотр снят."


func _clear_preview() -> void:
	var had_preview := creation != null
	creation = null
	if is_instance_valid(_save_button):
		_save_button.disabled = true
	preview_changed.emit(null, null)
	if had_preview and is_instance_valid(_info):
		_info.text = "Предпросмотр снят. Настройки черновика сохранены до смены объекта."


func prepare() -> void:
	_clear_preview()
	if recipe == null:
		return
	# Freeze from the original recipe, not from pending foliage edits.
	if recipe.structure.is_empty():
		var frozen := Generator.freeze_structure(_baseline)
		if frozen.has("error"):
			_info.text = str(frozen.error)
			return
		recipe.structure = frozen.recipe.structure.duplicate(true)
	var name := _variation_name.text.strip_edges()
	if name.is_empty():
		_info.text = "Укажите имя вариации или объекта."
		return
	var candidate := recipe.duplicate(true)
	var family := _source_id if _baseline.family_id.is_empty() else str(_baseline.family_id)
	var family_title := _source.display_name if _baseline.family_title.is_empty() else str(_baseline.family_title)
	if _save_mode.selected == 2:
		candidate.family_id = ""
		candidate.family_title = name
		candidate.variation_name = "Основной"
	else:
		candidate.family_id = family
		candidate.family_title = family_title
		candidate.variation_name = name
		var exclude := _source_id if _save_mode.selected == 1 else ""
		if Creation.variation_name_exists(family, name, exclude, recipe_directory):
			_info.text = "Такое имя в семействе уже есть. Выберите другое или обновите выбранную вариацию."
			return
	creation = Creation.new()
	creation.recipe_directory = recipe_directory
	creation.asset_changed.connect(func(id: String): assets_changed.emit(id))
	var title := name if _save_mode.selected == 2 else family_title + " · " + name
	if not creation.prepare_recipe(candidate, title, _source_id if _save_mode.selected == 1 else ""):
		_info.text = creation.error
		creation = null
		return
	_save_button.disabled = context.is_empty() or not context.has("undo")
	_info.text = "Точный предпросмотр готов. Камера доступна.\n" + ("Обновление заменит эту вариацию и все её экземпляры. Ручные изменения защищены проверкой." if _save_mode.selected == 1 else "Будет отдельная модель рядом с исходником; карточка семейства останется одна." if _save_mode.selected == 0 else "Будет новый самостоятельный объект с отдельной карточкой.")
	preview_changed.emit(creation.packed, creation.source)


func save_variant() -> void:
	if creation == null or context.is_empty() or not context.has("undo"):
		return
	creation.world_size = float(context.world_size)
	if _save_mode.selected == 1:
		if not creation.update_variation(_source_id, context):
			_info.text = creation.error
			return
		_clear_preview()
		_info.text = "Выбранная вариация обновлена. Scene Undo/Redo восстанавливает геометрию и рецепт."
		return
	var offset := Vector3(float(_source.size_blocks.x + 1) * creation.world_size, 0, 0)
	var prop: EmberVoxelProp = creation.commit(context.root, context.parent, context.undo, context.position + offset)
	if prop == null:
		_info.text = creation.error
		return
	if context.get("transform") is Transform3D:
		prop.basis = context.transform.basis
	variant_created.emit(prop)
	_clear_preview()
	_info.text = "Сохранён отдельный вариант: " + prop.model_id


func _save_mode_changed(_index: int) -> void:
	_clear_preview()
	if _baseline == null:
		return
	if _save_mode.selected == 1:
		_variation_name.text = _baseline.variation_name
		_save_button.text = "Обновить вариацию · все экземпляры"
		_info.text = "Обновление меняет только выбранную вариацию и все её экземпляры. Остальные вариации не изменятся."
	else:
		_variation_name.text = "Новая вариация" if _save_mode.selected == 0 else _source.display_name + " · копия"
		_save_button.text = "Сохранить вариацию и поставить" if _save_mode.selected == 0 else "Сохранить отдельный объект"


func close_source() -> void:
	_clear_preview()
	history.clear_history()
	recipe = null
	_baseline = null
	context = {}
