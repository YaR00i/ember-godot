@tool
class_name OrbitCamera
extends Node3D
## Reusable orbit/pan/zoom rig. It can own a generated Camera3D (legacy spike)
## or drive a scene-authored child selected by camera_path (Combat Lab).

@export_group("Ракурс")
@export var camera_path := NodePath("Camera3D")
@export var target := Vector3.ZERO
@export_range(2.0, 220.0, 0.1, "or_greater") var distance := 48.0
@export_range(-180.0, 180.0, 0.5) var yaw_degrees := 34.0
@export_range(5.0, 85.0, 0.5) var pitch_degrees := 32.0
@export_range(5.0, 85.0, 0.5) var min_pitch_degrees := 10.0
@export_range(5.0, 89.0, 0.5) var max_pitch_degrees := 82.0
@export_range(2.0, 220.0, 0.1) var min_distance := 8.0
@export_range(2.0, 400.0, 0.1) var max_distance := 220.0

@export_group("Объектив")
@export_enum("Ортографическая", "Перспективная") var projection_mode := 0:
	set(value):
		projection_mode = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
		_apply(true)
## Масштаб ортографической камеры. В перспективном режиме не используется.
@export_range(2.0, 80.0, 0.1) var orthographic_size := 18.0
@export_range(2.0, 80.0, 0.1) var min_orthographic_size := 4.0
@export_range(2.0, 160.0, 0.1) var max_orthographic_size := 60.0
## Угол обзора перспективной камеры. В ортографическом режиме не используется.
@export_range(10.0, 100.0, 0.5) var fov := 40.0
@export_range(0.01, 10.0, 0.01) var camera_near := 0.2
@export_range(100.0, 10000.0, 10.0) var camera_far := 2000.0

@export_group("Управление в бою")
@export var controls_enabled := true
@export var keyboard_pan_enabled := true
## Keeps authored lens/zoom values editable while allowing a battle scene to
## reserve the mouse wheel for command lists and other UI.
@export var mouse_wheel_zoom_enabled := true
@export var invert_vertical_axis := false
## Keeps horizontal orbit on the authored four isometric sides. The transition
## between sides is interpolated so a drag never cuts to another view.
@export var axis_lock_enabled := false
@export var horizontal_rotation_locked := false
@export var vertical_rotation_locked := false
## Compatibility aggregate for older callers. Independent axis locks below are
## the actual source of truth for input handling.
@export var angle_lock_enabled := false
@export_range(0.05, 3.0, 0.05) var orbit_sensitivity := 0.5
@export_range(0.1, 4.0, 0.05) var mouse_pan_sensitivity := 1.0
@export_range(0.1, 60.0, 0.1) var keyboard_pan_speed := 9.0
@export_range(5.0, 180.0, 1.0) var keyboard_rotate_speed := 55.0
@export_range(15.0, 180.0, 15.0) var rotation_step_degrees := 90.0
@export_range(8.0, 80.0, 1.0) var axis_drag_threshold := 24.0
@export_range(0.05, 0.8, 0.01) var step_rotation_duration := 0.28
@export_range(0.02, 0.5, 0.01) var zoom_step := 0.1
@export_range(0.0, 1.5, 0.05) var focus_smoothing_duration := 0.4

var _cam: Camera3D
var _last_signature := ""
var _initial_view: Dictionary = {}
var _authored_view: Dictionary = {}
var _axis_reference_yaw := 0.0
var _axis_drag_degrees := 0.0
var _camera_tween: Tween
var _rotation_tween: Tween
var _axis_target_yaw := 0.0


func _validate_property(property: Dictionary) -> void:
	var property_name := str(property.get("name", ""))
	var inactive_lens := (
		property_name == "fov" and projection_mode == 0
	) or (
		property_name == "orthographic_size" and projection_mode == 1
	)
	if inactive_lens:
		property["usage"] = int(property.get("usage", PROPERTY_USAGE_DEFAULT)) | PROPERTY_USAGE_READ_ONLY


func _ready() -> void:
	_resolve_camera()
	_authored_view = view_snapshot()
	_initial_view = _authored_view.duplicate(true)
	_axis_reference_yaw = yaw_degrees
	_axis_target_yaw = yaw_degrees
	if angle_lock_enabled:
		horizontal_rotation_locked = true
		vertical_rotation_locked = true
	else:
		_update_aggregate_angle_lock()
	if axis_lock_enabled:
		_snap_yaw_to_axis()
		_axis_target_yaw = yaw_degrees
	_apply(true)


func _process(delta: float) -> void:
	if _cam == null:
		_resolve_camera()
	if Engine.is_editor_hint():
		_apply()
		return
	if controls_enabled and keyboard_pan_enabled:
		_apply_keyboard_input(delta)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if handle_input(event):
		get_viewport().set_input_as_handled()


func handle_input(event: InputEvent) -> bool:
	if not controls_enabled or _cam == null:
		return false
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_kill_view_tween()
			if not vertical_rotation_locked:
				var vertical_direction := 1.0 if invert_vertical_axis else -1.0
				pitch_degrees = clampf(
					pitch_degrees + event.relative.y * orbit_sensitivity * vertical_direction,
					min_pitch_degrees,
					max_pitch_degrees,
				)
			if not horizontal_rotation_locked:
				if axis_lock_enabled:
					_axis_drag_degrees -= event.relative.x * orbit_sensitivity
					_apply_axis_drag_steps()
				else:
					_kill_rotation_tween()
					yaw_degrees -= event.relative.x * orbit_sensitivity
					_axis_target_yaw = yaw_degrees
			_apply(true)
			return true
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_kill_camera_tween()
			_pan_pixels(event.relative)
			_apply(true)
			return true
	if event is InputEventMouseButton and event.pressed and mouse_wheel_zoom_enabled:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_kill_camera_tween()
			_zoom_by(1.0 - zoom_step)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_kill_camera_tween()
			_zoom_by(1.0 + zoom_step)
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_HOME:
			return_home_view()
			return true
	return false


func apply_settings() -> void:
	_apply(true)


func reset_view() -> void:
	if _initial_view.is_empty():
		return
	_kill_camera_tween()
	target = _initial_view.get("target", target)
	distance = float(_initial_view.get("distance", distance))
	yaw_degrees = float(_initial_view.get("yawDegrees", yaw_degrees))
	_axis_target_yaw = yaw_degrees
	pitch_degrees = float(_initial_view.get("pitchDegrees", pitch_degrees))
	orthographic_size = float(_initial_view.get("orthographicSize", orthographic_size))
	projection_mode = int(_initial_view.get("projectionMode", projection_mode))
	fov = float(_initial_view.get("fov", fov))
	_apply(true)


func rotate_step(direction: int) -> void:
	if direction == 0 or horizontal_rotation_locked:
		return
	_kill_view_tween()
	_axis_target_yaw += signi(direction) * rotation_step_degrees
	_start_axis_rotation()


func focus_on(world_target: Vector3, smooth: bool = true) -> void:
	_kill_view_tween()
	if not smooth or focus_smoothing_duration <= 0.0 or Engine.is_editor_hint():
		target = world_target
		_apply(true)
		return
	_camera_tween = create_tween()
	_camera_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(self, "target", world_target, focus_smoothing_duration)


func set_home_view(
	world_target: Vector3,
	requested_orthographic_size: float,
	requested_distance: float = -1.0,
) -> void:
	_kill_camera_tween()
	target = world_target
	if projection_mode == 0:
		orthographic_size = clampf(
			requested_orthographic_size, min_orthographic_size, max_orthographic_size
		)
	if requested_distance > 0.0:
		distance = clampf(requested_distance, min_distance, max_distance)
	_axis_target_yaw = yaw_degrees
	_apply(true)
	_initial_view = view_snapshot()


func restore_authored_home() -> void:
	if _authored_view.is_empty():
		return
	_initial_view = _authored_view.duplicate(true)
	reset_view()


func return_home_view(smooth: bool = true) -> void:
	if _initial_view.is_empty():
		return
	_kill_camera_tween()
	projection_mode = int(_initial_view.get("projectionMode", projection_mode))
	fov = float(_initial_view.get("fov", fov))
	var home_target: Vector3 = _initial_view.get("target", target)
	var home_distance := float(_initial_view.get("distance", distance))
	var home_pitch := float(_initial_view.get("pitchDegrees", pitch_degrees))
	var home_size := float(_initial_view.get("orthographicSize", orthographic_size))
	var raw_home_yaw := float(_initial_view.get("yawDegrees", yaw_degrees))
	var home_yaw := raw_home_yaw + roundf((yaw_degrees - raw_home_yaw) / 360.0) * 360.0
	_axis_target_yaw = home_yaw
	if not smooth or focus_smoothing_duration <= 0.0 or Engine.is_editor_hint():
		target = home_target
		distance = home_distance
		yaw_degrees = raw_home_yaw
		pitch_degrees = home_pitch
		orthographic_size = home_size
		_apply(true)
		return
	_camera_tween = create_tween()
	_camera_tween.set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_camera_tween.tween_property(self, "target", home_target, focus_smoothing_duration)
	_camera_tween.tween_property(self, "distance", home_distance, focus_smoothing_duration)
	_camera_tween.tween_property(self, "yaw_degrees", home_yaw, focus_smoothing_duration)
	_camera_tween.tween_property(self, "pitch_degrees", home_pitch, focus_smoothing_duration)
	_camera_tween.tween_property(self, "orthographic_size", home_size, focus_smoothing_duration)


func set_invert_vertical(enabled: bool) -> void:
	invert_vertical_axis = enabled


func set_axis_lock(enabled: bool) -> void:
	axis_lock_enabled = enabled
	_axis_drag_degrees = 0.0
	if axis_lock_enabled:
		_axis_target_yaw = _nearest_axis_yaw(yaw_degrees)
		_start_axis_rotation()
	else:
		_kill_rotation_tween()
		_axis_target_yaw = yaw_degrees


func set_horizontal_rotation_lock(enabled: bool) -> void:
	horizontal_rotation_locked = enabled
	if horizontal_rotation_locked:
		_kill_rotation_tween()
		_axis_target_yaw = yaw_degrees
	_update_aggregate_angle_lock()


func set_vertical_rotation_lock(enabled: bool) -> void:
	vertical_rotation_locked = enabled
	_update_aggregate_angle_lock()


func set_angle_lock(enabled: bool) -> void:
	angle_lock_enabled = enabled
	horizontal_rotation_locked = enabled
	vertical_rotation_locked = enabled
	_axis_drag_degrees = 0.0
	if enabled:
		_kill_rotation_tween()
		_axis_target_yaw = yaw_degrees


func control_snapshot() -> Dictionary:
	return {
		"invertVertical": invert_vertical_axis,
		"axisLock": axis_lock_enabled,
		"horizontalLock": horizontal_rotation_locked,
		"verticalLock": vertical_rotation_locked,
		"angleLock": horizontal_rotation_locked and vertical_rotation_locked,
	}


func view_snapshot() -> Dictionary:
	return {
		"target": target,
		"distance": distance,
		"yawDegrees": yaw_degrees,
		"pitchDegrees": pitch_degrees,
		"orthographicSize": orthographic_size,
		"projectionMode": projection_mode,
		"fov": fov,
	}


func _resolve_camera() -> void:
	_cam = get_node_or_null(camera_path) as Camera3D
	if _cam != null:
		return
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	add_child(_cam)
	if Engine.is_editor_hint() and owner != null:
		_cam.owner = owner


func _apply(force: bool = false) -> void:
	if _cam == null:
		return
	var signature := "%s|%.4f|%.4f|%.4f|%d|%.4f|%.4f|%.4f|%.4f" % [
		target, distance, yaw_degrees, pitch_degrees, projection_mode,
		orthographic_size, fov, camera_near, camera_far,
	]
	if not force and signature == _last_signature:
		return
	_last_signature = signature
	pitch_degrees = clampf(pitch_degrees, min_pitch_degrees, max_pitch_degrees)
	distance = clampf(distance, min_distance, max_distance)
	orthographic_size = clampf(
		orthographic_size, min_orthographic_size, max_orthographic_size
	)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL if projection_mode == 0 else Camera3D.PROJECTION_PERSPECTIVE
	_cam.size = orthographic_size
	_cam.fov = fov
	_cam.near = camera_near
	_cam.far = camera_far
	_cam.current = true
	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var direction := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw),
	)
	_cam.global_position = target + direction * distance
	_cam.look_at(target, Vector3.UP)


func _zoom_by(factor: float) -> void:
	if projection_mode == 0:
		orthographic_size = clampf(
			orthographic_size * factor,
			min_orthographic_size,
			max_orthographic_size,
		)
	else:
		distance = clampf(distance * factor, min_distance, max_distance)
	_apply(true)


func _pan_pixels(relative: Vector2) -> void:
	var height := maxf(1.0, get_viewport().get_visible_rect().size.y)
	var world_per_pixel := (
		orthographic_size / height
		if projection_mode == 0
		else distance * 1.6 / height
	)
	var right := _ground_axis(_cam.global_transform.basis.x, Vector3.RIGHT)
	var forward := _ground_axis(-_cam.global_transform.basis.z, Vector3.FORWARD)
	target += (
		right * -relative.x + forward * relative.y
	) * world_per_pixel * mouse_pan_sensitivity


func _apply_keyboard_input(delta: float) -> void:
	var x := float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
	x -= float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	var y := float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	y -= float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
	var axis := Vector2(x, y).limit_length(1.0)
	if not axis.is_zero_approx():
		var right := _ground_axis(_cam.global_transform.basis.x, Vector3.RIGHT)
		var forward := _ground_axis(-_cam.global_transform.basis.z, Vector3.FORWARD)
		target += (right * axis.x + forward * axis.y) * keyboard_pan_speed * delta


func _ground_axis(value: Vector3, fallback: Vector3) -> Vector3:
	var planar := Vector3(value.x, 0.0, value.z)
	return fallback if planar.is_zero_approx() else planar.normalized()


func _apply_axis_drag_steps() -> void:
	var threshold := maxf(1.0, axis_drag_threshold)
	var changed := false
	while absf(_axis_drag_degrees) >= threshold:
		var direction := signf(_axis_drag_degrees)
		_axis_target_yaw += direction * rotation_step_degrees
		_axis_drag_degrees -= direction * threshold
		changed = true
	if changed:
		_start_axis_rotation()


func _snap_yaw_to_axis() -> void:
	yaw_degrees = _nearest_axis_yaw(yaw_degrees)


func _nearest_axis_yaw(value: float) -> float:
	var step := maxf(1.0, rotation_step_degrees)
	return _axis_reference_yaw + roundf((value - _axis_reference_yaw) / step) * step


func _start_axis_rotation() -> void:
	_kill_rotation_tween()
	var delta := absf(_axis_target_yaw - yaw_degrees)
	if delta <= 0.001 or step_rotation_duration <= 0.0 or Engine.is_editor_hint():
		yaw_degrees = _axis_target_yaw
		_apply(true)
		return
	var duration := clampf(
		step_rotation_duration * delta / maxf(1.0, rotation_step_degrees),
		step_rotation_duration * 0.55,
		step_rotation_duration * 2.2,
	)
	_rotation_tween = create_tween()
	_rotation_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_rotation_tween.tween_property(self, "yaw_degrees", _axis_target_yaw, duration)


func _update_aggregate_angle_lock() -> void:
	angle_lock_enabled = horizontal_rotation_locked and vertical_rotation_locked


func _kill_view_tween() -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = null


func _kill_rotation_tween() -> void:
	if _rotation_tween != null and _rotation_tween.is_valid():
		_rotation_tween.kill()
	_rotation_tween = null


func _kill_camera_tween() -> void:
	_kill_view_tween()
	_kill_rotation_tween()
