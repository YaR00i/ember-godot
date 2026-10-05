extends Node
## Presentation only: the Map and authored Environment own every setting.


func _ready() -> void:
	var map := get_parent().get_node("Map") as EmberMapLoader
	var environment: Environment = map.get_node("Look/WorldEnvironment").environment
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 82)
	panel.custom_minimum_size.x = 285
	layer.add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	var title := Label.new()
	title.text = "Сравнение света материалов"
	rows.add_child(title)
	var choice := OptionButton.new()
	for caption in ["Прежний свет", "Естественный мультяшный", "Игрушечный пластик"]:
		choice.add_item(caption)
	choice.select(map.compact_material_light_mode)
	rows.add_child(choice)
	choice.item_selected.connect(func(index: int): map.compact_material_light_mode = index)
	var gray := CheckBox.new()
	gray.text = "Один серый цвет"
	gray.button_pressed = map.compact_material_gray_preview
	rows.add_child(gray)
	gray.toggled.connect(func(value: bool): map.compact_material_gray_preview = value)
	var contact := CheckBox.new()
	contact.text = "Затемнение в стыках"
	contact.button_pressed = environment.ssao_enabled
	rows.add_child(contact)
	contact.toggled.connect(func(value: bool): environment.ssao_enabled = value)
	var hint := Label.new()
	hint.text = "Сохранение — в редакторе:\nВид мира → Материалы → Ctrl+S.\nСолнце меняется в панели справа."
	rows.add_child(hint)
