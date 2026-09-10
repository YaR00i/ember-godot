@tool
extends VBoxContainer
## View state only. Workspace owns gesture finalization and preview scheduling.
signal change_requested(enabled: bool, height: int)
var _enabled: CheckButton
var _height: SpinBox


func _init() -> void:
	name = "SurfaceHeightSlice"
	_enabled = CheckButton.new()
	_enabled.name = "EnableHeightSlice"
	_enabled.text = "Срез по высоте"
	_enabled.tooltip_text = "Скрыть верх и защитить его от кистей. 1 vox — нижний слой; вода скрыта. Файл и игровой вид остаются полными."
	add_child(_enabled)
	_height = SpinBox.new()
	_height.name = "HeightSliceLevel"
	_height.prefix = "Видно снизу"
	_height.suffix = "vox"
	_height.min_value = 1
	_height.step = 1
	_height.editable = false
	add_child(_height)
	_enabled.toggled.connect(func(enabled: bool) -> void:
		_height.editable = enabled
		change_requested.emit(enabled, int(_height.value))
	)
	_height.value_changed.connect(func(value: float) -> void:
		if _enabled.button_pressed:
			change_requested.emit(true, int(value))
	)


func configure(height: int) -> void:
	_enabled.set_pressed_no_signal(false)
	_height.set_block_signals(true)
	_height.max_value = maxi(1, height)
	_height.value = maxi(1, height)
	_height.set_block_signals(false)
	_height.editable = false


func restore_view(slice_height: int) -> void:
	var enabled := slice_height >= 1
	_enabled.set_pressed_no_signal(enabled)
	_height.set_block_signals(true)
	_height.value = clampi(slice_height, 1, int(_height.max_value)) if enabled else int(_height.max_value)
	_height.set_block_signals(false)
	_height.editable = enabled
