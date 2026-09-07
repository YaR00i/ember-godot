@tool
class_name EmberTypedValueEditor
extends VBoxContainer
## Shared guided bool/string/number input for action and dialogue flags.

signal value_changed(value: Variant)

var _prefix := "TypedValue"
var _type: OptionButton
var _bool_value: OptionButton
var _input: LineEdit


func setup(current: Variant, prefix := "TypedValue") -> void:
	_prefix = prefix
	add_theme_constant_override("separation", 3)
	var type_row := _row("Тип значения")
	_type = OptionButton.new()
	_type.name = "%s_type" % prefix
	for data in [["Да/Нет", "bool"], ["Текст", "string"], ["Число", "number"]]:
		_type.add_item(data[0])
		_type.set_item_metadata(_type.item_count - 1, data[1])
	_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(_type)
	add_child(type_row)
	var value_row := _row("Значение")
	_bool_value = OptionButton.new()
	_bool_value.name = "%s_bool" % prefix
	_bool_value.add_item("Да (true)")
	_bool_value.set_item_metadata(0, true)
	_bool_value.add_item("Нет (false)")
	_bool_value.set_item_metadata(1, false)
	_bool_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_row.add_child(_bool_value)
	_input = LineEdit.new()
	_input.name = prefix
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_row.add_child(_input)
	add_child(value_row)
	match typeof(current):
		TYPE_BOOL:
			_type.select(0)
			_bool_value.select(0 if current else 1)
		TYPE_INT, TYPE_FLOAT:
			_type.select(2)
			_input.text = str(current)
		_:
			_type.select(1)
			_input.text = str(current)
	_type.item_selected.connect(_on_type_selected)
	_bool_value.item_selected.connect(func(_index: int) -> void: value_changed.emit(value()))
	_input.text_changed.connect(func(_text: String) -> void: value_changed.emit(value()))
	_sync()


func value() -> Variant:
	var type_id := str(_type.get_item_metadata(_type.selected)) if _type != null else "string"
	match type_id:
		"bool":
			return true if _bool_value == null or _bool_value.selected < 0 else bool(_bool_value.get_item_metadata(_bool_value.selected))
		"number":
			return float(_input.text) if _input != null else 0.0
	return _input.text if _input != null else ""


func _sync() -> void:
	if _type == null:
		return
	var type_id := str(_type.get_item_metadata(_type.selected))
	_bool_value.visible = type_id == "bool"
	_input.visible = type_id != "bool"
	_input.placeholder_text = "например: west" if type_id == "string" else "например: 3"


func _on_type_selected(_index: int) -> void:
	_sync()
	value_changed.emit(value())


func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 88.0
	label.modulate = Color(0.72, 0.72, 0.75)
	row.add_child(label)
	return row
