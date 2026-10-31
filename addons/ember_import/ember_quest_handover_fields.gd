@tool
extends RefCounted

static func add(parent: Container, value: Dictionary, changed: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "QuestHandoverFields"
	parent.add_child(box)
	var label := Label.new()
	label.text = "Предмет для сдачи NPC"
	box.add_child(label)
	var picker := OptionButton.new()
	picker.name = "HandoverItem"
	picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	picker.add_item("Выбери предмет…")
	picker.set_item_metadata(0, "")
	var current := str(value.get("handoverItemId", ""))
	var found := current.is_empty()
	for id in EmberItemCatalog.native_ids():
		picker.add_item(str(EmberItemCatalog.definition(id).get("nameRu", id)))
		picker.set_item_metadata(picker.item_count - 1, id)
		if current == id:
			found = true
			picker.select(picker.item_count - 1)
	if not found:
		picker.add_item("Недоступно · " + current)
		picker.set_item_metadata(picker.item_count - 1, current)
		picker.select(picker.item_count - 1)
	box.add_child(picker)
	picker.item_selected.connect(func(_index: int) -> void: changed.call(str(picker.get_selected_metadata())))
	var hint := Label.new()
	hint.text = "Счётчик показывает содержимое сумки. Цель завершится только после передачи. NPC и реплика назначаются в карточке Ember Graph."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	box.add_child(hint)
	return box
