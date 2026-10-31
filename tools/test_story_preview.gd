extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage = load("res://scenes/prototypes/camera_preset_study.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	await process_frame
	var preview = stage.get_node("StoryPreview")
	preview.dialogue = null # Visual-only regression; dialogue lifecycle has its own gate.
	var player: AnimationPlayer = stage.get_node("AnimationPlayer")
	var item: Node3D = stage.get_node("Item")
	var actor: Node3D = stage.get_node("ActorB")
	var rig = stage.get_node("ShotRig")
	var caption: Label = stage.get_node("StoryText/Caption")
	var item_start := item.transform
	var actor_start := actor.transform
	var outcomes: Array[String] = []
	preview.finished.connect(func(outcome: String): outcomes.append(outcome))
	assert(preview.start())
	assert(not preview.start(), "Starting twice must not replace the rollback snapshot")
	preview.scrub(3.65)
	assert(preview.paused and not player.is_playing())
	assert(item.position.is_equal_approx(Vector3(0.4, 1.25, 0.9)))
	assert(actor.position.is_equal_approx(Vector3(0.5, 0, 0)))
	assert(rig.shot == 5 and not caption.text.is_empty())
	await process_frame
	await process_frame
	assert(rig.camera.global_transform.is_equal_approx(rig.shot_pose().transform), "Scrub snap must stay snapped on following frames")
	await _capture("story-detail.png")
	preview.restore()
	assert(item.transform.is_equal_approx(item_start))
	assert(actor.transform.is_equal_approx(actor_start))
	assert(caption.text.is_empty() and outcomes == ["cancelled"])
	preview.restore()
	assert(outcomes.size() == 1, "Repeated stop emitted a second outcome")
	for moment in [0.0, 3.65, 7.9]:
		assert(preview.start())
		preview.scrub(moment)
		preview.skip()
		assert(item.position.is_equal_approx(Vector3(0.8, 0.88, 0.9)))
		assert(not preview.active)
		preview.skip()
	assert(outcomes == ["cancelled", "skipped", "skipped", "skipped"])
	# Replaying returns to the original snapshot instead of accumulating movement.
	assert(preview.start())
	preview.scrub(0.0)
	assert(item.transform.is_equal_approx(item_start))
	preview.restore()
	# Ordinary finish is a distinct outcome and retains the final pose for review.
	player.speed_scale = 32.0
	assert(preview.start())
	await create_timer(0.5).timeout
	assert(not preview.active and outcomes.back() == "completed")
	assert(item.position.is_equal_approx(Vector3(0.8, 0.88, 0.9)))
	await _capture("story-finish.png")
	preview.restore()
	player.speed_scale = 1.0
	# Author an actual native timeline key, Undo/Redo, save/reopen and play it.
	var clip := player.get_animation("story_example")
	var history := UndoRedo.new()
	var changed := Vector3(0.95, 0.88, 0.9)
	history.create_action("Change item destination")
	history.add_do_method(clip.track_set_key_value.bind(2, 3, changed))
	history.add_undo_method(clip.track_set_key_value.bind(2, 3, Vector3(0.8, 0.88, 0.9)))
	history.commit_action()
	history.undo()
	assert(clip.track_get_key_value(2, 3) == Vector3(0.8, 0.88, 0.9))
	history.redo()
	var packed := PackedScene.new()
	assert(packed.pack(stage) == OK)
	assert(ResourceSaver.save(packed, "user://story-authoring-roundtrip.tscn") == OK)
	var reopened = load("user://story-authoring-roundtrip.tscn").instantiate()
	root.add_child(reopened)
	await process_frame
	assert(reopened.get_node("StoryPreview").start())
	reopened.get_node("StoryPreview").skip()
	assert(reopened.get_node("Item").position.is_equal_approx(changed))
	reopened.queue_free()
	await process_frame
	history.clear_history()
	history.free()
	# Missing targets / unsupported method tracks fail before any clip mutation.
	clip.track_set_path(2, NodePath("MissingItem:position"))
	assert(not preview.start())
	assert(item.transform.is_equal_approx(item_start))
	clip.track_set_path(2, NodePath("Item:position"))
	var unsupported := clip.add_track(Animation.TYPE_METHOD)
	clip.track_set_path(unsupported, NodePath("."))
	assert(not preview.start())
	clip.remove_track(unsupported)
	assert(preview.start())
	preview.scrub(3.65)
	# Removing the stage restores targets before they leave the scene tree.
	root.remove_child(stage)
	assert(item.transform.is_equal_approx(item_start))
	assert(actor.transform.is_equal_approx(actor_start))
	stage.free()
	await process_frame
	print("PASS story preview: movement/caption/camera, pause/scrub, skip/cancel/replay/finish/exit, native key Undo/Redo/save/reopen, invalid tracks")
	quit()


func _capture(name: String) -> void:
	var directory := OS.get_environment("EMBER_CAMERA_CAPTURE")
	if directory.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name))
