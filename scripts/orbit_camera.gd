class_name OrbitCamera
extends Node3D
## Look-only orbit. Not play WASD.

@export var distance := 48.0
@export var yaw := 0.6
@export var pitch := 0.55
@export var target := Vector3.ZERO
@export var min_distance := 8.0
@export var max_distance := 220.0

var _cam: Camera3D


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 40.0
	_cam.near = 0.2
	_cam.far = 2000.0
	add_child(_cam)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch - event.relative.y * 0.005, 0.12, 1.45)
		_apply()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clampf(distance * 0.9, min_distance, max_distance)
			_apply()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clampf(distance * 1.1, min_distance, max_distance)
			_apply()


func _apply() -> void:
	if _cam == null:
		return
	var dir := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw),
	)
	_cam.position = target + dir * distance
	_cam.look_at(target)
