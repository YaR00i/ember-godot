@tool
class_name EmberItemEditor
extends VBoxContainer
## Compact editor for one canonical item. It keeps the established Dictionary
## schema; all existing items are native Resources.

const Store = preload("res://addons/ember_import/ember_item_store.gd")
const ItemVisuals = preload("res://scripts/ember_item_visuals.gd")
const VisualLibraryPicker = preload("res://addons/ember_import/ember_visual_library_picker.gd")
const Equipment = preload("res://scripts/ember_equipment.gd")
const Party = preload("res://scripts/ember_party_state.gd")
const Units = preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const EquipmentPreview = preload("res://addons/ember_import/ember_equipment_preview.gd")
const OPTION_LABELS := {
	"material": "Материал", "consumable": "Расходник", "weapon_jrpg": "Оружие", "weapon_arena": "Старое оружие арены", "armor": "Броня", "shoes": "Обувь", "accessory": "Аксессуар", "key": "Ключевой предмет",
	"none": "Нет", "weapon": "Оружие", "head": "Старый головной убор", "body": "Броня",
	"common": "Обычная", "uncommon": "Необычная", "rare": "Редкая", "epic": "Эпическая",
	"explore": "Исследование", "arena": "Бой", "both": "Исследование и бой",
}

signal save_requested(document: Dictionary)
signal cancel_requested
signal document_changed(document: Dictionary, field_key: String)

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
var _combat_delay: SpinBox
var _hp_bonus: SpinBox
var _mp_bonus: SpinBox
var _allowed_heroes: LineEdit
var _type_hint: Label
var _equipment_fields: VBoxContainer
var _use_fields: VBoxContainer
var _unsellable: CheckBox
var _sell_price: SpinBox
var _tags: LineEdit
var _notes: TextEdit
var _validation: Label
var _preview_context := {}
var _properties: VBoxContainer
var _preview: VBoxContainer
var _preview_button: Button
var _properties_button: Button


func setup(item_id: String, suggested_id: String) -> void:
	name = "EmberItemEditor"
	_current_id = item_id.strip_edges()
	_suggested_id = suggested_id.strip_edges()
	_base = Store.document(_current_id)
	_build()


func setup_document(document: Dictionary, preview_context: Dictionary = {}) -> void:
	_current_id = str(document.get("id", ""))
	_base = document.duplicate(true)
	_preview_context = preview_context
	_build()


func _build() -> void:
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "ПРЕДМЕТ"
	title.modulate = Color(0.48, 0.84, 1.0)
	add_child(title)
	var existing := not _base.is_empty()
	var editable := true
	_id_input = _line_row("ItemId", "ID", "snake_case; после создания не переименовывается")
	_id_input.text = _current_id if existing else _suggested_id
	_id_input.editable = not existing
	_name_input = _line_row("ItemNameRu", "Название", "Показывается игроку")
	_name_input.text = str(_base.get("nameRu", "Новый предмет"))
	_name_input.editable = editable
	_english_input = _line_row("ItemName", "Внутреннее имя", "Английское имя; необязательно")
	_english_input.text = str(_base.get("name", ""))
	_english_input.editable = editable
	if existing:
		_add_owner_row()
	var kinds: Array = Store.KINDS.duplicate()
	if str(_base.get("kind", "")) in Store.LEGACY_KINDS: kinds.append(_base.kind)
	_kind = _option_row("ItemKind", "Тип", kinds, str(_base.get("kind", "material")), editable)
	_rarity = _option_row("ItemRarity", "Редкость", Store.RARITIES, str(_base.get("rarity", "common")), editable)
	_stack = _number_row("ItemStackMax", "В стопке", float(_base.get("stackMax", 1)), 1.0, 999.0, editable)
	_icon = _option_row("ItemIcon", "Иконка", Store.icon_ids(), str(_base.get("iconId", "")), editable, true)
	_add_icon_library(editable)
	_type_hint = Label.new()
	_type_hint.name = "ItemTypeHint"
	_type_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_type_hint)
	_equipment_fields = _section("ItemEquipmentFields", "ЭКИПИРОВКА")
	var slots: Array = Store.SLOTS.duplicate()
	if str(_base.get("slot", "")) == "head": slots.append("head")
	var current_slot := str(_base.get("slot", "none"))
	if current_slot == "body": current_slot = "armor"
	_slot = _option_row("ItemSlot", "Слот", slots, current_slot, editable)
	for index in _slot.item_count:
		_slot.set_item_disabled(index, str(_slot.get_item_metadata(index)) != "armor")
	_move_row(_slot, _equipment_fields)
	_atk = _number_row("ItemAtk", "Атака", float(_base.get("atk", 0)), 0.0, 9999.0, editable)
	_move_row(_atk, _equipment_fields)
	_defense = _number_row("ItemDef", "Защита", float(_base.get("def", 0)), 0.0, 9999.0, editable)
	_move_row(_defense, _equipment_fields)
	_hp_bonus = _number_row("ItemHpBonus", "Бонус max HP", float(_base.get("hpBonus", 0)), -9999.0, 9999.0, editable)
	_move_row(_hp_bonus, _equipment_fields)
	_mp_bonus = _number_row("ItemMpBonus", "Бонус max MP", float(_base.get("mpBonus", 0)), -9999.0, 9999.0, editable)
	_move_row(_mp_bonus, _equipment_fields)
	_allowed_heroes = _line_row("ItemAllowedHeroes", "Герои", "ID через запятую. Пусто — всем героям. Неизвестные ID сохраняются.")
	_allowed_heroes.text = ", ".join(_string_array(_base.get("allowedHeroIds", [])))
	_move_row(_allowed_heroes, _equipment_fields)
	var hero_hint := Label.new()
	hero_hint.name = "ItemHeroHint"
	hero_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var heroes: Array[String] = []
	var unit_names := {}
	for unit in Units.resources(): unit_names[unit.unit_id] = unit.display_name
	for hero_id in Party.HERO_IDS:
		heroes.append("%s: %s" % [hero_id, unit_names.get(hero_id, hero_id)])
	hero_hint.text = "Пустой список — всем. " + "; ".join(heroes)
	_equipment_fields.add_child(hero_hint)
	_use_fields = _section("ItemUseFields", "ПРИМЕНЕНИЕ РАСХОДНИКА")
	_use_in = _option_row("ItemUseIn", "Режим", Store.USE_TARGETS, str(_base.get("useIn", "explore")), editable)
	_move_row(_use_in, _use_fields)
	_heal = _number_row("ItemHpRestore", "Лечение", float(_base.get("hpRestore", 0)), 0.0, 9999.0, editable)
	_move_row(_heal, _use_fields)
	_mana = _number_row("ItemMpRestore", "Восстановление MP", float(_base.get("mpRestore", 0)), 0.0, 9999.0, editable)
	_move_row(_mana, _use_fields)
	_revive = _number_row("ItemReviveHp", "HP при воскрешении", float(_base.get("reviveHp", 0)), 0.0, 9999.0, editable)
	_move_row(_revive, _use_fields)
	_combat_range = _number_row("ItemCombatRange", "Дальность в бою", float(_base.get("combatRange", 1)), 0.0, 99.0, editable)
	_move_row(_combat_range, _use_fields)
	_combat_delay = _number_row("ItemCombatDelay", "Задержка в бою", float(_base.get("combatDelay", 100)), 1.0, 9999.0, editable)
	_move_row(_combat_delay, _use_fields)
	_section("ItemEconomyHeading", "ХРАНЕНИЕ И ОПИСАНИЕ")
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
	_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
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
	_kind.item_selected.connect(_kind_changed)
	_use_in.item_selected.connect(func(_index: int) -> void: _refresh_type_fields())
	_refresh_type_fields()
	_connect_changes(self)
	_install_preview(actions)


func _install_preview(actions: Control) -> void:
	_properties = VBoxContainer.new()
	_properties.name = "ItemProperties"
	_properties.add_theme_constant_override("separation", 6)
	for child in get_children():
		if child != actions and child != _validation:
			remove_child(child)
			_properties.add_child(child)
	var tabs := HBoxContainer.new()
	tabs.name = "ItemEditorViews"
	add_child(tabs)
	move_child(tabs, 0)
	_properties_button = Button.new()
	_properties_button.name = "ItemPropertiesView"
	_properties_button.text = "Свойства"
	_properties_button.toggle_mode = true
	_properties_button.pressed.connect(_show_preview.bind(false))
	tabs.add_child(_properties_button)
	_preview_button = Button.new()
	_preview_button.name = "ItemFittingView"
	_preview_button.text = "Примерка"
	_preview_button.toggle_mode = true
	_preview_button.pressed.connect(_show_preview.bind(true))
	tabs.add_child(_preview_button)
	add_child(_properties)
	move_child(_properties, 1)
	_preview = EquipmentPreview.new()
	add_child(_preview)
	move_child(_preview, 2)
	_preview.call("setup", _preview_context)
	_preview.call("set_document", _document())
	_refresh_type_fields()
	_show_preview(bool(_preview_context.get("preview", false)))


func _show_preview(show: bool) -> void:
	show = show and not _preview_button.disabled
	_preview_context["preview"] = show
	_properties.visible = not show
	_preview.visible = show
	_properties_button.set_pressed_no_signal(not show)
	_preview_button.set_pressed_no_signal(show)


func _section(node_name: String, title: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = node_name
	section.add_theme_constant_override("separation", 6)
	add_child(section)
	var heading := Label.new()
	heading.text = title
	heading.modulate = Color(0.70, 0.74, 0.82)
	section.add_child(heading)
	return section


func _move_row(control: Control, section: VBoxContainer) -> void:
	control.get_parent().reparent(section)


func _kind_changed(_index: int) -> void:
	# Keep inactive authored values. Armor alone needs an actual supported slot.
	var kind := _selected(_kind)
	if kind == "armor" and _selected(_slot) != "armor": _select_option(_slot, "armor")
	_refresh_type_fields()


func _refresh_type_fields() -> void:
	var kind := _selected(_kind)
	var gear := kind in ["weapon_jrpg", "armor", "shoes", "accessory"]
	_equipment_fields.visible = gear
	_slot.get_parent().visible = kind == "armor"
	_atk.get_parent().visible = kind in ["weapon_jrpg", "accessory"]
	_defense.get_parent().visible = kind in ["armor", "shoes", "accessory"]
	_allowed_heroes.get_parent().visible = kind != "accessory"
	(find_child("ItemHeroHint", true, false) as Label).visible = kind != "accessory"
	# Exploration already supports healing fields irrespective of kind. Retain access
	# to these legacy authored values rather than hiding a working use operation.
	_use_fields.visible = kind == "consumable" or _heal.value > 0 or _mana.value > 0 or _revive.value > 0
	var battle_use := _selected(_use_in) in ["arena", "both"] and kind == "consumable"
	_combat_range.get_parent().visible = battle_use
	_combat_delay.get_parent().visible = battle_use
	_type_hint.text = "Материал хранится в сумке; применение задаётся связанными игровыми действиями."
	if kind == "key": _type_hint.text = "Ключевой предмет хранится в сумке; его роль задаётся игровыми действиями и диалогами."
	elif kind == "consumable": _type_hint.text = "Восстанавливает HP/MP или воскрешает. Для боя ниже задаются дальность и задержка."
	elif gear:
		var slot := Equipment.slot_for_item({"kind": kind, "slot": _selected(_slot)})
		_type_hint.text = "Слот: %s. Бонусы HP/MP меняют максимум; отрицательные значения уменьшают его." % Equipment.SLOT_LABELS.get(slot, "выберите слот брони")
		if kind == "accessory": _type_hint.text += " Аксессуары доступны всем героям и занимают один из двух слотов."
	elif kind == "weapon_arena": _type_hint.text = "Старое оружие арены хранится в сумке. Для новой экипировки выберите актуальный тип."
	_type_hint.text += " Скрытые свойства сохраняются при смене типа."
	if _preview_button != null:
		_preview_button.disabled = not gear
		_preview_button.tooltip_text = "Выберите тип экипировки, чтобы примерить предмет." if not gear else "Сравнить показатели героя с текущим черновиком."
		if not gear: _show_preview(false)


func _connect_changes(node: Node) -> void:
	# A SpinBox owns a LineEdit; connect the SpinBox once, not its implementation children.
	if node is SpinBox:
		node.value_changed.connect(func(_value: float) -> void: _emit_changed(str(node.name)))
		return
	for child in node.get_children(): _connect_changes(child)
	if node is LineEdit: node.text_changed.connect(func(_text: String) -> void: _emit_changed(str(node.name)))
	elif node is TextEdit: node.text_changed.connect(_emit_changed.bind(str(node.name)))
	elif node is OptionButton: node.item_selected.connect(func(_index: int) -> void: _emit_changed(str(node.name)))
	elif node is CheckBox: node.toggled.connect(func(_checked: bool) -> void: _emit_changed(str(node.name)))


func _emit_changed(field_key: String) -> void:
	_refresh_type_fields()
	var document := _document()
	if _preview != null: _preview.call("set_document", document)
	document_changed.emit(document, field_key)


func _add_owner_row() -> void:
	var row := HBoxContainer.new()
	var source := Label.new()
	source.name = "ItemStorageOwner"
	source.text = "Godot Resource"
	source.tooltip_text = Store.source_path(_current_id)
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source.modulate = Color(0.50, 0.82, 0.60)
	row.add_child(source)
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
	_icon.item_selected.emit(_icon.selected)
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
		option.add_item(str(OPTION_LABELS.get(value, value)) if node_name != "ItemIcon" else value)
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
	input.min_value = minf(minimum, value)
	input.max_value = maxf(maximum, value)
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
	label.custom_minimum_size.x = 132.0
	label.size_flags_horizontal = Control.SIZE_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var optional_numbers := {"hpBonus": roundi(_hp_bonus.value), "mpBonus": roundi(_mp_bonus.value), "combatDelay": roundi(_combat_delay.value)}
	for key in optional_numbers:
		var value: int = optional_numbers[key]
		if _base.has(key) or value != (100 if key == "combatDelay" else 0): result[key] = value
	var allowed := _allowed_heroes.text.split(",", false)
	if _base.has("allowedHeroIds") or not allowed.is_empty(): result["allowedHeroIds"] = allowed
	return Store.normalized_document(result)


func _selected(option: OptionButton) -> String:
	return "" if option == null or option.selected < 0 else str(option.get_item_metadata(option.selected))


func _string_array(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(raw) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
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


func _reload_after_migration() -> void:
	if Store.owner(_current_id) != "native":
		_validation.visible = true
		_validation.text = "Не удалось перенести предмет в Godot Resource."
		return
	for child in get_children():
		child.free()
	_base = Store.document(_current_id)
	_build()
