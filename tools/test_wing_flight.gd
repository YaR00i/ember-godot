extends SceneTree
## Flight math, the real player/camera, disposable collision and course lifecycle.

const Motion := preload("res://scripts/ember_wing_flight_motion.gd")
const Trial := preload("res://scripts/ember_wing_flight_trial.gd")
const Course := preload("res://scenes/wing_flight_trial.tscn")
var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func simulate(hz: int, controls: Vector3, throttle: float = 0.0, brake: float = 0.0) -> RefCounted:
	var motion := Motion.new()
	for frame in range(hz * 2):
		motion.step(1.0 / hz, controls, throttle, brake)
	return motion


func _run() -> void:
	var trial = Course.instantiate()
	trial.tuning_path = "user://ember-tests/flight-tuning-%d.json" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ember-tests"))
	root.add_child(trial)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await _capture(trial)
		trial.free()
		for failure in failures:
			push_error(failure)
		quit(0 if failures.is_empty() else 1)
		return
	var coast := simulate(60, Vector3.ZERO)
	check(absf(coast.velocity.length() - 26.0) < 0.01, "released triggers must hold selected speed")
	check(simulate(60, Vector3.ZERO, 1.0).velocity.length() > 40.0, "throttle should build speed")
	check(simulate(60, Vector3.ZERO, 0.0, 1.0).velocity.length() < 10.0, "brake should reduce speed")
	var roll := simulate(60, Vector3(0, 0, 1))
	for frame in range(120):
		roll.step(1.0 / 60, Vector3(0, 0, 1), 0, 0)
	check((-Basis(roll.orientation).z).distance_to(Vector3.FORWARD) < 0.001, "roll alone must not turn nose sideways")
	check(Basis(roll.orientation).y.dot(Vector3.UP) < -0.9, "roll must allow inversion without horizon correction")
	roll.reset(Quaternion(Vector3.FORWARD, PI / 2))
	for i in range(60):
		roll.step(1.0 / 60, Vector3(1, 0, 0), 0, 0)
	check((-Basis(roll.orientation).z).x > 0.2, "pitch after banking must turn in the body's local plane")
	check(roll.velocity.normalized().distance_to(-Basis(roll.orientation).z) > 0.08, "trajectory must lag body heading")
	var climb := Motion.new()
	climb.reset(Quaternion(Vector3.RIGHT, 0.4))
	var dive := Motion.new()
	dive.reset(Quaternion(Vector3.RIGHT, -0.4))
	for i in range(60):
		climb.step(1.0 / 60, Vector3.ZERO, 0, 0)
		dive.step(1.0 / 60, Vector3.ZERO, 0, 0)
	check(absf(dive.velocity.length() - 26.0) < 0.01 and absf(climb.velocity.length() - 26.0) < 0.01, "automatic speed hold must compensate climb/descent when triggers are released")
	_cruise_and_speed_authority_cases()
	_tuning_cases(trial)
	var sixty := simulate(60, Vector3(0.3, 0, 0.5))
	for hz in [30, 120]:
		var other = simulate(hz, Vector3(0.3, 0, 0.5))
		check(other.velocity.distance_to(sixty.velocity) < 0.5, "flight response diverged at %d Hz" % hz)
		check(absf(other.orientation.dot(sixty.orientation)) > 0.999, "rotation response diverged at %d Hz" % hz)
	var steady := Motion.new()
	for i in range(1800):
		steady.step(1.0 / 60, Vector3(0.8, 0.4, 1), 1, 0)
	check(steady.velocity.is_finite() and absf(steady.orientation.length() - 1) < 0.0001, "loops must remain finite and normalized")
	_tight_turn_cases()
	check(Trial.crosses_gate(Vector3(0, 0, 100), Vector3(0, 0, -100), Transform3D.IDENTITY), "swept crossing missed fast pass")
	check(not Trial.crosses_gate(Vector3(30, 0, 5), Vector3(30, 0, -5), Transform3D.IDENTITY), "missed gate counted")
	check(not Trial.crosses_gate(Vector3(0, 0, -5), Vector3(0, 0, 5), Transform3D.IDENTITY), "reverse gate counted")
	check(not trial.running and not trial.player.is_physics_processing(), "course must wait for explicit start")
	check(not trial.player.progress_state.persistence_enabled and not trial.player.progress_state.restore_enabled, "trial must isolate progress")
	trial.start_run()
	trial.player.set_physics_process(false)
	for angle in [0.0, PI / 2, PI, PI * 1.5, TAU]:
		trial.player.global_basis = Basis(Quaternion(Vector3.FORWARD, angle))
		trial.camera._process(0.016)
		var camera_error: float = trial.camera._cam.global_basis.get_rotation_quaternion().angle_to(trial.player.global_basis.get_rotation_quaternion())
		check(camera_error <= deg_to_rad(14.01), "camera lag must stay bounded during inversion")
		if angle > 0.0:
			check(camera_error > 0.01, "camera should not snap to a new roll")
		for frame in range(60):
			trial.camera._process(1.0 / 60)
		check(trial.camera._cam.global_basis.y.dot(trial.player.global_basis.y) > 0.9999, "camera must inherit full roll")
		check(trial.camera._cam.global_basis.z.dot(trial.player.global_basis.z) > 0.9999, "camera must inherit full facing")
		var projected: Vector2 = trial.camera._cam.unproject_position(trial.player.global_position)
		var viewport := root.get_visible_rect().size
		check(projected.y > viewport.y * 0.60 and projected.y < viewport.y * 0.9, "body must stay low in frame at roll %.2f" % angle)
	# Pitch past vertical: no world-up singularity and no centering flip.
	trial.player.global_basis = Basis(Quaternion(Vector3.RIGHT, PI * 0.55))
	for frame in range(60):
		trial.camera._process(1.0 / 60)
	check(trial.camera._cam.global_basis.y.dot(trial.player.global_basis.y) > 0.9999, "camera must inherit pitch past vertical")
	trial.player.flight_motion.angular_velocity = Vector3(1, 0, 0.8)
	for frame in range(40):
		trial.camera._process(1.0 / 60)
	check(trial.camera._flight_offset.y > 3.8, "camera should visibly rise under maneuver effort")
	var maneuver_screen: Vector2 = trial.camera._cam.unproject_position(trial.player.global_position)
	var maneuver_height := root.get_visible_rect().size.y
	check(maneuver_screen.y > maneuver_height * 0.75 and maneuver_screen.y < maneuver_height * 0.87, "strong maneuver should visibly lower body in frame without losing it")
	var lifted: float = trial.camera._flight_offset.y
	trial.player.flight_motion.angular_velocity = Vector3.ZERO
	trial.camera._process(1.0 / 60)
	check(trial.camera._flight_offset.y < lifted and trial.camera._flight_offset.y > 2.4, "camera lift must recover smoothly, without snapping")
	for frame in range(120):
		trial.camera._process(1.0 / 60)
	check(absf(trial.camera._flight_offset.y - 2.4) < 0.005, "camera must settle back after the turn")
	trial.player.flight_motion.angular_velocity = Vector3(-1, 0, 0)
	for frame in range(60):
		trial.camera._process(1.0 / 60)
	check(trial.camera._flight_offset.y < 1.5, "pushing nose down must move camera oppositely to pulling up")
	var dive_screen: Vector2 = trial.camera._cam.unproject_position(trial.player.global_position)
	check(dive_screen.y > maneuver_height * 0.55 and dive_screen.y < maneuver_height * 0.70, "dive must retain body below center")
	trial.player.velocity = Vector3(0, 0, -500)
	var previous_fov: float = trial.camera._cam.fov
	trial.camera._process(1.0 / 60)
	check(trial.camera._cam.fov > previous_fov and trial.camera._cam.fov < previous_fov + 1.0, "speed FOV must widen gradually")
	for frame in range(120):
		trial.camera._process(1.0 / 60)
	check(trial.camera._cam.fov > 85.0, "top speed should visibly widen FOV")
	trial.start_run()
	trial.camera._process(1.0 / 60)
	check(trial.camera._flight_offset.is_equal_approx(Vector3(0, 2.4, 10)), "restart must clear camera lag and lift")
	var back_basis: Basis = trial.camera._cam.global_basis
	for frame in range(45):
		trial.camera._update_wing_flight(1.0 / 60, Vector2(1, -0.6))
	check(back_basis.z.angle_to(trial.camera._cam.global_basis.z) > deg_to_rad(70), "right stick must orbit around aircraft")
	check(trial.camera._cam.unproject_position(trial.player.global_position).y > root.get_visible_rect().size.y * 0.55, "orbit must retain body low in frame")
	for frame in range(120):
		trial.camera._update_wing_flight(1.0 / 60)
	check(back_basis.z.angle_to(trial.camera._cam.global_basis.z) < 0.001, "released look must return smoothly behind aircraft")
	trial.camera.configure_flight({"lag_seconds": 0.6, "lag_angle_deg": 30})
	trial.player.global_basis = trial.player.global_basis.rotated(trial.player.global_basis.z, deg_to_rad(45))
	trial.camera._update_wing_flight(1.0 / 60)
	var custom_lag: float = trial.camera._cam.global_basis.get_rotation_quaternion().angle_to(trial.player.global_basis.get_rotation_quaternion())
	check(custom_lag > deg_to_rad(20) and custom_lag < deg_to_rad(30.1), "camera settings must allow visibly larger bounded lag")
	trial.camera.configure_flight({"lag_angle_deg": 0})
	trial.camera._update_wing_flight(1.0 / 60)
	check(trial.camera._cam.global_basis.get_rotation_quaternion().angle_to(trial.player.global_basis.get_rotation_quaternion()) < 0.001, "zero lag limit must follow immediately")
	trial.camera.configure_flight({})
	trial.player.set_physics_process(false)
	trial._show_menu("test pause", "resume")
	var before_pause: float = trial.elapsed
	trial._physics_process(1.0)
	check(trial.elapsed == before_pause and not trial.player.is_physics_processing(), "pause must freeze time and motion")
	trial._start_or_resume()
	check(trial.player.is_physics_processing() and not trial._menu.visible, "resume must release pause")
	trial.player.set_physics_process(false)
	# Real CharacterBody sweep against a disposable solid, never an author map.
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 1)
	collision.shape = box
	wall.add_child(collision)
	wall.position = trial.player.position + Vector3(0, 0, -1.8)
	trial.add_child(wall)
	await physics_frame
	await physics_frame
	trial.player._tick_flight(1.0 / 60)
	check(trial._reset_pending, "real collision must request restart")
	await process_frame
	trial.player.set_physics_process(false)
	check(trial.next_gate == 0 and trial.player.position.distance_to(trial.get_node("Start").position) < 0.1, "collision must reset course and body")
	wall.free()
	# Exact course progression and finish; no party/battle/save transition.
	for gate in trial.gates:
		trial.previous_position = gate.global_position + gate.global_basis.z * 5
		trial.player.global_position = gate.global_position - gate.global_basis.z * 5
		trial._physics_process(0.016)
	check(trial.next_gate == 6 and not trial.running and trial._menu.visible, "six forward gates must finish and offer replay")
	trial.start_run()
	trial.player.set_physics_process(false)
	check(trial.next_gate == 0 and trial.elapsed == 0 and trial.player.flight_motion.angular_velocity == Vector3.ZERO, "replay must clear progress, time and rotation inertia")
	trial.player.end_wing_flight()
	trial.camera._process(0.016)
	check(is_equal_approx(trial.camera._cam.fov, trial.camera.fov), "ground return must restore configured lens")
	check(trial.player.flight_motion == null and not trial.camera.wing_flight_view and trial.player.motion_mode == CharacterBody3D.MOTION_MODE_GROUNDED, "exit must restore ground movement/camera")
	trial.free()
	for failure in failures:
		push_error(failure)
	print("PASS wing flight: inertia, local bank/pitch, throttle/brake, dive/climb, 30/60/120Hz, full-roll camera/framing, collision/restart, pause, gates/finish/replay, isolated progress, ground return" if failures.is_empty() else "FAIL wing flight")
	quit(0 if failures.is_empty() else 1)


func _cruise_and_speed_authority_cases() -> void:
	for initial in [26.0, 208.0 / 3.6]:
		var cruise := Motion.new()
		cruise.reset(Quaternion.IDENTITY, initial)
		for frame in range(600):
			cruise.step(1.0 / 60, Vector3.ZERO, 0.02, 0.02)
		check(absf(cruise.velocity.length() - initial) * 3.6 < 0.05, "selected cruise speed must hold for ten seconds despite trigger noise")
	var accelerating := simulate(60, Vector3.ZERO, 1, 0)
	var released: float = accelerating.velocity.length()
	for frame in range(600):
		accelerating.step(1.0 / 60, Vector3.ZERO, 0, 0)
	check(absf(accelerating.velocity.length() - released) * 3.6 < 0.05, "releasing accelerator must hold speed actually reached")
	for frame in range(30):
		accelerating.step(1.0 / 60, Vector3.ZERO, 0, 1)
	var braked: float = accelerating.velocity.length()
	check(braked < released - 5, "brake must lower selected speed")
	for frame in range(300):
		accelerating.step(1.0 / 60, Vector3.ZERO, 0, 0)
	check(absf(accelerating.velocity.length() - braked) * 3.6 < 0.05, "releasing brake must hold new lower speed, not restore former cruise")
	var angles: Array[float] = []
	var radii: Array[float] = []
	for initial in [8.0, 100.0, 500.0]:
		var turning := Motion.new()
		turning.reset(Quaternion(Vector3.FORWARD, PI / 2), initial)
		var position := Vector3.ZERO
		for frame in range(120):
			turning.step(1.0 / 60, Vector3(1, 0, 0), 0, 0)
			position += turning.velocity / 60
		var angle := Vector3.FORWARD.angle_to(turning.velocity.normalized())
		angles.append(angle)
		radii.append(position.length() / angle)
	check(angles[0] < angles[1] * 0.5, "low speed should weaken turn authority")
	check(angles[2] < angles[1] * 0.7 and radii[2] > radii[1] * 2, "high speed should require a wider actual turn than medium speed")
	var onset := Motion.new()
	onset.step(1.0 / 60, Vector3(1, 0, 1), 0, 0)
	check(onset.angular_velocity.length() < 0.08, "first input frame must build angular momentum rather than snap")
	onset.reset()
	check(is_equal_approx(onset.cruise_speed, 26.0), "restart must clear selected cruise speed")
	var fast := Motion.new()
	fast.reset(Quaternion.IDENTITY, 100)
	for frame in range(720):
		fast.step(1.0 / 60, Vector3.ZERO, 1, 0)
	check(fast.velocity.length() * 3.6 > 1700 and fast.velocity.length() * 3.6 <= 1800.1, "jet speed range must be reachable and bounded")
	var jet_speed: float = fast.velocity.length()
	for frame in range(120):
		fast.step(1.0 / 60, Vector3.ZERO, 0, 0)
	check(absf(fast.velocity.length() - jet_speed) < 0.01, "jet speed must hold after release")


func _tuning_cases(trial: Node3D) -> void:
	trial._tuning_sliders["pitch_rate_deg"].value = 55
	check(trial.tuning.pitch_rate_deg == 55 and trial.player.flight_motion.tuning.pitch_rate_deg == 55, "slider must configure actual flight state")
	trial._tuning_sliders["camera_lag_angle_deg"].value = 28
	trial._tuning_sliders["camera_push_shift"].value = 3.2
	check(trial.camera.flight_tuning.lag_angle_deg == 28 and is_equal_approx(trial.camera.flight_tuning.push_shift, 3.2), "camera sliders must configure the active camera")
	check(trial.save_tuning(), "tuning save failed")
	var saved := FileAccess.get_file_as_string(trial.tuning_path)
	trial.reset_tuning()
	check(trial.tuning.pitch_rate_deg == 40 and FileAccess.get_file_as_string(trial.tuning_path) == saved, "reset must restore session without overwriting saved tuning")
	check(trial.load_tuning() and trial.tuning.pitch_rate_deg == 55 and trial._tuning_sliders["pitch_rate_deg"].value == 55, "load must restore saved settings and slider")
	check(trial.camera.flight_tuning.lag_angle_deg == 28, "camera tuning must survive save/reset/load")
	var reopened = Course.instantiate()
	reopened.tuning_path = trial.tuning_path
	root.add_child(reopened)
	check(reopened.tuning.pitch_rate_deg == 55 and reopened.player.flight_motion.tuning.pitch_rate_deg == 55, "cold scene reopen must apply persisted tuning")
	check(reopened.camera.flight_tuning.lag_angle_deg == 28, "cold reopen must apply persisted camera")
	reopened.free()
	var broken := FileAccess.open(trial.tuning_path, FileAccess.WRITE)
	broken.store_string("not json")
	broken.close()
	check(not trial.load_tuning() and trial.tuning.pitch_rate_deg == 55, "invalid tuning file must preserve current session")
	var bounded := Motion.sanitize({"pitch_rate_deg": 99999, "max_speed_kmh": INF, "roll_rate_deg": "wrong", "unknown": 1})
	check(bounded.pitch_rate_deg == 100 and bounded.max_speed_kmh == 1800 and bounded.roll_rate_deg == 70 and not bounded.has("unknown"), "tuning validation must reject nonfinite/type errors, clamp values, ignore unknowns")
	var camera_bounds: Dictionary = trial.FollowCamera.sanitize_flight({"push_shift": 999, "lag_seconds": INF, "speed_fov": "bad"})
	check(camera_bounds.push_shift == 4 and camera_bounds.speed_fov == 14 and camera_bounds.lag_seconds < 0.2, "camera validation must reject invalid values")
	var legacy := FileAccess.open(trial.tuning_path, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version": 1, "values": {"pitch_rate_deg": 65}}))
	legacy.close()
	check(trial.load_tuning() and trial.tuning.pitch_rate_deg == 65 and trial.camera.flight_tuning.lag_angle_deg == 14, "legacy flight-only file must load with camera defaults")
	trial.reset_tuning()


func _tight_turn_cases() -> void:
	var regular := Motion.new()
	var tighter := Motion.new()
	var bank := Quaternion(Vector3.FORWARD, PI / 2)
	regular.reset(bank, 38)
	tighter.reset(bank, 38)
	var regular_position := Vector3.ZERO
	var tight_position := Vector3.ZERO
	for frame in range(48):
		regular.step(1.0 / 60, Vector3(1, 0, 0), 0, 0)
		tighter.step(1.0 / 60, Vector3(1, 0, 0), 1, 1)
		regular_position += regular.velocity / 60
		tight_position += tighter.velocity / 60
	var normal_angle := Vector3.FORWARD.angle_to(regular.velocity.normalized())
	var tight_angle := Vector3.FORWARD.angle_to(tighter.velocity.normalized())
	check(tight_angle > normal_angle * 1.3, "tight turn must redirect actual velocity, not just rotate body")
	check(tighter.velocity.length() < regular.velocity.length() - 5, "tight turn must spend speed")
	check(tight_position.length() / tight_angle < regular_position.length() / normal_angle * 0.8, "tight turn must reduce trajectory radius")
	for hz in [30, 120]:
		var other := Motion.new()
		other.reset(bank, 38)
		for frame in range(roundi(hz * 0.8)):
			other.step(1.0 / hz, Vector3(1, 0, 0), 1, 1)
		check(other.velocity.distance_to(tighter.velocity) < 0.8, "tight-turn trajectory diverged at %d Hz" % hz)
		check(absf(other.orientation.dot(tighter.orientation)) > 0.999, "tight-turn rotation diverged at %d Hz" % hz)
	for controls in [Vector3.ZERO, Vector3(-1, 0, 0), Vector3(0, 0, 1)]:
		var inactive := Motion.new()
		inactive.step(0.1, controls, 1, 1)
		check(is_zero_approx(inactive.tight_turn), "straight/negative-pitch/roll must not trigger tight turn")
	for triggers in [Vector2(1, 0), Vector2(0, 1)]:
		var single := Motion.new()
		single.step(0.1, Vector3(1, 0, 0), triggers.x, triggers.y)
		check(is_zero_approx(single.tight_turn), "single trigger must not trigger tight turn")
	var slow := Motion.new()
	slow.reset(Quaternion.IDENTITY, 8)
	for frame in range(60):
		slow.step(1.0 / 60, Vector3(1, 0, 0), 1, 1)
	check(is_zero_approx(slow.tight_turn), "slow flight must not grant free tight-turn authority")
	tighter.reset()
	check(is_zero_approx(tighter.tight_turn), "restart must clear tight turn")


func _capture(trial: Node3D) -> void:
	var directory := "user://ember-tests/wing-flight"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + "/menu.png")
	if "--menu-only" in OS.get_cmdline_user_args():
		var tabs: TabContainer = trial._tuning_sliders["camera_lag_angle_deg"].get_parent().get_parent()
		tabs.current_tab = 1
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory + "/camera-menu.png")
	if "--menu-only" in OS.get_cmdline_user_args():
		print("FLIGHT MENU CAPTURE: " + ProjectSettings.globalize_path(directory + "/menu.png"))
		return
	trial.start_run()
	trial.player.set_physics_process(false)
	for degrees in [0, 90, 180]:
		trial.player.global_basis = Basis(Quaternion(Vector3.FORWARD, deg_to_rad(degrees)))
		trial.camera._process(0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory + "/roll-%d.png" % degrees)
	print("FLIGHT CAPTURE: " + ProjectSettings.globalize_path(directory))
	# Forward+ input/physics smoke, through the same physical-key path as play.
	trial.start_run()
	_key(KEY_SPACE, true)
	_key(KEY_D, true)
	for frame in range(45):
		await physics_frame
	_key(KEY_D, false)
	_key(KEY_S, true)
	for frame in range(25):
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + "/maneuver.png")
	_key(KEY_S, false)
	_key(KEY_SPACE, false)
	check(trial.player.velocity.length() > 30.0, "Forward+ physical throttle input did not accelerate")
	check(trial.player.global_basis.y.dot(Vector3.UP) < 0.95, "Forward+ physical roll input did not bank")
	check(absf(trial.player.velocity.x) > 0.1, "Forward+ bank/pitch input did not turn trajectory")
	var position_before: Vector3 = trial.player.position
	var speed_before: float = trial.player.velocity.length()
	for frame in range(12):
		await physics_frame
	check(trial.player.position.distance_to(position_before) > 3.0, "Forward+ release lost inertia")
	check(absf(trial.player.velocity.length() - speed_before) < 0.05, "Forward+ released throttle did not hold reached speed")
	_key(KEY_ESCAPE, true)
	await process_frame
	_key(KEY_ESCAPE, false)
	await process_frame
	check(trial._menu.visible and not trial.player.is_physics_processing(), "Forward+ Esc did not pause")
	var position_paused: Vector3 = trial.player.position
	for frame in range(5):
		await physics_frame
	check(trial.player.position.is_equal_approx(position_paused), "Forward+ pause allowed motion")
	_key(KEY_ESCAPE, true)
	await process_frame
	_key(KEY_ESCAPE, false)
	await process_frame
	check(not trial._menu.visible and trial.player.is_physics_processing(), "Forward+ Esc did not resume")
	trial.start_run()
	_key(KEY_SPACE, true)
	_key(KEY_SHIFT, true)
	_key(KEY_S, true)
	var peak_tight_turn := 0.0
	for frame in range(30):
		await physics_frame
		peak_tight_turn = maxf(peak_tight_turn, trial.player.flight_motion.tight_turn)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + "/tight-turn.png")
	_key(KEY_SPACE, false)
	_key(KEY_SHIFT, false)
	_key(KEY_S, false)
	check(peak_tight_turn > 0.2, "Forward+ physical dual-trigger equivalent did not activate tight turn")
	var screen: Vector2 = trial.camera._cam.unproject_position(trial.player.global_position)
	check(screen.y > root.get_visible_rect().size.y * 0.60 and screen.y < root.get_visible_rect().size.y * 0.85, "camera maneuver lift lost the body framing")
	trial.start_run()
	var mouse_button := InputEventMouseButton.new()
	mouse_button.button_index = MOUSE_BUTTON_RIGHT
	mouse_button.pressed = true
	Input.parse_input_event(mouse_button)
	await process_frame
	var mouse_motion := InputEventMouseMotion.new()
	mouse_motion.relative = Vector2(180, 30)
	Input.parse_input_event(mouse_motion)
	for frame in range(12):
		await process_frame
	check(absf(trial.camera._flight_orbit.x) > 0.3, "Forward+ RMB mouse input must orbit camera")
	mouse_button = InputEventMouseButton.new()
	mouse_button.button_index = MOUSE_BUTTON_RIGHT
	mouse_button.pressed = false
	Input.parse_input_event(mouse_button)
	for frame in range(35):
		await process_frame
	check(absf(trial.camera._flight_orbit.x) < 0.01, "released RMB must return camera behind plane")
	trial.player.set_physics_process(false)
	print("PASS Forward+ flight input, bank/pitch, throttle, release, pause/resume" if failures.is_empty() else "FAIL Forward+ flight smoke")


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
