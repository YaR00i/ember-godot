extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const ActionStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const DialogueStore = preload("res://addons/ember_import/ember_dialogue_store.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
var errors: Array[String] = []

func _init() -> void:
	if not Fixture.prepare(self):
		quit(2)
		return
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func finish(ui: EmberInteractionUi) -> void:
	for index in 20:
		if not ui.is_open():
			break
		ui.advance()

func capture(label: String) -> void:
	var directory := OS.get_environment("EMBER_NPC_OPTIONS_CAPTURE")
	if directory.is_empty():
		return
	root.size = Vector2i(1600, 1200)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("npc-" + label + ".png"))

func _run() -> void:
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled = false
	state.flags.clear()
	check(DialogueStore.write_graph_document({"id": "npc_options_line", "nameRu": "Напоминание смотрителя", "startStepId": "line", "steps": [
		{"id": "line", "type": "dialogue", "textRu": "Ящик всё ещё ждёт на берегу.", "next": "end"}, {"id": "end", "type": "end"},
	]}) == OK, "dialogue fixture invalid")
	var source := DialogueStore.document("npc_options_line")
	var scene := Node3D.new()
	scene.name = "NpcOptions"
	root.add_child(scene)
	current_scene = scene
	var workspace := Workspace.new()
	root.add_child(workspace)
	workspace.set_scene_root(scene)
	workspace.open_resource("quest", "interaction_quest")
	(workspace.find_child("GraphNewQuest", true, false) as Button).pressed.emit()
	workspace.call("_add_quest_objective", "main")
	var quest: Dictionary = workspace.get("_quest_draft").duplicate(true)
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	var npc := actions.create_quest_conversation(scene, Vector3.ZERO, "Смотритель", Store.event_token(str(quest.id), "objective", "main"), "npc_options_line", quest)
	check(npc != null, "NPC creation failed")
	if npc == null:
		quit(1)
		return
	var giver := npc.get_node("Talk") as EmberInteract
	var original_route := str((giver.get("objective_scripts") as Dictionary).main)
	var original_chain := ActionStore.document(original_route)
	workspace.accept_quest_binding_save("", true)
	workspace.set_scene_selection(npc)
	workspace.call("_set_quest_focus", "main")
	workspace.quest_conversation_bind_requested.connect(func(path: NodePath, token: String, dialogue_id: String, draft: Dictionary, costs: Dictionary, choice: Dictionary, options: Dictionary) -> void:
		check(actions.bind_quest_conversation(scene.get_node(path), token, dialogue_id, scene, draft, null, Vector3.ZERO, costs, choice, options), "UI binding rejected")
	)
	var mode := workspace.find_child("QuestConversationMode_0", true, false) as OptionButton
	mode.select(1)
	mode.item_selected.emit(1)
	check(not (workspace.find_child("QuestRewardEnabled_0", true, false) as Control).visible, "reminder allows reward")
	(workspace.find_child("BindQuestConversation_0", true, false) as Button).pressed.emit()
	var reminder_route := str((giver.get("objective_scripts") as Dictionary).main)
	check(ActionStore.document(reminder_route).steps == [{"type": "talk", "dialogueId": "npc_options_line"}], "reminder is not talk only")
	check(ActionStore.document(original_route) == original_chain, "shared original chain changed")
	history.undo()
	check(str((giver.get("objective_scripts") as Dictionary).main) == original_route and not ActionStore.exists(reminder_route), "reminder Undo failed")
	history.redo()
	check(str((giver.get("objective_scripts") as Dictionary).main) == reminder_route, "reminder Redo failed")
	var ui := EmberInteractionUi.new()
	ui.economy_state = state
	root.add_child(ui)
	var flags_before := state.flags.duplicate(true)
	var items_before := state.inventory.duplicate(true)
	for index in 2:
		ui.activate(giver)
		finish(ui)
	check(state.flags == flags_before and state.inventory == items_before, "reminder mutated quest or inventory")
	workspace.accept_quest_binding_save("", true)
	workspace.call("_set_quest_focus", "quest_root")
	workspace.call("_set_quest_focus", "main")
	check((workspace.find_child("QuestConversationMode_0", true, false) as OptionButton).selected == 1, "reminder mode did not reopen")
	await capture("reminder")
	var objective_id := str(quest.objectives[1].id)
	var token := Store.event_token(str(quest.id), "objective", objective_id)
	workspace.call("_set_quest_focus", objective_id)
	var picker := workspace.find_child("QuestConversationDialogue_1", true, false) as OptionButton
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == "npc_options_line":
			picker.select(index)
			picker.item_selected.emit(index)
	var enabled := workspace.find_child("QuestRewardEnabled_1", true, false) as CheckBox
	enabled.button_pressed = true
	(workspace.find_child("BindQuestConversation_1", true, false) as Button).pressed.emit()
	check(not (giver.get("objective_scripts") as Dictionary).has(objective_id), "empty reward was silently accepted")
	var counts = workspace.find_child("QuestRewardItems_1", true, false)
	counts.add_row("coin", 3)
	counts.add_row("shore_shell", 2)
	await capture("reward")
	(workspace.find_child("BindQuestConversation_1", true, false) as Button).pressed.emit()
	var reward_route := str((giver.get("objective_scripts") as Dictionary)[objective_id])
	var reward_chain := ActionStore.document(reward_route)
	check(reward_chain.steps.size() == 3 and reward_chain.steps[1] == {"type": "exchange_items", "costs": {}, "rewards": {"coin": 3, "shore_shell": 2}}, "UI rewards did not compile to exchange")
	history.undo()
	check(not (giver.get("objective_scripts") as Dictionary).has(objective_id) and not ActionStore.exists(reward_route), "reward Undo failed")
	history.redo()
	check(ActionStore.document(reward_route) == reward_chain, "reward Redo failed")
	check(not actions.bind_quest_conversation(npc, token, "npc_options_line", scene, quest, null, Vector3.ZERO, {}, {}, {"reminder": true, "rewards": {"coin": 3}}), "reminder plus reward accepted")
	check(not actions.bind_quest_conversation(npc, token, "npc_options_line", scene, quest, null, Vector3.ZERO, {}, {"stepId": "choice", "optionIndex": 0}, {"rewards": {"coin": 3}}), "choice plus unconditional reward accepted")
	var unsafe_source := source.duplicate(true)
	unsafe_source.id = "npc_options_unsafe"
	unsafe_source.steps[0].next = "write"
	unsafe_source.steps.insert(1, {"id": "write", "type": "set_flag", "flag": str(quest.objectives[0].flagId), "value": true, "next": "end"})
	check(DialogueStore.write_graph_document(unsafe_source) == OK, "unsafe fixture invalid")
	check(not actions.bind_quest_conversation(npc, token, "npc_options_unsafe", scene, quest, null, Vector3.ZERO, {}, {}, {"reminder": true}), "reminder with quest writer accepted")
	# Existing gate, cancellation and repeated NPC routing protect the reward.
	state.apply_authored_flag(str(quest.objectives[0].flagId), true, false)
	ui.activate(giver)
	ui.close()
	check(state.inventory == items_before and not state.flags.get(str(quest.objectives[1].flagId), false), "cancelled reward changed state")
	ui.activate(giver)
	finish(ui)
	check(int(state.inventory.get("coin", 0)) == int(items_before.get("coin", 0)) + 3 and int(state.inventory.get("shore_shell", 0)) == int(items_before.get("shore_shell", 0)) + 2, "reward counts incorrect")
	var granted := state.inventory.duplicate(true)
	ui.activate(giver)
	finish(ui)
	check(state.inventory == granted, "reward was granted twice")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK and ResourceSaver.save(packed, "user://npc-options.tscn") == OK, "scene save failed")
	var reopened := (ResourceLoader.load("user://npc-options.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check((reopened.get_node(NodePath(str(npc.name) + "/Talk")).get("objective_scripts") as Dictionary) == giver.get("objective_scripts"), "NPC routes lost on reopen")
	reopened.free()
	state.persistence_enabled = true
	state.set_world_context("npc_options", npc, 16.0)
	check(state.save_slot(1), "save failed")
	var cold := EmberExploreState.new()
	root.add_child(cold)
	check(cold.load_slot(1) and cold.inventory == granted and cold.flags.get(str(quest.objectives[1].flagId), false), "cold load lost reward")
	check(not giver.runtime_available(cold.flags), "cold-loaded NPC offers finished reward")
	cold.free()
	state.persistence_enabled = false
	workspace.accept_quest_binding_save("", true)
	workspace.call("_set_quest_focus", "quest_root")
	workspace.call("_set_quest_focus", objective_id)
	check((workspace.find_child("QuestRewardEnabled_1", true, false) as CheckBox).button_pressed, "reward enabled did not reopen")
	check(workspace.find_child("QuestRewardItems_1", true, false).value() == {"coin": 3, "shore_shell": 2}, "reward list did not reopen")
	await capture("reward")
	check(DialogueStore.document("npc_options_line") == source, "source dialogue changed")
	var extra := actions.create_quest_conversation(scene, Vector3(32, 0, 0), "Напоминающий NPC", token, "npc_options_line", quest, {}, {}, {"reminder": true})
	check(extra != null, "NPC creator did not pass reminder options")
	if extra != null:
		var extra_route := str((extra.get_node("Talk").get("objective_scripts") as Dictionary)[objective_id])
		check(ActionStore.document(extra_route).steps.size() == 1, "new reminder NPC completes goal")
		history.undo()
		check(not extra.is_inside_tree(), "Undo did not remove new reminder NPC")
	history.clear_history()
	history.free()
	ui.queue_free()
	workspace.queue_free()
	scene.queue_free()
	await process_frame
	Fixture.verify_sources(errors)
	if errors.is_empty():
		print("PASS quest NPC options: reminder/rewards UI, shared chain preserved, unsafe combinations rejected, cancel/repeat, Undo/Redo, scene reopen, cold save/load")
		quit(0)
	else:
		for error in errors:
			printerr("FAIL ", error)
		quit(1)
