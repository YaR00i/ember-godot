extends SceneTree
const Motion := preload("res://scripts/ember_wing_flight_motion.gd")
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var flight := Motion.new()
	var initial: float = flight.velocity.length()
	flight.step(0.1, Vector3.ZERO, 1, 1)
	var armed: bool = flight.get("high_g_armed") == true
	var holds: bool = absf(flight.velocity.length() - initial) < 0.01
	print("Dual triggers before pulling: armed=", armed, " speed held=", holds, " speed=", flight.velocity.length())
	if not armed or not holds:
		push_error("Dual triggers should arm the maneuver without applying ordinary braking before the pull")
		quit(1)
		return
	else:
		var course = load("res://scenes/wing_flight_trial.tscn").instantiate()
		course.tuning_path = "user://ember-tests/trigger-mode-%d.json" % OS.get_process_id()
		root.add_child(course)
		course.player.set_physics_process(false)
		course.player.flight_motion.step(0.1, Vector3.ZERO, 1, 1)
		course._update_hud()
		var visible_ready: bool = course._hud.text.contains("ВИРАЖ ГОТОВ") and course._hud.text.contains("RT 100% · LT 100%")
		course.player.flight_motion.step(0.1, Vector3(1, 0, 0), 1, 1)
		course._update_hud()
		var visible_active: bool = course._hud.text.contains("КРУТОЙ ВИРАЖ")
		course.player.flight_motion.reset(Quaternion.IDENTITY, 8)
		course.player.velocity = Vector3(0, 0, -8)
		course.player.flight_motion.step(0.1, Vector3(1, 0, 0), 1, 1)
		course._update_hud()
		var visible_slow: bool = course._hud.text.contains("нужна скорость")
		course.free()
		if not visible_ready or not visible_active or not visible_slow:
			push_error("Ready/active/low-speed HUD states are not visible")
			quit(1)
			return
		print("PASS dual-trigger arming, no premature braking, ready/active/low-speed HUD and trigger percentages")
		quit(0)
