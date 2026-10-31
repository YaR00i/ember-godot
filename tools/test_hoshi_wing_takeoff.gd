extends SceneTree
## Walking/jump/deploy/boost in the existing player, plus frame-rate/state invariants.
const Flap := preload("res://scripts/ember_wing_flap_motion.gd")
var failures: Array[String] = []
func _init() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func tick(motion: RefCounted, seconds: float, trigger: float = 0.0, hz: int = 60, controls := Vector3.ZERO) -> void:
	for i in range(roundi(seconds * hz)):
		motion.step(1.0 / hz, controls, trigger, 0.0)
func press_space(trial: Node, echo_event := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	event.echo = echo_event
	trial._input(event)
func _math_cases() -> void:
	for hz in [30, 60, 120]:
		var motion := Flap.new()
		motion.reset()
		motion.jump_pressed()
		check(motion.phase == Flap.Phase.STANDING, "cannot start a grounded jump without support")
		motion.ground_supported = true
		motion.jump_pressed()
		tick(motion, 0.2, 0, hz)
		check(motion.phase == Flap.Phase.JUMPING and motion.velocity.y > 0, "first press is an ordinary jump")
		motion.jump_pressed()
		tick(motion, 0.5, 0, hz)
		check(motion.phase == Flap.Phase.DEPLOYING and motion.cocoon_progress() > 0.4, "second press deploys cocoon")
		check(motion.orientation.is_equal_approx(Quaternion.IDENTITY), "cocoon must not spin physical orientation")
		tick(motion, 0.7, 0, hz)
		check(motion.phase == Flap.Phase.FLYING and motion.velocity.length() > 20, "deployment must launch without RT")
		var supports: int = motion.support_count
		tick(motion, 4, 0, hz)
		check(motion.support_count > supports, "level flight automatically flaps")
		motion.orientation = Quaternion(Vector3.RIGHT, -0.65)
		motion.velocity = -Basis(motion.orientation).z * motion.cruise_speed
		motion.flap_age = 0.3
		supports = motion.support_count
		tick(motion, 5, 0, hz)
		check(motion.is_diving() and motion.flap_age < 0 and motion.support_count == supports, "dive glides without support flaps")
		motion.orientation = Quaternion.IDENTITY
		tick(motion, 0.2, 1, hz)
		check(motion.boost_count == 1 and motion.impulse_count == 0, "boost windup has no early impulse")
		tick(motion, 5, 1, hz)
		check(motion.boost_count == 1 and motion.impulse_count == 1, "held RT produces one boost")
		for i in range(3):
			tick(motion, 0.1, 0, hz)
			tick(motion, 0.1, 1, hz)
		tick(motion, 4, 0, hz)
		check(motion.boost_count == 4 and motion.impulse_count == 4 and motion.queued_boosts == 0, "three taps produce three queued boosts")
		motion.suspend_trigger()
		tick(motion, 2, 1, hz)
		check(motion.boost_count == 4, "held menu RT cannot generate a boost on resume")
		for direction in [-1, 1]:
			motion.orientation = Quaternion.IDENTITY
			for frame in range(hz * 8):
				motion.step(1.0 / hz, Vector3(0, 0, direction), 0, 0)
				check(Basis(motion.orientation).y.dot(Vector3.UP) >= -0.001, "bank must remain within 90 degrees")
		motion.reset()
		check(motion.phase == Flap.Phase.STANDING and motion.queued_boosts == 0 and motion.boost_age < 0, "reset removes cocoon/queue")

func _run() -> void:
	_math_cases()
	var trial = load("res://scenes/wing_flight_trial.tscn").instantiate()
	trial.hoshi_mode = true
	trial.tuning_path = "user://ember-tests/hoshi-wing-test.json"
	root.add_child(trial)
	await process_frame
	# This fixture drives frames/input explicitly; OS focus changes must not
	# pause it halfway through a scripted jump. Runtime keeps its focus guard.
	if root.focus_exited.is_connected(trial._focus_lost):
		root.focus_exited.disconnect(trial._focus_lost)
	check(trial._hoshi_ready, "local Hoshi / native wing clips must load")
	if trial._hoshi_ready:
		trial.start_run()
		trial.player.set_physics_process(false)
		trial.set_physics_process(false)
		for i in range(5):
			await frame(trial)
		check(trial.player.is_on_floor() and not trial.hoshi_visual.wings.visible, "standing on platform without wings")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_W
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		var start: Vector3 = trial.player.position
		for i in range(20): await frame(trial)
		check(trial.player.position.distance_to(start) > 0.8 and trial.hoshi_visual.hoshi.motion.current_animation == "walk", "real WASD walks Hoshi")
		key.pressed = false
		Input.parse_input_event(key)
		await process_frame
		await capture(trial, "walking")
		press_space(trial)
		for i in range(12): await frame(trial)
		press_space(trial, true)
		check(trial.player.flight_motion.phase == Flap.Phase.JUMPING and not trial.hoshi_visual.wings.visible, "held/echo jump cannot reveal wings")
		for i in range(85): await frame(trial)
		check(trial.player.flight_motion.phase == Flap.Phase.STANDING and trial.player.is_on_floor(), "one jump lands without deploying")
		press_space(trial)
		for i in range(12): await frame(trial)
		var jump_button := InputEventJoypadButton.new()
		jump_button.button_index = JOY_BUTTON_A
		jump_button.pressed = true
		trial._input(jump_button)
		for i in range(28): await frame(trial)
		check(trial.player.flight_motion.phase == Flap.Phase.DEPLOYING and trial.hoshi_visual.wings.visible, "second jump reveals cocoon")
		check(absf(trial.hoshi_visual.rotation.z) > 0.5 and trial.player.global_basis.is_equal_approx(Basis.IDENTITY), "only model spins, camera/body orientation unchanged")
		await capture(trial, "deploy-cocoon")
		for i in range(45): await frame(trial)
		check(trial.player.flight_motion.phase == Flap.Phase.FLYING and trial.player.velocity.length() > 20, "jump/deploy transitions into actual flight")
		await capture(trial, "flight")
		key.physical_keycode = KEY_CTRL
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		for i in range(28): await frame(trial)
		check(trial.player.flight_motion.boost_count == 1 and trial.player.flight_motion.impulse_count == 1, "real Ctrl drives cocoon boost")
		await capture(trial, "boost-cocoon")
		var age: float = trial.player.flight_motion.boost_age
		var pos: Vector3 = trial.player.position
		trial._show_menu("Пауза", "Продолжить")
		for i in range(5): await physics_frame
		check(trial.player.position == pos and trial.player.flight_motion.boost_age == age, "pause freezes cocoon and motion")
		trial._menu.hide()
		for i in range(100): await frame(trial)
		check(trial.player.flight_motion.boost_count == 1, "held Ctrl doesn't repeat after pause")
		key.pressed = false
		Input.parse_input_event(key)
		await process_frame
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			var trigger := InputEventJoypadMotion.new()
			trigger.device = pads[0]
			trigger.axis = JOY_AXIS_TRIGGER_RIGHT
			trigger.axis_value = 0.0
			Input.parse_input_event(trigger)
			await process_frame
			await frame(trial)
			trigger.axis_value = 1.0
			Input.parse_input_event(trigger)
			await process_frame
			for i in range(80): await frame(trial)
			check(trial.player.flight_motion.boost_count == 2 and trial.player.flight_motion.impulse_count == 2, "actual RT axis held produces one additional cocoon boost")
			trigger.axis_value = 0.0
			Input.parse_input_event(trigger)
			await process_frame
		var wall := StaticBody3D.new()
		var solid := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(10, 10, 0.2)
		solid.shape = box
		wall.add_child(solid)
		trial.add_child(wall)
		wall.position = trial.player.position + Vector3(0, 0, -0.7)
		await physics_frame
		trial.player._tick_flight(1.0 / 30)
		check(trial._reset_pending, "actual collision requests restart")
		await process_frame
		trial.player.set_physics_process(false)
		wall.free()
		check(trial.player.flight_motion.phase == Flap.Phase.STANDING and not trial.hoshi_visual.wings.visible, "collision reset returns to walking and hides wings")
	trial.free()
	for failure in failures: push_error(failure)
	print("PASS Hoshi: walk, single jump/landing, double jump/cocoon, deploy flight, discrete boosts/queue, auto flap/dive, 90deg bank, pause/reset, 30/60/120Hz" if failures.is_empty() else "FAIL Hoshi wings")
	quit(0 if failures.is_empty() else 1)

func frame(trial: Node) -> void:
	trial.player._tick_flight(1.0 / 60)
	trial.hoshi_visual.update_pose(1.0 / 60, trial.player.flight_motion)
	await physics_frame

func capture(trial: Node, label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	trial._update_hud()
	for i in range(12):
		trial.camera._process(1.0 / 30)
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://ember-tests/hoshi-wings"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	root.get_texture().get_image().save_png(path + "/" + label + ".png")
