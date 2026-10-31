extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(FileAccess.file_exists("res://.interaction-test-sandbox"), "Disposable fixture required")
	var global_state: EmberExploreState = root.get_node("EmberExploreProgress")
	var original_flags := global_state.flags.duplicate(true)
	var stage = load("res://scenes/prototypes/camera_preset_study.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	await process_frame
	var preview = stage.get_node("StoryPreview")
	var ui: EmberInteractionUi = stage.get_node("DialogueLayer/InteractionUi")
	var player: AnimationPlayer = stage.get_node("AnimationPlayer")
	var item: Node3D = stage.get_node("Item")
	var origin := item.transform
	var outcomes: Array[String] = []
	preview.finished.connect(func(outcome: String): outcomes.append(outcome))
	assert(ui.economy_state != global_state and not ui.economy_state.persistence_enabled)
	assert(preview.start())
	preview.skip() # Visual skip still requires the authored conversation/choice.
	assert(ui.is_open() and preview.active and not player.is_playing())
	assert(not ui.activate_dialogue("camera_story_exchange").is_empty(), "Must not replace an open dialogue")
	var line: String = ui.view_state().body
	assert(ui.history_entries().size() == 1)
	await _key(KEY_H)
	assert(ui.is_history_open())
	ui.advance()
	ui.choose(0)
	preview.toggle_pause()
	preview.scrub(7.9)
	assert(ui.view_state().body == line and not player.is_playing())
	await _capture("dialogue-history.png")
	# H/Esc closes the journal only; the conversation remains at the same line.
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	ui._input(escape)
	assert(not ui.is_history_open() and ui.is_open())
	await _key(KEY_F)
	assert(ui.view_state().choices.contains("Покажи"))
	await _capture("dialogue-choice.png")
	ui.find_child("DialogueChoice_0", true, false).pressed.emit()
	assert(ui.view_state().body.begins_with("Небольшая посылка"))
	var entries := ui.history_entries()
	assert(entries.size() == 4 and entries[2].kind == "answer")
	assert(entries[2].text == "Покажи, что принёс.")
	assert(not str(entries).contains("Хорошо, оставь её здесь."), "Unchosen alternative leaked into history")
	entries[0].text = "mutated copy"
	assert(ui.history_entries()[0].text != "mutated copy")
	ui.toggle_history()
	await _capture("dialogue-history-answer.png")
	ui.toggle_history()
	ui.advance()
	assert(not ui.is_open() and not preview.active and outcomes == ["skipped"])
	assert(item.position.is_equal_approx(Vector3(0.8, 0.88, 0.9)))
	preview.restore()
	assert(item.transform.is_equal_approx(origin))
	# Cancel during dialogue never resumes playback or emits successful completion.
	assert(preview.start())
	preview.skip()
	ui.close()
	assert(not preview.active and not player.is_playing() and outcomes.back() == "cancelled")
	assert(item.transform.is_equal_approx(origin))
	# Real timed checkpoint, without pressing skip; closing normally resumes movement.
	assert(preview.start())
	preview.scrub(2.25)
	preview.toggle_pause()
	await process_frame
	await process_frame
	assert(ui.is_open())
	await _key(KEY_ENTER)
	await _key(KEY_S)
	await _key(KEY_ENTER)
	assert(ui.view_state().body.begins_with("Хорошо. Ставлю"))
	await _key(KEY_ENTER)
	assert(preview.active and player.is_playing())
	preview.restore()
	var packed := PackedScene.new()
	assert(packed.pack(stage) == OK)
	assert(ResourceSaver.save(packed, "user://story-dialogue-binding.tscn") == OK)
	var reopened = load("user://story-dialogue-binding.tscn").instantiate()
	assert(reopened.get_node("StoryPreview").dialogue.dialogue_id == "camera_story_exchange")
	assert(is_equal_approx(reopened.get_node("StoryPreview").dialogue_time, 2.2))
	reopened.free()
	# History is a bounded transcript, not a replay/quest mutation log.
	var session := EmberDialogueSession.new()
	for index in 205:
		assert(session.start({"id": "history_probe", "startStepId": "line", "steps": [
			{"id": "line", "type": "dialogue", "nameRu": "Спикер", "textRu": "Реплика%d" % index}]}))
	assert(session.history_entries().size() == 200)
	assert(session.history_entries()[0].text == "Реплика5")
	session.clear_history()
	assert(session.history_entries().is_empty())
	assert(global_state.flags == original_flags, "Preview changed the author's progress owner")
	stage.queue_free()
	await process_frame
	print("PASS dialogue story/history: authored checkpoint/choice/resume, modal history, real F input, mouse answer, skip/cancel, bounded immutable transcript, isolated state")
	quit()


func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _capture(name: String) -> void:
	var directory := OS.get_environment("EMBER_CAMERA_CAPTURE")
	if directory.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name))
