@tool
extends RefCounted
## One pair of catalog selectors, shared by the two existing quest authoring views.

static func add(parent: Container, value: Dictionary, changed: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "QuestPurchaseFields"
	parent.add_child(box)
	var shop_label := Label.new()
	shop_label.text = "Лавка"
	box.add_child(shop_label)
	var shop := OptionButton.new()
	shop.name = "PurchaseShop"
	shop.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	shop.add_item("Выбери лавку…")
	shop.set_item_metadata(0, "")
	for id in EmberShopCatalog.ids():
		shop.add_item(str(EmberShopCatalog.definition(id).get("nameRu", id)))
		shop.set_item_metadata(shop.item_count - 1, id)
	_select(shop, str(value.get("purchaseShopId", "")))
	box.add_child(shop)
	var item_label := Label.new()
	item_label.text = "Товар"
	box.add_child(item_label)
	var item := OptionButton.new()
	item.name = "PurchaseItem"
	item.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(item)
	var fill_items := func(selected: String) -> void:
		item.clear()
		item.add_item("Выбери товар…")
		item.set_item_metadata(0, "")
		var definition := EmberShopCatalog.definition(str(shop.get_selected_metadata()))
		for listing in definition.get("listings", []):
			var id := str(listing.get("itemId", ""))
			item.add_item(str(EmberItemCatalog.definition(id).get("nameRu", id)))
			item.set_item_metadata(item.item_count - 1, id)
		_select(item, selected)
	fill_items.call(str(value.get("purchaseItemId", "")))
	shop.item_selected.connect(func(_index: int) -> void:
		fill_items.call("")
		changed.call(str(shop.get_selected_metadata()), "")
	)
	item.item_selected.connect(func(_index: int) -> void:
		changed.call(str(shop.get_selected_metadata()), str(item.get_selected_metadata()))
	)
	var hint := Label.new()
	hint.text = "Только покупки после принятия квеста и открытия цели. Подбор и продажа не засчитываются."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	return box


static func _select(picker: OptionButton, id: String) -> void:
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == id:
			picker.select(index)
			return
	if not id.is_empty():
		picker.add_item("Недоступно · " + id)
		picker.set_item_metadata(picker.item_count - 1, id)
		picker.select(picker.item_count - 1)
