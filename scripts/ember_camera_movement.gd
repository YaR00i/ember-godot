class_name EmberCameraMovement
extends RefCounted
## Pure camera-yaw projection shared by runtime and headless tests.
## Input axes: X = left/right, Y = forward/back (forward is negative).


static func world_direction(input_axis: Vector2, camera_yaw: float) -> Vector3:
	var planar := input_axis.limit_length(1.0)
	if planar.is_zero_approx():
		return Vector3.ZERO
	var cosine := cos(camera_yaw)
	var sine := sin(camera_yaw)
	return Vector3(
		planar.x * cosine + planar.y * sine,
		0.0,
		-planar.x * sine + planar.y * cosine,
	)
