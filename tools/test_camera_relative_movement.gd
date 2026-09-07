extends SceneTree
## Wave 4 movement contract: WASD follows camera yaw on the ground plane.

const CameraMovement = preload("res://scripts/ember_camera_movement.gd")
const EPSILON := 0.00001


func _init() -> void:
	var errors: Array[String] = []
	_expect(errors, "yaw 0 W", CameraMovement.world_direction(Vector2(0, -1), 0.0), Vector3(0, 0, -1))
	_expect(errors, "yaw 0 D", CameraMovement.world_direction(Vector2(1, 0), 0.0), Vector3(1, 0, 0))
	_expect(errors, "yaw 90 W", CameraMovement.world_direction(Vector2(0, -1), PI * 0.5), Vector3(-1, 0, 0))
	_expect(errors, "yaw 90 D", CameraMovement.world_direction(Vector2(1, 0), PI * 0.5), Vector3(0, 0, -1))
	var diagonal := CameraMovement.world_direction(Vector2(1, -1), PI * 0.25)
	if absf(diagonal.length() - 1.0) > EPSILON:
		errors.append("diagonal movement is not normalized")
	if absf(diagonal.y) > EPSILON:
		errors.append("camera pitch leaked into ground movement")
	if not errors.is_empty():
		printerr("FAIL camera-relative movement")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS camera-relative movement")
	print("  W follows camera forward; D follows camera right")
	print("  diagonal speed normalized; pitch excluded")
	quit(0)


func _expect(errors: Array[String], label: String, actual: Vector3, expected: Vector3) -> void:
	if not actual.is_equal_approx(expected):
		errors.append("%s expected %s, got %s" % [label, expected, actual])
