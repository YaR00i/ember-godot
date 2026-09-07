@tool
class_name EmberShopEditor
extends VBoxContainer
## Compact editor for one canonical shop definition. Legacy catalog entries are
## visible but locked until the explicit per-shop Resource migration.

const Store = preload("res://addons/ember_import/ember_shop_store.gd")
const ItemStore = preload("res://addons/ember_import/ember_item_store.gd")
const ItemEditor = preload("res://addons/ember_import/ember_item_editor.gd")
const ItemVisuals = preload("res://scripts/ember_item_visuals.gd")
const VisualLibraryPicker = preload("res://addons/ember_import/ember_visual_library_picker.gd")

signal save_requested(document: Dictionary)
signal migrate_requested(shop_id: String)
signal item_save_requested(document: Dictionary)
signal item_migrate_requested(item_id: String)
signal cancel_requested

var _current_id := ""
var _suggested_id := ""
var _base: Dictionary = {}
var _id_input: LineEdit
var _name_input: LineEdit
var _listings: VBoxContainer
var _validation: Label
var _save: Button
var _item_popup: PopupPanel
var _item_picker: EmberVisualLibraryPicker
var _library_option: OptionButton
var _library_preview: TextureRect


func setup(shop_id: String, suggested_id: String) -> void:
	name = "EmberShopEditor"
	_current_id = shop_id.strip_edges()
	_suggested_id = suggested_id.strip_edges()
	_base = Store.document(_current_id)
	_build()


func _build() -> void:
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "МАГАЗИН"
	title.modulate = Color(0.96, 0.72, 0.32)
	add_child(title)
	var existing := not _base.is_empty()
	var owner := Store.owner(_current_id)
	var editable := not existing or owner == "native"
	_id_input = _line_row("ShopId", "ID", "snake_case; после создания не переименовывается")
	_id_input.text = _current_id if existing else _suggested_id
	_id_input.editable = not existing
	_name_input = _line_row("ShopName", "Название", "Показывается игроку")
	_name_input.text = str(_base.get("nameRu", "Новый магазин"))
	_name_input.editable = editable
	if existing:
		_add_owner_row(owner)
	if owner == "legacy":
		var hint := Label.new()
		hint.text = "Legacy catalog доступен только для чтения. Перенеси этот магазин в .tres, затем редактируй ассортимент."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.modulate = Color(0.90, 0.68, 0.36)
		add_child(hint)
	_listings = VBoxContainer.new()
	_listings.name = "ShopListings"
	_listings.add_theme_constant_override("separation", 5)
	add_child(_listings)
	var raw_listings: Variant = _base.get("listings", [])
	if typeof(raw_listings) == TYPE_ARRAY:
		for raw_listing in raw_listings:
			if typeof(raw_listing) == TYPE_DICTIONARY:
				_add_listing(raw_listing, editable)
	var add := Button.new()
	add.name = "AddShopListing"
	add.text = "+ Товар"
	add.disabled = not editable
	add.pressed.connect(_add_listing.bind({}, true))
	add_child(add)
	_validation = Label.new()
	_validation.name = "ShopValidation"
	_validation.visible = false
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation.modulate = Color(1.0, 0.48, 0.42)
	add_child(_validation)
	var actions := HBoxContainer.new()
	add_child(actions)
	_save = Button.new()
	_save.name = "SaveShop"
	_save.text = "Сохранить магазин"
	_save.disabled = not editable
	_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save.tooltip_text = "Сохраняет res://content/shops/<id>.tres одной Editor Undo/Redo operation."
	_save.pressed.connect(_submit)
	actions.add_child(_save)
	var cancel := Button.new()
	cancel.name = "CancelShop"
	cancel.text = "Закрыть"
	cancel.pressed.connect(cancel_requested.emit)
	actions.add_child(cancel)
	_reindex()


func _add_owner_row(owner: String) -> void:
	var row := HBoxContainer.new()
	var source := Label.new()
	source.name = "ShopStorageOwner"
	source.text = "Godot Resource" if owner == "native" else "Legacy JSON"
	source.tooltip_text = Store.source_path(_current_id)
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source.modulate = Color(0.50, 0.82, 0.60) if owner == "native" else Color(0.90, 0.68, 0.36)
	row.add_child(source)
	var migrate := Button.new()
	migrate.name = "MigrateShopResource"
	migrate.text = "Уже .tres" if owner == "native" else "Перенести в .tres"
	migrate.disabled = owner != "legacy"
	migrate.tooltip_text = "Создаёт отдельный native Resource. Общий shops/catalog.json не меняется; Ctrl+Z отменяет."
	migrate.pressed.connect(_request_migration)
	row.add_child(migrate)
	add_child(row)


func _add_listing(raw: Dictionary = {}, editable: bool = true) -> void:
	var listing := raw.duplicate(true)
	var panel := PanelContainer.new()
	panel.name = "ShopListing"
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	panel.add_child(body)
	var head := HBoxContainer.new()
	body.add_child(head)
	var caption := Label.new()
	caption.name = "ShopListingCaption"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(caption)
	for spec in [["↑", -1], ["↓", 1]]:
		var move := Button.new()
		move.text = str(spec[0])
		move.disabled = not editable
		move.pressed.connect(_move_listing.bind(panel, int(spec[1])))
		head.add_child(move)
	var remove := Button.new()
	remove.text = "×"
	remove.disabled = not editable
	remove.modulate = Color(1.0, 0.62, 0.58)
	remove.pressed.connect(_remove_listing.bind(panel))
	head.add_child(remove)
	var item_row := _field_row("Предмет")
	var item := OptionButton.new()
	item.name = "ShopItem"
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.add_item("— выберите —")
	item.set_item_metadata(0, "")
	var current_item := str(listing.get("itemId", ""))
	for item_id in EmberInteractionContent.item_ids():
		item.add_item(ItemVisuals.item_label(item_id))
		item.set_item_metadata(item.item_count - 1, item_id)
		if item_id == current_item:
			item.select(item.item_count - 1)
	item.disabled = not editable
	item_row.add_child(item)
	var preview := TextureRect.new()
	preview.name = "ShopItemPreview"
	preview.custom_minimum_size = Vector2(42, 42)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	item_row.add_child(preview)
	var library := Button.new()
	library.name = "ShopItemLibrary"
	library.text = "Библиотека…"
	library.disabled = not editable
	library.tooltip_text = "Визуальный каталог предметов с иконками, названиями и поиском."
	library.pressed.connect(_open_item_library.bind(item, preview))
	item_row.add_child(library)
	var edit_item := Button.new()
	edit_item.name = "EditShopItem"
	edit_item.text = "Предмет…"
	edit_item.disabled = not editable
	edit_item.tooltip_text = "Создать или отредактировать выбранный предмет без выхода из магазина."
	item_row.add_child(edit_item)
	item.item_selected.connect(func(_index: int) -> void: _refresh_item_preview(item, preview))
	_refresh_item_preview(item, preview)
	body.add_child(item_row)
	var item_holder := VBoxContainer.new()
	item_holder.name = "ItemEditorHolder"
	item_holder.visible = false
	body.add_child(item_holder)
	edit_item.pressed.connect(_toggle_item_editor.bind(item_holder, edit_item, item))
	body.add_child(_number_row("ShopBuyPrice", "Покупка", float(listing.get("buyPrice", 0)), editable))
	body.add_child(_number_row("ShopSellPrice", "Продажа", float(listing.get("sellPrice", 0)), editable))
	var stock_row := _field_row("Запас")
	var finite := CheckBox.new()
	finite.name = "ShopFiniteStock"
	finite.text = "Ограничен"
	finite.button_pressed = listing.has("stock")
	finite.disabled = not editable
	stock_row.add_child(finite)
	var stock := SpinBox.new()
	stock.name = "ShopStock"
	stock.min_value = 0.0
	stock.max_value = 9999.0
	stock.step = 1.0
	stock.value = float(listing.get("stock", 0))
	stock.editable = editable and finite.button_pressed
	stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_row.add_child(stock)
	finite.toggled.connect(func(enabled: bool) -> void: stock.editable = editable and enabled)
	body.add_child(stock_row)
	_listings.add_child(panel)
	_reindex()


func _line_row(node_name: String, label_text: String, tooltip: String) -> LineEdit:
	var row := _field_row(label_text)
	var input := LineEdit.new()
	input.name = node_name
	input.tooltip_text = tooltip
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	add_child(row)
	return input


func _number_row(node_name: String, label_text: String, value: float, editable: bool) -> Control:
	var row := _field_row(label_text)
	var input := SpinBox.new()
	input.name = node_name
	input.min_value = 0.0
	input.max_value = 999999.0
	input.step = 1.0
	input.value = value
	input.editable = editable
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	return row


func _field_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 88.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	return row


func _move_listing(panel: PanelContainer, delta: int) -> void:
	_listings.move_child(panel, clampi(panel.get_index() + delta, 0, _listings.get_child_count() - 1))
	_reindex()


func _remove_listing(panel: PanelContainer) -> void:
	_listings.remove_child(panel)
	panel.queue_free()
	_reindex()


func _toggle_item_editor(holder: VBoxContainer, button: Button, option: OptionButton) -> void:
	if holder.get_child_count() == 0:
		var item_id := _selected_metadata(option)
		var editable_id := item_id if ItemStore.exists(item_id) else ""
		var source_id := _id_input.text if _id_input != null else "shop"
		var editor := ItemEditor.new() as EmberItemEditor
		editor.setup(editable_id, ItemStore.suggested_id(source_id))
		editor.save_requested.connect(_on_item_save.bind(holder, button, option))
		editor.migrate_requested.connect(item_migrate_requested.emit)
		editor.cancel_requested.connect(_dismiss_item_editor.bind(holder, button))
		holder.add_child(editor)
		holder.visible = true
	else:
		holder.visible = not holder.visible
	button.text = "Скрыть" if holder.visible else "Предмет…"


func _on_item_save(document: Dictionary, holder: VBoxContainer, button: Button, option: OptionButton) -> void:
	item_save_requested.emit(document)
	_select_item(option, str(document.get("id", "")))
	var preview := option.get_parent().find_child("ShopItemPreview", false, false) as TextureRect
	_refresh_item_preview(option, preview)
	_dismiss_item_editor(holder, button)


func _dismiss_item_editor(holder: VBoxContainer, button: Button) -> void:
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()
	holder.visible = false
	button.text = "Предмет…"


func _select_item(option: OptionButton, item_id: String) -> void:
	option.clear()
	option.add_item("— выберите —")
	option.set_item_metadata(0, "")
	var ids := EmberInteractionContent.item_ids()
	if not item_id.is_empty() and item_id not in ids:
		ids.append(item_id)
		ids.sort()
	for known_id in ids:
		option.add_item(ItemVisuals.item_label(known_id))
		option.set_item_metadata(option.item_count - 1, known_id)
		if known_id == item_id:
			option.select(option.item_count - 1)


func _open_item_library(option: OptionButton, preview: TextureRect) -> void:
	_library_option = option
	_library_preview = preview
	if _item_popup == null or not is_instance_valid(_item_popup):
		_item_popup = PopupPanel.new()
		_item_popup.name = "ShopItemLibraryPopup"
		add_child(_item_popup)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_right", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		_item_popup.add_child(margin)
		_item_picker = VisualLibraryPicker.new() as EmberVisualLibraryPicker
		margin.add_child(_item_picker)
		_item_picker.value_chosen.connect(_choose_library_item)
	_item_picker.setup("БИБЛИОТЕКА ПРЕДМЕТОВ", ItemVisuals.item_entries(), _selected_metadata(option))
	_item_popup.popup_centered(Vector2i(660, 530))


func _choose_library_item(item_id: String) -> void:
	if _library_option == null:
		return
	_select_item(_library_option, item_id)
	_refresh_item_preview(_library_option, _library_preview)
	_item_popup.hide()


func _refresh_item_preview(option: OptionButton, preview: TextureRect) -> void:
	if preview == null:
		return
	var item_id := _selected_metadata(option)
	preview.texture = ItemVisuals.item_texture(item_id, 42)
	preview.tooltip_text = ItemVisuals.item_label(item_id) if not item_id.is_empty() else "Предмет не выбран"


func _selected_metadata(option: OptionButton) -> String:
	return "" if option == null or option.selected < 0 else str(option.get_item_metadata(option.selected))


func _reindex() -> void:
	if _listings == null:
		return
	for index in _listings.get_child_count():
		var caption := _listings.get_child(index).find_child("ShopListingCaption", true, false) as Label
		if caption != null:
			caption.text = "%d. Товар" % (index + 1)


func _document() -> Dictionary:
	var listings: Array[Dictionary] = []
	for child in _listings.get_children():
		var panel := child as PanelContainer
		var item := panel.find_child("ShopItem", true, false) as OptionButton
		var buy := panel.find_child("ShopBuyPrice", true, false) as SpinBox
		var sell := panel.find_child("ShopSellPrice", true, false) as SpinBox
		var finite := panel.find_child("ShopFiniteStock", true, false) as CheckBox
		var stock := panel.find_child("ShopStock", true, false) as SpinBox
		var listing := {
			"itemId": "" if item.selected < 0 else str(item.get_item_metadata(item.selected)),
			"buyPrice": roundi(buy.value),
			"sellPrice": roundi(sell.value),
		}
		if finite.button_pressed:
			listing["stock"] = roundi(stock.value)
		listings.append(listing)
	return Store.normalized_document({
		"id": _id_input.text,
		"nameRu": _name_input.text,
		"listings": listings,
	})


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
		_validation.text = "Не удалось перенести магазин в Godot Resource."
		return
	for child in get_children():
		child.free()
	_base = Store.document(_current_id)
	_build()
