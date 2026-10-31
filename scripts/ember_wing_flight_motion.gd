extends RefCounted
## Transient arcade flight state. Local controls: pitch up, yaw left, roll right.
## Owns no input, collision, scene, save or character presentation.

var orientation := Quaternion.IDENTITY
var velocity := Vector3(0, 0, -26)
var angular_velocity := Vector3.ZERO
var tight_turn := 0.0
var cruise_speed := 26.0
var high_g_armed := false
var throttle_input := 0.0
var brake_input := 0.0

const TUNING := {
	"max_speed_kmh": Vector4(300, 1800, 100, 1800),
	"acceleration_kmh_s": Vector4(40, 300, 10, 140),
	"pitch_rate_deg": Vector4(20, 100, 5, 40),
	"roll_rate_deg": Vector4(40, 180, 5, 70),
	"response_seconds": Vector4(0.1, 0.6, 0.05, 0.25),
	"high_g_multiplier": Vector4(1.5, 5, 0.25, 3),
}
var tuning := defaults()

static func defaults() -> Dictionary:
	var values := {}
	for key in TUNING:
		values[key] = TUNING[key].w
	return values

static func sanitize(values: Dictionary) -> Dictionary:
	var result := defaults()
	for key in TUNING:
		var value: Variant = values.get(key)
		if typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)):
			result[key] = clampf(float(value), TUNING[key].x, TUNING[key].y)
	return result

func configure(values: Dictionary) -> void:
	tuning = sanitize(values)
	cruise_speed = clampf(cruise_speed, 6.0, tuning.max_speed_kmh / 3.6)
	velocity = velocity.normalized() * clampf(velocity.length(), 6.0, tuning.max_speed_kmh / 3.6)


func reset(rotation: Quaternion = Quaternion.IDENTITY, speed: float = 26.0) -> void:
	orientation = rotation.normalized()
	velocity = Basis(orientation) * Vector3(0, 0, -speed)
	angular_velocity = Vector3.ZERO
	tight_turn = 0.0
	cruise_speed = clampf(speed, 6.0, tuning.max_speed_kmh / 3.6)
	velocity = Basis(orientation) * Vector3(0, 0, -cruise_speed)
	high_g_armed = false
	throttle_input = 0.0
	brake_input = 0.0


func step(dt: float, controls: Vector3, throttle: float, brake: float) -> void:
	if dt <= 0.0:
		return
	var speed := velocity.length()
	# Triggers change speed; released triggers engage automatic speed holding.
	# A small deadzone prevents controller noise from slowly changing the setting.
	throttle = clampf((throttle - 0.05) / 0.95, 0.0, 1.0)
	brake = clampf((brake - 0.05) / 0.95, 0.0, 1.0)
	throttle_input = throttle
	brake_input = brake
	# Deliberate dual-trigger pull: spend speed for a tighter actual trajectory.
	# No extra roll/yaw authority, no free boost while slow or flying straight.
	var requested := 0.0
	high_g_armed = throttle > 0.55 and brake > 0.55
	if high_g_armed and controls.x > 0.05:
		requested = minf(throttle, brake) * controls.x * clampf((speed - 12.0) / 14.0, 0.0, 1.0)
	tight_turn = lerpf(tight_turn, requested, 1.0 - exp(-8.0 * dt))
	# Best authority at medium speed. Slow air weakens controls; fast flight
	# needs a wider arc at the same input rather than a toy-like instant turn.
	var airflow := clampf((speed - 6.0) / 35.0, 0.2, 1.0)
	var turn_authority := airflow * clampf(sqrt(100.0 / maxf(speed, 1.0)), 0.6, 1.3)
	var roll_authority := lerpf(0.4, 1.0, airflow) * sqrt(minf(1.0, 200.0 / maxf(speed, 1.0)))
	var pitch_rate: float = deg_to_rad(tuning.pitch_rate_deg)
	var roll_rate: float = deg_to_rad(tuning.roll_rate_deg)
	var multiplier: float = 1.0 + (tuning.high_g_multiplier - 1.0) * tight_turn
	var desired := Vector3(controls.x * pitch_rate * turn_authority * multiplier, controls.y * 0.3 * turn_authority, -controls.z * roll_rate * roll_authority)
	angular_velocity = angular_velocity.lerp(desired, 1.0 - exp(-dt / tuning.response_seconds))
	var rotation_step := angular_velocity * dt
	if rotation_step.length_squared() > 0.00000001:
		orientation = (orientation * Quaternion(rotation_step.normalized(), rotation_step.length())).normalized()
	_constrain_orientation()
	var forward := -Basis(orientation).z
	# A gentle minimum flying speed avoids a hard stall in this first trial.
	if high_g_armed:
		# Both triggers are one command, never accelerator minus ordinary brake.
		# Holding them without pulling arms the maneuver without losing speed.
		speed = clampf(speed - (210.0 / 3.6) * 0.7 * requested * dt, 6.0, tuning.max_speed_kmh / 3.6)
		cruise_speed = speed
	elif throttle > 0.0 or brake > 0.0:
		speed = clampf(speed + (tuning.acceleration_kmh_s / 3.6 * throttle - 210.0 / 3.6 * brake) * dt, 6.0, tuning.max_speed_kmh / 3.6)
		cruise_speed = speed
	else:
		# Autothrottle compensates drag/height changes, holding the speed reached
		# on release, including the lower speed left after braking or a tight turn.
		speed = cruise_speed
	var follow_response := (1.7 + 4.5 * tight_turn) * lerpf(0.6, 1.0, airflow)
	var direction := velocity.normalized().lerp(forward, 1.0 - exp(-follow_response * dt)).normalized()
	velocity = direction * speed

func _constrain_orientation() -> void:
	pass
