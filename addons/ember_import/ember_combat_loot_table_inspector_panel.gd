@tool
class_name EmberCombatLootTableInspectorPanel
extends VBoxContainer
## Visual item rows for a Loot Table Resource. Every edit replaces the entry
## array atomically so nested Resource changes participate in Inspector Undo.

const ItemVisuals := preload("res://scripts/ember_item_visuals.gd")
const VisualPopup := preload("res://addons/ember_import/ember_visual_library_popup.gd")

var _table: EmberCombatLootTableResource
var _editor_interface: EditorInterface
var _undo_redo: Object
var _rows: VBoxContainer
var _validation: Label
var _popup: EmberVisualLibraryPopup
var _replace_index := -1


func setup(
	table: EmberCombatLootTableResource,
	editor_interface: EditorInterface = null,
	undo_redo: Object = null,
) -> void:
	_table = table
	_editor_interface = editor_interface
	_undo_redo = undo_redo
	name = "CombatLootTableOverview"
	add_theme_constant_override("separation", 7)
	var title := Label.new()
	title.text = "ТАБЛИЦА ЛУТА"
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color("ffc85a")
	add_child(title)
	var hint := Label.new()
	hint.text = "Каждая строка бросается независимо. Иконка и ID берутся из общей библиотеки предметов; результат боя только формирует очередь наград."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.62, 0.72, 0.82)
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)
	_rows = VBoxContainer.new()
	_rows.name = "CombatLootRows"
	_rows.add_theme_constant_override("separation", 5)
	add_child(_rows)
	_validation = Label.new()
	_validation.name = "CombatLootValidation"
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_validation)
	if not _table.changed.is_connected(_refresh):
		_table.changed.connect(_refresh)
	_refresh()


func _exit_tree() -> void:
	if _table != null and _table.changed.is_connected(_refresh):
		_table.changed.disconnect(_refresh)


func _refresh() -> void:
	if _table == null or _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	for index in _table.entries.size():
		_build_row(index, _table.entries[index])
	var add := Button.new()
	add.name = "CombatLootAddEntry"
	add.text = "+ Добавить предмет из библиотеки…"
	add.disabled = _undo_redo == null or _available_item_entries().is_empty()
	add.pressed.connect(_open_item_library.bind(-1))
	_rows.add_child(add)
	var errors := _table.validation_errors()
	_validation.text = "✓ Таблица готова" if errors.is_empty() else "⚠ " + "\n⚠ ".join(errors)
	_validation.modulate = Color("79d99a") if errors.is_empty() else Color("ff8d78")


func _build_row(index: int, entry: EmberCombatLootEntryResource) -> void:
	var panel := PanelContainer.new()
	panel.name = "CombatLootEntry_%d" % index
	_rows.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = ItemVisuals.item_texture(entry.item_id, 44) if entry != null else null
	row.add_child(icon)
	var item := Button.new()
	item.name = "CombatLootItem_%d" % index
	item.text = ItemVisuals.item_label(entry.item_id) if entry != null else "⚠ Пустая строка"
	item.tooltip_text = "Выбрать другой предмет из общей визуальной библиотеки."
	item.clip_text = true
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.custom_minimum_size.x = 150
	item.disabled = _undo_redo == null
	item.pressed.connect(_open_item_library.bind(index))
	row.add_child(item)
	var chance := SpinBox.new()
	chance.name = "CombatLootChance_%d" % index
	chance.tooltip_text = "Независимый шанс выпадения."
	chance.min_value = 0.1
	chance.max_value = 100.0
	chance.step = 0.1
	chance.suffix = "%"
	chance.custom_minimum_size.x = 86
	chance.value = entry.chance_percent if entry != null else 100.0
	chance.editable = _undo_redo != null
	chance.value_changed.connect(_change_number.bind(index, "chance_percent"))
	row.add_child(chance)
	for spec in [["minimum_count", "мин"], ["maximum_count", "макс"]]:
		var amount := SpinBox.new()
		amount.name = "CombatLoot%s_%d" % ["Minimum" if spec[0] == "minimum_count" else "Maximum", index]
		amount.tooltip_text = str(spec[1]).capitalize() + " количество при успешном броске."
		amount.min_value = 1
		amount.max_value = 999
		amount.step = 1
		amount.prefix = "%s " % spec[1]
		amount.custom_minimum_size.x = 86
		amount.value = int(entry.get(spec[0])) if entry != null else 1
		amount.editable = _undo_redo != null
		amount.value_changed.connect(_change_number.bind(index, spec[0]))
		row.add_child(amount)
	var remove := Button.new()
	remove.text = "×"
	remove.tooltip_text = "Удалить строку. Ctrl+Z отменяет."
	remove.disabled = _undo_redo == null
	remove.modulate = Color(1.0, 0.56, 0.52)
	remove.pressed.connect(_remove_entry.bind(index))
	row.add_child(remove)


func _open_item_library(index: int) -> void:
	_replace_index = index
	if _popup == null:
		_popup = VisualPopup.new() as EmberVisualLibraryPopup
		_popup.name = "CombatLootItemLibrary"
		_popup.value_chosen.connect(_choose_item)
		add_child(_popup)
	var selected := ""
	if index >= 0 and index < _table.entries.size() and _table.entries[index] != null:
		selected = _table.entries[index].item_id
	_popup.open_library(
		"БИБЛИОТЕКА ПРЕДМЕТОВ ДЛЯ ЛУТА",
		_replace_item_entries(index) if index >= 0 else _available_item_entries(),
		selected,
		Vector2i(64, 64),
		150,
	)


func _choose_item(item_id: String) -> void:
	if item_id.is_empty():
		return
	var next := _duplicate_entries()
	if _replace_index >= 0 and _replace_index < next.size():
		next[_replace_index].item_id = item_id
	else:
		var entry := EmberCombatLootEntryResource.new()
		entry.item_id = item_id
		next.append(entry)
	_commit_entries(next, "Изменить предмет в таблице лута")


func _change_number(value: float, index: int, property: String) -> void:
	var next := _duplicate_entries()
	if index < 0 or index >= next.size():
		return
	if property == "chance_percent":
		next[index].chance_percent = value
	else:
		next[index].set(property, roundi(value))
	_commit_entries(next, "Изменить строку таблицы лута")


func _remove_entry(index: int) -> void:
	var next := _duplicate_entries()
	if index < 0 or index >= next.size():
		return
	next.remove_at(index)
	_commit_entries(next, "Удалить предмет из таблицы лута")


func _available_item_entries() -> Array[Dictionary]:
	var used := {}
	for entry in _table.entries:
		if entry != null:
			used[entry.item_id] = true
	var result: Array[Dictionary] = []
	for entry in ItemVisuals.item_entries():
		if not used.has(str(entry.get("id", ""))):
			result.append(entry)
	return result


func _replace_item_entries(index: int) -> Array[Dictionary]:
	var used_elsewhere := {}
	for entry_index in _table.entries.size():
		var entry := _table.entries[entry_index]
		if entry_index != index and entry != null:
			used_elsewhere[entry.item_id] = true
	var result: Array[Dictionary] = []
	for visual in ItemVisuals.item_entries():
		if not used_elsewhere.has(str(visual.get("id", ""))):
			result.append(visual)
	return result


func _duplicate_entries() -> Array[EmberCombatLootEntryResource]:
	var result: Array[EmberCombatLootEntryResource] = []
	for entry in _table.entries:
		result.append(entry.duplicate_entry() if entry != null else EmberCombatLootEntryResource.new())
	return result


func _commit_entries(next: Array[EmberCombatLootEntryResource], title: String) -> void:
	if _table == null or _undo_redo == null:
		return
	var previous := _duplicate_entries()
	if _undo_redo is EditorUndoRedoManager:
		(_undo_redo as EditorUndoRedoManager).create_action(title, UndoRedo.MERGE_DISABLE, _table)
		(_undo_redo as EditorUndoRedoManager).add_do_property(_table, "entries", next)
		Callable(_undo_redo, "add_do_method").call(_table, "emit_changed")
		(_undo_redo as EditorUndoRedoManager).add_undo_property(_table, "entries", previous)
		Callable(_undo_redo, "add_undo_method").call(_table, "emit_changed")
		(_undo_redo as EditorUndoRedoManager).commit_action()
	else:
		(_undo_redo as UndoRedo).create_action(title, UndoRedo.MERGE_DISABLE)
		(_undo_redo as UndoRedo).add_do_property(_table, "entries", next)
		(_undo_redo as UndoRedo).add_do_method(Callable(_table, "emit_changed"))
		(_undo_redo as UndoRedo).add_undo_property(_table, "entries", previous)
		(_undo_redo as UndoRedo).add_undo_method(Callable(_table, "emit_changed"))
		(_undo_redo as UndoRedo).commit_action()
