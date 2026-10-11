@tool
extends ConfirmationDialog
## Transient report UI. Resource owners and draft sessions stay in the workspace.
signal record_requested(issue: Dictionary)
signal file_requested(path: String)
const Service = preload("res://addons/ember_import/ember_game_systems_check_service.gd")
var _service := Service.new()
var _report := {}
var _issues: Array = []
var _summary: Label
var _search: LineEdit
var _tree: Tree
var _detail: RichTextLabel
var _open: Button
var _file: Button
var _repeat: Button
var _selected := {}

func setup() -> void:
	name = "GameSystemsLibraryCheck"
	# Keep report rows scrollable within a bounded body. Automatic dialog
	# wrapping must not grow the Window when feedback changes the layout.
	wrap_controls = false
	min_size = Vector2i(860, 620)
	title = "Проверка сохранённой библиотеки"
	ok_button_text = "Закрыть"
	get_cancel_button().hide()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.custom_minimum_size = Vector2(840, 540)
	add_child(content)
	_summary = Label.new()
	_summary.name = "LibraryCheckSummary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.text = "Проверяются сохранённые записи. Черновики не входят в отчёт."
	content.add_child(_summary)
	_search = LineEdit.new()
	_search.name = "LibraryCheckSearch"
	_search.placeholder_text = "Фильтр по разделу, записи, файлу или проблеме…"
	_search.text_changed.connect(func(_text: String) -> void: _render())
	content.add_child(_search)
	_tree = Tree.new()
	_tree.name = "LibraryCheckIssues"
	_tree.hide_root = true
	_tree.columns = 2
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "Раздел · запись")
	_tree.set_column_title(1, "Проблема")
	_tree.set_column_expand_ratio(0, 1)
	_tree.set_column_expand_ratio(1, 2)
	_tree.size_flags_vertical = Control.SIZE_FILL
	_tree.custom_minimum_size.y = 280
	_tree.item_selected.connect(_select_issue)
	_tree.item_activated.connect(_open_issue)
	content.add_child(_tree)
	_detail = RichTextLabel.new()
	_detail.name = "LibraryCheckDetail"
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size.y = 90
	_detail.fit_content = false
	_detail.selection_enabled = true
	content.add_child(_detail)
	var buttons := HBoxContainer.new()
	content.add_child(buttons)
	_open = _button(buttons, "Открыть запись", "LibraryCheckOpen", _open_issue)
	_file = _button(buttons, "Показать файл", "LibraryCheckFile", _show_file)
	_repeat = _button(buttons, "Повторить проверку", "LibraryCheckRepeat", _start)
	_open.disabled = true
	_file.disabled = true

func open_report() -> void:
	if DisplayServer.get_name() != "headless": popup_centered_clamped(Vector2i(920, 660), 0.9)
	if _report.is_empty() and not _service.running(): _start()

func _start() -> void:
	var started := _service.start()
	if not started.get("ok", false):
		_summary.text = str(started.get("error", "Проверка не запущена."))
		return
	_summary.text = "Проверяю сохранённую библиотеку… Несохранённые изменения остаются в своих черновиках."
	_repeat.disabled = true
	_open.disabled = true
	_file.disabled = true

func _process(_delta: float) -> void:
	if not _service.running(): return
	var report := _service.poll()
	if report.is_empty(): return
	_repeat.disabled = false
	if not report.get("ok", false):
		_summary.text = str(report.get("error", "Проверка не завершилась."))
		return
	_report = report
	_issues = report.issues
	_summary.text = "Проверено записей: %d · проблем: %d · %.2f с.\nСохранённые игровые разделы; иконки и цепочки исхода — ID и файловые ссылки. Повторите проверку после изменений." % [report.recordCount, report.issueCount, float(report.elapsedMs) / 1000.0]
	_render()

func mark_stale() -> void:
	if not _report.is_empty(): _summary.text = "После проверки данные сохранялись. Повторите проверку, чтобы получить актуальные результаты."

func feedback(message: String) -> void:
	_detail.text = message

func _render() -> void:
	_tree.clear()
	_selected = {}
	_open.disabled = true
	_file.disabled = true
	_detail.text = "Ошибок в проверенных данных не найдено." if not _report.is_empty() and _issues.is_empty() else "Выберите проблему, чтобы увидеть полный текст и точный путь файла."
	var root := _tree.create_item()
	var query := _search.text.strip_edges().to_lower()
	for issue in _issues:
		if not query.is_empty() and query not in (_module_name(str(issue.module)) + " " + str(issue.module) + " " + str(issue.name) + " " + str(issue.id) + " " + str(issue.path) + " " + str(issue.message)).to_lower(): continue
		var row := _tree.create_item(root)
		row.set_text(0, "%s · %s" % [_module_name(str(issue.module)), str(issue.name)])
		row.set_text(1, str(issue.message))
		row.set_tooltip_text(0, str(issue.path))
		row.set_tooltip_text(1, str(issue.message))
		row.set_metadata(0, issue)

func _select_issue() -> void:
	var row := _tree.get_selected()
	_selected = row.get_metadata(0) if row != null else {}
	if _selected.is_empty(): return
	_detail.text = "%s\n%s" % [_selected.message, _selected.path]
	_open.disabled = not _selected.get("loadable", false) or not FileAccess.file_exists(str(_selected.path)) or _service.running()
	_file.disabled = not FileAccess.file_exists(str(_selected.path)) or _service.running()

func _open_issue() -> void:
	if not _selected.is_empty() and not _open.disabled: record_requested.emit(_selected)

func _show_file() -> void:
	if not _selected.is_empty() and not _file.disabled: file_requested.emit(str(_selected.path))

func _exit_tree() -> void:
	_service.cancel()

func _button(parent: Node, text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _module_name(module: String) -> String:
	return str({"item": "Предметы", "status": "Статусы", "effect": "Эффекты", "action": "Приёмы", "unit": "Бойцы", "ai": "ИИ", "loot": "Лут", "field": "Поля", "encounter": "Встречи", "icon": "Иконки", "story_action": "Цепочки исхода"}.get(module, module))
