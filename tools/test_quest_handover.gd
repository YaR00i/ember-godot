extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_interaction_test_fixture.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const ActionStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const Editor = preload("res://addons/ember_import/ember_quest_editor.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
const ChainEditor = preload("res://addons/ember_import/ember_action_chain_editor.gd")
var setup: Dictionary

func _initialize() -> void:
	setup = Fixture.prepare(self)
	if setup.refused: quit(2); return
	_run.call_deferred()

func _run() -> void:
	assert(setup.error == OK)
	var quest := Store.document("story_shell_handover")
	assert(Store.validation_errors(quest).is_empty())
	var invalid := quest.duplicate(true)
	invalid.objectives[1].handoverItemId = "missing_item"
	assert(not Store.validation_errors(invalid).is_empty())
	invalid = quest.duplicate(true)
	invalid.objectives[1].requiredCount = 100
	assert(not Store.validation_errors(invalid).is_empty())
	var compiled := Store.action_for_event_in_document(Store.event_token("story_shell_handover", "objective", "deliver"), quest)
	assert(compiled.type == "handover_quest_items" and compiled.objectiveId == "deliver")
	var stage: Node3D = load("res://scenes/prototypes/camera_preset_study.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.reset_shell_trial()
	var state: EmberExploreState = stage._preview_state
	var ui: EmberInteractionUi = stage.get_node("QuestLayer/InteractionUi")
	assert(not state.handover_quest_items("story_shell_handover", "deliver", {"coin": 5}, false).ok)
	# Already owned items count, but do not complete a goal without submission.
	stage.pickup_shell_trial()
	stage.start_shell_trial()
	ui.close() # cancel acceptance
	assert(not state.flags.has("story_shell_meet"))
	stage.start_shell_trial()
	ui.advance()
	assert(state.flags.story_shell_meet)
	var tracker := preload("res://scripts/ember_quest_tracker_ui.gd").new()
	tracker.progress_state = state
	tracker._tracked_id = "story_shell_handover"
	root.add_child(tracker)
	assert("1/3" in tracker._objective.text)
	stage.pickup_shell_trial()
	stage.pickup_shell_trial()
	assert("3/3" in tracker._objective.text)
	assert(not EmberQuestCatalog.projection(quest, state.flags, state.inventory).objectives[1].done)
	assert(not state.apply_authored_flag("story_shell_delivered", true, false).allowed)
	stage.drop_shell_trial()
	assert(state.inventory.shore_shell == 2 and "2/3" in tracker._objective.text)
	var before := state.inventory.duplicate(true)
	stage.start_shell_trial()
	ui.advance()
	assert(ui.view_state().mode == "notice" and state.inventory == before and not state.flags.has("story_shell_delivered"))
	ui.close()
	state.storage_root = str(setup.directory).path_join("handover-save")
	state.persistence_enabled = true
	assert(state.save_autosave())
	var restored := EmberExploreState.new()
	restored.restore_enabled = false
	restored.storage_root = state.storage_root
	restored.persistence_enabled = false
	assert(restored.load_autosave())
	assert(restored.inventory.shore_shell == 2)
	assert(EmberQuestCatalog.projection(quest, restored.flags, restored.inventory).objectives[1].currentCount == 2)
	var dropped := ""
	for id in restored.world_items:
		if str(id).begins_with("drop_"): dropped = str(id)
	assert(not dropped.is_empty() and restored.pickup_world_item(dropped, false).ok)
	assert(EmberQuestCatalog.projection(quest, restored.flags, restored.inventory).objectives[1].currentCount == 3)
	# Missing target/locked state/full reward stack must not partially consume items.
	assert(not restored.handover_quest_items("story_shell_handover", "missing", {}, false).ok)
	var old_flags := restored.flags.duplicate(true)
	restored.inventory.coin = 999999
	assert(not restored.handover_quest_items("story_shell_handover", "deliver", {"coin": 5}, false).ok)
	assert(restored.inventory.shore_shell == 3 and restored.flags == old_flags)
	restored.inventory.erase("coin")
	assert(restored.handover_quest_items("story_shell_handover", "deliver", {"coin": 5}, false).ok)
	assert(restored.inventory.get("shore_shell", 0) == 0 and restored.inventory.coin == 5)
	var completed := EmberQuestCatalog.projection(quest, restored.flags, restored.inventory)
	assert(completed.status == "done" and completed.objectives[1].currentCount == 3)
	assert(not restored.handover_quest_items("story_shell_handover", "deliver", {"coin": 5}, false).ok)
	assert(restored.inventory.coin == 5)
	# Cancel with enough items, then finish: one atomic observer snapshot/save.
	stage.pickup_shell_trial()
	stage.start_shell_trial()
	ui.close()
	assert(state.inventory.shore_shell == 3 and not state.flags.has("story_shell_delivered"))
	var snapshots: Array[Dictionary] = []
	state.economy_changed.connect(func(): snapshots.append({"items": state.inventory.get("shore_shell", 0), "done": state.flags.get("story_shell_delivered", false), "coin": state.inventory.get("coin", 0)}))
	var saved: Array[String] = []
	state.saved.connect(func(path: String): saved.append(path))
	stage.start_shell_trial()
	ui.advance()
	assert(state.inventory.get("shore_shell", 0) == 0 and state.inventory.coin == 5 and state.flags.story_shell_delivered)
	assert(snapshots.size() == 1 and snapshots[0] == {"items": 0, "done": true, "coin": 5})
	assert(saved.size() == 1)
	stage.start_shell_trial()
	ui.advance()
	assert(state.inventory.coin == 5)
	assert(restored.load_autosave() and restored.inventory.coin == 5 and restored.flags.story_shell_delivered)
	# Both native authoring views preserve fields; Graph undo/redo/save/reopen/discard.
	var form := Editor.new()
	root.add_child(form)
	form.setup("story_shell_handover", "")
	assert(form._document() == Store.normalized_document(quest))
	assert(form._objectives.get_child(1).find_child("QuestHandoverFields", true, false).visible)
	var workspace := Workspace.new()
	root.add_child(workspace)
	workspace._current_kind = "quest"
	workspace._current_id = "story_shell_handover"
	workspace._reset_quest_draft(quest)
	var holder := VBoxContainer.new()
	root.add_child(holder)
	workspace._add_quest_objective_progress(holder, 1, quest.objectives[1])
	var count := holder.get_node("InlineQuestObjective_1_requiredCount") as SpinBox
	count.value = 5
	assert(workspace._quest_draft.objectives[1].requiredCount == 5)
	workspace._undo_action_draft()
	assert(workspace._quest_draft.objectives[1].requiredCount == 3)
	workspace._redo_action_draft()
	assert(workspace._quest_draft.objectives[1].requiredCount == 5)
	assert(Store.write_document(workspace._quest_draft) == OK)
	assert(Store.document("story_shell_handover").objectives[1].requiredCount == 5)
	workspace._reset_quest_draft(Store.document("story_shell_handover"))
	workspace._push_quest_draft(quest)
	workspace._request_navigation("quest", "story_shell_handover", true)
	assert(not workspace._pending_navigation.is_empty())
	workspace._cancel_discard_navigation()
	assert(workspace._quest_draft.objectives[1].requiredCount == 3)
	workspace._request_navigation("quest", "story_shell_handover", true)
	workspace._confirm_discard_navigation()
	assert(workspace._quest_draft.objectives[1].requiredCount == 5)
	assert(Store.write_document(quest) == OK)
	# The real NPC bind command compiles one transaction with rewards; item/count
	# remain in the quest, so later edits do not leave stale Action costs.
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	var giver: EmberInteract = stage.get_node("ShellGiver")
	var old_routes: Dictionary = giver.objective_scripts.duplicate(true)
	assert(actions.bind_quest_conversation(giver, Store.event_token("story_shell_handover", "objective", "deliver"), "story_shell_deliver_talk", stage, quest, null, Vector3.ZERO, {}, {}, {"rewards": {"coin": 7}}))
	var chain := ActionStore.document(str(giver.objective_scripts.deliver))
	assert(chain.steps.size() == 2 and chain.steps[1].type == "handover_quest_items" and chain.steps[1].rewards.coin == 7)
	assert(not chain.steps[1].has("costs"))
	assert(not EmberQuestUsageIndex.entries(quest).is_empty())
	history.undo()
	assert(giver.objective_scripts == old_routes)
	history.redo()
	var chain_form := ChainEditor.new()
	root.add_child(chain_form)
	chain_form.setup(str(chain.id), "")
	assert(chain_form._document().steps[1] == chain.steps[1])
	var changed := quest.duplicate(true)
	changed.objectives[1].requiredCount = 2
	assert(Store.write_document(changed) == OK)
	# Restore fresh state (old save only contains done flags); current definition wins.
	state.flags = {"story_shell_status": "active", "story_shell_meet": true}
	state.inventory = {"shore_shell": 2}
	ui.activate(giver)
	ui.advance()
	assert(state.flags.story_shell_delivered and state.inventory.coin == 7 and not state.inventory.has("shore_shell"))
	assert(Store.write_document(quest) == OK)
	chain_form.queue_free()
	form.queue_free()
	workspace.queue_free()
	holder.queue_free()
	tracker.queue_free()
	stage.queue_free()
	restored.free()
	history.clear_history()
	await process_frame
	print("PASS quest handover: live bag/drop/pickup, cancel/failure/atomic reward once, cold save/load, both forms, Graph and NPC bind Undo/Redo/reopen/discard, current goal edits")
	quit()
