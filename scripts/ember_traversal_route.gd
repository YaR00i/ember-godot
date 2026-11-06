@tool
extends EmberInteract
## A tracked descent with steering around the tube axis. Route samples also
## let companions follow the same successful line through the obstacles.

const RIDER_CLEARANCE := Vector3(0, 0.5, 0)
const CABLE_HEIGHT := 25.0
const FOLLOW_DELAY := 0.38
const EXIT_BLEND_START := 0.86
enum Mode { CABLE, VINE, PIPE, CLIMB_ROPE }
@export_enum("Канат", "Лиана", "Труба", "Спускаемая верёвка") var route_mode: int = Mode.CABLE
@export var rope_flag := ""
@export_range(1.0, 180.0, 1.0) var speed := 38.0
@export_group("Переходы между ветками")
@export_node_path("Area3D") var left_vine: NodePath
@export_node_path("Area3D") var right_vine: NodePath
@export_range(0.05, 0.95, 0.01) var transfer_start := 0.25
@export_range(0.05, 0.95, 0.01) var transfer_end := 0.65
@export_group("")
@onready var landing := get_node_or_null("Landing") as Marker3D
@export_enum("Полутруба", "Закрытая труба") var cross_section := 0
@export_range(12.0, 80.0, 0.5) var radius := 25.0
@export_range(1, 32) var segment_count := 6
@export_range(0.5, 4.0, 0.05) var steer_rate := 1.65
const Obstacle := preload("res://scripts/ember_pipe_obstacle.gd")
const RopeShader := preload("res://shaders/ember_route_rope.gdshader")
var _angle := 0.0
var _samples: Array[Vector2] = []
var _shell: MeshInstance3D
var _line: MeshInstance3D
var _transfer_sign: Label3D
var _air_samples: Array[Vector3] = []
var _air_step := 0.0
var _preview_key: Array = []
var _climb_reverse := false
var _rope_material: ShaderMaterial
var _rope_load := 0.0
var _rope_phase := 0.0
var _rope_amount := 0.0
var _rope_active := false


func _ready() -> void:
	super._ready()
	_refresh_geometry()
	if Engine.is_editor_hint():
		set_process(true)
	else:
		var approach := get_node_or_null("ApproachView") as Area3D
		if approach != null and is_pipe():
			approach.body_entered.connect(_on_approach_entered)
			approach.body_exited.connect(_on_approach_exited)


func _process(_dt: float) -> void:
	if not Engine.is_editor_hint():
		if not _rope_active:
			_rope_amount = move_toward(_rope_amount, 0.0, _dt * 1.8)
			_rope_phase += _dt * 8.0
			_sync_rope_shader()
			if _rope_amount <= 0.0:
				set_process(false)
		return
	var key := [_local_point(1.0), route_mode, radius, cross_section, segment_count,
		left_vine, right_vine, transfer_start, transfer_end]
	var path := _route_path()
	if path != null:
		key.append_array([path.transform, path.curve.bake_interval])
		for i in path.curve.point_count:
			key.append_array([path.curve.get_point_position(i), path.curve.get_point_in(i), path.curve.get_point_out(i)])
	for child in get_children():
		if child is Obstacle:
			key.append_array([child.get_instance_id(), child.segment, child.segment_offset, child.wall_angle])
	if key != _preview_key:
		_preview_key = key
		_refresh_geometry()


func _on_approach_entered(body: Node3D) -> void:
	if body is EmberPlayer and is_instance_valid(body.camera_rig):
		body.camera_rig.set_pipe_approach(self)


func _on_approach_exited(body: Node3D) -> void:
	if body is EmberPlayer and is_instance_valid(body.camera_rig):
		body.camera_rig.clear_pipe_approach(self)


func refresh_runtime_binding() -> void:
	if not Engine.is_editor_hint():
		add_to_group("ember_interact")
		if route_mode == Mode.CLIMB_ROPE and is_instance_valid(_line):
			_line.visible = _rope_deployed()


func can_mount(actor: CharacterBody3D) -> bool:
	if route_length() < 1.0:
		return false
	if route_mode == Mode.CLIMB_ROPE and not _rope_deployed():
		return false
	var entrance := _entry_for(actor.global_position)
	if actor.global_position.distance_to(entrance) > 8.0:
		return false
	if absf(actor.global_position.y - entrance.y) > 2.0:
		return false
	var exit := route_point(1.0)
	var ray := PhysicsRayQueryParameters3D.create(
		exit + Vector3.UP * 2.0, exit - Vector3.UP * 2.0, 1
	)
	return not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func duration() -> float:
	return maxf(0.001, route_length() / maxf(1.0, speed))


func _route_path() -> Path3D:
	var path := get_node_or_null("RoutePath") as Path3D
	return path if path != null and path.curve != null and path.curve.point_count >= 2 else null


func route_length() -> float:
	var path := _route_path()
	if path != null:
		return path.curve.get_baked_length()
	return landing.position.length() if is_instance_valid(landing) else 0.0


func _local_point(progress: float) -> Vector3:
	var path := _route_path()
	var t := clampf(progress, 0.0, 1.0)
	if path != null:
		return path.transform * path.curve.sample_baked(t * path.curve.get_baked_length())
	return landing.position * t if is_instance_valid(landing) else Vector3.ZERO


func route_point(progress: float) -> Vector3:
	return to_global(_local_point(progress))


func distance_to_world(world: Vector3) -> float:
	return world.distance_to(_entry_for(world))


func _entry_for(world: Vector3) -> Vector3:
	var top := route_point(0.0)
	var bottom := route_point(1.0)
	if route_mode == Mode.CLIMB_ROPE and _rope_deployed() and world.distance_squared_to(bottom) < world.distance_squared_to(top):
		return bottom
	return top


func _rope_deployed() -> bool:
	var progress := _progress()
	return progress != null and bool(progress.flags.get(rope_flag, false))


func _local_forward(progress: float) -> Vector3:
	var t := clampf(progress, 0.0, 1.0)
	var delta := 0.5 / maxf(1.0, route_length())
	return (_local_point(t + delta) - _local_point(t - delta)).normalized()


func _local_right(progress: float) -> Vector3:
	var right := _local_forward(progress).cross(Vector3.UP).normalized()
	return right if not right.is_zero_approx() else Vector3.BACK


func is_pipe() -> bool:
	return route_mode == Mode.PIPE


func is_vine() -> bool:
	return route_mode == Mode.VINE

func is_cable() -> bool:
	return route_mode == Mode.CABLE

func cable_grip_at(elapsed: float, spacing: float) -> Dictionary:
	var length := route_length()
	if not is_cable() or length <= spacing * 2.0 or elapsed >= duration():
		return {}
	var progress := clampf(elapsed / duration(), 0.0, 1.0)
	var offset := spacing / length
	var center := clampf(progress, offset, 1.0 - offset)
	var left := _cable_point(center - offset)
	var right := _cable_point(center + offset)
	return {
		"points": PackedVector3Array([left, right]),
		"tangent": left.direction_to(right),
		"weight": smoothstep(0.0, 0.16, elapsed) * smoothstep(0.0, 0.22, duration() - elapsed),
	}

func _cable_point(progress: float) -> Vector3:
	return to_global(_local_point(progress) + Vector3.UP * CABLE_HEIGHT) + rope_offset(progress)


func supports_transfers() -> bool:
	return route_mode in [Mode.VINE, Mode.CABLE]


func vine_transfer_target(elapsed: float, direction: int) -> Node3D:
	if not supports_transfers():
		return null
	var progress := elapsed / duration()
	if progress < transfer_start or progress > transfer_end:
		return null
	var path := left_vine if direction < 0 else right_vine
	var target := get_node_or_null(path) as Node3D if not path.is_empty() else null
	if target == null or target == self or not target.has_method("supports_transfers") or target.get("route_mode") != route_mode:
		return null
	return target


func vine_arrival_time(at: Vector3, advance: float) -> float:
	var path := _route_path()
	if path != null:
		var arrival := path.curve.get_closest_offset(path.to_local(at)) / maxf(1.0, speed) + advance
		return arrival if arrival > 0.0 and arrival < duration() - 0.15 else -1.0
	var axis := route_point(1.0) - route_point(0.0)
	if axis.length_squared() < 1.0:
		return -1.0
	var progress := (at - global_position).dot(axis) / axis.length_squared()
	var arrival := progress * duration() + advance
	return arrival if arrival > 0.0 and arrival < duration() - 0.15 else -1.0


func vine_hint(elapsed: float) -> String:
	var sides := PackedStringArray()
	if vine_transfer_target(elapsed, -1) != null:
		sides.append("A — влево")
	if vine_transfer_target(elapsed, 1) != null:
		sides.append("D — вправо")
	return "Прыжок · " + "  /  ".join(sides) if not sides.is_empty() else prompt()


func prompt() -> String:
	match route_mode:
		Mode.PIPE: return "Спуститься по трубе"
		Mode.VINE: return "Спуститься по лиане"
		Mode.CLIMB_ROPE: return "Подняться / спуститься по верёвке" if _rope_deployed() else "Спустить верёвку"
	return "Спуститься по канату"


func activate_from(actor: Node3D) -> String:
	if route_mode == Mode.CLIMB_ROPE and not _rope_deployed():
		if rope_flag.is_empty() or actor.global_position.distance_to(route_point(0.0)) > 8.0:
			return "До верёвки нужно добраться сверху."
		var progress := _progress()
		if progress != null:
			progress.set_flag(rope_flag, true)
			_refresh_geometry()
		return "Верёвка спущена. Теперь по ней можно подняться."
	if actor.begin_zipline(self):
		return ride_hint()
	return "Подойди к началу маршрута и освободи руки."


func ride_hint() -> String:
	return "Спуск по трубе · A / D — смещение по стенке" if is_pipe() else prompt()


func start_ride(at: Vector3) -> void:
	_climb_reverse = route_mode == Mode.CLIMB_ROPE and _entry_for(at).is_equal_approx(route_point(1.0))
	_angle = 0.0
	_air_samples.clear()
	_samples.assign([Vector2.ZERO])


func advance_rope_load(elapsed: float, dt: float) -> void:
	if _rope_material == null:
		return
	_rope_active = true
	var progress := clampf(elapsed / duration(), 0.0, 1.0)
	_rope_load = 1.0 - progress if _climb_reverse else progress
	_rope_amount = move_toward(_rope_amount, 1.0, dt * 5.0)
	_rope_phase += dt * 8.0
	_sync_rope_shader()


func release_rope_load() -> void:
	if _rope_material == null:
		return
	_rope_active = false
	set_process(true)


func _sync_rope_shader() -> void:
	if _rope_material == null:
		return
	_rope_material.set_shader_parameter("load_progress", _rope_load)
	_rope_material.set_shader_parameter("load_amount", _rope_amount)
	_rope_material.set_shader_parameter("phase", _rope_phase)


func rope_offset(progress: float) -> Vector3:
	if _rope_material == null:
		return Vector3.ZERO
	var wave := sin(_rope_phase - progress * 5.0)
	if route_mode == Mode.CLIMB_ROPE:
		var weight := maxf(0.0, 1.0 - absf(progress - _rope_load) * 3.2)
		var sway := (wave * 2.7 + 0.5 * weight) * progress * progress
		return global_basis * Vector3(0.0, 0.0, sway) * _rope_amount
	# Keep the shader and the rider's CPU sample on the same curve.
	var sag := minf(progress, _rope_load) * (1.0 - maxf(progress, _rope_load))
	var sway := wave * 0.65 * 4.0 * progress * (1.0 - progress)
	return global_basis * Vector3(0.0, -10.0 * sag, sway) * _rope_amount


func steer_ride(elapsed: float, dt: float, steering: float) -> void:
	if not is_pipe() or elapsed >= duration() * (1.0 if cross_section == 1 else EXIT_BLEND_START):
		return
	_angle += steering * steer_rate * dt
	if cross_section == 0:
		_angle = clampf(_angle, -1.18, 1.18)
	_samples.append(Vector2(elapsed, _angle))


func rider_position(elapsed: float) -> Vector3:
	var total := duration()
	if elapsed > total and not _air_samples.is_empty():
		var sample := clampf((elapsed - total) / _air_step, 0.0, _air_samples.size() - 1)
		var index := floori(sample)
		return _air_samples[index].lerp(_air_samples[mini(index + 1, _air_samples.size() - 1)], sample - index)
	var t := clampf(elapsed / total, 0.0, 1.0)
	var progress := 1.0 - t if _climb_reverse else t
	var baseline := route_point(progress) + RIDER_CLEARANCE + rope_offset(progress)
	return baseline + global_basis * _wall_offset(_rider_angle(elapsed), _local_right(t)) if is_pipe() else baseline


func begin_air_exit(step: float, at: Vector3) -> void:
	_air_step = step
	_air_samples.assign([at])


func record_air_exit(at: Vector3) -> void:
	_air_samples.append(at)


func rider_basis(elapsed: float) -> Basis:
	var progress := clampf(elapsed / duration(), 0.0, 1.0)
	var forward := pipe_forward(elapsed)
	var up := global_basis * _surface_normal(_rider_angle(elapsed), _local_forward(progress), _local_right(progress))
	var wall_pose := Basis(up.cross(forward).normalized(), up, forward)
	if elapsed <= duration():
		return wall_pose
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	var upright := Basis(Vector3.UP.cross(flat_forward), Vector3.UP, flat_forward)
	return wall_pose.slerp(upright, smoothstep(0.0, 0.45, elapsed - duration()))


func pipe_forward(elapsed: float = 0.0) -> Vector3:
	return (global_basis * _local_forward(elapsed / duration())).normalized()


func _rider_angle(elapsed: float) -> float:
	var t := clampf(elapsed / duration(), 0.0, 1.0)
	var angle := _sample_angle(elapsed)
	return angle if cross_section == 1 or t < EXIT_BLEND_START else lerp_angle(angle, 0.0, smoothstep(EXIT_BLEND_START, 1.0, t))


func _surface_normal(angle: float, forward: Vector3, right: Vector3) -> Vector3:
	return (Vector3.UP * sin(angle) + right * cos(angle)).cross(forward).normalized()


func _sample_angle(elapsed: float) -> float:
	if _samples.is_empty():
		return 0.0
	for index in range(_samples.size() - 1, 0, -1):
		var next := _samples[index]
		var previous := _samples[index - 1]
		if elapsed >= previous.x:
			return lerpf(previous.y, next.y, clampf(inverse_lerp(previous.x, next.x, elapsed), 0.0, 1.0))
	return 0.0


func _wall_offset(angle: float, right: Vector3) -> Vector3:
	return radius * (Vector3.UP * (1.0 - cos(angle)) + right * sin(angle))


func _place_obstacles() -> void:
	for child in get_children():
		if child is Obstacle:
			var segment := clampi(child.segment, 1, segment_count)
			var progress: float = (segment - 1 + child.segment_offset) / float(segment_count)
			var angle := deg_to_rad(child.wall_angle)
			var forward := _local_forward(progress)
			var right := _local_right(progress)
			child.position = _local_point(progress) + _wall_offset(angle, right)
			if not forward.is_zero_approx():
				var up := _surface_normal(angle, forward, right)
				child.basis = Basis(forward, up, forward.cross(up)).orthonormalized()


func ride_camera_origin(elapsed: float, torso: Vector3) -> Vector3:
	var forward := pipe_forward(elapsed)
	var horizontal := Vector3(forward.x, 0.0, forward.z).normalized()
	if cross_section == 0:
		return torso + Vector3.UP * 37.0 - horizontal * 56.0
	var progress := clampf(elapsed / duration(), 0.0, 1.0)
	var center := route_point(progress)
	var behind := progress - 56.0 / maxf(1.0, route_length() * Vector2(forward.x, forward.z).length())
	var camera_center := route_point(behind)
	if behind < 0.0:
		camera_center += pipe_forward() * (behind * route_length())
	var right := global_basis * _local_right(maxf(behind, 0.0))
	var lateral := right * (torso - center).dot(right)
	return camera_center + Vector3.UP * radius + lateral * 0.4


func ride_camera_target(elapsed: float, torso: Vector3) -> Vector3:
	if cross_section == 0:
		return torso + pipe_forward(elapsed) * 24.0
	var progress := clampf(elapsed / duration(), 0.0, 1.0)
	var center := route_point(progress)
	var ahead := progress + 24.0 / maxf(1.0, route_length())
	var lead := route_point(ahead) - center
	if ahead > 1.0:
		lead += pipe_forward(duration()) * ((ahead - 1.0) * route_length())
	return (center + Vector3.UP * radius * 0.75).lerp(torso, 0.55) + lead


func _refresh_geometry() -> void:
	if is_pipe():
		_build_shell()
		_place_obstacles()
	elif route_length() > 0.0:
		_build_line()
	if is_instance_valid(_shell):
		_shell.visible = is_pipe() and route_length() >= 1.0
	if is_instance_valid(_line):
		_line.visible = not is_pipe() and route_length() > 0.0 and (
			route_mode != Mode.CLIMB_ROPE or Engine.is_editor_hint() or _rope_deployed()
		)
	if is_instance_valid(_transfer_sign):
		_transfer_sign.visible = supports_transfers() and (not left_vine.is_empty() or not right_vine.is_empty())
	for child in get_children():
		if child is Obstacle:
			child.visible = is_pipe()
			child.process_mode = Node.PROCESS_MODE_INHERIT if is_pipe() else Node.PROCESS_MODE_DISABLED


func _build_line() -> void:
	if not is_instance_valid(_line):
		_line = MeshInstance3D.new()
		_line.name = "RouteLine"
		add_child(_line)
	var material: Material
	_rope_material = null
	if is_vine():
		var vine_material := StandardMaterial3D.new()
		vine_material.albedo_color = Color(0.22, 0.37, 0.11)
		vine_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material = vine_material
	else:
		_rope_material = ShaderMaterial.new()
		_rope_material.shader = RopeShader
		_rope_material.set_shader_parameter("free_end", route_mode == Mode.CLIMB_ROPE)
		material = _rope_material
	var height := -3.0 if is_vine() else (5.0 if route_mode == Mode.CLIMB_ROPE else CABLE_HEIGHT)
	_line.mesh = _build_sweep(material, PI, 8, 24 if _rope_material != null else 1, 3.5 if is_vine() else 0.6, height)
	if supports_transfers() and (not left_vine.is_empty() or not right_vine.is_empty()):
		if not is_instance_valid(_transfer_sign):
			_transfer_sign = Label3D.new()
			_transfer_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			_transfer_sign.pixel_size = 0.085
			_transfer_sign.modulate = Color("e3ffc1")
			add_child(_transfer_sign)
		_transfer_sign.position = _local_point(transfer_start) + Vector3.UP * 29.0
		_transfer_sign.text = "Прыжок  A ← / → D" if not left_vine.is_empty() and not right_vine.is_empty() else (
			"← A  Прыжок" if not left_vine.is_empty() else "Прыжок  D →"
		)


func _build_shell() -> void:
	if route_length() < 1.0:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.52, 0.57)
	material.roughness = 0.63
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if not is_instance_valid(_shell):
		_shell = MeshInstance3D.new()
		_shell.name = "PipeShell"
		add_child(_shell)
	_shell.mesh = _build_sweep(material, PI if cross_section == 1 else 1.85, 24, segment_count, radius, radius)


func _build_sweep(material: Material, half_arc: float, sides: int, divisions: int, sweep_radius: float, center_height: float) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	if _route_path() != null:
		divisions = clampi(ceili(route_length() / 3.0), divisions, 256)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for segment in divisions:
		var t0 := float(segment) / divisions
		var t1 := float(segment + 1) / divisions
		var start := _local_point(t0) + Vector3.UP * center_height
		var end := _local_point(t1) + Vector3.UP * center_height
		var right0 := _local_right(t0)
		var right1 := _local_right(t1)
		var forward := _local_forward((t0 + t1) * 0.5)
		var up0 := right0.cross(forward).normalized() if route_mode == Mode.CLIMB_ROPE else Vector3.UP
		var up1 := right1.cross(forward).normalized() if route_mode == Mode.CLIMB_ROPE else Vector3.UP
		for side in sides:
			var a := lerpf(-half_arc, half_arc, float(side) / sides)
			var b := lerpf(-half_arc, half_arc, float(side + 1) / sides)
			var p0 := start + sweep_radius * (-up0 * cos(a) + right0 * sin(a))
			var p1 := end + sweep_radius * (-up1 * cos(a) + right1 * sin(a))
			var p2 := start + sweep_radius * (-up0 * cos(b) + right0 * sin(b))
			var p3 := end + sweep_radius * (-up1 * cos(b) + right1 * sin(b))
			var angle := (a + b) * 0.5
			var normal := ((up0 + up1).normalized() * sin(angle) + (right0 + right1).normalized() * cos(angle)).cross(forward).normalized()
			var corners := [p0, p1, p2, p2, p1, p3]
			for index in corners.size():
				mesh.surface_set_uv(Vector2(t1 if index in [1, 4, 5] else t0, 0.0))
				mesh.surface_set_normal(normal if is_pipe() else -normal)
				mesh.surface_add_vertex(corners[index])
	mesh.surface_end()
	return mesh
