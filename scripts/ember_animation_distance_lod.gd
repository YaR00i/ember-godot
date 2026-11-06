extends RefCounted
## Presentation sampling only. The controller/physics keeps its normal tick.
## AnimationMixer manual advance: https://docs.godotengine.org/en/stable/classes/class_animationmixer.html
const NEAR_METRES := 16.0
const FAR_METRES := 40.0
const HYSTERESIS := 0.1
const INTERVALS := [0.0, 1.0 / 30.0, 1.0 / 15.0]
const OFFSCREEN_INTERVAL := 0.2
const HIDDEN_INTERVAL := 0.5

var _distance_tier := 0
var _interval := 0.0
var _remaining := 0.0
var _pending_wall := 0.0
var _pending_scaled := 0.0
var _phase := 0.0
var _skeleton: Skeleton3D
var _skeleton_mode := Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
var _manual_skeleton := false
var _springs: Array[SpringBoneSimulator3D] = []
var _spring_authored_active: Array[bool] = []
var _reset_secondary_motion := false
var _physical_simulators: Array[PhysicalBoneSimulator3D] = []


func _init(instance_seed: int = 0) -> void:
	# Different characters sample on different frames, without adding fake time.
	_phase = fposmod(float(instance_seed % 1024) * 0.61803398875, 1.0)


func bind_skeleton(target: Skeleton3D, secondary_motion_enabled := true) -> void:
	_skeleton = target
	_skeleton_mode = target.modifier_callback_mode_process
	for modifier in target.find_children("*", "SkeletonModifier3D", true, false):
		if modifier is SpringBoneSimulator3D:
			_springs.append(modifier)
			_spring_authored_active.append(modifier.active)
		if modifier is PhysicalBoneSimulator3D: _physical_simulators.append(modifier)
	set_secondary_motion_enabled(secondary_motion_enabled)


func set_secondary_motion_enabled(enabled: bool) -> void:
	# Only this visual's instantiated modifiers change; imported assets stay intact.
	# Keep authored inactive chains inactive when importance returns.
	for index in _springs.size():
		var spring := _springs[index]
		if not is_instance_valid(spring): continue
		var active := enabled and _spring_authored_active[index]
		if spring.active != active:
			spring.active = active
			spring.reset()
			_reset_secondary_motion = true


static func is_party_visual(subject: Node) -> bool:
	# These are the existing owners, rather than a new party flag or data schema.
	var node := subject
	while is_instance_valid(node):
		var script := node.get_script() as Script
		while script != null:
			if script.get_global_name() in [&"EmberPlayer", &"EmberPartyFollowers"]:
				return true
			script = script.get_base_script()
		node = node.get_parent()
	return false


func advance(player: AnimationPlayer, delta: float, camera: Camera3D, center: Vector3,
		radius: float, units_per_metre: float, full_rate: bool, shown: bool) -> float:
	for simulator in _physical_simulators:
		if is_instance_valid(simulator) and simulator.is_simulating_physics():
			full_rate = true
	# Party/flight keeps the native callback; distant presentation owns only its rig.
	_manual_skeleton = is_instance_valid(_skeleton) and not full_rate
	if is_instance_valid(_skeleton):
		_skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL if _manual_skeleton else _skeleton_mode
	_pending_wall += maxf(delta, 0.0)
	# Integrate each frame's playback speed even when no pose is evaluated.
	_pending_scaled += maxf(delta, 0.0) * player.speed_scale
	var interval := _sample_interval(camera, center, radius, units_per_metre, full_rate, shown)
	if interval < _interval or interval == 0.0:
		_remaining = 0.0
	elif interval != _interval:
		_remaining = interval * _phase
	_interval = interval
	_remaining -= maxf(delta, 0.0)
	if _remaining > 0.000001:
		return -1.0
	# Preserve overshoot, but never run multiple catch-up evaluations in one frame.
	_remaining = fposmod(_remaining, interval) if interval > 0.0 else 0.0
	return flush(player)


func flush(player: AnimationPlayer) -> float:
	# Flush BEFORE switching clips, so elapsed time belongs to the old clip.
	var elapsed := _pending_wall
	if elapsed > 0.0:
		var speed := player.speed_scale
		player.speed_scale = 1.0
		player.advance(_pending_scaled)
		player.speed_scale = speed
		# Importance can return after a long gap or teleport. Seed history only
		# after the current body pose is evaluated, before native spring callbacks.
		if _reset_secondary_motion:
			for spring in _springs:
				if is_instance_valid(spring) and spring.active: spring.reset()
			_reset_secondary_motion = false
		if _manual_skeleton:
			# A long unseen gap must not launch hair springs with a huge physics step.
			# Reset secondary motion at the current, elapsed-time-correct animated pose.
			if elapsed > 0.1:
				for spring in _springs:
					if is_instance_valid(spring) and spring.active: spring.reset()
			_skeleton.advance(minf(elapsed, 0.1))
	_pending_wall = 0.0
	_pending_scaled = 0.0
	return elapsed


func _sample_interval(camera: Camera3D, center: Vector3, radius: float,
		units_per_metre: float, full_rate: bool, shown: bool) -> float:
	if full_rate or not is_instance_valid(camera) or not camera.is_inside_tree():
		_distance_tier = 0
		return 0.0
	var metres := camera.global_position.distance_to(center) / maxf(units_per_metre, 0.001)
	while _distance_tier < 2:
		var limit: float = NEAR_METRES if _distance_tier == 0 else FAR_METRES
		if metres <= limit * (1.0 + HYSTERESIS):
			break
		_distance_tier += 1
	while _distance_tier > 0:
		var limit: float = NEAR_METRES if _distance_tier == 1 else FAR_METRES
		if metres >= limit * (1.0 - HYSTERESIS):
			break
		_distance_tier -= 1
	if not shown:
		return HIDDEN_INTERVAL
	# Nearby offscreen characters can still cast a visible shadow into the view.
	if _distance_tier==0:return 0.0
	# A sphere keeps heads/limbs at the frame edge from being classified by feet.
	for plane: Plane in camera.get_frustum():
		if plane.distance_to(center) > radius:
			return OFFSCREEN_INTERVAL
	return INTERVALS[_distance_tier]
