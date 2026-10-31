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
var wing_flight_view := false
var flight_framing_scale := 1.0
var _flight_lens_active := false
var _flight_fov := 72.0
var _flight_initialized := false
var _flight_orientation := Quaternion.IDENTITY
var _flight_offset := Vector3(0, 2.4, 10)
var _flight_last_position := Vector3.ZERO
var _flight_orbit := Vector2.ZERO
var _flight_mouse_orbit := Vector2.ZERO
const FLIGHT_TUNING := {
	"lag_seconds": Vector4(0.04, 0.65, 0.01, 0.14),
	"lag_angle_deg": Vector4(0, 35, 1, 14),
	"push_shift": Vector4(0, 4, 0.1, 1.5),
	"pull_shift": Vector4(0, 4, 0.1, 1.8),
	"return_seconds": Vector4(0.1, 1.2, 0.05, 0.285),
	"speed_fov": Vector4(0, 25, 1, 14),
	"look_angle_deg": Vector4(30, 130, 5, 100),
}
var flight_tuning := flight_defaults()

static func flight_defaults() -> Dictionary:
	var values := {}
	for key in FLIGHT_TUNING:
		values[key] = FLIGHT_TUNING[key].w
	return values

static func sanitize_flight(values: Dictionary) -> Dictionary:
	var result := flight_defaults()
	for key in FLIGHT_TUNING:
		var value: Variant = values.get(key)
		if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)):
			result[key] = clampf(float(value), FLIGHT_TUNING[key].x, FLIGHT_TUNING[key].y)
	return result

func configure_flight(values: Dictionary) -> void:
	flight_tuning = sanitize_flight(values)



func _ready() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.current = true
	add_to_group("ember_follow_camera")
	add_child(_cam)
	_apply_lens()


func _unhandled_input(event: InputEvent) -> void:
	if wing_flight_view:
		if target is EmberPlayer and target.is_physics_processing() and event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_flight_mouse_orbit += event.relative * 0.004
			var limit := Vector2(deg_to_rad(flight_tuning.look_angle_deg), deg_to_rad(55.0))
			_flight_mouse_orbit = _flight_mouse_orbit.clamp(-limit, limit)
		return
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
	if _flight_lens_active and not wing_flight_view:
		_applied_fov = -1.0
		_flight_lens_active = false
	_apply_lens()
	if wing_flight_view:
		_update_wing_flight(dt, _read_flight_look())
		return
	_flight_initialized = false
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
	_flight_initialized = false


func _read_flight_look() -> Vector2:
	if not target is EmberPlayer or not target.is_physics_processing():
		return Vector2.ZERO
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return Vector2.ZERO
	var stick := Vector2(Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_X), Input.get_joy_axis(pads[0], JOY_AXIS_RIGHT_Y))
	return Vector2.ZERO if stick.length() <= 0.18 else stick.normalized() * clampf((stick.length() - 0.18) / 0.82, 0.0, 1.0)

func _update_wing_flight(dt: float, look: Vector2 = Vector2.ZERO) -> void:
	var wanted := target.global_basis.orthonormalized().get_rotation_quaternion()
	var angular := Vector3.ZERO
	var tight := 0.0
	if target is EmberPlayer and target.flight_motion != null:
		angular = target.flight_motion.angular_velocity
		tight = target.flight_motion.tight_turn
	var effort := clampf(absf(angular.x) * 1.7 + absf(angular.z) * 0.53, 0.0, 1.0)
	# A visible lift is intentional: orientation lag alone keeps a body-anchored
	# camera's subject at almost the same screen height throughout the maneuver.
	var offset := Vector3(clampf(angular.z * 0.32, -0.5, 0.5), 2.4 + flight_tuning.pull_shift * clampf(angular.x * 1.7, 0.0, 1.0) - flight_tuning.push_shift * clampf(-angular.x * 1.7, 0.0, 1.0) + 0.5 * clampf(absf(angular.z), 0.0, 1.0) + 0.7 * tight, 10.0 + 0.7 * effort + 0.2 * tight)
	offset.y = clampf(offset.y, 0.8, 5.2)
	if not _flight_initialized or target.global_position.distance_to(_flight_last_position) > 40.0:
		_flight_orientation = wanted
		_flight_offset = Vector3(0, 2.4, 10)
		_flight_orbit = Vector2.ZERO
		_flight_mouse_orbit = Vector2.ZERO
		_flight_fov = fov
		_flight_initialized = true
	else:
		_flight_orientation = _flight_orientation.slerp(wanted, 1.0 - exp(-maxf(dt, 0.0) / flight_tuning.lag_seconds)).normalized()
		# Bound lag rather than locking to world-up, including through inversions.
		var error := _flight_orientation.angle_to(wanted)
		if error > deg_to_rad(flight_tuning.lag_angle_deg):
			_flight_orientation = wanted.slerp(_flight_orientation, deg_to_rad(flight_tuning.lag_angle_deg) / error).normalized()
		var response: float = 7.0 if absf(offset.y - 2.4) > absf(_flight_offset.y - 2.4) else 1.0 / flight_tuning.return_seconds
		_flight_offset = _flight_offset.lerp(offset, 1.0 - exp(-response * maxf(dt, 0.0)))
	var speed: float = target.velocity.length() if target is EmberPlayer else 0.0
	var speed_blend := smoothstep(60.0, 420.0, speed)
	_flight_fov = lerpf(_flight_fov, fov + flight_tuning.speed_fov * speed_blend, 1.0 - exp(-2.8 * maxf(dt, 0.0)))
	_cam.fov = _flight_fov
	_flight_lens_active = true
	_flight_last_position = target.global_position
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_flight_mouse_orbit = Vector2.ZERO
	var orbit_target := Vector2(-look.x * deg_to_rad(flight_tuning.look_angle_deg), -look.y * deg_to_rad(55.0)) - _flight_mouse_orbit
	_flight_orbit = _flight_orbit.lerp(orbit_target, 1.0 - exp(-7.0 * maxf(dt, 0.0)))
	var basis := Basis(_flight_orientation * Quaternion(Vector3.UP, _flight_orbit.x) * Quaternion(Vector3.RIGHT, _flight_orbit.y))
	_cam.global_transform = Transform3D(basis, target.global_position + basis * _flight_offset * flight_framing_scale)


func _apply_lens() -> void:
	if is_equal_approx(_applied_fov, fov) and is_equal_approx(_applied_near, cam_near) and is_equal_approx(_applied_far, cam_far):
		return
	_applied_fov = fov
	_applied_near = cam_near
	_applied_far = cam_far
	_cam.fov = fov
	_cam.near = cam_near
	_cam.far = cam_far
