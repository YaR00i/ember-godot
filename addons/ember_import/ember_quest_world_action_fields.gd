@tool
extends RefCounted
## Shared controls for both existing quest forms. No progress writes here.
const WorldActions = preload("res://scripts/ember_quest_world_actions.gd")

static func add(parent: Container, value: Dictionary, changed: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "QuestWorldActionFields"
	parent.add_child(box)
	var action := OptionButton.new()
	action.name = "WorldAction"
	action.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	action.add_item("Выбери действие…")
	action.set_item_metadata(0, "")
	for id in WorldActions.LABELS:
		action.add_item(WorldActions.LABELS[id])
		action.set_item_metadata(action.item_count - 1, id)
	_select(action, str(value.get("worldAction", "")))
	box.add_child(action)
	var target := OptionButton.new()
	target.name = "WorldActionTarget"
	target.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	box.add_child(target)
	var fill := func(selected: String) -> void:
		target.clear()
		var kind := str(action.get_selected_metadata())
		target.add_item("Выбери рецепт…" if kind == "craft" else "Выбери предмет…")
		target.set_item_metadata(0, "")
		var targets := WorldActions.targets(kind)
		for id in targets:
			target.add_item(str(targets[id]))
			target.set_item_metadata(target.item_count - 1, id)
		_select(target, selected)
		target.visible = kind in ["destroy", "collect", "craft"]
	fill.call(str(value.get("worldTargetId", "")))
	action.item_selected.connect(func(_index: int) -> void:
		fill.call("")
		changed.call(str(action.get_selected_metadata()), "")
	)
	target.item_selected.connect(func(_index: int) -> void:
		changed.call(str(action.get_selected_metadata()), str(target.get_selected_metadata()))
	)
	var hint := Label.new()
	hint.text = "Считаются успешные действия после открытия цели. Сбор — подбор в мире и ягоды с куста; покупки, награды и собственные выброшенные предметы не считаются. Крафт — число выполнений рецепта. Трава — интерактивные пучки."
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
