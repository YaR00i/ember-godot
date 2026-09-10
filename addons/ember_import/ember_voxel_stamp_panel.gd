@tool
extends VBoxContainer
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
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
var _card_scroll: ScrollContainer
var _library_actions: HBoxContainer

func setup(owner_workspace: Control) -> void:
	workspace = owner_workspace
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 7)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 5)
	add_child(toolbar)
	var heading := Label.new()
	heading.text = "ОБЪЁМНЫЕ ШТАМПЫ"
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
	_create_toggle.text = "+ Новый штамп"
	_create_toggle.tooltip_text = "Сохранить текущее выделение как новый штамп"
	_create_toggle.theme_type_variation = &"WorkshopToolButton"
	_create_toggle.icon = _editor_icon(&"Add")
	_create_toggle.toggle_mode = true
	_create_toggle.toggled.connect(_set_create_expanded)
	add_child(_create_toggle)
	_create_panel = VBoxContainer.new()
	_create_panel.name = "VoxelWorkshopCreateStampPanel"
	_create_panel.add_theme_constant_override("separation", 5)
	add_child(_create_panel)
	var capture_hint := Label.new()
	capture_hint.text = "Сохранить текущее выделение в библиотеку"
	capture_hint.modulate = Color(0.54, 0.64, 0.74)
	_create_panel.add_child(capture_hint)
	_title = LineEdit.new()
	_title.placeholder_text = "Название штампа"
	_create_panel.add_child(_title)
	var save := Button.new()
	save.text = "Сохранить как штамп"
	save.clip_text = true
	save.theme_type_variation = &"WorkshopPrimaryButton"
	save.pressed.connect(_save)
	_create_panel.add_child(save)
	_create_panel.hide()
	_library = OptionButton.new()
	_library.fit_to_longest_item = false
	_library.clip_text = true
	_library.hide()
	add_child(_library)
	add_child(HSeparator.new())
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
	_empty_label.text = "Библиотека пуста. Выделите фрагмент на Canvas и нажмите «Новый штамп»."
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
	_place_button.text = "Разместить"
	_place_button.tooltip_text = "Перейти к размещению выбранного штампа на Canvas"
	_place_button.theme_type_variation = &"WorkshopPrimaryButton"
	_place_button.icon = _editor_icon(&"Play")
	_place_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_button.pressed.connect(_place)
	_library_actions.add_child(_place_button)
	_edit_button = Button.new()
	_edit_button.text = "Редактировать"
	_edit_button.tooltip_text = "Открыть геометрию выбранного штампа в этом Canvas"
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
	_create_toggle.text = "− Скрыть создание" if expanded else "+ Новый штамп"
	if expanded:
		_title.grab_focus()

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
		preview.tooltip_text = "%s · %d vox/block" % [entry.name, entry.density]
		preview.pressed.connect(_select_entry.bind(index))
		card.add_child(preview)
		_card_buttons.append(preview)
		var caption := Button.new()
		caption.flat = true
		caption.custom_minimum_size = Vector2(132.0, 42.0)
		caption.text = "%s\n%d vox/block" % [entry.name, entry.density]
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
	_selected_label.text = "Выбран: %s" % entry.name
	_selected_label.tooltip_text = entry.path
	workspace._select_workshop_stamp(entry.name)


func _thumbnail(path: String) -> Texture2D:
	var image := Image.create(112, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.035, 0.055, 0.075, 0.0))
	var preset := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not preset is Stamp.Preset or preset.geometry == null:
		return ImageTexture.create_from_image(image)
	var geometry: EmberVoxelModelResource = preset.geometry
	var size := geometry.grid_size()
	var columns := {}
	var low := Vector2i(size.x, size.z)
	var high := Vector2i.ZERO
	for index in geometry.voxels.size():
		var color_index := int(geometry.voxels[index])
		if color_index == 0:
			continue
		var cell := Vector3i(index % size.x, index / (size.x * size.z), (index / size.x) % size.z)
		var key := Vector2i(cell.x, cell.z)
		if not columns.has(key) or cell.y >= int(columns[key].height):
			var color := geometry.palette[color_index] if color_index < geometry.palette.size() else Color.WHITE
			columns[key] = {"height":cell.y, "color":color}
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
		var shade := clampf(float(entry.height) / float(maxi(1, size.y - 1)) * 0.28, 0.0, 0.28)
		var color: Color = entry.color.lightened(shade)
		color.a = 1.0
		var point := origin + (key - low) * cell_size
		_paint_rect(image, Rect2i(point, Vector2i(cell_size, cell_size)), color.darkened(0.28))
		if cell_size > 2:
			_paint_rect(image, Rect2i(point + Vector2i.ONE, Vector2i(cell_size - 2, cell_size - 2)), color)
	return ImageTexture.create_from_image(image)


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
		EditorInterface.get_resource_filesystem().scan()

func _place() -> void:
	workspace._finish_palette_gesture()
	workspace._finish_stroke()
	if workspace._resource == null or _entries.is_empty() or workspace._selection_panel.busy():
		return
	if workspace._selection_panel._mask.button_pressed or workspace._groups_panel.isolation_enabled() or not workspace._hidden_group_indices.is_empty():
		workspace._set_status("Для штампа отключите маску выделения, изоляцию и скрытие групп. Защита групп остаётся действующей.",true)
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
	if preset is Stamp.Preset and preset.geometry != null:
		workspace.open_surface(preset.geometry,preset.geometry.resource_path)
