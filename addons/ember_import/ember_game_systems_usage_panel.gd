@tool
extends ConfirmationDialog
## Read-only incoming references; workspace owns navigation and dirty guards.
signal record_requested(source: Dictionary)
signal file_requested(source: Dictionary)
signal refresh_requested
var _title: Label
var _search: LineEdit
var _tree: Tree
var _detail: RichTextLabel
var _open: Button
var _file: Button
var _rows: Array[Dictionary] = []
var _selected := {}

func setup() -> void:
	name = "GameSystemsUsageDialog"
	title = "Где используется"
	wrap_controls = false
	min_size = Vector2i(800, 580)
	ok_button_text = "Закрыть"
	get_cancel_button().hide()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	_title = Label.new()
	_title.name = "UsageSummary"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_title)
	_search = LineEdit.new()
	_search.name = "UsageSearch"
	_search.placeholder_text = "Найти по имени, ID, разделу или файлу…"
	_search.text_changed.connect(func(_text: String) -> void: _render())
	body.add_child(_search)
	_tree = Tree.new()
	_tree.name = "UsageRecords"
	_tree.hide_root = true
	_tree.columns = 2
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "Запись · ID · файл")
	_tree.set_column_title(1, "Связь")
	_tree.set_column_expand_ratio(0, 2)
	_tree.set_column_expand_ratio(1, 1)
	_tree.custom_minimum_size.y = 270
	_tree.size_flags_vertical = Control.SIZE_FILL
	_tree.item_selected.connect(_select)
	_tree.item_activated.connect(_open_selected)
	body.add_child(_tree)
	_detail = RichTextLabel.new()
	_detail.name = "UsageDetail"
	_detail.custom_minimum_size.y = 95
	_detail.fit_content = false
	_detail.selection_enabled = true
	body.add_child(_detail)
	var buttons := HBoxContainer.new()
	body.add_child(buttons)
	_open = _button(buttons, "Открыть запись", "UsageOpen", _open_selected)
	_file = _button(buttons, "Показать файл", "UsageFile", func() -> void: file_requested.emit(_selected.duplicate(true)))
	_button(buttons, "Обновить список", "UsageRefresh", refresh_requested.emit)

func show_sources(record: Dictionary, rows: Array[Dictionary], show_window := true) -> void:
	_rows = rows.duplicate(true)
	_search.text = ""
	_title.text = "«%s» · найдено файлов: %d. Прямые связи и файловые ссылки подтверждены; совпадения ID в тексте требуют проверки." % [record.name, rows.size()]
	_render()
	if show_window and DisplayServer.get_name() != "headless": popup_centered_clamped(Vector2i(900, 640), 0.92)

func feedback(message: String) -> void:
	_detail.text = message

func _render() -> void:
	_tree.clear()
	_selected = {}
	_open.disabled = true
	_file.disabled = true
	_detail.text = "Выберите запись. Двойной щелчок откроет её в библиотеке; для внешнего файла — покажет его в FileSystem." if not _rows.is_empty() else "Ссылок не найдено. Динамические обращения и сохранения могут содержать этот ID."
	var root := _tree.create_item()
	var query := _search.text.strip_edges().to_lower()
	for source in _rows:
		var section := _section(str(source.module))
		if not query.is_empty() and query not in (section + " " + str(source.name) + " " + str(source.id) + " " + str(source.path)).to_lower(): continue
		var row := _tree.create_item(root)
		var identity := str(source.id) + " · " + str(source.path).get_file() if not str(source.id).is_empty() else str(source.path)
		row.set_text(0, "%s · %s\n%s" % [section, source.name, identity])
		row.set_text(1, "\n".join(source.reasons))
		row.set_tooltip_text(0, str(source.path))
		row.set_tooltip_text(1, "\n".join(source.reasons))
		row.set_metadata(0, source)
		row.set_custom_minimum_height(48)

func _select() -> void:
	var row := _tree.get_selected()
	_selected = row.get_metadata(0).duplicate(true) if row != null else {}
	_open.disabled = _selected.is_empty() or str(_selected.get("module", "")).is_empty()
	_file.disabled = _selected.is_empty()
	if not _selected.is_empty(): _detail.text = "%s\nID: %s\n%s\n%s" % [_selected.name, _selected.id, _selected.path, " · ".join(_selected.reasons)]

func _open_selected() -> void:
	if _selected.is_empty(): return
	if str(_selected.module).is_empty(): file_requested.emit(_selected.duplicate(true))
	else: record_requested.emit(_selected.duplicate(true))

func _section(module: String) -> String:
	for info in preload("res://addons/ember_import/ember_game_systems_catalog.gd").MODULES:
		if info[0] == module: return str(info[1])
	return "Файл проекта"

func _button(parent: Node, text: String, node_name: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.name = node_name
	button.pressed.connect(action)
	parent.add_child(button)
	return button
