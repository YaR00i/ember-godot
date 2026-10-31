@tool
extends VBoxContainer
## One item/count picker for container contents and authored inventory exchanges.
var _rows: VBoxContainer
var _excluded := ""

func setup(counts: Dictionary, title := "Предметы", excluded := "") -> void:
	_excluded = excluded
	var label := Label.new(); label.text = title; add_child(label)
	_rows = VBoxContainer.new(); add_child(_rows)
	for id in counts: add_row(str(id),int(counts[id]))
	var add := Button.new(); add.text = "+ Предмет"; add_child(add)
	add.pressed.connect(func() -> void: add_row("",1))

func add_row(id: String, count: int) -> void:
	var row := HBoxContainer.new(); _rows.add_child(row)
	var picker := OptionButton.new(); picker.name = "Item"; picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.add_item("Выберите предмет…"); picker.set_item_metadata(0,"")
	for target in EmberItemCatalog.ids():
		if target == _excluded: continue
		picker.add_item(str(EmberItemCatalog.definition(target).get("nameRu",target)))
		picker.set_item_metadata(picker.item_count-1,target)
		if target == id: picker.select(picker.item_count-1)
	row.add_child(picker)
	var amount := SpinBox.new(); amount.name = "Count"; amount.min_value = 1; amount.max_value = 999; amount.value = count; row.add_child(amount)
	var remove := Button.new(); remove.text = "Убрать"; row.add_child(remove)
	remove.pressed.connect(func() -> void: _rows.remove_child(row); row.queue_free())

func value() -> Dictionary:
	var result := {}
	for row in _rows.get_children():
		var picker: OptionButton = row.get_node("Item")
		var id := str(picker.get_item_metadata(picker.selected))
		result[id] = int(result.get(id,0))+int(row.get_node("Count").value)
	return result

func set_value(counts: Dictionary) -> void:
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	for id in counts:
		add_row(str(id), int(counts[id]))
