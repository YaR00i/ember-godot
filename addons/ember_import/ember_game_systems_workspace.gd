@tool
extends VBoxContainer
## Native navigation prototype: browsing never writes gameplay Resources.

const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const ItemVisuals = preload("res://scripts/ember_item_visuals.gd")
const ItemStore = preload("res://addons/ember_import/ember_item_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const DraftEditor = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const LabLauncher = preload("res://addons/ember_import/ember_game_systems_lab_launcher.gd")
const CheckPanel = preload("res://addons/ember_import/ember_game_systems_check_panel.gd")
signal editor_requested(module: String, record: Dictionary)
signal library_file_requested(path: String)
var _check_panel: ConfirmationDialog
var _session := Session.new()
var _draft_editor: Control
var _pending := {}
var _discard_dialog: ConfirmationDialog
var _create_dialog: ConfirmationDialog
var _create_id: LineEdit
var _create_name: LineEdit
var _duplicate_source: Resource
var _new_button: Button
var _copy_button: Button
var _delete_dialog: ConfirmationDialog
var _delete_record := {}
var _delete_signature := ""
var _draft_search := ""
var _header: HBoxContainer
var _refresh_button: Button
var _draft_actions: Control

func configure(undo: Object) -> void:
	_session.configure(undo)

func _exit_tree() -> void:
	_session.discard()

func has_unsaved_changes() -> bool:
	return _session.has_changes()

func discard_changes() -> void:
	_session.discard()
	_pending = {}

func show_current_status() -> void:
	if is_instance_valid(_draft_editor): _draft_editor.call("update_status")

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey: return
	var key := event as InputEventKey
	if not key.pressed or key.echo or not (key.ctrl_pressed or key.meta_pressed): return
	var focus := get_viewport().gui_get_focus_owner()
	if key.keycode == KEY_F:
		_search.grab_focus()
		_search.select_all()
	elif key.keycode == KEY_N:
		_open_create(false)
	elif key.keycode == KEY_D and not (focus is LineEdit or focus is TextEdit):
		_open_create(true)
	elif key.keycode == KEY_S and _session.draft != null:
		_save_draft()
	elif key.keycode == KEY_Z and _session.draft != null and not (focus is LineEdit or focus is TextEdit):
		_draft_editor.call("_redo_draft" if key.shift_pressed else "_undo_draft")
	else: return
	get_viewport().set_input_as_handled()

var _module := "item"
var _selected := ""
var _records: Array[Dictionary] = []
var _module_buttons: Dictionary = {}
var _search: LineEdit
var _list: Tree
var _detail: VBoxContainer
var _heading: Label
var _count: Label
var _description: Label
var _category: OptionButton
var _category_id := ""
var _library: VBoxContainer
const ITEM_FILTERS := [["", "Все предметы"], ["equipment", "Вся экипировка"], ["consumable", "Расходники"], ["material", "Материалы"], ["key", "Ключевые предметы"], ["weapon_jrpg", "Оружие"], ["armor", "Броня"], ["shoes", "Обувь"], ["accessory", "Аксессуары"]]


func setup() -> void:
	name = "GameSystemsWorkspace"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	_header = header
	add_child(header)
	var title := _label("Игровые системы", 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_new_button = Button.new()
	_new_button.name = "GameSystemsNew"
	_new_button.text = "Создать"
	_new_button.pressed.connect(_open_create.bind(false))
	header.add_child(_new_button)
	_copy_button = Button.new()
	_copy_button.name = "GameSystemsCopy"
	_copy_button.text = "Копировать"
	_copy_button.pressed.connect(_open_create.bind(true))
	header.add_child(_copy_button)
	var refresh_button := Button.new()
	_refresh_button = refresh_button
	refresh_button.text = "Обновить библиотеки"
	refresh_button.pressed.connect(refresh)
	header.add_child(refresh_button)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	add_child(columns)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 175
	navigation.add_theme_constant_override("separation", 4)
	columns.add_child(navigation)
	for module in Catalog.MODULES:
		var button := Button.new()
		button.name = "GameSystemsModule_" + str(module[0])
		button.text = module[1]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.pressed.connect(select_module.bind(str(module[0]), ""))
		navigation.add_child(button)
		_module_buttons[module[0]] = button
	navigation.add_child(HSeparator.new())
	var check := Button.new()
	check.name = "GameSystemsCheckLibrary"
	check.text = "Проверка библиотеки"
	check.pressed.connect(_open_library_check)
	navigation.add_child(check)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	columns.add_child(body)
	_heading = _label("", 21)
	body.add_child(_heading)
	_description = _label("", 14)
	body.add_child(_description)
	var split := HSplitContainer.new()
	split.name = "GameSystemsSplit"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 0
	body.add_child(split)
	var library := VBoxContainer.new()
	_library = library
	library.custom_minimum_size.x = 230
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library.size_flags_stretch_ratio = 0.42
	library.add_theme_constant_override("separation", 7)
	split.add_child(library)
	_search = LineEdit.new()
	_search.name = "GameSystemsSearch"
	_search.placeholder_text = "Поиск по названию или ID…"
	_search.text_changed.connect(func(_text: String) -> void: _refresh_list())
	library.add_child(_search)
	_category = OptionButton.new()
	_category.name = "GameSystemsItemFilter"
	for filter in ITEM_FILTERS:
		_category.add_item(str(filter[1]))
		_category.set_item_metadata(_category.item_count - 1, filter[0])
	_category.item_selected.connect(_select_category)
	library.add_child(_category)
	_count = _label("", 13)
	library.add_child(_count)
	_list = Tree.new()
	_list.name = "GameSystemsList"
	_list.hide_root = true
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(_open_editor)
	library.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 0.58
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_detail = VBoxContainer.new()
	_detail.name = "GameSystemsDetail"
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 12)
	scroll.add_child(_detail)
	_build_dialogs()
	_session.published.connect(_on_published)
	select_module(_module)


func refresh() -> void:
	if has_unsaved_changes():
		_pending = {"module": _module, "id": _selected, "category": _category_id}
		_confirm_navigation()
		return
	Catalog.refresh()
	select_module(_module, _selected, _category_id)


func select_module(module: String, preferred := "", category := "") -> void:
	# Old equipment links resolve to a filter of the same library and draft owner.
	if module == "equipment":
		module = "item"
		category = "equipment"
	if not _module_buttons.has(module): return
	if has_unsaved_changes():
		_pending = {"module": module, "id": preferred, "category": category}
		_confirm_navigation()
		return
	_session.discard()
	_module = module
	_category_id = category if module == "item" else ""
	_category.visible = module == "item"
	_sync_category()
	_selected = preferred
	_search.text = ""
	for key in _module_buttons:
		(_module_buttons[key] as Button).set_pressed_no_signal(key == module)
	for info in Catalog.MODULES:
		if info[0] == module:
			_heading.text = info[1]
			_description.text = info[2]
	_records = Catalog.entries(module)
	_new_button.disabled = not Store.SPECS.has(Store.kind(module))
	_copy_button.disabled = _new_button.disabled or _records.is_empty()
	_refresh_list()
	if not preferred.is_empty() and not _records.any(func(record: Dictionary) -> bool: return record.id == preferred):
		_list.deselect_all()
		_selected = ""
		_show_detail({})
		_note("Связанная запись %s не найдена. Откройте её исходный редактор и проверьте ссылку." % preferred)


func _refresh_list() -> void:
	if has_unsaved_changes():
		_pending = {"module": _module, "id": _selected, "search": _search.text, "category": _category_id}
		_search.text = _draft_search
		_confirm_navigation()
		return
	_list.clear()
	var root := _list.create_item()
	var query := _search.text.strip_edges().to_lower()
	var selected: TreeItem
	var visible_count := 0
	for record in _records:
		if _module == "item" and not _matches_category(record): continue
		if not query.is_empty() and not query in (str(record.name) + " " + str(record.id)).to_lower(): continue
		var row := _list.create_item(root)
		row.set_text(0, "%s\n%s" % [record.name, record.id])
		row.set_metadata(0, record.id)
		row.set_tooltip_text(0, str(record.path))
		row.set_custom_minimum_height(54)
		if record.id == _selected: selected = row
		visible_count += 1
	_count.text = "%d из %d записей" % [visible_count, _records.size()]
	if selected == null: selected = root.get_first_child()
	if selected != null:
		selected.select(0)
		_on_selected()
	else:
		_selected = ""
		_show_detail({})


func _matches_category(record: Dictionary) -> bool:
	if _category_id == "equipment": return str(record.data.get("kind", "")) in ["weapon_jrpg", "armor", "shoes", "accessory"]
	return _category_id.is_empty() or str(record.data.get("kind", "")) == _category_id


func _sync_category() -> void:
	for index in _category.item_count:
		if str(_category.get_item_metadata(index)) == _category_id: _category.select(index)


func _select_category(index: int) -> void:
	var next := str(_category.get_item_metadata(index))
	if has_unsaved_changes():
		_pending = {"module": _module, "id": "", "category": next, "search": _draft_search}
		_sync_category()
		_confirm_navigation()
		return
	_session.discard()
	_category_id = next
	_selected = ""
	_refresh_list()


func _on_selected() -> void:
	var row := _list.get_selected()
	if row == null: return
	if has_unsaved_changes() and str(row.get_metadata(0)) != _selected:
		_pending = {"module": _module, "id": str(row.get_metadata(0)), "category": _category_id}
		_confirm_navigation()
		return
	if has_unsaved_changes(): return
	if _session.draft != null: _session.discard()
	_selected = str(row.get_metadata(0))
	_show_detail(selected_record())


func selected_record() -> Dictionary:
	for record in _records:
		if record.id == _selected: return record
	return {}


func _show_detail(record: Dictionary) -> void:
	_clear_draft_actions()
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	if record.is_empty():
		_detail.add_child(_label("Ничего не найдено", 20))
		_detail.add_child(_label("Измените поиск или выберите другой раздел.", 14))
		return
	_detail.add_child(_label(str(record.name), 23))
	var id := _label(str(record.id), 13)
	id.modulate = Color("8bbbc7")
	_detail.add_child(id)
	if not str(record.description).is_empty(): _detail.add_child(_label(str(record.description), 14))
	var data: Dictionary = record.data
	if _module in ["item", "equipment"]:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = ItemVisuals.icon_texture(str(data.get("iconId", "")))
		_detail.add_child(icon)
		var kind_name := str({"material": "Материал", "consumable": "Расходник", "key": "Ключевой предмет", "armor": "Броня", "accessory": "Аксессуар", "weapon_jrpg": "Оружие", "weapon_arena": "Оружие арены"}.get(str(data.get("kind", "")), data.get("kind", "")))
		_detail.add_child(_label("Тип: %s  ·  Стек: %d" % [kind_name, int(data.get("stackMax", 1))], 14))
		if not Catalog.Equipment.slot_for_item(data).is_empty():
			var slot := Catalog.Equipment.slot_for_item(data)
			_detail.add_child(_label("Текущий слот: %s" % Catalog.Equipment.SLOT_LABELS.get(slot, slot), 14))
			_note("Пять слотов: оружие, броня, обувь и два аксессуара. Примерка в редакторе показывает результат замены для выбранного героя.")
		for pair in [["atk", "Атака"], ["def", "Защита"], ["hpBonus", "Бонус max HP"], ["mpBonus", "Бонус max MP"], ["hpRestore", "Лечение HP"], ["mpRestore", "Восстановление MP"], ["reviveHp", "Воскрешение HP"]]:
			if int(data.get(pair[0], 0)) != 0: _detail.add_child(_label("%s: %d" % [pair[1], int(data[pair[0]])], 14))
	if _module in ["status", "effect", "action", "unit", "ai", "loot", "encounter"] and record.get("resource") != null:
		_note(str(record.resource.call("behavior_summary")))
	var resource := record.get("resource") as Resource
	var errors: Array = []
	if _module in ["item", "equipment"]:
		errors = ItemStore.validation_errors(data)
	elif resource != null and resource.has_method("validation_errors"):
		errors = resource.call("validation_errors", Catalog.Actions.ids()) if _module == "unit" else resource.call("validation_errors")
	_detail.add_child(_label("Проверка записи", 16))
	_detail.add_child(_label("• " + "\n• ".join(errors) if not errors.is_empty() else "Ошибок проверки данных не найдено.", 14))
	var open := Button.new()
	open.name = "GameSystemsOpenEditor"
	open.text = "Открыть лабораторию" if _module == "lab" else "Открыть существующий редактор"
	open.pressed.connect(_open_existing_editor)
	_detail.add_child(open)
	if _module == "encounter":
		var run := Button.new()
		run.name = "GameSystemsRunEncounter"
		run.text = "Проверить встречу в Lab"
		run.tooltip_text = "Открыть сохранённую встречу в отдельном тестовом окне. Игровые сохранения не используются; награды только показываются."
		run.disabled = not errors.is_empty()
		run.pressed.connect(_run_selected_encounter)
		_detail.add_child(run)
	if Store.SPECS.has(Store.kind(_module)):
		var edit := Button.new()
		edit.name = "GameSystemsEditDraft"
		edit.text = "Редактировать черновик"
		edit.pressed.connect(begin_edit)
		_detail.add_child(edit)
		var usage := Button.new()
		usage.name = "GameSystemsUsage"
		usage.text = "Где используется"
		usage.pressed.connect(_show_usage.bind(record))
		_detail.add_child(usage)
		var remove := Button.new()
		remove.name = "GameSystemsDelete"
		remove.text = "Удалить запись…"
		remove.pressed.connect(_request_delete.bind(record))
		_detail.add_child(remove)
	var links := Catalog.relations(_module, record)
	_detail.add_child(_label("Связанные записи", 16))
	if links.is_empty(): _detail.add_child(_label("Связи в этом макете не найдены.", 14))
	for link in links:
		var button := Button.new()
		button.text = str(link.label)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = str(link.label)
		button.pressed.connect(select_module.bind(str(link.module), str(link.id)))
		_detail.add_child(button)
	var path := _label(str(record.path), 12)
	path.modulate = Color("8c939f")
	_detail.add_child(path)


func _open_editor() -> void:
	if Store.SPECS.has(Store.kind(_module)):
		begin_edit()
		return
	_open_existing_editor()

func _open_existing_editor() -> void:
	var record := selected_record()
	if not record.is_empty(): editor_requested.emit(_module, record)


func _open_library_check() -> void:
	if _check_panel == null:
		_check_panel = CheckPanel.new()
		add_child(_check_panel)
		_check_panel.call("setup")
		_check_panel.connect("record_requested", _open_checked_record)
		_check_panel.connect("file_requested", library_file_requested.emit)
	_check_panel.call("open_report")

func _open_checked_record(issue: Dictionary) -> void:
	if has_unsaved_changes():
		_check_panel.call("feedback", "В черновике есть изменения. Сохраните или закройте его перед переходом к другой записи.")
		return
	var path := str(issue.get("path", ""))
	if not FileAccess.file_exists(path):
		_check_panel.call("feedback", "Файл уже удалён или перемещён. Повторите проверку.")
		return
	_check_panel.hide()
	# Exact file route, not ID lookup: duplicate IDs must open the chosen source.
	editor_requested.emit("library_check", {"path": path})

func _run_selected_encounter() -> Dictionary:
	if _module != "encounter": return {"ok": false, "error": "Выберите встречу."}
	if has_unsaved_changes():
		_session.last_error = "Сначала сохраните черновик встречи, затем запустите тест из библиотеки."
		show_current_status()
		return {"ok": false, "error": _session.last_error}
	var record := selected_record()
	if record.is_empty(): return {"ok": false, "error": "Выберите сохранённую встречу."}
	var result := LabLauncher.start(str(record.path))
	_note("Тест открыт в отдельном окне. Результат не изменяет игровой прогресс." if result.get("ok", false) else str(result.get("error", "Не удалось запустить тест.")))
	return result

func _note(text: String) -> void:
	var note := _label(text, 14)
	note.modulate = Color("ddbd7f")
	_detail.add_child(note)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _build_dialogs() -> void:
	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.name = "GameSystemsDiscardDialog"
	_discard_dialog.title = "Несохранённый черновик"
	_discard_dialog.dialog_text = "Переход отбросит изменения этой записи. Можно остаться и сохранить черновик."
	_discard_dialog.ok_button_text = "Отбросить и перейти"
	_discard_dialog.cancel_button_text = "Остаться"
	_discard_dialog.confirmed.connect(_accept_navigation)
	_discard_dialog.canceled.connect(func() -> void:
		_pending = {}
		var row := _list.get_root().get_first_child()
		while row != null:
			if str(row.get_metadata(0)) == _selected: row.select(0)
			row = row.get_next()
	)
	add_child(_discard_dialog)
	_create_dialog = ConfirmationDialog.new()
	_create_dialog.name = "GameSystemsCreateDialog"
	_create_dialog.title = "Новая запись"
	_create_dialog.ok_button_text = "Открыть черновик"
	var fields := VBoxContainer.new()
	_create_id = LineEdit.new()
	_create_id.placeholder_text = "Новый ID: a-z, 0-9, _ и -"
	_create_id.custom_minimum_size.x = 420
	fields.add_child(_create_id)
	_create_name = LineEdit.new()
	_create_name.placeholder_text = "Название"
	fields.add_child(_create_name)
	fields.add_child(_label("Копия сохраняет общие ссылки на эффекты и другие записи. Внутренние строки копируются независимо.", 14))
	_create_dialog.add_child(fields)
	_create_dialog.confirmed.connect(_create_draft)
	add_child(_create_dialog)
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.name = "GameSystemsDeleteDialog"
	_delete_dialog.title = "Удалить запись из библиотеки?"
	_delete_dialog.ok_button_text = "Удалить с резервной копией"
	_delete_dialog.confirmed.connect(_delete_confirmed)
	add_child(_delete_dialog)

func _confirm_navigation() -> void:
	if DisplayServer.get_name() != "headless": _discard_dialog.popup_centered_clamped(Vector2i(500, 180), 0.9)

func _accept_navigation() -> void:
	var target := _pending.duplicate()
	_session.discard()
	_pending = {}
	select_module(str(target.get("module", _module)), str(target.get("id", "")), str(target.get("category", _category_id)))
	if target.has("search"):
		_search.text = str(target.search)
		_refresh_list()
	if target.has("create"): _open_create(bool(target.create))

func _open_create(duplicate_selected: bool) -> void:
	if has_unsaved_changes():
		_pending = {"module": _module, "id": _selected, "create": duplicate_selected, "category": _category_id}
		_confirm_navigation()
		return
	var record := selected_record()
	_duplicate_source = ResourceLoader.load(str(record.path), "", ResourceLoader.CACHE_MODE_IGNORE) if duplicate_selected and not record.is_empty() else null
	_create_id.text = str(record.get("id", "")) + "_copy" if _duplicate_source != null else ""
	_create_name.text = str(record.get("name", "")) + " — копия" if _duplicate_source != null else ""
	_create_dialog.popup_centered_clamped(Vector2i(500, 240), 0.9)

func _create_draft() -> void:
	if _create_name.text.strip_edges().is_empty(): return
	if not _session.create(_module, _create_id.text.strip_edges(), _create_name.text.strip_edges(), _duplicate_source):
		_note(_session.last_error)
		return
	if _module == "item" and _duplicate_source == null and not _category_id.is_empty():
		var data: Dictionary = _session.draft.definition.duplicate(true)
		data["kind"] = "armor" if _category_id == "equipment" else _category_id
		data["slot"] = str({"armor": "armor", "shoes": "shoes", "accessory": "accessory", "weapon_jrpg": "weapon"}.get(data.kind, "none"))
		_session.set_value("definition", data)
	_mount_draft()

func begin_edit() -> void:
	if has_unsaved_changes(): return
	var record := selected_record()
	if record.is_empty(): return
	if _session.open(_module, record): _mount_draft()
	else: _note(_session.last_error)

func begin_new(module: String, source: Resource = null) -> void:
	select_module(module)
	_duplicate_source = source
	_create_id.text = ""
	_create_name.text = str(source.get("display_name")) + " — копия" if source != null else ""
	_create_dialog.popup_centered_clamped(Vector2i(500, 240), 0.9)

func _mount_draft() -> void:
	_draft_search = _search.text
	_clear_draft_actions()
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	_draft_editor = DraftEditor.new()
	_detail.add_child(_draft_editor)
	_draft_editor.call("setup", _session)
	_draft_actions = _draft_editor.get_node("GameSystemsDraftActions") as Control
	_draft_actions.reparent(_header)
	_library.hide()
	_new_button.hide()
	_copy_button.hide()
	_refresh_button.hide()
	_draft_editor.connect("save_requested", _save_draft)
	_draft_editor.connect("discard_requested", _close_draft)

func _clear_draft_actions() -> void:
	if is_instance_valid(_draft_actions):
		_draft_actions.get_parent().remove_child(_draft_actions)
		_draft_actions.queue_free()
	_draft_actions = null
	if _library != null: _library.show()
	if _new_button != null: _new_button.show()
	if _copy_button != null: _copy_button.show()
	if _refresh_button != null: _refresh_button.show()

func _save_draft() -> void:
	if not _session.save(): show_current_status()

func _close_draft() -> void:
	if has_unsaved_changes():
		_pending = {"module": _module, "id": _selected, "category": _category_id}
		_confirm_navigation()
	else:
		_session.discard()
		_show_detail(selected_record())

func _on_published() -> void:
	if _check_panel != null: _check_panel.call("mark_stale")
	if has_unsaved_changes(): return
	var id := Store.id_for(_session.module, _session.draft) if _session.draft != null else _selected
	if Engine.is_editor_hint(): preload("res://addons/ember_import/ember_editor_filesystem.gd").request()
	Catalog.refresh()
	# A saved type change must remain visible even if it left the current filter.
	var category := _category_id
	if _module == "item":
		for record in Catalog.entries("item"):
			if record.id == id and not _matches_category(record): category = ""
	select_module(_module, id, category)

func _show_usage(record: Dictionary) -> void:
	var sources := Catalog.incoming(_module, record)
	_detail.add_child(_label("Прямые ссылки:\n" + "\n".join(sources) if not sources.is_empty() else "Прямых ссылок не найдено. Динамические ссылки и сохранения требуют отдельной проверки перед удалением.", 14))

func _request_delete(record: Dictionary) -> void:
	var sources := Catalog.incoming(_module, record)
	if not sources.is_empty():
		_note("Удаление заблокировано: найдены ссылки или совпадающие ID.\n" + "\n".join(sources))
		return
	_delete_record = record
	_delete_signature = Store.signature(str(record.path))
	_delete_dialog.dialog_text = "Будет удалена запись «%s». Сохранится точная резервная копия; Undo вернёт файл.\n\nПрямых ссылок не найдено. Проверьте динамические ссылки. Старые сохранения не удаляются: оставшийся в них ID станет неизвестным." % record.name
	_delete_dialog.popup_centered_clamped(Vector2i(570, 260), 0.9)

func _delete_confirmed() -> void:
	if not _session.remove(_module, _delete_record, _delete_signature): _note(_session.last_error)
