@tool
class_name EmberCombatLootLibraryWorkspace
extends HSplitContainer
## Full-size catalog view for enemy loot tables. It is a projection of the same
## .tres Resources used by Unit Inspector and runtime; no duplicate documents.

const Catalog := preload("res://scripts/prototypes/ember_combat_loot_table_catalog.gd")
const ItemVisuals := preload("res://scripts/ember_item_visuals.gd")
const LootPanel := preload("res://addons/ember_import/ember_combat_loot_table_inspector_panel.gd")
const UnitCatalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")

signal table_selected(table_id: String)

var _editor_interface: EditorInterface
var _undo_redo: Object
var _tables: Array[EmberCombatLootTableResource] = []
var _search: LineEdit
var _list: ItemList
var _summary: Label
var _editor: VBoxContainer
var _selected_id := ""


func setup(editor_interface: EditorInterface, undo_redo: Object = null) -> void:
	_editor_interface = editor_interface
	_undo_redo = undo_redo
	name = "CombatLootLibraryWorkspace"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = 430
	if get_child_count() == 0:
		_build()
	refresh()


func refresh(preferred_id := "") -> void:
	_tables = Catalog.resources()
	if not preferred_id.is_empty():
		_selected_id = preferred_id
	if _selected_id.is_empty() and not _tables.is_empty():
		_selected_id = _tables[0].table_id
	_refresh_list()
	_show_selected()


func select_table(table_id: String) -> void:
	if table_id.is_empty() or table_id == _selected_id:
		return
	_selected_id = table_id
	_refresh_list()
	_show_selected()


func _build() -> void:
	var library := VBoxContainer.new()
	library.name = "CombatLootLibrary"
	library.custom_minimum_size.x = 360
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library.add_theme_constant_override("separation", 7)
	add_child(library)
	var heading := Label.new()
	heading.text = "ТАБЛИЦЫ ЛУТА ВРАГОВ"
	heading.add_theme_font_size_override("font_size", 18)
	heading.modulate = Color("ffc85a")
	library.add_child(heading)
	_summary = Label.new()
	_summary.name = "CombatLootLibrarySummary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.modulate = Color(0.66, 0.74, 0.84)
	library.add_child(_summary)
	_search = LineEdit.new()
	_search.name = "CombatLootLibrarySearch"
	_search.placeholder_text = "Поиск таблицы, врага или предмета…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value: String) -> void: _refresh_list())
	library.add_child(_search)
	_list = ItemList.new()
	_list.name = "CombatLootLibraryList"
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.fixed_icon_size = Vector2i(64, 64)
	_list.fixed_column_width = 178
	_list.max_text_lines = 3
	_list.same_column_width = true
	_list.allow_reselect = true
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_on_item_selected)
	library.add_child(_list)
	var hint := Label.new()
	hint.text = "Один клик — открыть таблицу. Она остаётся общей для всех назначенных типов врагов."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.62, 0.68, 0.76)
	hint.add_theme_font_size_override("font_size", 12)
	library.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.name = "CombatLootLibraryEditorScroll"
	scroll.custom_minimum_size.x = 620
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_editor = VBoxContainer.new()
	_editor.name = "CombatLootLibraryEditor"
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.add_theme_constant_override("separation", 8)
	scroll.add_child(_editor)


func _refresh_list() -> void:
	if _list == null:
		return
	_list.clear()
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	var selected_index := -1
	for table in _tables:
		var searchable := "%s %s %s" % [table.display_name, table.table_id, table.description]
		var item_names: Array[String] = []
		var assigned_units := _assigned_units(table.table_id)
		searchable += " " + " ".join(assigned_units)
		for entry in table.entries:
			if entry == null:
				continue
			var label := ItemVisuals.item_label(entry.item_id)
			item_names.append(label)
			searchable += " %s %s" % [entry.item_id, label]
		if not query.is_empty() and query not in searchable.to_lower():
			continue
		var texture: Texture2D
		if not table.entries.is_empty() and table.entries[0] != null:
			texture = ItemVisuals.item_texture(table.entries[0].item_id, 64)
		_list.add_item("%s\n%s\n%d поз." % [table.display_name, table.table_id, table.entries.size()], texture)
		var index := _list.item_count - 1
		_list.set_item_metadata(index, table.table_id)
		_list.set_item_tooltip(index, "%s\n%s\nИспользуют: %s\n%s" % [
			table.display_name,
			table.description,
			", ".join(assigned_units) if not assigned_units.is_empty() else "пока никто",
			", ".join(item_names) if not item_names.is_empty() else "Пустая таблица",
		])
		if table.table_id == _selected_id:
			selected_index = index
	if selected_index >= 0:
		_list.select(selected_index)
	elif _list.item_count > 0:
		_list.select(0)
		_selected_id = str(_list.get_item_metadata(0))
	_summary.text = "%d таблиц · %d показано · данные: res://content/combat/loot_tables" % [
		_tables.size(), _list.item_count,
	]


func _assigned_units(table_id: String) -> Array[String]:
	var result: Array[String] = []
	for unit in UnitCatalog.resources("enemy"):
		if unit.loot_table != null and unit.loot_table.table_id == table_id:
			result.append("%s · %s" % [unit.display_name, unit.unit_id])
	return result


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _list.item_count:
		return
	var next_id := str(_list.get_item_metadata(index))
	if next_id.is_empty():
		return
	_selected_id = next_id
	_show_selected()
	table_selected.emit(_selected_id)


func _show_selected() -> void:
	if _editor == null:
		return
	for child in _editor.get_children():
		_editor.remove_child(child)
		child.queue_free()
	var table := Catalog.resource(_selected_id)
	if table == null:
		var empty := Label.new()
		empty.text = "Таблица не выбрана или больше не существует."
		_editor.add_child(empty)
		return
	var header := HBoxContainer.new()
	_editor.add_child(header)
	var title := Label.new()
	title.text = "%s\n%s" % [table.display_name, table.resource_path]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.modulate = table.accent_color
	header.add_child(title)
	var inspect := Button.new()
	inspect.name = "CombatLootOpenResource"
	inspect.text = "Открыть в Inspector"
	inspect.tooltip_text = "Показать тот же canonical .tres в штатном Inspector Godot."
	inspect.disabled = _editor_interface == null
	inspect.pressed.connect(func() -> void:
		if _editor_interface != null:
			_editor_interface.edit_resource(table)
	)
	header.add_child(inspect)
	var panel := LootPanel.new() as EmberCombatLootTableInspectorPanel
	panel.setup(table, _editor_interface, _undo_redo)
	panel.name = "CombatLootCentralEditor"
	_editor.add_child(panel)
