extends CharacterBody3D
## Presentation and ambient behaviour for animals. Encounters can drive the
## same presentation from their own gameplay controller.

const AnimalProfile = preload("res://scripts/ember_animal_profile.gd")
enum State { ROAM, ALERT, RETREAT, WAIT, RETURN }

@export var profile: AnimalProfile
var roam_shape: CollisionShape3D

var _gait: AnimationPlayer
var _origin: Vector3
var _destination: Vector3
var _state := State.ROAM
var _remaining := 1.0
var _patrol_leg := 0

@onready var _visual: Node3D = $Visual

func _ready() -> void:
	if profile == null or profile.model == null:
		return
	_setup_presentation()
	_origin = global_position
	_destination = _origin
	floor_snap_length = 2.0
	var box := BoxShape3D.new()
	box.size = profile.body_size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	add_child(shape)

func _setup_presentation() -> void:
	if profile == null or profile.model == null:
		return
	var model := profile.model.instantiate() as Node3D
	_visual.add_child(model)
	model.scale *= profile.model_scale
	model.rotation.y += profile.model_yaw
	model.position.y += profile.ground_offset
	_gait = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_animate_gait(0.0)

func _physics_process(dt: float) -> void:
	if profile == null or profile.model == null:
		return
	var world := get_tree().current_scene
	if world == null or (world.has_method("is_world_preparation_complete") and not world.is_world_preparation_complete()):
		return
	var player := world.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return
	var offset := (global_position - player.global_position).slide(Vector3.UP)
	if offset.length_squared() > 1440000.0:
		if _gait != null: _gait.active = false
		return
	if _gait != null: _gait.active = true
	var near := profile.reaction != AnimalProfile.Reaction.ENCOUNTER and offset.length_squared() < profile.notice_distance ** 2
	_update_behaviour(dt, near, offset)
	var speed := profile.retreat_speed if _state == State.RETREAT else profile.walk_speed
	_destination = _inside_roam_area(_destination)
	var direction := (_destination - global_position).slide(Vector3.UP)
	var moving := _state in [State.ROAM, State.RETREAT, State.RETURN] and direction.length() > 0.7
	var travel := direction.normalized() * minf(speed, direction.length() / dt) if moving else Vector3.ZERO
	velocity = Vector3(travel.x, velocity.y - 150.0 * dt, travel.z)
	if moving:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(-travel.x, -travel.z), 1.0 - exp(-10.0 * dt))
	var previous := global_position
	move_and_slide()
	if not _inside_roam_area(global_position).is_equal_approx(global_position):
		global_position = previous
		_animate_gait(0.0)
		return
	_animate_gait(get_real_velocity().slide(Vector3.UP).length())

func _inside_roam_area(point: Vector3) -> Vector3:
	if not is_instance_valid(roam_shape):
		return point
	var local := roam_shape.to_local(point)
	var half: Vector3 = roam_shape.shape.size * 0.5
	var margin := minf(minf(half.x, half.z) * 0.25, maxf(profile.body_size.x, profile.body_size.z) * 0.5)
	local.x = clampf(local.x, -half.x + margin, half.x - margin)
	local.z = clampf(local.z, -half.z + margin, half.z - margin)
	return roam_shape.to_global(local)

func _update_behaviour(dt: float, near: bool, away: Vector3) -> void:
	_remaining -= dt
	var arrived := (_destination - global_position).slide(Vector3.UP).length() < 0.8
	if near and _state in [State.ROAM, State.RETURN]:
		_state = State.ALERT
		_remaining = 0.5 if profile.reaction == AnimalProfile.Reaction.STARTLE else 0.0
	match _state:
		State.ALERT:
			if profile.reaction == AnimalProfile.Reaction.FREEZE:
				_state = State.WAIT
			elif _remaining <= 0.0:
				_state = State.RETREAT
				_remaining = 1.6
				var direction := away.normalized() if not away.is_zero_approx() else Vector3.FORWARD
				var target := global_position - _origin + direction * profile.retreat_radius
				_destination = _origin + target.slide(Vector3.UP).limit_length(profile.retreat_radius)
		State.RETREAT:
			if arrived or _remaining <= 0.0:
				_state = State.WAIT
		State.WAIT:
			if not near:
				_state = State.RETURN
				_destination = _origin
		State.RETURN:
			if arrived:
				_state = State.ROAM
				_remaining = 0.7
		State.ROAM:
			if arrived and _remaining <= 0.0:
				_patrol_leg += 1
				var angle := float(_patrol_leg) * 2.4
				_destination = _origin + Vector3(cos(angle), 0, sin(angle)) * profile.roam_radius
				_remaining = 1.6

func _animate_gait(speed: float) -> void:
	if _gait == null or profile == null:
		return
	var moving := speed > 0.4
	var clip := profile.move_clip if moving else profile.idle_clip
	if _gait.current_animation != clip and _gait.has_animation(clip):
		_gait.play(clip, 0.12)
	_gait.speed_scale = clampf(speed / maxf(0.1, profile.walk_speed), 0.25, 3.5) if moving else 1.0
