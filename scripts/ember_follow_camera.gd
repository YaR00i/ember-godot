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

var target: Node3D
var _cam: Camera3D
var _applied_fov := -1.0
var _applied_near := -1.0
var _applied_far := -1.0


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


func _process(_dt: float) -> void:
	if target == null or _cam == null:
		return
	_apply_lens()
	var look := target.global_position + Vector3(0.0, look_height, 0.0)
	var polar := clampf(polar_angle, polar_min, polar_max)
	var dir := Vector3(
		sin(polar) * sin(yaw),
		cos(polar),
		sin(polar) * cos(yaw),
	)
	_cam.global_position = look + dir * follow_distance
	_cam.look_at(look)


func _apply_lens() -> void:
	if is_equal_approx(_applied_fov, fov) and is_equal_approx(_applied_near, cam_near) and is_equal_approx(_applied_far, cam_far):
		return
	_applied_fov = fov
	_applied_near = cam_near
	_applied_far = cam_far
	_cam.fov = fov
	_cam.near = cam_near
	_cam.far = cam_far
