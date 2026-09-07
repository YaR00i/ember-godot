@tool
class_name EmberItemEditor
extends VBoxContainer
## Compact editor for one canonical item. It keeps the established Dictionary
## schema and locks legacy entries until an explicit Resource migration.

const Store = preload("res://addons/ember_import/ember_item_store.gd")
const ItemVisuals = preload("res://scripts/ember_item_visuals.gd")
const VisualLibraryPicker = preload("res://addons/ember_import/ember_visual_library_picker.gd")

signal save_requested(document: Dictionary)
signal migrate_requested(item_id: String)
signal cancel_requested

var _current_id := ""
var _suggested_id := ""
var _base: Dictionary = {}
var _id_input: LineEdit
var _name_input: LineEdit
var _english_input: LineEdit
var _kind: OptionButton
var _slot: OptionButton
var _rarity: OptionButton
var _use_in: OptionButton
var _stack: SpinBox
var _icon: OptionButton
var _icon_preview: TextureRect
var _icon_popup: PopupPanel
var _icon_picker: EmberVisualLibraryPicker
var _atk: SpinBox
var _defense: SpinBox
var _heal: SpinBox
var _mana: SpinBox
var _revive: SpinBox
var _combat_range: SpinBox
var _unsellable: CheckBox
var _sell_price: SpinBox
var _tags: LineEdit
var _notes: TextEdit
var _validation: Label


func setup(item_id: String, suggested_id: String) -> void:
	name = "EmberItemEditor"
	_current_id = item_id.strip_edges()
	_suggested_id = suggested_id.strip_edges()
	_base = Store.document(_current_id)
	_build()


func _build() -> void:
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "ПРЕДМЕТ"
	title.modulate = Color(0.48, 0.84, 1.0)
	add_child(title)
	var existing := not _base.is_empty()
	var owner := Store.owner(_current_id)
	var editable := not existing or owner == "native"
	_id_input = _line_row("ItemId", "ID", "snake_case; после создания не переименовывается")
	_id_input.text = _current_id if existing else _suggested_id
	_id_input.editable = not existing
	_name_input = _line_row("ItemNameRu", "Название", "Показывается игроку")
	_name_input.text = str(_base.get("nameRu", "Новый предмет"))
	_name_input.editable = editable
	_english_input = _line_row("ItemName", "Name", "Внутреннее английское имя; необязательно")
	_english_input.text = str(_base.get("name", ""))
	_english_input.editable = editable
	if existing:
		_add_owner_row(owner)
	if owner == "legacy":
		var hint := Label.new()
		hint.text = "Legacy item доступен только для чтения. Перенеси его в .tres, затем редактируй характеристики."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.modulate = Color(0.90, 0.68, 0.36)
		add_child(hint)
	_kind = _option_row("ItemKind", "Тип", Store.KINDS, str(_base.get("kind", "material")), editable)
	_slot = _option_row("ItemSlot", "Слот", Store.SLOTS, str(_base.get("slot", "none")), editable)
	_rarity = _option_row("ItemRarity", "Редкость", Store.RARITIES, str(_base.get("rarity", "common")), editable)
	_use_in = _option_row("ItemUseIn", "Режим", Store.USE_TARGETS, str(_base.get("useIn", "explore")), editable)
	_stack = _number_row("ItemStackMax", "Стак", float(_base.get("stackMax", 1)), 1.0, 999.0, editable)
	_icon = _option_row("ItemIcon", "Иконка", Store.icon_ids(), str(_base.get("iconId", "")), editable, true)
	_add_icon_library(editable)
	var stats_title := Label.new()
	stats_title.text = "ХАРАКТЕРИСТИКИ"
	stats_title.modulate = Color(0.70, 0.74, 0.82)
	add_child(stats_title)
	_atk = _number_row("ItemAtk", "Атака", float(_base.get("atk", 0)), 0.0, 9999.0, editable)
	_defense = _number_row("ItemDef", "Защита", float(_base.get("def", 0)), 0.0, 9999.0, editable)
	_heal = _number_row("ItemHpRestore", "Лечение", float(_base.get("hpRestore", 0)), 0.0, 9999.0, editable)
	_mana = _number_row("ItemMpRestore", "Восстановление MP", float(_base.get("mpRestore", 0)), 0.0, 9999.0, editable)
	_revive = _number_row("ItemReviveHp", "HP при воскрешении", float(_base.get("reviveHp", 0)), 0.0, 9999.0, editable)
	_combat_range = _number_row("ItemCombatRange", "Дальность в бою", float(_base.get("combatRange", 1)), 0.0, 99.0, editable)
	var sell_row := _field_row("Продажа")
	_unsellable = CheckBox.new()
	_unsellable.name = "ItemUnsellable"
	_unsellable.text = "Запрещена"
	_unsellable.button_pressed = bool(_base.get("unsellable", false))
	_unsellable.disabled = not editable
	sell_row.add_child(_unsellable)
	_sell_price = SpinBox.new()
	_sell_price.name = "ItemSellPrice"
	_sell_price.min_value = 0.0
	_sell_price.max_value = 999999.0
	_sell_price.step = 1.0
	_sell_price.value = float(_base.get("sellPrice", 0))
	_sell_price.editable = editable and not _unsellable.button_pressed
	_sell_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_row.add_child(_sell_price)
	_unsellable.toggled.connect(func(blocked: bool) -> void: _sell_price.editable = editable and not blocked)
	add_child(sell_row)
	_tags = _line_row("ItemTags", "Теги", "Через запятую")
	_tags.text = ", ".join(_string_array(_base.get("tags", [])))
	_tags.editable = editable
	var notes_row := _field_row("Описание")
	_notes = TextEdit.new()
	_notes.name = "ItemNotes"
	_notes.custom_minimum_size.y = 70.0
	_notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes.text = str(_base.get("notesRu", ""))
	_notes.editable = editable
	notes_row.add_child(_notes)
	add_child(notes_row)
	_validation = Label.new()
	_validation.name = "ItemValidation"
	_validation.visible = false
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation.modulate = Color(1.0, 0.48, 0.42)
	add_child(_validation)
	var actions := HBoxContainer.new()
	add_child(actions)
	var save := Button.new()
	save.name = "SaveItem"
	save.text = "Сохранить предмет"
	save.disabled = not editable
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.tooltip_text = "Сохраняет res://content/items/<id>.tres одной Editor Undo/Redo operation."
	save.pressed.connect(_submit)
	actions.add_child(save)
	var cancel := Button.new()
	cancel.name = "CancelItem"
	cancel.text = "Закрыть"
	cancel.pressed.connect(cancel_requested.emit)
	actions.add_child(cancel)


func _add_owner_row(owner: String) -> void:
	var row := HBoxContainer.new()
	var source := Label.new()
	source.name = "ItemStorageOwner"
	source.text = "Godot Resource" if owner == "native" else "Legacy JSON"
	source.tooltip_text = Store.source_path(_current_id)
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source.modulate = Color(0.50, 0.82, 0.60) if owner == "native" else Color(0.90, 0.68, 0.36)
	row.add_child(source)
	var migrate := Button.new()
	migrate.name = "MigrateItemResource"
	migrate.text = "Уже .tres" if owner == "native" else "Перенести в .tres"
	migrate.disabled = owner != "legacy"
	migrate.tooltip_text = "Создаёт отдельный native Resource. Общий items/catalog.json не меняется; Ctrl+Z отменяет."
	migrate.pressed.connect(_request_migration)
	row.add_child(migrate)
	add_child(row)


func _add_icon_library(editable: bool) -> void:
	var row := _icon.get_parent() as HBoxContainer
	_icon_preview = TextureRect.new()
	_icon_preview.name = "ItemIconPreview"
	_icon_preview.custom_minimum_size = Vector2(42, 42)
	_icon_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(_icon_preview)
	var library := Button.new()
	library.name = "OpenItemIconLibrary"
	library.text = "Библиотека…"
	library.disabled = not editable
	library.tooltip_text = "Плитки с настоящим пиксельным превью, поиском по имени и iconId."
	library.pressed.connect(_open_icon_library)
	row.add_child(library)
	_icon.item_selected.connect(func(_index: int) -> void: _refresh_icon_preview())
	_refresh_icon_preview()


func _open_icon_library() -> void:
	if _icon_popup == null or not is_instance_valid(_icon_popup):
		_icon_popup = PopupPanel.new()
		_icon_popup.name = "ItemIconLibraryPopup"
		add_child(_icon_popup)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		_icon_popup.add_child(margin)
		_icon_picker = VisualLibraryPicker.new() as EmberVisualLibraryPicker
		margin.add_child(_icon_picker)
		_icon_picker.value_chosen.connect(_choose_icon)
	_icon_picker.setup("БИБЛИОТЕКА ИКОНОК", ItemVisuals.icon_entries(), _selected(_icon))
	_icon_popup.popup_centered(Vector2i(660, 530))


func _choose_icon(icon_id: String) -> void:
	_select_option(_icon, icon_id)
	_refresh_icon_preview()
	_icon_popup.hide()


func _refresh_icon_preview() -> void:
	if _icon_preview != null:
		_icon_preview.texture = ItemVisuals.icon_texture(_selected(_icon), 42)
		_icon_preview.tooltip_text = "iconId: %s" % (_selected(_icon) if not _selected(_icon).is_empty() else "—")


func _select_option(option: OptionButton, value: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return


func _line_row(node_name: String, label_text: String, tooltip: String) -> LineEdit:
	var row := _field_row(label_text)
	var input := LineEdit.new()
	input.name = node_name
	input.tooltip_text = tooltip
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	add_child(row)
	return input


func _option_row(
	node_name: String,
	label_text: String,
	values: Array,
	current: String,
	editable: bool,
	allow_empty := false,
) -> OptionButton:
	var row := _field_row(label_text)
	var option := OptionButton.new()
	option.name = node_name
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if allow_empty:
		option.add_item("— нет —")
		option.set_item_metadata(0, "")
	for raw_value in values:
		var value := str(raw_value)
		option.add_item(value)
		option.set_item_metadata(option.item_count - 1, value)
		if value == current:
			option.select(option.item_count - 1)
	option.disabled = not editable
	row.add_child(option)
	add_child(row)
	return option


func _number_row(
	node_name: String,
	label_text: String,
	value: float,
	minimum: float,
	maximum: float,
	editable: bool,
) -> SpinBox:
	var row := _field_row(label_text)
	var input := SpinBox.new()
	input.name = node_name
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1.0
	input.value = value
	input.editable = editable
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	add_child(row)
	return input


func _field_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 88.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	return row


func _document() -> Dictionary:
	var result := _base.duplicate(true)
	result.merge({
		"id": _id_input.text,
		"name": _english_input.text,
		"nameRu": _name_input.text,
		"kind": _selected(_kind),
		"slot": _selected(_slot),
		"rarity": _selected(_rarity),
		"stackMax": roundi(_stack.value),
		"useIn": _selected(_use_in),
		"iconId": _selected(_icon),
		"atk": roundi(_atk.value),
		"def": roundi(_defense.value),
		"hpRestore": roundi(_heal.value),
		"mpRestore": roundi(_mana.value),
		"reviveHp": roundi(_revive.value),
		"combatRange": roundi(_combat_range.value),
		"sellPrice": roundi(_sell_price.value),
		"unsellable": _unsellable.button_pressed,
		"tags": _tags.text.split(",", false),
		"notesRu": _notes.text,
	}, true)
	return Store.normalized_document(result)


func _selected(option: OptionButton) -> String:
	return "" if option == null or option.selected < 0 else str(option.get_item_metadata(option.selected))


func _string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(raw) == TYPE_ARRAY:
		for value in raw:
			result.append(str(value))
	return result


func _submit() -> void:
	var value := _document()
	var errors := Store.validation_errors(value)
	_validation.visible = not errors.is_empty()
	_validation.text = "\n".join(errors)
	if errors.is_empty():
		save_requested.emit(value)


func _request_migration() -> void:
	if Store.owner(_current_id) != "legacy":
		return
	migrate_requested.emit(_current_id)
	call_deferred("_reload_after_migration")


func _reload_after_migration() -> void:
	if Store.owner(_current_id) != "native":
		_validation.visible = true
		_validation.text = "Не удалось перенести предмет в Godot Resource."
		return
	for child in get_children():
		child.free()
	_base = Store.document(_current_id)
	_build()
