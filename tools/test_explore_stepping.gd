extends SceneTree
## Real CharacterBody/world collision fixture, independent of authored scenes/saves.

const Player := preload("res://scripts/ember_player.gd")
const FollowCamera := preload("res://scripts/ember_follow_camera.gd")
var errors: Array[String] = []
var fixture: Node3D
var player: EmberPlayer
var capture := false


func _init() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if progress != null:
		progress.persistence_enabled = false
		progress.restore_enabled = false
		progress.reset_new_game()
	for hz in [30, 60, 120]:
		await _walk_case(4.0, false, hz, true)
	await _walk_case(0.5, false, 60, true)
	await _walk_case(4.5, false, 60, false)
	await _walk_case(4.0, true, 60, false)
	await _stairs_case()
	await _diagonal_case()
	await _cancel_case()
	await _camera_case()
	if errors.is_empty():
		print("PASS exploration stepping: physical smooth ascent at 30/60/120Hz, small detail, stairs, diagonal, high wall, ceiling, cancellation, camera height-only lag/reset")
	else:
		for error in errors:
			push_error(error)
	quit(0 if errors.is_empty() else 1)


func _box(center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	body.position = center
	fixture.add_child(body)
	if capture:
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		visual.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		visual.material_override = material
		body.add_child(visual)


func _setup(height: float, ceiling: bool, width: float = 24.0) -> void:
	fixture = Node3D.new()
	root.add_child(fixture)
	_box(Vector3(5, -2, 0), Vector3(60, 4, 32), Color("ae885b"))
	_box(Vector3(18, height * 0.5, 0), Vector3(20, height, width), Color("edbc79"))
	if ceiling:
		_box(Vector3(7, 15, 0), Vector3(30, 2, 26), Color("75614e"))
	player = Player.new()
	fixture.add_child(player)
	player.set_physics_process(false)
	if capture:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-60, -25, 0)
		fixture.add_child(light)
		var camera := FollowCamera.new()
		camera.target = player
		camera.yaw = 0.0
		camera.follow_distance = 58.0
		player.camera_rig = camera
		fixture.add_child(camera)
	for frame in 20:
		await physics_frame
		player._physics_process(1.0 / 60.0)


func _teardown() -> void:
	Input.action_release("move_east")
	Input.action_release("move_west")
	fixture.queue_free()
	await process_frame
	await physics_frame


func _walk_case(height: float, ceiling: bool, hz: int, should_pass: bool) -> void:
	Engine.physics_ticks_per_second = hz
	await _setup(height, ceiling)
	Input.action_press("move_east")
	var previous_y := player.position.y
	var max_up := 0.0
	var intermediate := false
	var captured := false
	for frame in int(hz * 0.42):
		await physics_frame
		player._physics_process(1.0 / float(hz))
		max_up = maxf(max_up, player.position.y - previous_y)
		intermediate = intermediate or (player.position.y > 0.15 and player.position.y < height - 0.15)
		previous_y = player.position.y
		if capture and not captured and height == 4.0 and hz == 60 and not ceiling and player.position.y > 1.0 and player.position.y < 3.0:
			await process_frame
			await RenderingServer.frame_post_draw
			var path := "user://explore-step-mid-ascent.png"
			root.get_texture().get_image().save_png(path)
			print("CAPTURE ", ProjectSettings.globalize_path(path))
			captured = true
	print("step height=", height, " ceiling=", ceiling, " hz=", hz, " position=", player.position, " maxUp=", max_up, " active=", player.get("_step_active"), " top=", player.get("_step_top"))
	if should_pass:
		if player.position.x < 12.0 or absf(player.position.y - height) > 0.08:
			errors.append("did not climb height %s at %sHz: %s" % [height, hz, player.position])
		if height == 4.0 and (not intermediate or max_up > 4.0 / Player.STEP_SECONDS / hz + 0.12):
			errors.append("physical ascent jumped instead of moving smoothly at %sHz (max %s)" % [hz, max_up])
	else:
		if player.position.x > 6.0 or player.position.y > 0.1:
			errors.append("unsafe step passed high wall/ceiling: %s" % player.position)
	await _teardown()
	Engine.physics_ticks_per_second = 60


func _cancel_case() -> void:
	await _setup(4.0, false)
	Input.action_press("move_east")
	for frame in 25:
		await physics_frame
		player._physics_process(1.0 / 60.0)
		if player.get("_step_active"):
			break
	Input.action_release("move_east")
	for frame in 40:
		await physics_frame
		player._physics_process(1.0 / 60.0)
	if player.get("_step_active") or player.position.y > 0.05:
		errors.append("released input left player hovering mid-step")
	await _teardown()


func _stairs_case() -> void:
	await _setup(4.0, false)
	_box(Vector3(36, 4, 0), Vector3(24, 8, 24), Color("dfaa68"))
	await physics_frame
	Input.action_press("move_east")
	var max_up := 0.0
	for frame in 65:
		await physics_frame
		var before := player.position.y
		player._physics_process(1.0 / 60.0)
		max_up = maxf(max_up, player.position.y - before)
	if player.position.x < 30 or absf(player.position.y - 8) > 0.08 or max_up > 0.54:
		errors.append("consecutive treads lost smooth ascent: %s, maxUp %s" % [player.position, max_up])
	await _teardown()


func _diagonal_case() -> void:
	await _setup(4.0, false, 64.0)
	Input.action_press("move_east")
	Input.action_press("move_north")
	for frame in 36:
		await physics_frame
		player._physics_process(1.0 / 60.0)
	Input.action_release("move_north")
	if player.position.x < 12 or absf(player.position.y - 4) > 0.08:
		errors.append("diagonal approach did not climb the tread: %s" % player.position)
	await _teardown()


func _camera_case() -> void:
	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(2, 40, 5)
	var camera := FollowCamera.new()
	camera.target = target
	root.add_child(camera)
	camera.set_process(false)
	camera._process(1.0 / 60.0)
	if not is_equal_approx(camera.get("_follow_height"), 46.0):
		errors.append("camera initialization lagged from unrelated height")
	target.position += Vector3(3, 4, 2)
	camera._process(1.0 / 60.0)
	var height := float(camera.get("_follow_height"))
	if height <= 46.0 or height >= 50.0:
		errors.append("camera did not lag only the upward height change")
	target.position.y -= 0.01
	camera._process(1.0 / 60.0)
	if absf(float(camera.get("_follow_height")) - (height - 0.01)) > 0.0001:
		errors.append("small tread recovery erased camera ascent lag")
	target.position.y += 0.01
	var camera_node := camera.get_node("Camera3D") as Camera3D
	var direction := Vector3(sin(camera.polar_angle) * sin(camera.yaw), cos(camera.polar_angle), sin(camera.polar_angle) * cos(camera.yaw))
	var look := camera_node.position - direction * camera.follow_distance
	if absf(look.x - target.position.x) > 0.0001 or absf(look.z - target.position.z) > 0.0001:
		errors.append("height smoothing introduced horizontal lag")
	for frame in 90:
		camera._process(1.0 / 60.0)
	if absf(float(camera.get("_follow_height")) - 50.0) > 0.001:
		errors.append("camera did not settle after ascent stopped")
	target.position.y -= 4.0
	camera._process(1.0 / 60.0)
	if not is_equal_approx(camera.get("_follow_height"), 46.0):
		errors.append("camera added unrequested descent lag")
	target.position.y += 8.0
	camera.reset_follow_height()
	camera._process(1.0 / 60.0)
	if not is_equal_approx(camera.get("_follow_height"), 54.0):
		errors.append("camera reset did not snap to respawn/save height")
	camera.queue_free()
	target.queue_free()
	await process_frame
