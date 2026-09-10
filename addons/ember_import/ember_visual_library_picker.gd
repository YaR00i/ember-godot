@tool
class_name EmberVisualLibraryPicker
extends VBoxContainer
## Reusable tiled picker for canonical string-ID catalogs. Entries are a visual
## projection only; the source catalog remains the sole data owner.

signal value_chosen(value: String)
signal selection_changed(value: String)

var _entries: Array[Dictionary] = []
var _selected_id := ""
var _search: LineEdit
var _items: ItemList
var _choose: Button
var _actions: HBoxContainer


func setup(title_text: String, entries: Array[Dictionary], current_id: String) -> void:
	name = "EmberVisualLibraryPicker"
	if get_child_count() == 0:
		_build(title_text)
	else:
		(get_node("LibraryTitle") as Label).text = title_text
	set_entries(entries, current_id)


func set_entries(entries: Array[Dictionary], current_id: String, clear_search := true) -> void:
	_entries = entries.duplicate(true)
	_selected_id = current_id
	if clear_search and _search != null:
		_search.text = ""
	_refresh()


func selected_id() -> String:
	return _selected_id


func selected_entry() -> Dictionary:
	for entry in _entries:
		if str(entry.get("id", "")) == _selected_id:
			return entry.duplicate(true)
	return {}


func set_choose_text(value: String) -> void:
	if _choose != null:
		_choose.text = value


func set_choose_visible(value: bool) -> void:
	if _actions != null:
		_actions.visible = value


func set_tile_layout(icon_size: Vector2i, column_width: int, text_lines := 2) -> void:
	if _items == null:
		return
	_items.fixed_icon_size = icon_size
	_items.fixed_column_width = column_width
	_items.max_text_lines = text_lines


func set_entry_texture(value: String, texture: Texture2D) -> void:
	if texture == null:
		return
	for entry in _entries:
		if str(entry.get("id", "")) == value:
			entry["texture"] = texture
			break
	if _items == null:
		return
	for index in _items.item_count:
		if str(_items.get_item_metadata(index)) == value:
			_items.set_item_icon(index, texture)
			return


func _build(title_text: String) -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(620, 470)
	var title := Label.new()
	title.name = "LibraryTitle"
	title.text = title_text
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)
	_search = LineEdit.new()
	_search.name = "LibrarySearch"
	_search.placeholder_text = "Поиск по названию или ID…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_value: String) -> void: _refresh())
	add_child(_search)
	_items = ItemList.new()
	_items.name = "VisualLibraryList"
	_items.icon_mode = ItemList.ICON_MODE_TOP
	_items.fixed_icon_size = Vector2i(56, 56)
	_items.fixed_column_width = 116
	_items.max_columns = 0
	_items.max_text_lines = 2
	_items.same_column_width = true
	_items.allow_reselect = true
	_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_items.item_selected.connect(_on_item_selected)
	_items.item_activated.connect(_on_item_activated)
	add_child(_items)
	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_END
	add_child(_actions)
	var hint := Label.new()
	hint.text = "Двойной клик или Enter — выбрать"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.modulate = Color(0.66, 0.68, 0.74)
	_actions.add_child(hint)
	_choose = Button.new()
	_choose.name = "ChooseVisualLibraryItem"
	_choose.text = "Выбрать"
	_choose.pressed.connect(_emit_choice)
	_actions.add_child(_choose)


func _refresh() -> void:
	if _items == null:
		return
	_items.clear()
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	var selected_index := -1
	for entry in _entries:
		var item_id := str(entry.get("id", ""))
		var label := str(entry.get("label", item_id))
		var tooltip := str(entry.get("tooltip", label))
		if not query.is_empty() and query not in ("%s %s %s" % [label, item_id, tooltip]).to_lower():
			continue
		var texture: Texture2D = entry.get("texture", null) as Texture2D
		_items.add_item(label, texture)
		var index := _items.item_count - 1
		_items.set_item_metadata(index, item_id)
		_items.set_item_tooltip(index, tooltip)
		if item_id == _selected_id:
			selected_index = index
	if selected_index >= 0:
		_items.select(selected_index)
	elif _items.item_count > 0:
		_items.select(0)
		_selected_id = str(_items.get_item_metadata(0))
	_choose.disabled = _items.item_count == 0


func _on_item_selected(index: int) -> void:
	_selected_id = str(_items.get_item_metadata(index))
	selection_changed.emit(_selected_id)


func _on_item_activated(index: int) -> void:
	_on_item_selected(index)
	_emit_choice()


func _emit_choice() -> void:
	if _items.item_count > 0:
		value_chosen.emit(_selected_id)
