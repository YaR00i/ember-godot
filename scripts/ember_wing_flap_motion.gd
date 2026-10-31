extends "res://scripts/ember_wing_flight_motion.gd"
## Hoshi trial state on the existing flight math; Player still owns collision/input.
enum Phase { STANDING, JUMPING, DEPLOYING, FLYING }
const DEPLOY_SECONDS := 1.0
const BOOST_SECONDS := 1.0
const POWER_TIME := 0.38
const IMPULSE_MPS := 22.0
const FLAP_SECONDS := 1.1
const SUPPORT_INTERVAL := 3.2
var phase := Phase.STANDING
var ground_supported := false
var deploy_age := 0.0
var boost_age := -1.0
var flap_age := -1.0
var queued_boosts := 0
var boost_count := 0
var impulse_count := 0
var support_count := 0
var _support_clock := 0.0
var _held := true
var _powered := false
var _ground_orientation := Quaternion.IDENTITY

func reset(rotation: Quaternion = Quaternion.IDENTITY, _speed: float = 0.0) -> void:
	super.reset(rotation, 6.0)
	_ground_orientation = rotation
	velocity = Vector3.ZERO
	phase = Phase.STANDING
	ground_supported = false
	deploy_age = 0.0
	boost_age = -1.0
	flap_age = -1.0
	queued_boosts = 0
	boost_count = 0
	impulse_count = 0
	support_count = 0
	_support_clock = 0.0
	_held = true
	_powered = false

func configure(values: Dictionary) -> void:
	tuning = sanitize(values)
	if phase == Phase.FLYING:
		super.configure(values)

func jump_pressed() -> void:
	if phase == Phase.STANDING and ground_supported:
		phase = Phase.JUMPING
		velocity.y = 6.0
		ground_supported = false
	elif phase == Phase.JUMPING and not ground_supported:
		phase = Phase.DEPLOYING
		deploy_age = 0.0
		var flat := Vector3(velocity.x, 0, velocity.z)
		if flat.length() > 0.1:
			orientation = Quaternion(Vector3.UP, atan2(-flat.x, -flat.z))

func suspend_trigger() -> void:
	_held = true

func is_diving() -> bool:
	return phase == Phase.FLYING and (-Basis(orientation).z).y < -0.25

func cocoon_progress() -> float:
	if phase == Phase.DEPLOYING:
		return clampf(deploy_age / DEPLOY_SECONDS, 0.0, 1.0)
	return clampf(boost_age / BOOST_SECONDS, 0.0, 1.0) if boost_age >= 0.0 else -1.0

func step(dt: float, controls: Vector3, throttle: float, brake: float) -> void:
	if dt <= 0.0:
		return
	if throttle < 0.2:
		_held = false
	elif throttle > 0.55 and not _held:
		_held = true
		if phase == Phase.FLYING:
			queued_boosts += 1
	if phase in [Phase.STANDING, Phase.JUMPING]:
		if phase == Phase.JUMPING and ground_supported and velocity.y <= 0.0:
			phase = Phase.STANDING
		var wish := Basis(_ground_orientation) * Vector3(controls.z, 0, controls.x).limit_length(1.0) * 3.0
		velocity.x = wish.x
		velocity.z = wish.z
		velocity.y = -0.3 if ground_supported and phase == Phase.STANDING else velocity.y - 12.0 * dt
		return
	if phase == Phase.DEPLOYING:
		deploy_age = minf(deploy_age + dt, DEPLOY_SECONDS)
		velocity = velocity.lerp(Vector3.UP * 1.2, 1.0 - exp(-4.0 * dt))
		if deploy_age >= DEPLOY_SECONDS:
			phase = Phase.FLYING
			cruise_speed = minf(28.0, tuning.max_speed_kmh / 3.6)
			velocity = -Basis(orientation).z * cruise_speed
			flap_age = 0.0
			support_count += 1
		return
	if boost_age < 0.0 and queued_boosts > 0:
		queued_boosts -= 1
		boost_age = 0.0
		_powered = false
		boost_count += 1
		flap_age = -1.0
	if boost_age >= 0.0:
		boost_age += dt
		_support_clock = 0.0
		if not _powered and boost_age >= POWER_TIME:
			_powered = true
			impulse_count += 1
			cruise_speed = minf(velocity.length() + IMPULSE_MPS, tuning.max_speed_kmh / 3.6)
			velocity = velocity.normalized() * cruise_speed
		if boost_age >= BOOST_SECONDS:
			boost_age = -1.0
	else:
		_support_clock += dt
		if is_diving():
			flap_age = -1.0
			_support_clock = 0.0
		elif flap_age < 0.0 and _support_clock >= SUPPORT_INTERVAL:
			flap_age = 0.0
			_support_clock = 0.0
			support_count += 1
		if flap_age >= 0.0:
			flap_age += dt
			if flap_age >= FLAP_SECONDS:
				flap_age = -1.0
	super.step(dt, controls, 0.0, brake)

func _constrain_orientation() -> void:
	# Cocoon spins belong to presentation, never to the body/follow camera.
	var angles := Basis(orientation).get_euler(EULER_ORDER_YXZ)
	angles.x = clampf(angles.x, deg_to_rad(-80), deg_to_rad(80))
	angles.z = clampf(angles.z, -PI * 0.5, PI * 0.5)
	orientation = Basis.from_euler(angles, EULER_ORDER_YXZ).get_rotation_quaternion()
