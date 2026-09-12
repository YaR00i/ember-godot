@tool
class_name EmberVoxelObjectLibraryPanel
extends VBoxContainer
## Persistent bottom shelf for choosing canonical voxel objects. Catalog,
## previews and placement remain owned by the existing Ember systems.

signal place_requested(model_id: String, anchor: Node3D)
signal edit_requested(model_id: String)
signal open_resource_requested(model_id: String)
signal migrate_requested(model_id: String)
signal new_shape_requested
signal new_tree_requested
signal tree_variant_requested(model_id: String)
signal generate_similar_requested(model_id: String)
signal close_requested
signal rebuild_library_requested

const VisualLibraryPicker = preload("res://addons/ember_import/ember_visual_library_picker.gd")
const VoxelVisuals = preload("res://scripts/ember_voxel_visuals.gd")
const VoxelPreviewRenderer = preload("res://addons/ember_import/ember_voxel_preview_renderer.gd")
const WorkshopTheme = preload("res://addons/ember_import/ember_voxel_workshop_theme.gd")
const GenerativeObjects = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")

var _all_entries: Array[Dictionary] = []
var _owner_filter := "all"
var _anchor: WeakRef
var _can_place := false
var _textures: Dictionary = {}

var _context_label: Label
var _picker: EmberVisualLibraryPicker
var _preview: TextureRect
var _name_label: Label
var _id_label: Label
var _metadata_label: Label
var _owner_label: Label
var _place_button: Button
var _edit_button: Button
var _more_button: MenuButton
var _filter_buttons: Dictionary = {}
var _status: Label
var _preview_renderer: EmberVoxelPreviewRenderer
var recipe_directory := "res://content/editor/voxel_generators"
var _variations: OptionButton
var _preferred_variation := ""


func _ready() -> void:
	if get_child_count() == 0:
		_build()
	refresh()


func open_for(anchor: Node3D, can_place: bool, placement_text: String) -> void:
	if get_child_count() == 0:
		_build()
	_anchor = weakref(anchor) if is_instance_valid(anchor) else null
	_can_place = can_place
	_context_label.text = placement_text
	refresh()


func refresh(preferred_id := "") -> void:
	if _picker == null:
		return
	var selected_id := preferred_id if not preferred_id.is_empty() else selected_model_id()
	_all_entries = GenerativeObjects.grouped_entries(VoxelVisuals.entries(), recipe_directory)
	_preferred_variation = selected_id
	_apply_filter(selected_id)
	if DisplayServer.get_name() != "headless":
		for entry in _all_entries:
			for member in entry.get("variations", [entry]):
				_preview_renderer.queue_preview(str(member.id), str(member.get("previewPath", "")))


func refresh_context(anchor: Node3D, can_place: bool, placement_text: String) -> void:
	_anchor = weakref(anchor) if is_instance_valid(anchor) else null
	_can_place = can_place
	if _context_label != null:
		_context_label.text = placement_text
	_refresh_details()


func show_status(message: String, error := false) -> void:
	if _status == null:
		return
	_status.text = message
	_status.modulate = Color(1.0, 0.45, 0.40) if error else Color(0.60, 0.82, 0.94)


func _build() -> void:
	var base_theme := EditorInterface.get_editor_theme() if Engine.is_editor_hint() else ThemeDB.get_default_theme()
	theme = WorkshopTheme.build(base_theme)
	name = "EmberVoxelObjectLibrary"
	custom_minimum_size = Vector2(760, 330)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	add_child(header)
	var title := Label.new()
	title.text = "ОБЪЕКТЫ"
	title.modulate = Color(0.96, 0.72, 0.32)
	title.add_theme_font_size_override("font_size", 16)
	header.add_child(title)
	_context_label = Label.new()
	_context_label.name = "VoxelObjectPlacementContext"
	_context_label.text = "Место: откройте Ember Map"
	_context_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_context_label.clip_text = true
	_context_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_context_label.modulate = Color(0.66, 0.74, 0.84)
	header.add_child(_context_label)
	var new_shape := Button.new()
	new_shape.name = "VoxelLibraryNewShape"
	new_shape.text = "+ Новая форма"
	new_shape.pressed.connect(func() -> void: new_shape_requested.emit())
	header.add_child(new_shape)
	var new_tree := Button.new()
	new_tree.name = "VoxelLibraryNewLargeTree"
	new_tree.text = "Генерация…"
	new_tree.tooltip_text = "Открыть мастерскую процедурных объектов. Сейчас подключён генератор деревьев 64–256 vox; результаты сохраняются в библиотеку, не в карту."
	new_tree.pressed.connect(func() -> void: new_tree_requested.emit())
	header.add_child(new_tree)
	var rebuild_library := Button.new()
	rebuild_library.name = "RebuildVoxelLibrary"
	rebuild_library.text = "Пересобрать всю библиотеку"
	rebuild_library.tooltip_text = "Все модели и вариации по одной. Source/рецепты не меняются; прогресс и отмена в Ember Migration."
	rebuild_library.pressed.connect(func(): rebuild_library_requested.emit())
	var close := Button.new()
	close.name = "CloseVoxelObjectLibrary"
	close.text = "Закрыть"
	close.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close)

	var filters := HBoxContainer.new()
	filters.name = "VoxelObjectLibraryFilters"
	filters.add_theme_constant_override("separation", 4)
	add_child(filters)
	var filter_group := ButtonGroup.new()
	_add_filter(filters, filter_group, "all", "Все", true)
	_add_filter(filters, filter_group, "godot", "Готовы в Godot")
	_add_filter(filters, filter_group, "legacy_import", "Ожидают переноса")
	filters.add_child(rebuild_library)

	var body := HBoxContainer.new()
	body.name = "VoxelObjectLibraryBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	_picker = VisualLibraryPicker.new() as EmberVisualLibraryPicker
	_picker.setup("КАТАЛОГ", [], "")
	_picker.custom_minimum_size = Vector2(420, 260)
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker.set_tile_layout(Vector2i(96, 96), 154, 2)
	_picker.set_choose_visible(false)
	_picker.selection_changed.connect(func(_value: String) -> void: _refresh_details())
	_picker.value_chosen.connect(func(_value: String) -> void: _place_selected())
	body.add_child(_picker)

	var details_panel := PanelContainer.new()
	details_panel.name = "VoxelObjectLibraryDetails"
	details_panel.custom_minimum_size.x = 280.0
	details_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	body.add_child(details_panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	details_panel.add_child(margin)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	margin.add_child(details)
	_preview = TextureRect.new()
	_preview.name = "VoxelObjectLibraryPreview"
	_preview.custom_minimum_size = Vector2(140, 92)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	details.add_child(_preview)
	_name_label = Label.new()
	_name_label.name = "VoxelObjectLibraryName"
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.add_child(_name_label)
	_variations = OptionButton.new()
	_variations.name = "VoxelObjectVariations"
	_variations.item_selected.connect(func(_index: int):
		_preferred_variation = selected_model_id()
		_refresh_variant_details()
	)
	details.add_child(_variations)
	_id_label = Label.new()
	_id_label.name = "VoxelObjectLibraryId"
	_id_label.modulate = Color(0.54, 0.64, 0.74)
	_id_label.clip_text = true
	_id_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.add_child(_id_label)
	_metadata_label = Label.new()
	_metadata_label.name = "VoxelObjectLibraryMetadata"
	_metadata_label.clip_text = true
	_metadata_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.add_child(_metadata_label)
	_owner_label = Label.new()
	_owner_label.name = "VoxelObjectLibraryOwner"
	_owner_label.clip_text = true
	_owner_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.add_child(_owner_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(spacer)
	_edit_button = Button.new()
	_edit_button.name = "EditVoxelObjectTemplate"
	_edit_button.text = "Редактировать шаблон"
	_edit_button.tooltip_text = "Открыть общую voxel-модель в Canvas. Изменения затронут все её экземпляры в сценах."
	_edit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_button.pressed.connect(_edit_selected)
	details.add_child(_edit_button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	details.add_child(actions)
	_place_button = Button.new()
	_place_button.name = "PlaceVoxelObject"
	_place_button.text = "Поставить в сцену"
	_place_button.theme_type_variation = &"WorkshopPrimaryButton"
	_place_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_button.pressed.connect(_place_selected)
	actions.add_child(_place_button)
	_more_button = MenuButton.new()
	_more_button.name = "VoxelObjectLibraryMore"
	_more_button.text = "Ещё…"
	_more_button.get_popup().add_item("Открыть Godot Resource", 0)
	_more_button.get_popup().add_item("Перенести в Godot", 1)
	_more_button.get_popup().add_item("Создать вариант из рецепта…", 2)
	_more_button.get_popup().add_item("Генерировать похожие · параметры…", 3)
	_more_button.get_popup().id_pressed.connect(_on_more_action)
	actions.add_child(_more_button)

	_status = Label.new()
	_status.name = "VoxelObjectLibraryStatus"
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.modulate = Color(0.60, 0.82, 0.94)
	add_child(_status)
	_preview_renderer = VoxelPreviewRenderer.new() as EmberVoxelPreviewRenderer
	_preview_renderer.preview_ready.connect(_on_preview_ready)
	add_child(_preview_renderer)


func _add_filter(parent: Node, group: ButtonGroup, value: String, title: String, active := false) -> void:
	var button := Button.new()
	button.name = "VoxelObjectFilter_%s" % value
	button.text = title
	button.toggle_mode = true
	button.button_group = group
	button.button_pressed = active
	button.theme_type_variation = &"WorkshopSegmentButton"
	button.pressed.connect(func() -> void:
		_owner_filter = value
		_apply_filter(selected_model_id())
	)
	parent.add_child(button)
	_filter_buttons[value] = button


func _apply_filter(preferred_id: String) -> void:
	var filtered: Array[Dictionary] = []
	for entry in _all_entries:
		if _owner_filter == "all" or str(entry.get("owner", "")) == _owner_filter:
			var projected := entry.duplicate(true)
			var model_id := str(projected.get("id", ""))
			if _textures.has(model_id):
				projected["texture"] = _textures[model_id]
			filtered.append(projected)
	for entry in filtered:
		for member in entry.get("variations", []):
			if str(member.id) == preferred_id:
				_preferred_variation = preferred_id
				preferred_id = str(entry.id)
				break
	_picker.set_entries(filtered, preferred_id, false)
	_refresh_details()


func _refresh_details() -> void:
	if _picker == null:
		return
	var group := _picker.selected_entry()
	_variations.clear()
	for member in group.get("variations", []):
		_variations.add_item(str(member.get("variation_name", "Основной")))
		_variations.set_item_metadata(_variations.item_count - 1, str(member.id))
		if str(member.id) == _preferred_variation:
			_variations.select(_variations.item_count - 1)
	_variations.visible = _variations.item_count > 1
	_refresh_variant_details()


func selected_model_id() -> String:
	if _variations != null and _variations.selected >= 0:
		return str(_variations.get_item_metadata(_variations.selected))
	return _picker.selected_id() if _picker != null else ""


func _refresh_variant_details() -> void:
	var group := _picker.selected_entry()
	var entry := group
	var selected := selected_model_id()
	for member in group.get("variations", []):
		if str(member.id) == selected:
			entry = member
			break
	var model_id := str(entry.get("id", ""))
	var title := str(group.get("title", model_id))
	var owner := str(entry.get("owner", ""))
	_preview.texture = _textures.get(model_id, null) as Texture2D
	_name_label.text = title if not title.is_empty() else "Выберите объект"
	_id_label.text = model_id
	_id_label.tooltip_text = model_id
	_metadata_label.text = "Размер: %s" % str(entry.get("scale", "")).replace(" blocks", "")
	var tags := PackedStringArray(entry.get("tags", []))
	if not tags.is_empty():
		_metadata_label.text += "\nТеги: %s" % ", ".join(tags)
	_owner_label.text = (
		"● Готов для сцены"
		if owner == "godot"
		else "◇ Ожидает переноса · prefab соберётся при добавлении"
	)
	_owner_label.tooltip_text = (
		"Модель уже хранится как Godot Resource."
		if owner == "godot"
		else "Legacy-модель. При первом добавлении prefab будет собран автоматически."
	)
	_owner_label.modulate = Color(0.50, 0.86, 0.62) if owner == "godot" else Color(0.94, 0.70, 0.38)
	_place_button.disabled = model_id.is_empty() or not _can_place
	_edit_button.disabled = model_id.is_empty()
	_edit_button.text = "Перенести и редактировать" if owner == "legacy_import" else "Редактировать шаблон"
	_edit_button.tooltip_text = (
		"Перенести legacy-модель в Godot Resource и открыть общий шаблон в Canvas. Изменения затронут все её экземпляры."
		if owner == "legacy_import"
		else "Открыть общую voxel-модель в Canvas. Изменения затронут все её экземпляры в сценах."
	)
	var popup := _more_button.get_popup()
	popup.set_item_disabled(popup.get_item_index(0), owner != "godot")
	popup.set_item_disabled(popup.get_item_index(1), owner != "legacy_import")
	var recipe_path := recipe_directory.path_join(model_id + ".tres")
	popup.set_item_disabled(popup.get_item_index(2), owner != "godot" or not ResourceLoader.exists(recipe_path))
	var recipe := GenerativeObjects.load_recipe(model_id, recipe_directory)
	var generator := preload("res://addons/ember_import/ember_voxel_generator.gd")
	if popup.get_item_index(3) < 0: popup.add_item("Генерировать похожие · параметры…", 3)
	popup.set_item_disabled(popup.get_item_index(3), recipe == null or not generator.validation_errors(recipe).is_empty() or generator.creation_fields(str(recipe.generator_id)).is_empty())


func _place_selected() -> void:
	if _picker == null or _place_button.disabled:
		return
	var anchor := _anchor.get_ref() as Node3D if _anchor != null else null
	place_requested.emit(selected_model_id(), anchor)


func _edit_selected() -> void:
	if _picker == null or _edit_button.disabled:
		return
	edit_requested.emit(selected_model_id())


func _on_more_action(id: int) -> void:
	var model_id := selected_model_id()
	if model_id.is_empty():
		return
	if id == 0:
		open_resource_requested.emit(model_id)
	elif id == 1:
		migrate_requested.emit(model_id)
	elif id == 2:
		tree_variant_requested.emit(model_id)
	elif id == 3:
		generate_similar_requested.emit(model_id)


func _on_preview_ready(model_id: String, texture: Texture2D) -> void:
	_textures[model_id] = texture
	_picker.set_entry_texture(model_id, texture)
	if selected_model_id() == model_id:
		_preview.texture = texture
