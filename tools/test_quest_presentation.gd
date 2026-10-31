extends SceneTree
const Store = preload("res://addons/ember_import/ember_action_script_store.gd")
const Editor = preload("res://addons/ember_import/ember_action_chain_editor.gd")
const Binding = preload("res://scripts/ember_story_binding.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(FileAccess.file_exists("res://.interaction-test-sandbox"))
	var stage = load("res://scenes/prototypes/camera_preset_study.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	await process_frame
	var state: EmberExploreState = stage._preview_state
	var ui: EmberInteractionUi = stage.get_node("QuestLayer/InteractionUi")
	var inner: EmberInteractionUi = stage.get_node("DialogueLayer/InteractionUi")
	var preview = stage.get_node("StoryPreview")
	var item: Node3D = stage.get_node("Item")
	var initial := item.transform
	var data := Store.document("harbor_cargo_story_trial")
	assert(Store.validation_errors(data).is_empty())
	var editor := Editor.new()
	editor.presentation_scene_root = stage
	root.add_child(editor)
	editor.setup("harbor_cargo_story_trial", "", data)
	var picker := editor.find_child("StepField_presentationId", true, false) as OptionButton
	assert(picker != null)
	assert(picker.get_item_text(picker.selected) == "Передача посылки")
	assert(editor._document().steps[0] == data.steps[0])
	var empty := data.duplicate(true)
	empty.steps[0].presentationId = ""
	assert(not Store.validation_errors(empty).is_empty())
	# Native editor draft Undo/Redo + resource write/reopen/discard.
	var history := UndoRedo.new()
	history.create_action("Select cutscene")
	history.add_do_method(picker.select.bind(0))
	history.add_undo_method(picker.select.bind(picker.selected))
	history.commit_action()
	history.undo()
	assert(editor._document().steps[0] == data.steps[0])
	history.redo()
	history.undo()
	var authored := editor._document()
	authored.id = "presentation_editor_roundtrip"
	assert(Store.write_document(authored) == OK)
	assert(Store.document(authored.id).steps[0].presentationId == "cargo_delivery")
	editor.free()
	history.clear_history()
	history.free()
	# Cancel: no stage progress, no reward; the original pose is restored.
	assert(stage.start_quest_trial().is_empty())
	assert(ui.blocks_movement() and ui.view_state().mode == "presentation")
	preview.skip()
	assert(inner.is_open())
	inner.close()
	assert(not preview.active and not ui.is_open())
	assert(not state.flags.get("harbor_cargo_reward", false) and state.inventory.get("coin", 0) == 0)
	assert(item.transform.is_equal_approx(initial))
	# Successful replay: the existing quest/action owners commit exactly three coins.
	assert(stage.start_quest_trial().is_empty())
	preview.skip()
	inner.advance()
	inner.choose(0)
	inner.advance()
	assert(not preview.active and not ui.is_open())
	assert(state.flags.get("harbor_cargo_reward", false) and state.flags.harbor_cargo_status == "done")
	assert(state.inventory.get("coin", 0) == 3)
	assert(ui.history_entries().size() == 5, "Transcript must retain the cancelled line plus the completed conversation")
	await _capture("quest-completed.png")
	# A stale callback and another NPC conversation cannot award a second reward.
	preview.finished.emit("completed")
	assert(state.inventory.get("coin", 0) == 3)
	assert(stage.start_quest_trial().is_empty())
	assert(ui.view_state().mode == "dialogue")
	ui.advance()
	assert(state.inventory.get("coin", 0) == 3)
	# Missing/ambiguous scene binding aborts, rather than falling through to rewards.
	stage.reset_quest_trial()
	preview.presentation_id = "missing"
	assert(not stage.start_quest_trial().is_empty())
	assert(ui.view_state().mode == "notice" and state.inventory.get("coin", 0) == 0)
	ui.advance()
	preview.presentation_id = "cargo_delivery"
	var other = preview.duplicate()
	stage.add_child(other)
	await process_frame
	assert(not Binding.resolve(stage, "cargo_delivery").ok)
	assert(not stage.start_quest_trial().is_empty())
	ui.close()
	other.free()
	# Closing the outer action while waiting must cancel and disconnect late results.
	assert(stage.start_quest_trial().is_empty())
	preview.skip()
	ui.close()
	preview.finished.emit("skipped")
	assert(not inner.is_open() and not preview.active)
	assert(state.inventory.get("coin", 0) == 0 and not state.flags.get("harbor_cargo_reward", false))
	# Even a queued callback from an earlier run cannot resume a newer action.
	assert(stage.start_quest_trial().is_empty())
	var old_serial: int = ui._presentation_serial
	ui.close()
	ui._on_presentation_finished("completed", old_serial)
	assert(state.inventory.get("coin", 0) == 0)
	# Broken hand-authored data must survive normalization and fail closed.
	assert(EmberActionScript._normalize_step({"type": "play_cutscene"}).presentationId == "")
	# A normal finish, rather than End, also completes the quest exactly once.
	preview.dialogue_time = 0.0
	preview.player.speed_scale = 32.0
	assert(stage.start_quest_trial().is_empty())
	await process_frame
	await process_frame
	assert(inner.is_open())
	inner.advance()
	inner.choose(1)
	inner.advance()
	await create_timer(0.5).timeout
	assert(state.inventory.get("coin", 0) == 3 and not ui.is_open())
	# Removing a running presentation cancels its awaiting action.
	var second = load("res://scenes/prototypes/camera_preset_study.tscn").instantiate()
	root.add_child(second)
	await process_frame
	second.set_process(false)
	assert(second.start_quest_trial().is_empty())
	var second_preview = second.get_node("StoryPreview")
	second.remove_child(second_preview)
	assert(not second.get_node("QuestLayer/InteractionUi").is_open())
	assert(second._preview_state.inventory.get("coin", 0) == 0)
	second_preview.free()
	second.free()
	stage.queue_free()
	await process_frame
	print("PASS quest presentation: editor binding/Undo/serialization, cancel/retry/skip/dialogue/shared history, reward once, missing/duplicate target, late callbacks")
	quit()


func _capture(name: String) -> void:
	var directory := OS.get_environment("EMBER_CAMERA_CAPTURE")
	if directory.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name))
