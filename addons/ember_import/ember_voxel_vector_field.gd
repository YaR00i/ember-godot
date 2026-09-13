@tool
extends VBoxContainer
## One canonical Vector3i parameter, presented as three independently editable axes.
signal value_changed(value: Vector3i)
var _value := Vector3i.ZERO
var _spins: Array[SpinBox] = []

func setup(low: int, high: int) -> void:
	for axis in 3:
		var row := HBoxContainer.new()
		add_child(row)
		var label := Label.new()
		label.text = ["Ширина X · vox", "Высота Y · vox", "Глубина Z · vox"][axis]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = low
		spin.max_value = high
		spin.step = 1
		row.add_child(spin)
		_spins.append(spin)
		spin.value_changed.connect(func(value: float) -> void:
			_value[axis] = int(value)
			value_changed.emit(_value)
		)

func set_axis_maximum(limits: Vector3i) -> void:
	for axis in 3:
		_spins[axis].set_block_signals(true)
		_spins[axis].max_value = limits[axis]
		_spins[axis].set_block_signals(false)


func set_vector_value(value: Vector3i) -> void:
	_value = value
	for axis in 3:
		_spins[axis].set_block_signals(true)
		_spins[axis].value = value[axis]
		_spins[axis].set_block_signals(false)
