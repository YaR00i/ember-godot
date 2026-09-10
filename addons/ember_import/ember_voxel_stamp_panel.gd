@tool
extends VBoxContainer
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
var workspace: Control
var directory := Stamp.DIRECTORY
var sources := "res://content/voxel_models"
var _title: LineEdit
var _library: OptionButton
var _entries: Array[Dictionary] = []

func setup(owner_workspace: Control) -> void:
	workspace = owner_workspace
	var heading := Label.new()
	heading.text = "ОБЪЁМНЫЕ ШТАМПЫ"
	add_child(heading)
	_title = LineEdit.new()
	_title.placeholder_text = "Название штампа"
	add_child(_title)
	var save := Button.new()
	save.text = "Сохранить выделение как штамп"
	save.clip_text = true
	save.pressed.connect(_save)
	add_child(save)
	_library = OptionButton.new()
	_library.fit_to_longest_item = false
	_library.clip_text = true
	add_child(_library)
	var refresh := Button.new()
	refresh.text = "Обновить библиотеку"
	refresh.pressed.connect(refresh_library)
	add_child(refresh)
	var place := Button.new()
	place.text = "Разместить штамп…"
	place.pressed.connect(_place)
	add_child(place)
	var edit := Button.new()
	edit.text = "Редактировать модель штампа…"
	edit.pressed.connect(_edit)
	add_child(edit)
	refresh_library()

func refresh_library(preferred := "") -> void:
	_entries = Stamp.library(directory)
	_library.clear()
	for entry in _entries:
		_library.add_item("%s · %d vox/block" % [entry.name,entry.density])
		if entry.path == preferred:
			_library.select(_library.item_count-1)
	if _entries.is_empty():
		_library.add_item("Пока нет штампов")
	_library.disabled = _entries.is_empty()

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
