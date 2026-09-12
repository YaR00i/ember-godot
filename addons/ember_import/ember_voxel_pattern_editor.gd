@tool
extends Control
## Small binary-mask editor. The voxel Resource remains the serialized geometry owner.

signal pattern_changed

var pattern_size := Vector2i(8,8)
var drawing := true
var _mask := PackedByteArray()
var _painting := false
var _paint_value := 1


func _init() -> void:
	custom_minimum_size = Vector2(176,176)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_pattern_size(pattern_size)


func set_pattern_size(value: Vector2i) -> void:
	var next_size := Vector2i(clampi(value.x,1,16),clampi(value.y,1,16))
	var next_mask := PackedByteArray()
	next_mask.resize(next_size.x*next_size.y)
	for y in mini(pattern_size.y,next_size.y):
		for x in mini(pattern_size.x,next_size.x):
			if x+y*pattern_size.x < _mask.size():
				next_mask[x+y*next_size.x] = _mask[x+y*pattern_size.x]
	pattern_size = next_size
	_mask = next_mask
	queue_redraw()
	pattern_changed.emit()


func set_mask(value: PackedByteArray) -> void:
	_mask.resize(pattern_size.x*pattern_size.y)
	_mask.fill(0)
	for index in mini(value.size(),_mask.size()):
		_mask[index] = 1 if value[index] != 0 else 0
	queue_redraw()
	pattern_changed.emit()


func mask() -> PackedByteArray:
	return _mask.duplicate()


func clear() -> void:
	_mask.fill(0)
	queue_redraw()
	pattern_changed.emit()


func _cell_at(point: Vector2) -> Vector2i:
	var side := minf(size.x/float(pattern_size.x),size.y/float(pattern_size.y))
	var drawing_size := Vector2(pattern_size)*side
	var origin := (size-drawing_size)*0.5
	var local := point-origin
	if local.x < 0 or local.y < 0 or local.x >= drawing_size.x or local.y >= drawing_size.y:
		return Vector2i(-1,-1)
	return Vector2i(floori(local.x/side),floori(local.y/side))


func paint_at(point: Vector2, value: int) -> bool:
	var cell := _cell_at(point)
	if cell.x < 0:
		return false
	var index := cell.x+cell.y*pattern_size.x
	var normalized := 1 if value != 0 else 0
	if _mask[index] == normalized:
		return false
	_mask[index] = normalized
	queue_redraw()
	pattern_changed.emit()
	return true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		_painting = event.pressed
		_paint_value = 0 if event.button_index == MOUSE_BUTTON_RIGHT else (1 if drawing else 0)
		if event.pressed:
			paint_at(event.position,_paint_value)
			accept_event()
	elif event is InputEventMouseMotion and _painting:
		paint_at(event.position,_paint_value)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("0f171f"),true)
	var side := minf(size.x/float(pattern_size.x),size.y/float(pattern_size.y))
	var drawing_size := Vector2(pattern_size)*side
	var origin := (size-drawing_size)*0.5
	for y in pattern_size.y:
		for x in pattern_size.x:
			var rect := Rect2(origin+Vector2(x,y)*side,Vector2.ONE*side)
			var filled := _mask[x+y*pattern_size.x] != 0
			draw_rect(rect,Color("d98b2b") if filled else Color("18232d"),true)
			draw_rect(rect,Color("f0b24f") if filled else Color("344655"),false,1.0)
