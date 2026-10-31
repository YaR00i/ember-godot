extends SceneTree
## Run in an isolated project containing only the camera study and its two scripts.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage = load("res://scenes/prototypes/camera_preset_study.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	await process_frame
	var rig = stage.get_node("ShotRig")
	rig.transition_seconds = 0.0
	for shot in 6:
		rig.shot = shot
		await process_frame
		await process_frame
		var pose: Dictionary = rig.shot_pose()
		assert(not pose.is_empty())
		assert(rig.camera.global_transform.is_equal_approx(pose.transform))
		assert(rig.camera.is_position_in_frustum(pose.aim), "Shot target outside frustum")
		if shot in [0, 3, 4]:
			assert(rig.camera.global_position.z > 0, "Reverse shot crossed dialogue axis")
		var capture := OS.get_environment("EMBER_CAMERA_CAPTURE")
		if not capture.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture.path_join("shot-%d.png" % shot))
	# Binding follows a translated pair, rather than fixed world positions.
	rig.shot = 0
	var before: Transform3D = rig.shot_pose().transform
	var shift := Vector3(7, 2, -4)
	stage.get_node("ActorA").position += shift
	stage.get_node("ActorB").position += shift
	assert((rig.shot_pose().transform.origin - before.origin).is_equal_approx(shift))
	# Interrupted transitions converge to the newest shot; no old tween can resume.
	rig.transition_seconds = 0.1
	rig.shot = 1
	await process_frame
	rig.shot = 2
	await create_timer(0.25).timeout
	assert(rig.camera.global_transform.is_equal_approx(rig.shot_pose().transform))
	# Missing binding freezes safely; restoring the binding recovers.
	var saved: NodePath = rig.primary_anchor
	var frozen: Transform3D = rig.camera.global_transform
	rig.primary_anchor = NodePath("../Missing")
	await process_frame
	await process_frame
	assert(rig.shot_pose().is_empty())
	assert(rig.camera.global_transform.is_equal_approx(frozen))
	rig.primary_anchor = saved
	stage._set_target(1)
	assert(rig.get_node(rig.primary_anchor) == stage.get_node("ActorB/Anchor"))
	assert(rig.shot_pose().transform.origin.z > stage.get_node("ActorB/Anchor").global_position.z)
	rig.primary_anchor = NodePath("")
	assert(rig.shot_pose().is_empty(), "Empty binding must not resolve to the rig itself")
	stage._set_target(1)
	# Exercise the real control signals, including per-button captured shot indices.
	var column = stage.get_node("Controls/Panel").get_child(0).get_child(0)
	for index in 6:
		column.get_child(index + 1).pressed.emit()
		assert(rig.shot == index)
	# Scene serialization preserves authored bindings/settings, not external assets.
	rig.lens_fov = 46.0
	var packed := PackedScene.new()
	assert(packed.pack(stage) == OK)
	assert(ResourceSaver.save(packed, "user://camera-study-roundtrip.tscn") == OK)
	var reopened = load("user://camera-study-roundtrip.tscn").instantiate()
	assert(reopened.get_node("ShotRig").lens_fov == 46.0)
	assert(reopened.get_node("ShotRig").primary_anchor == rig.primary_anchor)
	reopened.free()
	stage._reset()
	assert(rig.shot == 0 and rig.lens_fov == 38.0)
	stage.queue_free()
	await process_frame
	print("PASS camera presets: six shots, axis, follow, interrupted transition, missing target, bindings, roundtrip, reset")
	quit()
