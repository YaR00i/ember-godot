class_name EmberFollowCamera
extends Node3D
## Play follow camera. Same fields as JOI `emberCamera.ts` (iso JRPG).

@export var fov := 40.0
@export var follow_distance := 120.0
@export var polar_angle := 0.95
@export var yaw := 0.785398
@export var look_height := 6.0
@export var pitch_lock := true
@export var polar_min := 0.35
@export var polar_max := 1.35
@export var mouse_sensitivity := 1.0
@export var cam_near := 1.0
@export var cam_far := 5000.0
## Only upward height changes lag; horizontal follow and descent stay direct.
@export var ascent_response := 8.0

var target: Node3D
var _cam: Camera3D
var _applied_fov := -1.0
var _applied_near := -1.0
var _applied_far := -1.0
var _height_initialized := false
var _follow_height := 0.0
var _last_target_position := Vector3.ZERO
var _height_target: Node3D


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.current = true
	add_to_group("ember_follow_camera")
	add_child(_cam)
	_apply_lens()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.005 * mouse_sensitivity
		if not pitch_lock:
			polar_angle = clampf(
				polar_angle + event.relative.y * 0.005 * mouse_sensitivity,
				polar_min,
				polar_max,
			)


func _process(dt: float) -> void:
	if not is_instance_valid(target) or _cam == null:
		return
	_apply_lens()
	var look := target.global_position + Vector3(0.0, look_height, 0.0)
	var moved_down := _height_initialized and target.global_position.y < _last_target_position.y - 0.0001
	var teleported := _height_initialized and target.global_position.distance_to(_last_target_position) > follow_distance * 0.25
	if not _height_initialized or target != _height_target or teleported:
		_follow_height = look.y
		_height_initialized = true
	elif moved_down:
		# Follow descent directly without suddenly erasing an unfinished ascent
		# lag (including tiny capsule recovery corrections on the upper tread).
		_follow_height = minf(look.y, _follow_height + target.global_position.y - _last_target_position.y)
	elif look.y > _follow_height:
		_follow_height = lerpf(_follow_height, look.y, 1.0 - exp(-ascent_response * maxf(dt, 0.0)))
		if look.y - _follow_height < 0.0001:
			_follow_height = look.y
	else:
		_follow_height = look.y
	_height_target = target
	_last_target_position = target.global_position
	look.y = _follow_height
	var polar := clampf(polar_angle, polar_min, polar_max)
	var dir := Vector3(
		sin(polar) * sin(yaw),
		cos(polar),
		sin(polar) * cos(yaw),
	)
	_cam.global_position = look + dir * follow_distance
	_cam.look_at(look)


func reset_follow_height() -> void:
	_height_initialized = false


func _apply_lens() -> void:
	if is_equal_approx(_applied_fov, fov) and is_equal_approx(_applied_near, cam_near) and is_equal_approx(_applied_far, cam_far):
		return
	_applied_fov = fov
	_applied_near = cam_near
	_applied_far = cam_far
	_cam.fov = fov
	_cam.near = cam_near
	_cam.far = cam_far
