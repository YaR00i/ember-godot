@tool
class_name EmberCompactMaterialPatternDialog
extends VBoxContainer
## Uses the existing Surface Canvas pattern grid; writes only on Save.

signal pattern_saved(pattern: Resource, id: String)
signal pattern_created(id: String, role: String)
signal edit_closed
signal variant_opened(id: String, role: String)
const EDIT_FIELDS := ["role_id", "base_color", "light_color", "shadow_color", "pixels", "side_pixels", "gloss", "sheen", "pixel_relief", "micro_relief", "micro_size_m", "micro_roughness", "relief_pixels", "side_relief_pixels", "roughness_pixels", "side_roughness_pixels", "pattern_size_m", "roughness_variation"]

const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const Pattern = preload("res://scripts/ember_compact_terrain_pattern.gd")
const PatternGrid = preload("res://addons/ember_import/ember_voxel_pattern_editor.gd")

var _draft: Pattern
var _history := UndoRedo.new()
var _grid: Control
var _tones: Array[ColorPickerButton] = []
var _finish_sliders: Dictionary = {}
var _finish_values: Dictionary = {}
var _ink_choice: OptionButton
var _channel_choice: OptionButton
var _channel := "color"
var _stroke_channel := "color"
var _face_choice: OptionButton
var _editing_side := false
var _stroke_side := false
var _message: Label
var _loading := false
var _id := ""
var _opened_hash := ""
var _stroke_before := PackedByteArray()
var pattern_path_override := "" # Test fixture.
var variant_directory_override := "" # Test fixture.
var parameters_panel: VBoxContainer
var _title: Label
var _canvas_title: Label
var _parameter_scroll: ScrollContainer
var _variant_choice: OptionButton
var _choices: Array[Dictionary] = []
var _switch_box: VBoxContainer
var _pending_variant := {}
var _baseline := {}
var _opened_path := ""
var _new_variant_box: VBoxContainer
var _save_button: Button
var _zoom: SpinBox
var _canvas_scroll: ScrollContainer
var _name_input: LineEdit
var _file_dialog: FileDialog
var _file_import := false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_history):
		_history.clear_history()
		_history.free()
	if what == NOTIFICATION_PREDELETE and is_instance_valid(parameters_panel): parameters_panel.free()


func _ready() -> void:
	parameters_panel = VBoxContainer.new(); parameters_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_title = Label.new(); _title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parameters_panel.add_child(_title)
	_parameter_scroll = ScrollContainer.new(); _parameter_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_parameter_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; parameters_panel.add_child(_parameter_scroll)
	var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _parameter_scroll.add_child(column)
	_variant_choice = OptionButton.new(); _variant_choice.clip_text = true
	_variant_choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_variant_choice.item_selected.connect(func(index): open_variant(_choices[index].id, _choices[index].role))
	column.add_child(_variant_choice); _variant_choice.hide()
	var hint := Label.new(); hint.text = "Общий вариант: сохранение изменит все карты, где он выбран."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(hint)
	for tone_index in 3:
		var label := Label.new(); label.text = ["Основной", "Светлый", "Тёмный"][tone_index]; column.add_child(label)
		var picker := ColorPickerButton.new(); picker.custom_minimum_size.y = 28
		picker.edit_alpha = false; picker.color_changed.connect(_change_tone.bind(tone_index)); column.add_child(picker); _tones.append(picker)
	for setting in [["gloss", "Глянец", 1.0, 0.0], ["sheen", "Сила блика", 1.0, 0.0], ["pixel_relief", "Рельеф рисунка", 0.3, 0.0],
		["micro_relief", "Сила мелкой фактуры", 0.3, 0.0], ["micro_size_m", "Размер фактуры · м", 1.0, 0.03], ["micro_roughness", "Неоднородность мелкого блика", 0.5, 0.0], ["pattern_size_m", "Размер рисунка · м", 16.0, 0.125], ["roughness_variation", "Сила рисунка матовости", 0.5, 0.0]]:
		var label := Label.new(); label.text = setting[1]; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(label)
		var row := HBoxContainer.new(); column.add_child(row)
		var slider := HSlider.new(); slider.min_value = setting[3]; slider.max_value = setting[2]; slider.step = 0.025 if setting[0]=="pattern_size_m" else 0.01
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL; slider.value_changed.connect(_change_finish.bind(setting[0])); row.add_child(slider)
		var value_label := Label.new(); value_label.custom_minimum_size.x = 44; row.add_child(value_label)
		_finish_sliders[setting[0]] = slider; _finish_values[setting[0]] = value_label
	_channel_choice=OptionButton.new()
	for caption in ["Цвет","Световой рельеф","Матовость"]: _channel_choice.add_item(caption)
	_channel_choice.item_selected.connect(_select_channel); column.add_child(_channel_choice)
	_face_choice = OptionButton.new(); _face_choice.add_item("Верх"); _face_choice.add_item("Боковые грани")
	_face_choice.tooltip_text = "Пока бока не нарисованы, они повторяют верх."
	_face_choice.item_selected.connect(_select_face); column.add_child(_face_choice)
	_ink_choice = OptionButton.new()
	for label in ["Основной", "Светлый", "Тёмный"]: _ink_choice.add_item(label)
	_ink_choice.item_selected.connect(func(index): _grid.current_tone = index); column.add_child(_ink_choice)
	var history_row := HBoxContainer.new(); column.add_child(history_row)
	for config in [["Отменить", true], ["Повторить", false]]:
		var action := Button.new(); action.text = config[0]; action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.pressed.connect(undo_edit if config[1] else redo_edit); history_row.add_child(action)
	var canvas_header := HBoxContainer.new(); add_child(canvas_header)
	_canvas_title = Label.new(); _canvas_title.text = "Рисунок материала · 16×16"; _canvas_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; canvas_header.add_child(_canvas_title)
	var zoom_label := Label.new(); zoom_label.text = "Масштаб"; canvas_header.add_child(zoom_label)
	_zoom = SpinBox.new(); _zoom.min_value = 100; _zoom.max_value = 200; _zoom.step = 25; _zoom.value = 100; _zoom.suffix = "%"; canvas_header.add_child(_zoom)
	var canvas_scroll := ScrollContainer.new(); _canvas_scroll = canvas_scroll
	canvas_scroll.custom_minimum_size.y = 280
	canvas_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL; add_child(canvas_scroll)
	var center := CenterContainer.new(); center.size_flags_horizontal = Control.SIZE_EXPAND_FILL; center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_scroll.add_child(center)
	_grid = PatternGrid.new(); _grid.custom_minimum_size = Vector2(256, 256); _grid.focus_mode = Control.FOCUS_ALL
	_grid.pattern_changed.connect(_on_grid_changed); _grid.stroke_started.connect(_begin_stroke)
	_grid.stroke_finished.connect(_finish_stroke); _grid.tone_picked.connect(_pick_tone); center.add_child(_grid)
	_grid.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: _grid.grab_focus()
	)
	_zoom.value_changed.connect(func(value): _grid.custom_minimum_size = Vector2.ONE * (256.0 * value / 100.0))
	var canvas_hint := Label.new(); canvas_hint.text = "ЛКМ — рисовать · ПКМ — взять тон · Ctrl+Z / Ctrl+Y — история рисунка"
	canvas_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(canvas_hint)
	for config in [["Новый вариант…", _show_new_variant], ["Экспорт PNG…", _show_export], ["Импорт PNG…", _show_import]]:
		var button := Button.new(); button.text = config[0]; button.pressed.connect(config[1]); column.add_child(button)
	_new_variant_box = VBoxContainer.new(); column.add_child(_new_variant_box); _new_variant_box.hide()
	_name_input = LineEdit.new(); _name_input.placeholder_text = "Имя: grass_autumn"; _new_variant_box.add_child(_name_input)
	var create := Button.new(); create.text = "Создать вариант"; create.pressed.connect(_create_variant); _new_variant_box.add_child(create)
	_switch_box = VBoxContainer.new(); parameters_panel.add_child(_switch_box); _switch_box.hide()
	for config in [["Сохранить и перейти", true], ["Отбросить и перейти", false]]:
		var button := Button.new(); button.text = config[0]; button.pressed.connect(_resolve_variant_switch.bind(config[1])); _switch_box.add_child(button)
	var stay := Button.new(); stay.text = "Остаться"; stay.pressed.connect(func(): _pending_variant.clear(); _switch_box.hide(); _sync_variant_choice()); _switch_box.add_child(stay)
	_message = Label.new(); _message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parameters_panel.add_child(_message)
	var actions := HBoxContainer.new(); parameters_panel.add_child(actions)
	_save_button = Button.new(); _save_button.text = "Сохранить"; _save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_button.pressed.connect(func(): _save()); actions.add_child(_save_button)
	var cancel := Button.new(); cancel.text = "Отмена"; cancel.pressed.connect(cancel_edit); actions.add_child(cancel)
	_file_dialog = FileDialog.new(); _file_dialog.access = FileDialog.ACCESS_FILESYSTEM; _file_dialog.use_native_dialog = true
	_file_dialog.add_filter("*.png", "PNG 16×16"); _file_dialog.file_selected.connect(_on_file_selected); add_child(_file_dialog)
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if _draft == null or not event is InputEventKey or not event.pressed or event.echo: return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit: return
	if focused == _grid or (is_instance_valid(focused) and parameters_panel.is_ancestor_of(focused)):
		if handle_history_key(event): get_viewport().set_input_as_handled()

func handle_history_key(event: InputEventKey) -> bool:
	if event.is_command_or_control_pressed() and event.keycode in [KEY_Z, KEY_Y]:
		if event.keycode == KEY_Y or event.shift_pressed: redo_edit()
		else: undo_edit()
		return true
	return false


func open_role(role: String) -> bool:
	return open_variant(role, role)


func set_variant_choices(choices: Array[Dictionary]) -> void:
	_choices = choices.duplicate(true); _variant_choice.clear()
	for choice in _choices: _variant_choice.add_item("%s · %s" % [EmberTerrainPilotResource.surface_role_name(choice.role), choice.id])
	_variant_choice.visible = _choices.size() > 1
	_sync_variant_choice()

func _sync_variant_choice() -> void:
	for index in _choices.size():
		if _choices[index].id == _id: _variant_choice.select(index); break

func is_dirty() -> bool:
	if _draft == null: return false
	for key in EDIT_FIELDS:
		if _draft.get(key) != _baseline.get(key): return true
	return false

func open_variant(id: String, role: String) -> bool:
	var path := pattern_path_override if not pattern_path_override.is_empty() else Materials.variant_path(id)
	var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Pattern if not path.is_empty() else null
	if source == null or source.role_id != role or not source.validation_errors().is_empty():
		_sync_variant_choice(); _message.text = "Выбранный материал не найден или повреждён."; return false
	if _draft != null and _id == id and _opened_path == path:
		show(); _sync_variant_choice(); return true
	if is_dirty():
		_pending_variant = {"id": id, "role": role, "path": path}
		_switch_box.show(); _sync_variant_choice()
		_message.text = "В рисунке есть правки. Выберите, как перейти к %s." % id
		return true
	return _load_variant(id, role, path)

func _load_variant(id: String, role: String, path: String) -> bool:
	var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Pattern
	if source == null or source.role_id != role or not source.validation_errors().is_empty(): return false
	_id = id; _opened_path = path; _opened_hash = FileAccess.get_sha256(path)
	_draft = source.duplicate(true) as Pattern
	_baseline.clear()
	for key in EDIT_FIELDS: _baseline[key] = _draft.get(key).duplicate() if _draft.get(key) is PackedByteArray else _draft.get(key)
	_editing_side = false; _face_choice.select(0); _channel="color"; _channel_choice.select(0); _history.clear_history(); _grid._painting = false
	_loading = true
	for index in 3: _tones[index].color = [_draft.base_color, _draft.light_color, _draft.shadow_color][index]
	for key in _finish_sliders:
		_set_finish(key, _draft.get(key))
		if key.begins_with("micro_"):
			_finish_sliders[key].editable = _draft.role_id in ["grass","soil"]
			_finish_sliders[key].tooltip_text = "Мелкая фактура травы и грунта; цветной рисунок сохраняется." if _finish_sliders[key].editable else "Эта проба фактуры доступна для травы и грунта."
	_loading = false; _grid.current_tone = 0; _ink_choice.select(0); _refresh_grid()
	_title.text = "%s · %s" % [EmberTerrainPilotResource.surface_role_name(role), id]; _canvas_title.text = _title.text + " · 16×16"
	_message.text = "Правки пока в черновике. Сохранение изменит общий вариант."
	_pending_variant.clear(); _switch_box.hide(); _new_variant_box.hide(); _parameter_scroll.scroll_vertical = 0
	show(); _sync_variant_choice(); variant_opened.emit(id, role)
	return true

func _resolve_variant_switch(save_changes: bool) -> void:
	if _pending_variant.is_empty(): return
	var next := _pending_variant.duplicate()
	if save_changes and not _save(true): return
	if not _load_variant(next.id, next.role, next.path): _message.text = "Следующий материал был изменён или удалён. Текущий черновик сохранён в панели."

func cancel_edit() -> void:
	_draft = null; _baseline.clear(); _pending_variant.clear(); _history.clear_history()
	_grid._painting = false; _switch_box.hide(); _new_variant_box.hide(); _file_dialog.hide(); hide()
	edit_closed.emit()


func undo_edit() -> void:
	if _history.has_undo(): _history.undo()


func redo_edit() -> void:
	if _history.has_redo(): _history.redo()


func _select_face(index: int) -> void:
	_face_choice.select(index)
	_editing_side = index == 1
	_refresh_grid()


func _refresh_grid() -> void:
	if _draft == null: return
	_grid.set_tones(_draft.surface_pixels(_channel,_editing_side), _channel_colors())
	for picker in _tones: picker.disabled=_channel!="color"
	_ink_choice.clear()
	var names=["Основной","Светлый","Тёмный"] if _channel=="color" else ["Средний","Выше","Ниже"] if _channel=="relief" else ["Средняя","Матовая","Гладкая"]
	for caption in names: _ink_choice.add_item(caption)
	_ink_choice.select(_grid.current_tone)


func _on_grid_changed() -> void:
	if _draft != null and _grid.tone_mode:
		_draft.set(_art_field(_channel,_editing_side),_grid.tones())


func _begin_stroke() -> void:
	if _draft != null:
		_stroke_side = _editing_side; _stroke_channel=_channel
		_stroke_before = _draft.get(_art_field(_stroke_channel,_stroke_side)).duplicate()


func _finish_stroke() -> void:
	if _draft == null: return
	var after: PackedByteArray = _draft.get(_art_field(_stroke_channel,_stroke_side)).duplicate()
	if _stroke_before == after: return
	var before := _stroke_before.duplicate()
	_history.create_action("Штрих паттерна")
	_history.add_do_method(Callable(self, "_set_pixels").bind(after, _stroke_side, _stroke_channel))
	_history.add_undo_method(Callable(self, "_set_pixels").bind(before, _stroke_side, _stroke_channel))
	_history.commit_action()


func _set_pixels(value: PackedByteArray, side := false, channel := "color") -> void:
	_draft.set(_art_field(channel,side),value.duplicate())
	_refresh_grid()


func _pick_tone(tone: int) -> void:
	_grid.current_tone = tone
	_ink_choice.select(tone)


func _change_tone(color: Color, tone_index: int) -> void:
	if _loading or _draft == null: return
	color.a = 1.0
	var before := _tone(tone_index)
	if before == color: return
	_history.create_action("Тон материала", UndoRedo.MERGE_ENDS)
	_history.add_do_method(Callable(self, "_set_tone").bind(tone_index, color))
	_history.add_undo_method(Callable(self, "_set_tone").bind(tone_index, before))
	_history.commit_action()


func _tone(index: int) -> Color:
	return [_draft.base_color, _draft.light_color, _draft.shadow_color][index]


func _set_tone(index: int, color: Color) -> void:
	match index:
		0: _draft.base_color = color
		1: _draft.light_color = color
		2: _draft.shadow_color = color
	_loading = true
	_tones[index].color = color
	_loading = false
	_refresh_grid()


func _change_finish(value: float, key: String) -> void:
	if _loading or _draft == null: return
	var before := float(_draft.get(key))
	if is_equal_approx(before, value): return
	_history.create_action("Поверхность материала: " + key, UndoRedo.MERGE_ENDS)
	_history.add_do_method(Callable(self, "_set_finish").bind(key, value))
	_history.add_undo_method(Callable(self, "_set_finish").bind(key, before))
	_history.commit_action()


func _set_finish(key: String, value: float) -> void:
	_draft.set(key, value)
	_loading = true
	(_finish_sliders[key] as HSlider).value = value
	(_finish_values[key] as Label).text = "%.2f" % value if key in ["micro_size_m","pattern_size_m"] else "%d%%" % roundi(value / (0.3 if key in ["pixel_relief","micro_relief"] else 0.5 if key in ["micro_roughness","roughness_variation"] else 1.0) * 100.0)
	_loading = false


func _show_new_variant() -> void:
	_name_input.text = "%s_new" % _id
	_new_variant_box.show(); _name_input.grab_focus()


func _create_variant() -> void:
	if _draft == null: return
	var id := _name_input.text.strip_edges()
	var path := _variant_path(id)
	if path.is_empty() or FileAccess.file_exists(path):
		_message.text = "Название: буквы, цифры и _. Оно не должно повторять существующее."
		return
	if ResourceSaver.save(_draft.duplicate(true), path) != OK:
		_message.text = "Не удалось сохранить новый вариант."
		return
	pattern_created.emit(id, _draft.role_id)
	cancel_edit()


func _variant_path(id: String) -> String:
	if not id.is_valid_identifier(): return ""
	return variant_directory_override.path_join(id + ".tres") if not variant_directory_override.is_empty() else Materials.variant_path(id)


func _show_export() -> void:
	_file_import = false
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.current_file = "%s%s.png" % [_id, "_sides" if _editing_side else ""]
	_file_dialog.popup_centered(Vector2i(700, 500))


func _show_import() -> void:
	_file_import = true
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.popup_centered(Vector2i(700, 500))


func _on_file_selected(path: String) -> void:
	if _draft == null: return
	if not _file_import:
		var image := _draft.surface_image(_channel,_editing_side)
		_message.text = "PNG сохранён: %s" % path if image != null and image.save_png(path) == OK else "Не удалось сохранить PNG."
		return
	var image := Image.new()
	if image.load(path) != OK or image.get_size() != Vector2i(16, 16):
		_message.text = "Нужен PNG размером ровно 16×16."
		return
	var next := PackedByteArray()
	# PNG/RGBA8 rounds picker floats. Match the actual exported bytes, not float hex.
	var palette_image := Image.create(3, 1, false, Image.FORMAT_RGBA8)
	var tones: Array[String] = []
	var colors := _channel_colors()
	for index in 3:
		palette_image.set_pixel(index, 0, colors[index])
		tones.append(palette_image.get_pixel(index, 0).to_html(false))
	for y in 16:
		for x in 16:
			var color := image.get_pixel(x, y)
			var tone := tones.find(color.to_html(false)) if is_equal_approx(color.a, 1.0) else -1
			if tone < 0:
				_message.text = "В PNG есть цвет вне трёх тонов выбранного слоя. Цвет использует палитру, рельеф/матовость — серый128, белый и чёрный."
				return
			next.append(tone)
	var before: PackedByteArray = _draft.get(_art_field(_channel,_editing_side)).duplicate()
	_history.create_action("Импорт PNG")
	_history.add_do_method(Callable(self, "_set_pixels").bind(next, _editing_side, _channel))
	_history.add_undo_method(Callable(self, "_set_pixels").bind(before, _editing_side, _channel))
	_history.commit_action()
	_message.text = "PNG загружен в черновик. Нажмите «Сохранить», чтобы применить."


func _save(keep_open := false) -> bool:
	if _draft == null: return false
	if _grid._painting: _grid._painting = false; _finish_stroke()
	var errors := _draft.validation_errors()
	if not errors.is_empty(): _message.text = errors[0]; return false
	if FileAccess.get_sha256(_opened_path) != _opened_hash:
		_message.text = "Файл изменился после открытия. Сохраните правки новым вариантом или отмените и откройте заново."
		return false
	if ResourceSaver.save(_draft, _opened_path) != OK: _message.text = "Не удалось сохранить рисунок."; return false
	_opened_hash = FileAccess.get_sha256(_opened_path)
	_baseline.clear()
	for key in EDIT_FIELDS: _baseline[key] = _draft.get(key).duplicate() if _draft.get(key) is PackedByteArray else _draft.get(key)
	pattern_saved.emit(_draft, _id)
	if not keep_open: cancel_edit()
	return true


func _art_field(channel: String, side: bool) -> String:
	if channel=="color": return "side_pixels" if side else "pixels"
	return ("side_" if side else "")+channel+"_pixels"

func _channel_colors() -> Array:
	return [_draft.base_color,_draft.light_color,_draft.shadow_color] if _channel=="color" else [Color(0.5,0.5,0.5),Color.WHITE,Color.BLACK]

func _select_channel(index: int) -> void:
	if _grid._painting: _grid._painting=false; _finish_stroke()
	_channel=["color","relief","roughness"][clampi(index,0,2)]
	_channel_choice.select(index); _grid.current_tone=0; _refresh_grid()
