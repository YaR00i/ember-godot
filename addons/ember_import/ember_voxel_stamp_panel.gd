@tool
extends VBoxContainer
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
const Pattern = preload("res://addons/ember_import/ember_voxel_pattern.gd")
const PatternEditor = preload("res://addons/ember_import/ember_voxel_pattern_editor.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
var workspace: Control
var directory := Stamp.DIRECTORY
var sources := "res://content/voxel_models"
var _title: LineEdit
var _library: OptionButton
var _entries: Array[Dictionary] = []
var _card_grid: GridContainer
var _card_group: ButtonGroup
var _card_buttons: Array[Button] = []
var _selected_label: Label
var _empty_label: Label
var _place_button: Button
var _edit_button: Button
var _create_toggle: Button
var _create_panel: VBoxContainer
var _create_scroll: ScrollContainer
var _card_scroll: ScrollContainer
var _library_actions: HBoxContainer
var _library_separator: HSeparator
var _capture_hint: Label
var _volume_save: Button
var _pattern_panel: VBoxContainer
var _pattern_editor: Control
var _pattern_width: SpinBox
var _pattern_height: SpinBox
var _pattern_depth: SpinBox
var _pattern_density: OptionButton
var _pattern_draw_button: Button
var _pattern_erase_button: Button
var _rock_panel: VBoxContainer
var _rock_preview: TextureRect
var _rock_width: SpinBox
var _rock_height: SpinBox
var _rock_depth: SpinBox
var _rock_roughness: SpinBox
var _rock_chips: SpinBox
var _rock_variant_count: SpinBox
var _rock_size_variation: SpinBox
var _rock_density: OptionButton
var _rock_seed := 0
var _rock_color_override := Color.TRANSPARENT
var _rock_material_override: Variant = null
var _rock_preview_geometry: EmberVoxelModelResource
var _rock_preview_variants: Array[EmberVoxelModelResource] = []
var _tree_panel: VBoxContainer
var _tree_preview: TextureRect
var _tree_height: SpinBox
var _tree_trunk_width: SpinBox
var _tree_crown_radius: SpinBox
var _tree_branchiness: SpinBox
var _tree_crown_roughness: SpinBox
var _tree_density: OptionButton
var _tree_trunk_color: ColorPickerButton
var _tree_foliage_color: ColorPickerButton
var _tree_variant_count: SpinBox
var _tree_size_variation: SpinBox
var _tree_seed := 0
var _tree_material_override: Variant = null
var _tree_preview_geometry: EmberVoxelModelResource
var _tree_preview_variants: Array[EmberVoxelModelResource] = []
var _bush_panel: VBoxContainer
var _bush_preview: TextureRect
var _bush_height: SpinBox
var _bush_spread_radius: SpinBox
var _bush_stem_count: SpinBox
var _bush_foliage_density: SpinBox
var _bush_roughness: SpinBox
var _bush_density: OptionButton
var _bush_stem_color: ColorPickerButton
var _bush_foliage_color: ColorPickerButton
var _bush_variant_count: SpinBox
var _bush_size_variation: SpinBox
var _bush_seed := 0
var _bush_material_override: Variant = null
var _bush_preview_geometry: EmberVoxelModelResource
var _bush_preview_variants: Array[EmberVoxelModelResource] = []
var _grass_panel: VBoxContainer
var _grass_preview: TextureRect
var _grass_height: SpinBox
var _grass_spread_radius: SpinBox
var _grass_blade_count: SpinBox
var _grass_height_variation: SpinBox
var _grass_lean: SpinBox
var _grass_density: OptionButton
var _grass_base_color: ColorPickerButton
var _grass_tip_color: ColorPickerButton
var _grass_variant_count: SpinBox
var _grass_size_variation: SpinBox
var _grass_seed := 0
var _grass_material_override: Variant = null
var _grass_preview_geometry: EmberVoxelModelResource
var _grass_preview_variants: Array[EmberVoxelModelResource] = []
var _create_kind_buttons: Array[Button] = []
var _create_kind := 0
var _editing_path := ""
var _editing_kind := -1

func setup(owner_workspace: Control) -> void:
	workspace = owner_workspace
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 5)
	add_child(toolbar)
	var heading := Label.new()
	heading.text = "ШТАМПЫ И ПАТТЕРНЫ"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar.add_child(heading)
	var refresh := Button.new()
	refresh.name = "VoxelWorkshopRefreshStamps"
	refresh.text = "Обновить"
	refresh.tooltip_text = "Перечитать библиотеку штампов с диска"
	refresh.theme_type_variation = &"WorkshopIconButton"
	refresh.icon = _editor_icon(&"Reload")
	refresh.pressed.connect(refresh_library)
	toolbar.add_child(refresh)
	_create_toggle = Button.new()
	_create_toggle.name = "VoxelWorkshopCreateStampToggle"
	_create_toggle.text = "+ Новый источник"
	_create_toggle.tooltip_text = "Создать штамп из выделения, нарисовать паттерн или сгенерировать природную форму"
	_create_toggle.theme_type_variation = &"WorkshopToolButton"
	_create_toggle.icon = _editor_icon(&"Add")
	_create_toggle.toggle_mode = true
	_create_toggle.toggled.connect(_set_create_expanded)
	add_child(_create_toggle)
	_create_scroll = ScrollContainer.new()
	_create_scroll.name = "VoxelWorkshopCreateStampScroll"
	_create_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_create_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_create_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_create_scroll)
	_create_panel = VBoxContainer.new()
	_create_panel.name = "VoxelWorkshopCreateStampPanel"
	_create_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create_panel.add_theme_constant_override("separation", 5)
	_create_scroll.add_child(_create_panel)
	_capture_hint = Label.new()
	_capture_hint.text = "Сохранить текущее выделение в библиотеку"
	_capture_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_capture_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_capture_hint.modulate = Color(0.54, 0.64, 0.74)
	_create_panel.add_child(_capture_hint)
	var kind_row := GridContainer.new()
	kind_row.columns = 3
	kind_row.add_theme_constant_override("separation",4)
	_create_panel.add_child(kind_row)
	var kind_group := ButtonGroup.new()
	kind_group.allow_unpress = false
	for index in 6:
		var kind_button := Button.new()
		kind_button.text = ["Объём", "Паттерн", "Камень", "Дерево", "Куст", "Трава"][index]
		kind_button.tooltip_text = kind_button.text
		kind_button.clip_text = true
		kind_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		kind_button.custom_minimum_size.x = 0.0
		kind_button.toggle_mode = true
		kind_button.button_group = kind_group
		kind_button.theme_type_variation = &"WorkshopSegmentButton"
		kind_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kind_button.pressed.connect(_select_create_kind.bind(index))
		kind_row.add_child(kind_button)
		_create_kind_buttons.append(kind_button)
	_title = LineEdit.new()
	_title.placeholder_text = "Название штампа"
	_create_panel.add_child(_title)
	_volume_save = Button.new()
	_volume_save.text = "Сохранить как штамп"
	_volume_save.clip_text = true
	_volume_save.theme_type_variation = &"WorkshopPrimaryButton"
	_volume_save.pressed.connect(_save)
	_create_panel.add_child(_volume_save)
	_build_pattern_editor()
	_build_rock_generator()
	_build_tree_generator()
	_build_bush_generator()
	_build_grass_generator()
	_create_panel.hide()
	_create_scroll.hide()
	_select_create_kind(0)
	_library = OptionButton.new()
	_library.fit_to_longest_item = false
	_library.clip_text = true
	_library.hide()
	add_child(_library)
	_library_separator = HSeparator.new()
	add_child(_library_separator)
	_card_scroll = ScrollContainer.new()
	_card_scroll.name = "VoxelWorkshopStampCardScroll"
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_card_scroll)
	var card_body := VBoxContainer.new()
	card_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_body.add_theme_constant_override("separation", 7)
	_card_scroll.add_child(card_body)
	_empty_label = Label.new()
	_empty_label.text = "Библиотека пуста. Сохраните выделение как штамп или нарисуйте плоский паттерн."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.modulate = Color(0.54, 0.64, 0.74)
	card_body.add_child(_empty_label)
	_card_group = ButtonGroup.new()
	_card_group.allow_unpress = false
	_card_grid = GridContainer.new()
	_card_grid.name = "VoxelWorkshopStampCards"
	_card_grid.columns = 2
	_card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_grid.add_theme_constant_override("h_separation", 6)
	_card_grid.add_theme_constant_override("v_separation", 8)
	card_body.add_child(_card_grid)
	_selected_label = Label.new()
	_selected_label.name = "VoxelWorkshopSelectedStamp"
	_selected_label.text = "Выберите штамп"
	_selected_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_selected_label)
	_library_actions = HBoxContainer.new()
	_library_actions.name = "VoxelWorkshopStampActions"
	_library_actions.add_theme_constant_override("separation", 5)
	add_child(_library_actions)
	_place_button = Button.new()
	_place_button.text = "Выбрать"
	_place_button.tooltip_text = "Выбрать штамп как постоянный инструмент Canvas; Enter применяет отдельный отпечаток"
	_place_button.theme_type_variation = &"WorkshopPrimaryButton"
	_place_button.icon = _editor_icon(&"Play")
	_place_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_button.pressed.connect(_place)
	_library_actions.add_child(_place_button)
	_edit_button = Button.new()
	_edit_button.text = "Редактировать"
	_edit_button.tooltip_text = "Открыть объёмный штамп в Canvas или паттерн в редакторе маски"
	_edit_button.icon = _editor_icon(&"Edit")
	_edit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_button.pressed.connect(_edit)
	_library_actions.add_child(_edit_button)
	refresh_library()

func _editor_icon(icon_name: StringName) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var editor_theme := EditorInterface.get_editor_theme()
	return editor_theme.get_icon(icon_name, &"EditorIcons") if editor_theme.has_icon(icon_name, &"EditorIcons") else null

func _set_create_expanded(expanded: bool) -> void:
	_create_toggle.set_pressed_no_signal(expanded)
	_create_panel.visible = expanded
	_create_scroll.visible = expanded
	_create_toggle.text = "− Скрыть создание" if expanded else "+ Новый источник"
	if expanded:
		_title.grab_focus()
	else:
		_editing_path = ""
		_editing_kind = -1
		_rock_color_override = Color.TRANSPARENT
		_rock_material_override = null
		_tree_material_override = null
		_bush_material_override = null
		_grass_material_override = null
		for button in _create_kind_buttons:
			button.disabled = false
	if is_instance_valid(_library_separator):
		_library_separator.visible = not expanded
		_card_scroll.visible = not expanded
		_selected_label.visible = not expanded
		_library_actions.visible = not expanded

func refresh_library(preferred := "") -> void:
	if preferred.is_empty() and not _entries.is_empty() and _library.selected >= 0 and _library.selected < _entries.size():
		preferred = _entries[_library.selected].path
	_entries = Stamp.library(directory)
	_library.clear()
	var selected_index := 0
	for index in _entries.size():
		var entry := _entries[index]
		_library.add_item("%s · %d vox/block" % [entry.name,entry.density])
		if entry.path == preferred:
			selected_index = index
	if _entries.is_empty():
		_library.add_item("Пока нет штампов")
	_library.disabled = _entries.is_empty()
	_empty_label.visible = _entries.is_empty()
	_place_button.disabled = _entries.is_empty()
	_edit_button.disabled = _entries.is_empty()
	_rebuild_cards()
	if _entries.is_empty():
		_selected_label.text = "Выберите штамп"
		workspace._select_workshop_stamp("")
	else:
		_select_entry(selected_index)


func _build_pattern_editor() -> void:
	_pattern_panel = VBoxContainer.new()
	_pattern_panel.name = "VoxelWorkshopPatternEditor"
	_pattern_panel.add_theme_constant_override("separation",5)
	_create_panel.add_child(_pattern_panel)
	var dimensions := HBoxContainer.new()
	dimensions.add_theme_constant_override("separation",5)
	_pattern_panel.add_child(dimensions)
	_pattern_width = _pattern_number("Ширина",1,Pattern.MAX_SIZE,8)
	_pattern_height = _pattern_number("Высота",1,Pattern.MAX_SIZE,8)
	dimensions.add_child(_pattern_width.get_parent())
	dimensions.add_child(_pattern_height.get_parent())
	_pattern_width.value_changed.connect(_on_pattern_size_changed.unbind(1))
	_pattern_height.value_changed.connect(_on_pattern_size_changed.unbind(1))
	var draw_row := HBoxContainer.new()
	draw_row.add_theme_constant_override("separation",4)
	_pattern_panel.add_child(draw_row)
	var draw_group := ButtonGroup.new()
	draw_group.allow_unpress = false
	_pattern_draw_button = Button.new()
	_pattern_draw_button.text = "Рисовать"
	_pattern_draw_button.toggle_mode = true
	_pattern_draw_button.button_group = draw_group
	_pattern_draw_button.theme_type_variation = &"WorkshopSegmentButton"
	_pattern_draw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pattern_draw_button.pressed.connect(_set_pattern_drawing.bind(true))
	draw_row.add_child(_pattern_draw_button)
	_pattern_erase_button = Button.new()
	_pattern_erase_button.text = "Стирать"
	_pattern_erase_button.toggle_mode = true
	_pattern_erase_button.button_group = draw_group
	_pattern_erase_button.theme_type_variation = &"WorkshopSegmentButton"
	_pattern_erase_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pattern_erase_button.pressed.connect(_set_pattern_drawing.bind(false))
	draw_row.add_child(_pattern_erase_button)
	var clear := Button.new()
	clear.text = "Очистить"
	clear.theme_type_variation = &"WorkshopIconButton"
	clear.pressed.connect(func() -> void: _pattern_editor.clear())
	draw_row.add_child(clear)
	_pattern_editor = PatternEditor.new()
	_pattern_editor.name = "VoxelWorkshopPatternCanvas"
	_pattern_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pattern_panel.add_child(_pattern_editor)
	var settings := HBoxContainer.new()
	settings.add_theme_constant_override("separation",5)
	_pattern_panel.add_child(settings)
	_pattern_depth = _pattern_number("Глубина",1,32,1)
	settings.add_child(_pattern_depth.get_parent())
	var density_box := VBoxContainer.new()
	density_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var density_label := Label.new()
	density_label.text = "Плотность"
	density_box.add_child(density_label)
	_pattern_density = OptionButton.new()
	_pattern_density.add_item("16 vox/block",16)
	_pattern_density.add_item("32 vox/block",32)
	_pattern_density.fit_to_longest_item = false
	density_box.add_child(_pattern_density)
	settings.add_child(density_box)
	var save := Button.new()
	save.name = "VoxelWorkshopSavePattern"
	save.text = "Сохранить паттерн"
	save.theme_type_variation = &"WorkshopPrimaryButton"
	save.pressed.connect(_save_pattern)
	_pattern_panel.add_child(save)
	_set_pattern_drawing(true)


func _build_rock_generator() -> void:
	_rock_panel = VBoxContainer.new()
	_rock_panel.name = "VoxelWorkshopRockGenerator"
	_rock_panel.add_theme_constant_override("separation", 6)
	_create_panel.add_child(_rock_panel)
	_rock_preview = TextureRect.new()
	_rock_preview.name = "VoxelWorkshopRockPreview"
	_rock_preview.custom_minimum_size = Vector2(220.0, 92.0)
	_rock_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rock_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rock_preview.tooltip_text = "Производная миниатюра будущего объёмного штампа"
	_rock_panel.add_child(_rock_preview)
	var size_label := Label.new()
	size_label.text = "Размер XYZ · vox"
	_rock_panel.add_child(size_label)
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 4)
	_rock_panel.add_child(size_row)
	var size_controls: Array[SpinBox] = []
	for axis in ["X", "Y", "Z"]:
		var number := SpinBox.new()
		number.min_value = 3
		number.max_value = 32
		number.step = 1
		number.prefix = axis + " "
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		number.value_changed.connect(_refresh_rock_preview.unbind(1))
		size_row.add_child(number)
		size_controls.append(number)
	_rock_width = size_controls[0]
	_rock_height = size_controls[1]
	_rock_depth = size_controls[2]
	_rock_width.value = 10
	_rock_height.value = 7
	_rock_depth.value = 9
	_rock_roughness = _pattern_number("Неровность", 0, 100, 35)
	_rock_roughness.suffix = "%"
	_rock_roughness.value_changed.connect(_refresh_rock_preview.unbind(1))
	_rock_panel.add_child(_rock_roughness.get_parent())
	_rock_chips = _pattern_number("Сколы", 0, 100, 25)
	_rock_chips.suffix = "%"
	_rock_chips.value_changed.connect(_refresh_rock_preview.unbind(1))
	_rock_panel.add_child(_rock_chips.get_parent())
	_rock_variant_count = _pattern_number("Форм в россыпи", 1, 8, 4)
	_rock_variant_count.tooltip_text = (
		"Количество заранее подготовленных силуэтов. Одиночный штамп использует первый, "
		+ "а Россыпь выбирает форму для каждой точки."
	)
	_rock_variant_count.value_changed.connect(_refresh_rock_preview.unbind(1))
	_rock_panel.add_child(_rock_variant_count.get_parent())
	_rock_size_variation = _pattern_number("Размер форм ±", 0, 50, 25)
	_rock_size_variation.suffix = "%"
	_rock_size_variation.tooltip_text = "Насколько варианты могут отличаться по X, Y и Z."
	_rock_size_variation.value_changed.connect(_refresh_rock_preview.unbind(1))
	_rock_panel.add_child(_rock_size_variation.get_parent())
	var density_row := HBoxContainer.new()
	var density_label := Label.new()
	density_label.text = "Плотность"
	density_row.add_child(density_label)
	_rock_density = OptionButton.new()
	_rock_density.add_item("16 vox/block", 16)
	_rock_density.add_item("32 vox/block", 32)
	_rock_density.fit_to_longest_item = false
	_rock_density.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rock_density.item_selected.connect(_refresh_rock_preview.unbind(1))
	density_row.add_child(_rock_density)
	_rock_panel.add_child(density_row)
	var variant := Button.new()
	variant.name = "VoxelWorkshopRockVariant"
	variant.text = "Другой вариант"
	variant.tooltip_text = "Меняет форму камня, сохраняя размеры и характер"
	variant.pressed.connect(_on_rock_variant)
	_rock_panel.add_child(variant)
	var save := Button.new()
	save.name = "VoxelWorkshopSaveRock"
	save.text = "Сохранить камень"
	save.theme_type_variation = &"WorkshopPrimaryButton"
	save.pressed.connect(_save_rock)
	_rock_panel.add_child(save)
	_rock_panel.hide()


func _build_tree_generator() -> void:
	_tree_panel = VBoxContainer.new()
	_tree_panel.name = "VoxelWorkshopTreeGenerator"
	_tree_panel.add_theme_constant_override("separation", 6)
	_create_panel.add_child(_tree_panel)
	_tree_preview = TextureRect.new()
	_tree_preview.name = "VoxelWorkshopTreePreview"
	_tree_preview.custom_minimum_size = Vector2(220.0, 112.0)
	_tree_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tree_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tree_panel.add_child(_tree_preview)
	_tree_height = _pattern_number("Высота", 8, 32, 18)
	_tree_height.suffix = " vox"
	_tree_height.value_changed.connect(_refresh_tree_preview.unbind(1))
	_tree_panel.add_child(_tree_height.get_parent())
	_tree_trunk_width = _pattern_number("Толщина ствола", 1, 5, 2)
	_tree_trunk_width.suffix = " vox"
	_tree_trunk_width.value_changed.connect(_refresh_tree_preview.unbind(1))
	_tree_panel.add_child(_tree_trunk_width.get_parent())
	_tree_crown_radius = _pattern_number("Размер кроны", 2, 10, 5)
	_tree_crown_radius.suffix = " vox"
	_tree_crown_radius.value_changed.connect(_refresh_tree_preview.unbind(1))
	_tree_panel.add_child(_tree_crown_radius.get_parent())
	_tree_branchiness = _pattern_number("Ветвистость", 0, 100, 55)
	_tree_branchiness.suffix = "%"
	_tree_branchiness.value_changed.connect(_refresh_tree_preview.unbind(1))
	_tree_panel.add_child(_tree_branchiness.get_parent())
	_tree_crown_roughness = _pattern_number("Неровность кроны", 0, 100, 35)
	_tree_crown_roughness.suffix = "%"
	_tree_crown_roughness.value_changed.connect(_refresh_tree_preview.unbind(1))
	_tree_panel.add_child(_tree_crown_roughness.get_parent())
	var colors_row := HBoxContainer.new()
	colors_row.add_theme_constant_override("separation", 6)
	_tree_panel.add_child(colors_row)
	_tree_trunk_color = _tree_color("Ствол", Color("7a5134"))
	_tree_trunk_color.color_changed.connect(_refresh_tree_preview.unbind(1))
	colors_row.add_child(_tree_trunk_color.get_parent())
	_tree_foliage_color = _tree_color("Крона", Color("4f9250"))
	_tree_foliage_color.color_changed.connect(_refresh_tree_preview.unbind(1))
	colors_row.add_child(_tree_foliage_color.get_parent())
	_tree_variant_count = _pattern_number("Форм в россыпи", 1, 8, 4)
	_tree_variant_count.value_changed.connect(_refresh_tree_preview.unbind(1))
	_tree_panel.add_child(_tree_variant_count.get_parent())
	_tree_size_variation = _pattern_number("Размер форм ±", 0, 50, 20)
	_tree_size_variation.suffix = "%"
	_tree_size_variation.value_changed.connect(_refresh_tree_preview.unbind(1))
	_tree_panel.add_child(_tree_size_variation.get_parent())
	var density_row := HBoxContainer.new()
	var density_label := Label.new()
	density_label.text = "Плотность"
	density_row.add_child(density_label)
	_tree_density = OptionButton.new()
	_tree_density.add_item("16 vox/block", 16)
	_tree_density.add_item("32 vox/block", 32)
	_tree_density.fit_to_longest_item = false
	_tree_density.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_density.item_selected.connect(_refresh_tree_preview.unbind(1))
	density_row.add_child(_tree_density)
	_tree_panel.add_child(density_row)
	var variant := Button.new()
	variant.name = "VoxelWorkshopTreeVariant"
	variant.text = "Другой вариант дерева"
	variant.tooltip_text = "Меняет изгиб ствола, ветви и расположение частей кроны"
	variant.pressed.connect(_on_tree_variant)
	_tree_panel.add_child(variant)
	var save := Button.new()
	save.name = "VoxelWorkshopSaveTree"
	save.text = "Сохранить дерево"
	save.theme_type_variation = &"WorkshopPrimaryButton"
	save.pressed.connect(_save_tree)
	_tree_panel.add_child(save)
	_tree_panel.hide()


func _build_bush_generator() -> void:
	_bush_panel = VBoxContainer.new()
	_bush_panel.name = "VoxelWorkshopBushGenerator"
	_bush_panel.add_theme_constant_override("separation", 6)
	_create_panel.add_child(_bush_panel)
	_bush_preview = TextureRect.new()
	_bush_preview.name = "VoxelWorkshopBushPreview"
	_bush_preview.custom_minimum_size = Vector2(220.0, 112.0)
	_bush_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bush_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bush_panel.add_child(_bush_preview)
	_bush_height = _pattern_number("Высота", 4, 24, 10)
	_bush_height.suffix = " vox"
	_bush_height.value_changed.connect(_refresh_bush_preview.unbind(1))
	_bush_panel.add_child(_bush_height.get_parent())
	_bush_spread_radius = _pattern_number("Размах", 2, 12, 5)
	_bush_spread_radius.suffix = " vox"
	_bush_spread_radius.tooltip_text = "Радиус, в пределах которого расходятся стебли и листва"
	_bush_spread_radius.value_changed.connect(_refresh_bush_preview.unbind(1))
	_bush_panel.add_child(_bush_spread_radius.get_parent())
	_bush_stem_count = _pattern_number("Стебли", 1, 12, 5)
	_bush_stem_count.value_changed.connect(_refresh_bush_preview.unbind(1))
	_bush_panel.add_child(_bush_stem_count.get_parent())
	_bush_foliage_density = _pattern_number("Пышность листвы", 20, 100, 65)
	_bush_foliage_density.suffix = "%"
	_bush_foliage_density.value_changed.connect(_refresh_bush_preview.unbind(1))
	_bush_panel.add_child(_bush_foliage_density.get_parent())
	_bush_roughness = _pattern_number("Неровность", 0, 100, 35)
	_bush_roughness.suffix = "%"
	_bush_roughness.value_changed.connect(_refresh_bush_preview.unbind(1))
	_bush_panel.add_child(_bush_roughness.get_parent())
	var colors_row := HBoxContainer.new()
	colors_row.add_theme_constant_override("separation", 6)
	_bush_panel.add_child(colors_row)
	_bush_stem_color = _tree_color("Стебли", Color("755039"))
	_bush_stem_color.color_changed.connect(_refresh_bush_preview.unbind(1))
	colors_row.add_child(_bush_stem_color.get_parent())
	_bush_foliage_color = _tree_color("Листва", Color("568f4d"))
	_bush_foliage_color.color_changed.connect(_refresh_bush_preview.unbind(1))
	colors_row.add_child(_bush_foliage_color.get_parent())
	_bush_variant_count = _pattern_number("Форм в россыпи", 1, 8, 4)
	_bush_variant_count.value_changed.connect(_refresh_bush_preview.unbind(1))
	_bush_panel.add_child(_bush_variant_count.get_parent())
	_bush_size_variation = _pattern_number("Размер форм ±", 0, 50, 20)
	_bush_size_variation.suffix = "%"
	_bush_size_variation.value_changed.connect(_refresh_bush_preview.unbind(1))
	_bush_panel.add_child(_bush_size_variation.get_parent())
	var density_row := HBoxContainer.new()
	var density_label := Label.new()
	density_label.text = "Плотность"
	density_row.add_child(density_label)
	_bush_density = OptionButton.new()
	_bush_density.add_item("16 vox/block", 16)
	_bush_density.add_item("32 vox/block", 32)
	_bush_density.fit_to_longest_item = false
	_bush_density.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bush_density.item_selected.connect(_refresh_bush_preview.unbind(1))
	density_row.add_child(_bush_density)
	_bush_panel.add_child(density_row)
	var variant := Button.new()
	variant.name = "VoxelWorkshopBushVariant"
	variant.text = "Другой вариант куста"
	variant.tooltip_text = "Меняет направление стеблей и распределение частей листвы"
	variant.pressed.connect(_on_bush_variant)
	_bush_panel.add_child(variant)
	var save := Button.new()
	save.name = "VoxelWorkshopSaveBush"
	save.text = "Сохранить куст"
	save.theme_type_variation = &"WorkshopPrimaryButton"
	save.pressed.connect(_save_bush)
	_bush_panel.add_child(save)
	_bush_panel.hide()


func _build_grass_generator() -> void:
	_grass_panel = VBoxContainer.new()
	_grass_panel.name = "VoxelWorkshopGrassGenerator"
	_grass_panel.add_theme_constant_override("separation", 6)
	_create_panel.add_child(_grass_panel)
	_grass_preview = TextureRect.new()
	_grass_preview.name = "VoxelWorkshopGrassPreview"
	_grass_preview.custom_minimum_size = Vector2(220.0, 112.0)
	_grass_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_grass_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_grass_panel.add_child(_grass_preview)
	_grass_height = _pattern_number("Высота", 2, 12, 6)
	_grass_height.suffix = " vox"
	_grass_height.value_changed.connect(_refresh_grass_preview.unbind(1))
	_grass_panel.add_child(_grass_height.get_parent())
	_grass_spread_radius = _pattern_number("Размах пучка", 1, 4, 2)
	_grass_spread_radius.suffix = " vox"
	_grass_spread_radius.value_changed.connect(_refresh_grass_preview.unbind(1))
	_grass_panel.add_child(_grass_spread_radius.get_parent())
	_grass_blade_count = _pattern_number("Травинки", 2, 16, 7)
	_grass_blade_count.value_changed.connect(_refresh_grass_preview.unbind(1))
	_grass_panel.add_child(_grass_blade_count.get_parent())
	_grass_height_variation = _pattern_number("Разброс высоты", 0, 75, 35)
	_grass_height_variation.suffix = "%"
	_grass_height_variation.value_changed.connect(_refresh_grass_preview.unbind(1))
	_grass_panel.add_child(_grass_height_variation.get_parent())
	_grass_lean = _pattern_number("Наклон", 0, 100, 30)
	_grass_lean.suffix = "%"
	_grass_lean.value_changed.connect(_refresh_grass_preview.unbind(1))
	_grass_panel.add_child(_grass_lean.get_parent())
	var colors_row := HBoxContainer.new()
	colors_row.add_theme_constant_override("separation", 6)
	_grass_panel.add_child(colors_row)
	_grass_base_color = _tree_color("Основание", Color("4f873e"))
	_grass_base_color.color_changed.connect(_refresh_grass_preview.unbind(1))
	colors_row.add_child(_grass_base_color.get_parent())
	_grass_tip_color = _tree_color("Кончики", Color("89bd58"))
	_grass_tip_color.color_changed.connect(_refresh_grass_preview.unbind(1))
	colors_row.add_child(_grass_tip_color.get_parent())
	_grass_variant_count = _pattern_number("Форм в россыпи", 1, 8, 6)
	_grass_variant_count.value_changed.connect(_refresh_grass_preview.unbind(1))
	_grass_panel.add_child(_grass_variant_count.get_parent())
	_grass_size_variation = _pattern_number("Размер форм ±", 0, 50, 20)
	_grass_size_variation.suffix = "%"
	_grass_size_variation.value_changed.connect(_refresh_grass_preview.unbind(1))
	_grass_panel.add_child(_grass_size_variation.get_parent())
	var density_row := HBoxContainer.new()
	var density_label := Label.new()
	density_label.text = "Плотность"
	density_row.add_child(density_label)
	_grass_density = OptionButton.new()
	_grass_density.add_item("16 vox/block", 16)
	_grass_density.add_item("32 vox/block", 32)
	_grass_density.fit_to_longest_item = false
	_grass_density.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grass_density.item_selected.connect(_refresh_grass_preview.unbind(1))
	density_row.add_child(_grass_density)
	_grass_panel.add_child(density_row)
	var note := Label.new()
	note.text = "Трава декоративная: растёт вверх и не создаёт коллизию."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.modulate = Color(0.54, 0.64, 0.74)
	_grass_panel.add_child(note)
	var variant := Button.new()
	variant.name = "VoxelWorkshopGrassVariant"
	variant.text = "Другой вариант травы"
	variant.tooltip_text = "Меняет высоты, наклон и расположение травинок"
	variant.pressed.connect(_on_grass_variant)
	_grass_panel.add_child(variant)
	var save := Button.new()
	save.name = "VoxelWorkshopSaveGrass"
	save.text = "Сохранить траву"
	save.theme_type_variation = &"WorkshopPrimaryButton"
	save.pressed.connect(_save_grass)
	_grass_panel.add_child(save)
	_grass_panel.hide()


func _tree_color(label_text: String, initial: Color) -> ColorPickerButton:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	var picker := ColorPickerButton.new()
	picker.color = initial
	picker.edit_alpha = false
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(picker)
	return picker


func _pattern_number(label_text: String, minimum: int, maximum: int, value: int) -> SpinBox:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.value = value
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(number)
	return number


func _select_create_kind(index: int) -> void:
	var requested := clampi(index, 0, 5)
	if _editing_kind >= 0 and requested != _editing_kind:
		requested = _editing_kind
	_create_kind = requested
	for button_index in _create_kind_buttons.size():
		_create_kind_buttons[button_index].set_pressed_no_signal(button_index == _create_kind)
	var pattern := _create_kind == 1
	var rock := _create_kind == 2
	var tree := _create_kind == 3
	var bush := _create_kind == 4
	var grass := _create_kind == 5
	_capture_hint.text = (
		"Нарисуйте бинарную маску; ЛКМ рисует, ПКМ стирает"
		if pattern
		else "Настройте процедурную форму; после сохранения она работает как обычный штамп"
		if rock or tree or bush or grass
		else "Сохранить текущее выделение в библиотеку"
	)
	_volume_save.visible = not pattern and not rock and not tree and not bush and not grass
	_pattern_panel.visible = pattern
	_rock_panel.visible = rock
	_tree_panel.visible = tree
	_bush_panel.visible = bush
	_grass_panel.visible = grass
	if pattern and workspace != null and workspace._resource != null and _editing_path.is_empty():
		_pattern_density.select(1 if workspace._resource.normalized_density() == 32 else 0)
	if rock:
		if workspace != null and workspace._resource != null and _editing_path.is_empty():
			_rock_density.select(1 if workspace._resource.normalized_density() == 32 else 0)
		_refresh_rock_preview()
	if tree:
		if workspace != null and workspace._resource != null and _editing_path.is_empty():
			_tree_density.select(1 if workspace._resource.normalized_density() == 32 else 0)
			if workspace._palette.selected >= 0:
				var palette_index := int(workspace._palette.get_selected_metadata())
				if palette_index > 0 and palette_index < workspace._resource.palette.size():
					_tree_foliage_color.color = workspace._resource.palette[palette_index]
		_refresh_tree_preview()
	if bush:
		if workspace != null and workspace._resource != null and _editing_path.is_empty():
			_bush_density.select(1 if workspace._resource.normalized_density() == 32 else 0)
			if workspace._palette.selected >= 0:
				var palette_index := int(workspace._palette.get_selected_metadata())
				if palette_index > 0 and palette_index < workspace._resource.palette.size():
					_bush_foliage_color.color = workspace._resource.palette[palette_index]
		_refresh_bush_preview()
	if grass:
		if workspace != null and workspace._resource != null and _editing_path.is_empty():
			_grass_density.select(1 if workspace._resource.normalized_density() == 32 else 0)
			if workspace._palette.selected >= 0:
				var palette_index := int(workspace._palette.get_selected_metadata())
				if palette_index > 0 and palette_index < workspace._resource.palette.size():
					_grass_base_color.color = workspace._resource.palette[palette_index]
		_refresh_grass_preview()


func _rock_parameters() -> Dictionary:
	return {
		"dimensions": Vector3i(
			int(_rock_width.value), int(_rock_height.value), int(_rock_depth.value)
		),
		"roughness": int(_rock_roughness.value),
		"chips": int(_rock_chips.value),
		"density": int(_rock_density.get_item_id(_rock_density.selected)),
		"variant_count": int(_rock_variant_count.value),
		"size_variation": int(_rock_size_variation.value),
	}


func _rock_recipe() -> Resource:
	var recipe := Generator.default_recipe(Generator.ROCK)
	recipe.seed = _rock_seed
	recipe.parameters = _rock_parameters()
	return recipe


func _rock_color() -> Color:
	if _rock_color_override.a > 0.0:
		return _rock_color_override
	if workspace != null and workspace._resource != null and workspace._palette.selected >= 0:
		var palette_index := int(workspace._palette.get_selected_metadata())
		if palette_index > 0 and palette_index < workspace._resource.palette.size():
			return workspace._resource.palette[palette_index]
	return Color(0.42, 0.46, 0.50)


func _refresh_rock_preview() -> void:
	if (
		not is_instance_valid(_rock_preview)
		or not is_instance_valid(_rock_density)
		or _rock_density.selected < 0
	):
		return
	var material: Dictionary = {}
	if _rock_material_override is Dictionary:
		material = (_rock_material_override as Dictionary).duplicate(true)
	elif workspace != null and workspace._resource != null:
		material = workspace._resource.material
	var title := _title.text.strip_edges()
	var result := Generator.build(
		_rock_recipe(), _rock_color(), material, title if not title.is_empty() else "Камень"
	)
	if result.has("error"):
		_rock_preview_geometry = null
		_rock_preview_variants.clear()
		_rock_preview.texture = null
		return
	_rock_preview_geometry = result.geometry
	var preview_recipe := _rock_recipe()
	preview_recipe.parameters = preview_recipe.parameters.duplicate(true)
	preview_recipe.parameters.variant_count = mini(
		int(preview_recipe.parameters.variant_count), 4
	)
	var variants := Generator.build_variants(preview_recipe, _rock_preview_geometry)
	if variants.has("error"):
		_rock_preview_variants.clear()
		_rock_preview.texture = _thumbnail_geometry(_rock_preview_geometry)
		return
	_rock_preview_variants.assign(variants.variants)
	_rock_preview.texture = _thumbnail_variant_set(_rock_preview_variants)
	_rock_preview.tooltip_text = "Предпросмотр %d из %d форм будущей россыпи" % [
		_rock_preview_variants.size(), int(_rock_variant_count.value)
	]


func _on_rock_variant() -> void:
	_rock_seed += 1
	_refresh_rock_preview()
	workspace._set_status(
		"Камень · вариант %d · набор %d форм · сохранение создаст обычный штамп"
		% [_rock_seed, int(_rock_variant_count.value)]
	)


func _save_rock() -> void:
	var title := _title.text.strip_edges()
	if title.is_empty():
		workspace._set_status("Введите название камня.", true)
		return
	_refresh_rock_preview()
	if _rock_preview_geometry == null:
		workspace._set_status("Не удалось построить камень с этими параметрами.", true)
		return
	var preset := Stamp.Preset.new()
	preset.display_name = title
	preset.kind = Stamp.Preset.KIND_GENERATED_VOLUME
	preset.anchor = 1
	preset.generator_recipe = _rock_recipe()
	preset.geometry = _rock_preview_geometry
	var result := {}
	if _editing_path.is_empty():
		result = Stamp.save_new(preset, directory, sources)
	else:
		var previous := ResourceLoader.load(
			_editing_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP
		)
		var source_path: String = (
			previous.geometry.resource_path
			if previous is Stamp.Preset and previous.geometry != null
			else ""
		)
		result = Stamp.save_existing(preset, _editing_path, source_path)
	if result.has("error"):
		workspace._set_status(result.error, true)
		return
	_editing_path = ""
	_editing_kind = -1
	refresh_library(result.path)
	_set_create_expanded(false)
	workspace._set_status("Камень сохранён как обычный штамп · выберите его для размещения")
	if Engine.is_editor_hint():
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()


func _tree_parameters() -> Dictionary:
	return {
		"height": int(_tree_height.value),
		"trunk_width": int(_tree_trunk_width.value),
		"crown_radius": int(_tree_crown_radius.value),
		"branchiness": int(_tree_branchiness.value),
		"crown_roughness": int(_tree_crown_roughness.value),
		"density": int(_tree_density.get_item_id(_tree_density.selected)),
		"trunk_color": _tree_trunk_color.color,
		"foliage_color": _tree_foliage_color.color,
		"variant_count": int(_tree_variant_count.value),
		"size_variation": int(_tree_size_variation.value),
	}


func _tree_recipe() -> Resource:
	var recipe := Generator.default_recipe(Generator.TREE)
	recipe.seed = _tree_seed
	recipe.parameters = _tree_parameters()
	return recipe


func _refresh_tree_preview() -> void:
	if (
		not is_instance_valid(_tree_preview)
		or not is_instance_valid(_tree_density)
		or _tree_density.selected < 0
	):
		return
	var material: Dictionary = {}
	if _tree_material_override is Dictionary:
		material = (_tree_material_override as Dictionary).duplicate(true)
	elif workspace != null and workspace._resource != null:
		material = workspace._resource.material
	var title := _title.text.strip_edges()
	var recipe := _tree_recipe()
	var result := Generator.build(
		recipe,
		_tree_foliage_color.color,
		material,
		title if not title.is_empty() else "Дерево",
	)
	if result.has("error"):
		_tree_preview_geometry = null
		_tree_preview_variants.clear()
		_tree_preview.texture = null
		return
	_tree_preview_geometry = result.geometry
	var preview_recipe := recipe.duplicate(true)
	preview_recipe.parameters = preview_recipe.parameters.duplicate(true)
	preview_recipe.parameters.variant_count = mini(
		int(preview_recipe.parameters.variant_count), 4
	)
	var variants := Generator.build_variants(preview_recipe, _tree_preview_geometry)
	if variants.has("error"):
		_tree_preview_variants.clear()
		_tree_preview.texture = _thumbnail_geometry(_tree_preview_geometry)
		return
	_tree_preview_variants.assign(variants.variants)
	_tree_preview.texture = _thumbnail_variant_set(_tree_preview_variants)
	_tree_preview.tooltip_text = "Предпросмотр %d из %d форм будущей лесной россыпи" % [
		_tree_preview_variants.size(), int(_tree_variant_count.value)
	]


func _on_tree_variant() -> void:
	_tree_seed += 1
	_refresh_tree_preview()
	workspace._set_status(
		"Дерево · вариант рецепта %d · набор %d форм"
		% [_tree_seed, int(_tree_variant_count.value)]
	)


func _save_tree() -> void:
	var title := _title.text.strip_edges()
	if title.is_empty():
		workspace._set_status("Введите название дерева.", true)
		return
	_refresh_tree_preview()
	if _tree_preview_geometry == null:
		workspace._set_status("Не удалось построить дерево с этими параметрами.", true)
		return
	var preset := Stamp.Preset.new()
	preset.display_name = title
	preset.kind = Stamp.Preset.KIND_GENERATED_VOLUME
	preset.anchor = 1
	preset.generator_recipe = _tree_recipe()
	preset.geometry = _tree_preview_geometry
	var result := {}
	if _editing_path.is_empty():
		result = Stamp.save_new(preset, directory, sources)
	else:
		var previous := ResourceLoader.load(
			_editing_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP
		)
		var source_path: String = (
			previous.geometry.resource_path
			if previous is Stamp.Preset and previous.geometry != null
			else ""
		)
		result = Stamp.save_existing(preset, _editing_path, source_path)
	if result.has("error"):
		workspace._set_status(result.error, true)
		return
	_editing_path = ""
	_editing_kind = -1
	refresh_library(result.path)
	_set_create_expanded(false)
	workspace._set_status("Дерево сохранено · выберите его для одиночной посадки или россыпи")
	if Engine.is_editor_hint():
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()


func _bush_parameters() -> Dictionary:
	return {
		"height": int(_bush_height.value),
		"spread_radius": int(_bush_spread_radius.value),
		"stem_count": int(_bush_stem_count.value),
		"foliage_density": int(_bush_foliage_density.value),
		"roughness": int(_bush_roughness.value),
		"density": int(_bush_density.get_item_id(_bush_density.selected)),
		"stem_color": _bush_stem_color.color,
		"foliage_color": _bush_foliage_color.color,
		"variant_count": int(_bush_variant_count.value),
		"size_variation": int(_bush_size_variation.value),
	}


func _bush_recipe() -> Resource:
	var recipe := Generator.default_recipe(Generator.BUSH)
	recipe.seed = _bush_seed
	recipe.parameters = _bush_parameters()
	return recipe


func _refresh_bush_preview() -> void:
	if (
		not is_instance_valid(_bush_preview)
		or not is_instance_valid(_bush_density)
		or _bush_density.selected < 0
	):
		return
	var material: Dictionary = {}
	if _bush_material_override is Dictionary:
		material = (_bush_material_override as Dictionary).duplicate(true)
	elif workspace != null and workspace._resource != null:
		material = workspace._resource.material
	var title := _title.text.strip_edges()
	var recipe := _bush_recipe()
	var result := Generator.build(
		recipe,
		_bush_foliage_color.color,
		material,
		title if not title.is_empty() else "Куст",
	)
	if result.has("error"):
		_bush_preview_geometry = null
		_bush_preview_variants.clear()
		_bush_preview.texture = null
		return
	_bush_preview_geometry = result.geometry
	var preview_recipe := recipe.duplicate(true)
	preview_recipe.parameters = preview_recipe.parameters.duplicate(true)
	preview_recipe.parameters.variant_count = mini(
		int(preview_recipe.parameters.variant_count), 4
	)
	var variants := Generator.build_variants(preview_recipe, _bush_preview_geometry)
	if variants.has("error"):
		_bush_preview_variants.clear()
		_bush_preview.texture = _thumbnail_geometry(_bush_preview_geometry)
		return
	_bush_preview_variants.assign(variants.variants)
	_bush_preview.texture = _thumbnail_variant_set(_bush_preview_variants)
	_bush_preview.tooltip_text = "Предпросмотр %d из %d форм будущей кустовой россыпи" % [
		_bush_preview_variants.size(), int(_bush_variant_count.value)
	]


func _on_bush_variant() -> void:
	_bush_seed += 1
	_refresh_bush_preview()
	workspace._set_status(
		"Куст · вариант рецепта %d · набор %d форм"
		% [_bush_seed, int(_bush_variant_count.value)]
	)


func _save_bush() -> void:
	var title := _title.text.strip_edges()
	if title.is_empty():
		workspace._set_status("Введите название куста.", true)
		return
	_refresh_bush_preview()
	if _bush_preview_geometry == null:
		workspace._set_status("Не удалось построить куст с этими параметрами.", true)
		return
	var preset := Stamp.Preset.new()
	preset.display_name = title
	preset.kind = Stamp.Preset.KIND_GENERATED_VOLUME
	preset.anchor = 1
	preset.generator_recipe = _bush_recipe()
	preset.geometry = _bush_preview_geometry
	var result := {}
	if _editing_path.is_empty():
		result = Stamp.save_new(preset, directory, sources)
	else:
		var previous := ResourceLoader.load(
			_editing_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP
		)
		var source_path: String = (
			previous.geometry.resource_path
			if previous is Stamp.Preset and previous.geometry != null
			else ""
		)
		result = Stamp.save_existing(preset, _editing_path, source_path)
	if result.has("error"):
		workspace._set_status(result.error, true)
		return
	_editing_path = ""
	_editing_kind = -1
	refresh_library(result.path)
	_set_create_expanded(false)
	workspace._set_status("Куст сохранён · выберите его для одиночной посадки или россыпи")
	if Engine.is_editor_hint():
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()


func _grass_parameters() -> Dictionary:
	return {
		"height": int(_grass_height.value),
		"spread_radius": int(_grass_spread_radius.value),
		"blade_count": int(_grass_blade_count.value),
		"height_variation": int(_grass_height_variation.value),
		"lean": int(_grass_lean.value),
		"density": int(_grass_density.get_item_id(_grass_density.selected)),
		"base_color": _grass_base_color.color,
		"tip_color": _grass_tip_color.color,
		"variant_count": int(_grass_variant_count.value),
		"size_variation": int(_grass_size_variation.value),
	}


func _grass_recipe() -> Resource:
	var recipe := Generator.default_recipe(Generator.GRASS)
	recipe.seed = _grass_seed
	recipe.parameters = _grass_parameters()
	return recipe


func _refresh_grass_preview() -> void:
	if (
		not is_instance_valid(_grass_preview)
		or not is_instance_valid(_grass_density)
		or _grass_density.selected < 0
	):
		return
	var material: Dictionary = {}
	if _grass_material_override is Dictionary:
		material = (_grass_material_override as Dictionary).duplicate(true)
	elif workspace != null and workspace._resource != null:
		material = workspace._resource.material
	var title := _title.text.strip_edges()
	var recipe := _grass_recipe()
	var result := Generator.build(
		recipe,
		_grass_base_color.color,
		material,
		title if not title.is_empty() else "Трава",
	)
	if result.has("error"):
		_grass_preview_geometry = null
		_grass_preview_variants.clear()
		_grass_preview.texture = null
		return
	_grass_preview_geometry = result.geometry
	var preview_recipe := recipe.duplicate(true)
	preview_recipe.parameters = preview_recipe.parameters.duplicate(true)
	preview_recipe.parameters.variant_count = mini(
		int(preview_recipe.parameters.variant_count), 4
	)
	var variants := Generator.build_variants(preview_recipe, _grass_preview_geometry)
	if variants.has("error"):
		_grass_preview_variants.clear()
		_grass_preview.texture = _thumbnail_geometry(_grass_preview_geometry)
		return
	_grass_preview_variants.assign(variants.variants)
	_grass_preview.texture = _thumbnail_variant_set(_grass_preview_variants)
	_grass_preview.tooltip_text = "Предпросмотр %d из %d форм будущей травяной россыпи" % [
		_grass_preview_variants.size(), int(_grass_variant_count.value)
	]


func _on_grass_variant() -> void:
	_grass_seed += 1
	_refresh_grass_preview()
	workspace._set_status(
		"Трава · вариант рецепта %d · набор %d форм"
		% [_grass_seed, int(_grass_variant_count.value)]
	)


func _save_grass() -> void:
	var title := _title.text.strip_edges()
	if title.is_empty():
		workspace._set_status("Введите название травы.", true)
		return
	_refresh_grass_preview()
	if _grass_preview_geometry == null:
		workspace._set_status("Не удалось построить траву с этими параметрами.", true)
		return
	var preset := Stamp.Preset.new()
	preset.display_name = title
	preset.kind = Stamp.Preset.KIND_GENERATED_VOLUME
	preset.anchor = 1
	preset.generator_recipe = _grass_recipe()
	preset.geometry = _grass_preview_geometry
	var result := {}
	if _editing_path.is_empty():
		result = Stamp.save_new(preset, directory, sources)
	else:
		var previous := ResourceLoader.load(
			_editing_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP
		)
		var source_path: String = (
			previous.geometry.resource_path
			if previous is Stamp.Preset and previous.geometry != null
			else ""
		)
		result = Stamp.save_existing(preset, _editing_path, source_path)
	if result.has("error"):
		workspace._set_status(result.error, true)
		return
	_editing_path = ""
	_editing_kind = -1
	refresh_library(result.path)
	_set_create_expanded(false)
	workspace._set_status("Трава сохранена · Россыпь выбрана по умолчанию, Enter применяет мазок")
	if Engine.is_editor_hint():
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()


func _set_pattern_drawing(active: bool) -> void:
	if _pattern_editor != null:
		_pattern_editor.drawing = active
	_pattern_draw_button.set_pressed_no_signal(active)
	_pattern_erase_button.set_pressed_no_signal(not active)


func _on_pattern_size_changed() -> void:
	_pattern_editor.set_pattern_size(Vector2i(int(_pattern_width.value),int(_pattern_height.value)))


func _save_pattern() -> void:
	var title := _title.text.strip_edges()
	if title.is_empty():
		workspace._set_status("Введите название паттерна.",true)
		return
	var density := int(_pattern_density.get_item_id(_pattern_density.selected))
	var built := Pattern.build_geometry(
		Vector2i(int(_pattern_width.value),int(_pattern_height.value)),
		_pattern_editor.mask(),density,title,
	)
	if built.has("error"):
		workspace._set_status(built.error,true)
		return
	var preset := Stamp.Preset.new()
	preset.display_name = title
	preset.kind = Stamp.Preset.KIND_PATTERN
	preset.pattern_size = Vector2i(int(_pattern_width.value),int(_pattern_height.value))
	preset.pattern_depth = int(_pattern_depth.value)
	preset.anchor = 1
	preset.geometry = built.geometry
	var result := {}
	if _editing_path.is_empty():
		result = Stamp.save_new(preset,directory,sources)
	else:
		var previous := ResourceLoader.load(_editing_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var source_path: String = previous.geometry.resource_path if previous is Stamp.Preset and previous.geometry != null else ""
		result = Stamp.save_existing(preset,_editing_path,source_path)
	if result.has("error"):
		workspace._set_status(result.error,true)
		return
	_editing_path = ""
	refresh_library(result.path)
	_set_create_expanded(false)
	workspace._set_status("Паттерн сохранён. Его маска остаётся редактируемой в библиотеке.")
	if Engine.is_editor_hint():
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()


func _rebuild_cards() -> void:
	for child in _card_grid.get_children():
		child.queue_free()
	_card_buttons.clear()
	for index in _entries.size():
		var entry := _entries[index]
		var card := VBoxContainer.new()
		card.custom_minimum_size.x = 132.0
		var preview := Button.new()
		preview.name = "VoxelWorkshopStampCard%d" % index
		preview.custom_minimum_size = Vector2(132.0, 76.0)
		preview.toggle_mode = true
		preview.theme_type_variation = &"WorkshopCardButton"
		preview.button_group = _card_group
		preview.icon = _thumbnail(entry.path)
		preview.expand_icon = true
		var kind_label := _entry_kind_label(entry)
		preview.tooltip_text = "%s · %s · %d vox/block" % [entry.name,kind_label,entry.density]
		preview.pressed.connect(_select_entry.bind(index))
		card.add_child(preview)
		_card_buttons.append(preview)
		var caption := Button.new()
		caption.flat = true
		caption.custom_minimum_size = Vector2(132.0, 42.0)
		caption.text = "%s\n%s" % [entry.name, _entry_caption(entry)]
		caption.tooltip_text = preview.tooltip_text
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		caption.pressed.connect(_select_entry.bind(index))
		card.add_child(caption)
		_card_grid.add_child(card)


func _select_entry(index: int) -> void:
	if index < 0 or index >= _entries.size():
		return
	_library.select(index)
	for button_index in _card_buttons.size():
		_card_buttons[button_index].set_pressed_no_signal(button_index == index)
	var entry := _entries[index]
	_selected_label.text = "Выбран: %s%s" % [entry.name, _entry_suffix(entry)]
	_selected_label.tooltip_text = entry.path
	workspace._select_workshop_stamp(entry.name)


func _thumbnail(path: String) -> Texture2D:
	var preset := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not preset is Stamp.Preset or preset.geometry == null:
		var image := Image.create(112, 64, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.035, 0.055, 0.075, 0.0))
		return ImageTexture.create_from_image(image)
	return _thumbnail_geometry(preset.geometry)


func _thumbnail_geometry(geometry: EmberVoxelModelResource) -> Texture2D:
	var image := Image.create(112, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.035, 0.055, 0.075, 0.0))
	if geometry == null:
		return ImageTexture.create_from_image(image)
	var size := geometry.grid_size()
	var side_view := (
		geometry.tags.has("tree") or geometry.tags.has("bush") or geometry.tags.has("grass")
	)
	var columns := {}
	var low := Vector2i(size.x, size.y if side_view else size.z)
	var high := Vector2i.ZERO
	for index in geometry.voxels.size():
		var color_index := int(geometry.voxels[index])
		if color_index == 0:
			continue
		var cell := Vector3i(index % size.x, index / (size.x * size.z), (index / size.x) % size.z)
		var key := (
			Vector2i(cell.x, size.y - 1 - cell.y)
			if side_view
			else Vector2i(cell.x, cell.z)
		)
		var depth := cell.z if side_view else cell.y
		if not columns.has(key) or depth >= int(columns[key].depth):
			var color := geometry.palette[color_index] if color_index < geometry.palette.size() else Color.WHITE
			columns[key] = {"depth":depth, "color":color}
		low = low.min(key)
		high = high.max(key)
	if columns.is_empty():
		return ImageTexture.create_from_image(image)
	var span := high - low + Vector2i.ONE
	var cell_size := clampi(mini(int(104.0 / float(maxi(1, span.x))), int(56.0 / float(maxi(1, span.y)))), 2, 8)
	var drawing_size := Vector2i(span.x * cell_size, span.y * cell_size)
	var origin := Vector2i((image.get_width() - drawing_size.x) / 2, (image.get_height() - drawing_size.y) / 2)
	for key: Vector2i in columns:
		var entry: Dictionary = columns[key]
		var depth_size := size.z if side_view else size.y
		var shade := clampf(float(entry.depth) / float(maxi(1, depth_size - 1)) * 0.28, 0.0, 0.28)
		var color: Color = entry.color.lightened(shade)
		color.a = 1.0
		var point := origin + (key - low) * cell_size
		_paint_rect(image, Rect2i(point, Vector2i(cell_size, cell_size)), color.darkened(0.28))
		if cell_size > 2:
			_paint_rect(image, Rect2i(point + Vector2i.ONE, Vector2i(cell_size - 2, cell_size - 2)), color)
	return ImageTexture.create_from_image(image)


func _thumbnail_variant_set(variants: Array[EmberVoxelModelResource]) -> Texture2D:
	if variants.is_empty():
		return _thumbnail_geometry(null)
	var image := Image.create(224, 96, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.035, 0.055, 0.075, 0.0))
	var columns := mini(variants.size(), 4)
	var rows := ceili(float(variants.size()) / float(columns))
	var tile_size := Vector2i(image.get_width() / columns, image.get_height() / rows)
	for index in variants.size():
		var tile := _thumbnail_geometry(variants[index]).get_image()
		var draw_size := Vector2i(maxi(8, tile_size.x - 4), maxi(8, tile_size.y - 4))
		tile.resize(draw_size.x, draw_size.y, Image.INTERPOLATE_NEAREST)
		var column := index % columns
		var row := floori(float(index) / float(columns))
		var position := Vector2i(column * tile_size.x + 2, row * tile_size.y + 2)
		image.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), position)
	return ImageTexture.create_from_image(image)


func _entry_kind_label(entry: Dictionary) -> String:
	if entry.kind == Stamp.Preset.KIND_PATTERN:
		return "Паттерн %s · глубина %d" % [entry.pattern_size, entry.pattern_depth]
	if entry.kind == Stamp.Preset.KIND_GENERATED_VOLUME:
		return "%s · %d форм" % [
			_generated_kind_name(entry.get("generator_id", ""), 0),
			int(entry.get("variant_count", 1)),
		]
	return "Объёмный штамп"


func _entry_caption(entry: Dictionary) -> String:
	if entry.kind == Stamp.Preset.KIND_PATTERN:
		return "Паттерн · %d vox" % entry.pattern_depth
	if entry.kind == Stamp.Preset.KIND_GENERATED_VOLUME:
		return "%s ×%d · %d vox/block" % [
			_generated_kind_name(entry.get("generator_id", ""), 1),
			int(entry.get("variant_count", 1)),
			entry.density,
		]
	return "%d vox/block" % entry.density


func _entry_suffix(entry: Dictionary) -> String:
	if entry.kind == Stamp.Preset.KIND_PATTERN:
		return " · паттерн"
	if entry.kind == Stamp.Preset.KIND_GENERATED_VOLUME:
		return " · процедурное %s ×%d" % [
			_generated_kind_name(entry.get("generator_id", ""), 2),
			int(entry.get("variant_count", 1)),
		]
	return ""


func _generated_kind_name(generator_id: String, form: int) -> String:
	match generator_id:
		Generator.TREE:
			return ["Процедурное дерево", "Дерево", "дерево"][form]
		Generator.BUSH:
			return ["Процедурный куст", "Куст", "куст"][form]
		Generator.GRASS:
			return ["Процедурная трава", "Трава", "трава"][form]
	return ["Процедурный камень", "Камень", "камень"][form]


func _paint_rect(image: Image, rect: Rect2i, color: Color) -> void:
	var clipped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			image.set_pixel(x, y, color)

func _save() -> void:
	workspace._finish_palette_gesture()
	workspace._finish_stroke()
	if workspace._resource == null or workspace._selection_panel.busy() or workspace._selection_interaction.transforming:
		workspace._set_status("Сначала завершите текущую операцию и выделите воксели.",true)
		return
	var result := Stamp.capture(workspace._resource,workspace._selection_panel.selection_indices(),_title.text)
	if not result.has("error"):
		result = Stamp.save_new(result.preset,directory,sources)
	if result.has("error"):
		workspace._set_status(result.error,true)
		return
	refresh_library(result.path)
	_set_create_expanded(false)
	workspace._set_status("Штамп сохранён в библиотеку. Исходный объект не изменён.")
	if Engine.is_editor_hint():
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()

func _place() -> void:
	workspace._finish_palette_gesture()
	workspace._finish_stroke()
	if workspace._resource == null or _entries.is_empty() or workspace._selection_panel.busy():
		return
	if workspace._groups_panel.isolation_enabled() or not workspace._hidden_group_indices.is_empty():
		workspace._set_status("Для штампа отключите изоляцию и скрытие групп. Маска выделения сохранится, но временно не действует; защита групп остаётся.",true)
		return
	if workspace._selection_interaction.transforming:
		workspace._set_status("Сначала примените или отмените текущий отпечаток/перенос.",true)
		return
	var preset := ResourceLoader.load(_entries[_library.selected].path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not preset is Stamp.Preset:
		workspace._set_status("Пресет не загрузился. Обновите библиотеку.",true)
		return
	workspace._selection_interaction.begin_stamp(preset)

func _edit() -> void:
	if _entries.is_empty() or workspace._selection_interaction.transforming:
		workspace._set_status("Сначала завершите отпечаток/перенос и выберите штамп.",true)
		return
	var preset := ResourceLoader.load(_entries[_library.selected].path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if preset is Stamp.Preset and preset.kind == Stamp.Preset.KIND_PATTERN:
		_editing_path = _entries[_library.selected].path
		_title.text = preset.display_name
		_pattern_width.value = preset.pattern_size.x
		_pattern_height.value = preset.pattern_size.y
		_pattern_depth.value = preset.pattern_depth
		_pattern_density.select(1 if preset.geometry.normalized_density() == 32 else 0)
		_pattern_editor.set_pattern_size(preset.pattern_size)
		_pattern_editor.set_mask(Pattern.mask_from_preset(preset))
		_select_create_kind(1)
		_editing_kind = 1
		for index in _create_kind_buttons.size():
			_create_kind_buttons[index].disabled = index != _editing_kind
		_set_create_expanded(true)
		workspace._set_status("Редактирование паттерна · сохранение обновит выбранную карточку")
	elif (
		preset is Stamp.Preset
		and preset.kind == Stamp.Preset.KIND_GENERATED_VOLUME
		and Generator.validation_errors(preset.generator_recipe).is_empty()
		and preset.generator_recipe.generator_id == Generator.ROCK
	):
		_editing_path = _entries[_library.selected].path
		_title.text = preset.display_name
		var settings := Generator.normalized_parameters(
			preset.generator_recipe.generator_id, preset.generator_recipe.parameters
		)
		var dimensions: Vector3i = settings.dimensions
		_rock_width.set_value_no_signal(dimensions.x)
		_rock_height.set_value_no_signal(dimensions.y)
		_rock_depth.set_value_no_signal(dimensions.z)
		_rock_roughness.set_value_no_signal(int(settings.roughness))
		_rock_chips.set_value_no_signal(int(settings.chips))
		_rock_variant_count.set_value_no_signal(int(settings.get("variant_count", 1)))
		_rock_size_variation.set_value_no_signal(int(settings.get("size_variation", 0)))
		_rock_density.select(1 if int(settings.density) == 32 else 0)
		_rock_seed = maxi(0, int(preset.generator_recipe.seed))
		_rock_color_override = (
			preset.geometry.palette[1]
			if preset.geometry != null and preset.geometry.palette.size() > 1
			else Color(0.42, 0.46, 0.50)
		)
		_rock_material_override = preset.geometry.material.duplicate(true)
		_select_create_kind(2)
		_editing_kind = 2
		for index in _create_kind_buttons.size():
			_create_kind_buttons[index].disabled = index != _editing_kind
		_set_create_expanded(true)
		_refresh_rock_preview()
		workspace._set_status(
			"Редактирование рецепта камня · сохранение обновит будущие отпечатки"
		)
	elif (
		preset is Stamp.Preset
		and preset.kind == Stamp.Preset.KIND_GENERATED_VOLUME
		and Generator.validation_errors(preset.generator_recipe).is_empty()
		and preset.generator_recipe.generator_id == Generator.TREE
	):
		_editing_path = _entries[_library.selected].path
		_title.text = preset.display_name
		var settings := Generator.normalized_parameters(
			preset.generator_recipe.generator_id, preset.generator_recipe.parameters
		)
		_tree_height.set_value_no_signal(int(settings.height))
		_tree_trunk_width.set_value_no_signal(int(settings.trunk_width))
		_tree_crown_radius.set_value_no_signal(int(settings.crown_radius))
		_tree_branchiness.set_value_no_signal(int(settings.branchiness))
		_tree_crown_roughness.set_value_no_signal(int(settings.crown_roughness))
		_tree_trunk_color.color = settings.trunk_color
		_tree_foliage_color.color = settings.foliage_color
		_tree_variant_count.set_value_no_signal(int(settings.get("variant_count", 1)))
		_tree_size_variation.set_value_no_signal(int(settings.get("size_variation", 0)))
		_tree_density.select(1 if int(settings.density) == 32 else 0)
		_tree_seed = maxi(0, int(preset.generator_recipe.seed))
		_tree_material_override = preset.geometry.material.duplicate(true)
		_select_create_kind(3)
		_editing_kind = 3
		for index in _create_kind_buttons.size():
			_create_kind_buttons[index].disabled = index != _editing_kind
		_set_create_expanded(true)
		_refresh_tree_preview()
		workspace._set_status(
			"Редактирование рецепта дерева · сохранение обновит будущие отпечатки"
		)
	elif (
		preset is Stamp.Preset
		and preset.kind == Stamp.Preset.KIND_GENERATED_VOLUME
		and Generator.validation_errors(preset.generator_recipe).is_empty()
		and preset.generator_recipe.generator_id == Generator.BUSH
	):
		_editing_path = _entries[_library.selected].path
		_title.text = preset.display_name
		var settings := Generator.normalized_parameters(
			preset.generator_recipe.generator_id, preset.generator_recipe.parameters
		)
		_bush_height.set_value_no_signal(int(settings.height))
		_bush_spread_radius.set_value_no_signal(int(settings.spread_radius))
		_bush_stem_count.set_value_no_signal(int(settings.stem_count))
		_bush_foliage_density.set_value_no_signal(int(settings.foliage_density))
		_bush_roughness.set_value_no_signal(int(settings.roughness))
		_bush_stem_color.color = settings.stem_color
		_bush_foliage_color.color = settings.foliage_color
		_bush_variant_count.set_value_no_signal(int(settings.get("variant_count", 1)))
		_bush_size_variation.set_value_no_signal(int(settings.get("size_variation", 0)))
		_bush_density.select(1 if int(settings.density) == 32 else 0)
		_bush_seed = maxi(0, int(preset.generator_recipe.seed))
		_bush_material_override = preset.geometry.material.duplicate(true)
		_select_create_kind(4)
		_editing_kind = 4
		for index in _create_kind_buttons.size():
			_create_kind_buttons[index].disabled = index != _editing_kind
		_set_create_expanded(true)
		_refresh_bush_preview()
		workspace._set_status(
			"Редактирование рецепта куста · сохранение обновит будущие отпечатки"
		)
	elif (
		preset is Stamp.Preset
		and preset.kind == Stamp.Preset.KIND_GENERATED_VOLUME
		and Generator.validation_errors(preset.generator_recipe).is_empty()
		and preset.generator_recipe.generator_id == Generator.GRASS
	):
		_editing_path = _entries[_library.selected].path
		_title.text = preset.display_name
		var settings := Generator.normalized_parameters(
			preset.generator_recipe.generator_id, preset.generator_recipe.parameters
		)
		_grass_height.set_value_no_signal(int(settings.height))
		_grass_spread_radius.set_value_no_signal(int(settings.spread_radius))
		_grass_blade_count.set_value_no_signal(int(settings.blade_count))
		_grass_height_variation.set_value_no_signal(int(settings.height_variation))
		_grass_lean.set_value_no_signal(int(settings.lean))
		_grass_base_color.color = settings.base_color
		_grass_tip_color.color = settings.tip_color
		_grass_variant_count.set_value_no_signal(int(settings.get("variant_count", 1)))
		_grass_size_variation.set_value_no_signal(int(settings.get("size_variation", 0)))
		_grass_density.select(1 if int(settings.density) == 32 else 0)
		_grass_seed = maxi(0, int(preset.generator_recipe.seed))
		_grass_material_override = preset.geometry.material.duplicate(true)
		_select_create_kind(5)
		_editing_kind = 5
		for index in _create_kind_buttons.size():
			_create_kind_buttons[index].disabled = index != _editing_kind
		_set_create_expanded(true)
		_refresh_grass_preview()
		workspace._set_status(
			"Редактирование рецепта травы · сохранение обновит будущие отпечатки"
		)
	elif preset is Stamp.Preset and preset.geometry != null:
		workspace.open_surface(preset.geometry,preset.geometry.resource_path)
