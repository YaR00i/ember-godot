@tool
class_name EmberCompactMaterialPatternDialog
extends ConfirmationDialog
## Uses the existing Surface Canvas pattern grid; writes only on Save.

signal pattern_saved(pattern: Resource, id: String)
signal pattern_created(id: String, role: String)

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
var _name_dialog: ConfirmationDialog
var _name_input: LineEdit
var _file_dialog: FileDialog
var _file_import := false


func _init() -> void:
	title = "Паттерн материала земли"
	size = Vector2i(580, 750)
	dialog_hide_on_ok = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_history):
		_history.clear_history()
		_history.free()


func _ready() -> void:
	get_ok_button().text = "Сохранить"
	get_cancel_button().text = "Отмена"
	confirmed.connect(_save)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	add_child(column)
	var hint := Label.new()
	hint.text = "Рисуйте протяжкой · правая кнопка берёт тон с клетки"
	column.add_child(hint)
	var tones_row := HBoxContainer.new()
	column.add_child(tones_row)
	for tone_index in 3:
		var tone_column := VBoxContainer.new()
		tones_row.add_child(tone_column)
		var label := Label.new()
		label.text = ["Основной", "Светлый", "Тёмный"][tone_index]
		tone_column.add_child(label)
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(105, 28)
		picker.edit_alpha = false
		picker.color_changed.connect(_change_tone.bind(tone_index))
		tone_column.add_child(picker)
		_tones.append(picker)
	var finish_title := Label.new()
	finish_title.text = "Поверхность · рисунок и цвета сохраняются"
	column.add_child(finish_title)
	for setting in [["gloss", "Глянец", 1.0], ["sheen", "Сила блика", 1.0], ["pixel_relief", "Рельеф пикселей", 0.3]]:
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := Label.new()
		label.text = setting[1]
		label.custom_minimum_size.x = 140
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = setting[2]
		slider.step = 0.01
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(_change_finish.bind(setting[0]))
		row.add_child(slider)
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 44
		row.add_child(value_label)
		_finish_sliders[setting[0]] = slider
		_finish_values[setting[0]] = value_label
	var tools_row := HBoxContainer.new()
	column.add_child(tools_row)
	_face_choice = OptionButton.new()
	_face_choice.add_item("Верх")
	_face_choice.add_item("Боковые грани")
	_face_choice.tooltip_text = "Отдельные рисунки в одном материале. Пока бока не нарисованы, они повторяют верх."
	_face_choice.item_selected.connect(_select_face)
	tools_row.add_child(_face_choice)
	_ink_choice = OptionButton.new()
	for label in ["Основной", "Светлый", "Тёмный"]: _ink_choice.add_item(label)
	_ink_choice.item_selected.connect(func(index: int): _grid.current_tone = index)
	tools_row.add_child(_ink_choice)
	for config in [["Отменить", true], ["Повторить", false]]:
		var action := Button.new()
		action.text = config[0]
		action.pressed.connect(undo_edit if config[1] else redo_edit)
		tools_row.add_child(action)
	_grid = PatternGrid.new()
	_grid.custom_minimum_size = Vector2(390, 390)
	_grid.pattern_changed.connect(_on_grid_changed)
	_grid.stroke_started.connect(_begin_stroke)
	_grid.stroke_finished.connect(_finish_stroke)
	_grid.tone_picked.connect(_pick_tone)
	column.add_child(_grid)
	var file_row := HBoxContainer.new()
	column.add_child(file_row)
	for config in [["Сохранить как новый…", _show_new_variant], ["Экспорт PNG…", _show_export], ["Импорт PNG…", _show_import]]:
		var button := Button.new()
		button.text = config[0]
		button.pressed.connect(config[1])
		file_row.add_child(button)
	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(440, 45)
	column.add_child(_message)
	_name_dialog = ConfirmationDialog.new()
	_name_dialog.title = "Новый вариант материала"
	_name_dialog.confirmed.connect(_create_variant)
	add_child(_name_dialog)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Например, grass_autumn"
	_name_dialog.add_child(_name_input)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.add_filter("*.png", "PNG 16×16")
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)


func open_role(role: String) -> bool:
	return open_variant(role, role)


func open_variant(id: String, role: String) -> bool:
	var path := pattern_path_override if not pattern_path_override.is_empty() else Materials.variant_path(id)
	if path.is_empty(): return false
	var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Pattern
	if source == null or source.role_id != role or not source.validation_errors().is_empty(): return false
	_id = id
	_opened_hash = FileAccess.get_sha256(path)
	_draft = source.duplicate(true) as Pattern
	_editing_side = false
	_face_choice.select(0)
	_history.clear_history()
	_loading = true
	for index in 3: _tones[index].color = [_draft.base_color, _draft.light_color, _draft.shadow_color][index]
	for key in _finish_sliders: _set_finish(key, _draft.get(key))
	_loading = false
	_grid.current_tone = 0
	_ink_choice.select(0)
	_refresh_grid()
	title = "%s · %s" % [EmberTerrainPilotResource.surface_role_name(role), id]
	_message.text = "Правка этого варианта изменит все карты, где он выбран. PNG должен содержать только три заданных тона."
	popup_centered(Vector2i(590, 780))
	return true


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
	_grid.set_tones(_draft.face_pixels(_editing_side), [_draft.base_color, _draft.light_color, _draft.shadow_color])


func _on_grid_changed() -> void:
	if _draft != null and _grid.tone_mode:
		if _editing_side: _draft.side_pixels = _grid.tones()
		else: _draft.pixels = _grid.tones()


func _begin_stroke() -> void:
	if _draft != null:
		_stroke_side = _editing_side
		_stroke_before = (_draft.side_pixels if _stroke_side else _draft.pixels).duplicate()


func _finish_stroke() -> void:
	if _draft == null: return
	var after := (_draft.side_pixels if _stroke_side else _draft.pixels).duplicate()
	if _stroke_before == after: return
	var before := _stroke_before.duplicate()
	_history.create_action("Штрих паттерна")
	_history.add_do_method(Callable(self, "_set_pixels").bind(after, _stroke_side))
	_history.add_undo_method(Callable(self, "_set_pixels").bind(before, _stroke_side))
	_history.commit_action()


func _set_pixels(value: PackedByteArray, side := false) -> void:
	if side: _draft.side_pixels = value.duplicate()
	else: _draft.pixels = value.duplicate()
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
	(_finish_values[key] as Label).text = "%d%%" % roundi(value / (0.3 if key == "pixel_relief" else 1.0) * 100.0)
	_loading = false


func _show_new_variant() -> void:
	_name_input.text = "%s_new" % _id
	_name_dialog.popup_centered(Vector2i(350, 100))


func _create_variant() -> void:
	var id := _name_input.text.strip_edges()
	var path := _variant_path(id)
	if path.is_empty() or FileAccess.file_exists(path):
		_message.text = "Название: буквы, цифры и _. Оно не должно повторять существующее."
		return
	if ResourceSaver.save(_draft.duplicate(true), path) != OK:
		_message.text = "Не удалось сохранить новый вариант."
		return
	pattern_created.emit(id, _draft.role_id)
	hide()


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
		var image := _draft.to_image(_editing_side)
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
	var colors := [_draft.base_color, _draft.light_color, _draft.shadow_color]
	for index in 3:
		palette_image.set_pixel(index, 0, colors[index])
		tones.append(palette_image.get_pixel(index, 0).to_html(false))
	for y in 16:
		for x in 16:
			var color := image.get_pixel(x, y)
			var tone := tones.find(color.to_html(false)) if is_equal_approx(color.a, 1.0) else -1
			if tone < 0:
				_message.text = "В PNG есть цвет вне трёх тонов. Задайте тона здесь и повторите импорт."
				return
			next.append(tone)
	var before := (_draft.side_pixels if _editing_side else _draft.pixels).duplicate()
	_history.create_action("Импорт PNG")
	_history.add_do_method(Callable(self, "_set_pixels").bind(next, _editing_side))
	_history.add_undo_method(Callable(self, "_set_pixels").bind(before, _editing_side))
	_history.commit_action()
	_message.text = "PNG загружен в черновик. Нажмите «Сохранить», чтобы применить."


func _save() -> void:
	if _draft == null: return
	var errors := _draft.validation_errors()
	if not errors.is_empty():
		_message.text = errors[0]
		return
	var path := pattern_path_override if not pattern_path_override.is_empty() else Materials.variant_path(_id)
	if FileAccess.get_sha256(path) != _opened_hash:
		_message.text = "Файл изменился после открытия. Закройте окно и откройте его заново."
		return
	if ResourceSaver.save(_draft, path) != OK:
		_message.text = "Не удалось сохранить паттерн."
		return
	pattern_saved.emit(_draft, _id)
	hide()
