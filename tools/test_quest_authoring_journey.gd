extends SceneTree
## Compose one quest through Graph controls, then play its saved scene.
## Own short replies; no prepared dialogues, quest IDs, flags or NPC routes.
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const DialogueStore = preload("res://addons/ember_import/ember_dialogue_store.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
var errors: Array[String] = []
var npc: Node3D
var placement: Node3D
var workspace: EmberGraphWorkspace

func _init() -> void:
	if not Fixture.prepare(self):
		quit(2)
		return
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func press(name: String) -> void:
	var button := workspace.find_child(name, true, false) as Button
	check(button != null and not button.disabled, "missing/disabled button: " + name)
	if button != null and not button.disabled:
		if button.toggle_mode:
			button.button_pressed = not button.button_pressed
		button.pressed.emit()

func text(name: String, value: String) -> void:
	var input := workspace.find_child(name, true, false) as LineEdit
	check(input != null, "missing field: " + name)
	if input != null:
		input.focus_entered.emit()
		input.text = value
		input.text_changed.emit(value)
		input.focus_exited.emit()

func reply(index: int, value: String) -> void:
	(workspace.find_child("QuestConversationOwnText_%d" % index, true, false) as CheckBox).button_pressed = true
	(workspace.find_child("QuestConversationText_%d" % index, true, false) as TextEdit).text = value

func finish(ui: EmberInteractionUi) -> void:
	for index in 20:
		if not ui.is_open():
			break
		ui.advance()

func frames(count := 10) -> void:
	for index in count:
		await physics_frame
	await process_frame

func _run() -> void:
	var state := root.get_node("EmberExploreProgress") as EmberExploreState
	state.persistence_enabled = false
	state.flags.clear()
	state.world_items.clear()
	var scene := Node3D.new()
	scene.name = "JourneyScene"
	root.add_child(scene)
	current_scene = scene
	var authored := Node3D.new()
	authored.name = "AuthoredQuest"
	scene.add_child(authored)
	workspace = Workspace.new()
	root.add_child(workspace)
	workspace.set_scene_root(authored)
	workspace.open_resource("quest", "interaction_quest")
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	# These adapters are the plugin's mutations with fixed fixture positions.
	# Physical map placement itself belongs to the previously checked plugin path.
	workspace.quest_conversation_create_requested.connect(func(_anchor: NodePath, display_name: String, token: String, dialogue_id: String, draft: Dictionary, costs: Dictionary, choice: Dictionary, options: Dictionary) -> void:
		npc = actions.create_quest_conversation(authored, Vector3.ZERO, display_name, token, dialogue_id, draft, costs, choice, options)
		check(npc != null, "NPC creation rejected")
	)
	workspace.quest_conversation_bind_requested.connect(func(path: NodePath, token: String, dialogue_id: String, draft: Dictionary, costs: Dictionary, choice: Dictionary, options: Dictionary) -> void:
		check(actions.bind_quest_conversation(authored.get_node(path), token, dialogue_id, authored, draft, null, Vector3.ZERO, costs, choice, options), "conversation rejected")
	)
	workspace.quest_reach_zone_requested.connect(func(_anchor: NodePath, objective_id: String, draft: Dictionary) -> void:
		check(actions.create_quest_reach_zone(authored, Vector3(0, 4, 48), objective_id, draft) != null, "reach creation rejected")
	)
	workspace.quest_object_placement_requested.connect(func(_anchor: NodePath, objective_id: String, draft: Dictionary) -> void:
		placement = actions.create_quest_object_placement(authored, Vector3(0, 0.15, 48), Vector3(64, 0, 48), objective_id, draft)
		check(placement != null, "crate creation rejected")
	)
	press("GraphNewQuest")
	text("InlineQuest_titleRu", "Поручение без ручных ключей")
	var titles := ["Поговорить со смотрителем", "Найти груз", "Поставить ящик на площадку", "Забрать награду"]
	for index in 4:
		if index > 0:
			press("QuestNextObjective_%d" % (index - 1))
		text("InlineQuestObjective_%d_textRu" % index, titles[index])
	var quest: Dictionary = workspace.get("_quest_draft").duplicate(true)
	var quest_id := str(quest.id)
	check(quest.objectives.size() == 4, "next-goal flow lost stages")
	for index in 4:
		check(quest.objectives[index].textRu == titles[index], "title input was not kept")
		if index > 0:
			check(quest.objectives[index].requiresObjectiveIds == [quest.objectives[index - 1].id], "next-goal flow lost prerequisite")
	workspace.call("_set_quest_focus", str(quest.objectives[0].id))
	reply(0, "")
	press("CreateQuestConversation_0")
	check(npc == null, "empty short reply created NPC")
	reply(0, "Помоги перенести груз.")
	text("QuestConversationName_0", "Смотритель")
	press("CreateQuestConversation_0")
	if npc == null:
		quit(1)
		return
	workspace.accept_quest_binding_save("", true)
	workspace.set_scene_selection(npc)
	for index in [1, 2]:
		workspace.call("_set_quest_focus", str(quest.objectives[index].id))
		press("CreateQuestReachZone_1" if index == 1 else "CreateQuestObjectPlacement_2")
		workspace.accept_quest_binding_save("", true)
		reply(index, "Ящик ещё ждёт на берегу.")
		var mode := workspace.find_child("QuestConversationMode_%d" % index, true, false) as OptionButton
		mode.select(1)
		mode.item_selected.emit(1)
		press("BindQuestConversation_%d" % index)
		workspace.accept_quest_binding_save("", true)
	workspace.call("_set_quest_focus", str(quest.objectives[3].id))
	reply(3, "Спасибо! Вот твоя награда.")
	(workspace.find_child("QuestRewardEnabled_3", true, false) as CheckBox).button_pressed = true
	workspace.find_child("QuestRewardItems_3", true, false).add_row("coin", 3)
	press("BindQuestConversation_3")
	workspace.accept_quest_binding_save("", true)
	var giver := npc.get_node("Talk") as EmberInteract
	var routes: Dictionary = giver.get("objective_scripts").duplicate()
	history.undo()
	check(not (giver.get("objective_scripts") as Dictionary).has(str(quest.objectives[3].id)), "Undo did not remove reward binding")
	check(giver.get("objective_scripts").size() == 3, "Undo damaged previous stages")
	history.redo()
	check(giver.get("objective_scripts") == routes, "Redo lost authored routes")
	check(Store.document(quest_id).objectives.size() == 4, "binding saved only part of quest")
	press("QuestCompletedConversationToggle_3")
	var completed_input := workspace.find_child("QuestCompletedConversationText_3", true, false) as TextEdit
	completed_input.text = "Спасибо, груз уже на месте!"
	press("BindQuestCompletedConversation_3")
	var completed_route := str(giver.get("completed_script_id"))
	var action_store = preload("res://addons/ember_import/ember_action_script_store.gd")
	var completed_chain: Dictionary = action_store.document(completed_route)
	check(completed_chain.steps.size() == 1 and completed_chain.steps[0].type == "talk", "final conversation can award or change stage")
	var completed_dialogue := str(completed_chain.steps[0].dialogueId)
	check(giver.get("objective_scripts") == routes, "final conversation damaged stage routes")
	history.undo()
	check(str(giver.get("completed_script_id")).is_empty() and not DialogueStore.exists(completed_dialogue) and not action_store.exists(completed_route), "final Undo did not remove all new resources")
	history.redo()
	check(str(giver.get("completed_script_id")) == completed_route and DialogueStore.exists(completed_dialogue), "final Redo failed")
	workspace.accept_quest_binding_save("", true)
	check((workspace.find_child("QuestCompletedConversationText_3", true, false) as TextEdit).text == "Спасибо, груз уже на месте!", "final text did not reopen")
	var saved_final := DialogueStore.document(completed_dialogue)
	press("BindQuestCompletedConversation_3")
	check(str(giver.get("completed_script_id")) == completed_route, "unchanged final reply created another route")
	(workspace.find_child("QuestCompletedConversationText_3", true, false) as TextEdit).text = "Уже всё перенесено. Спасибо ещё раз!"
	press("BindQuestCompletedConversation_3")
	check(str(giver.get("completed_script_id")) != completed_route and DialogueStore.document(completed_dialogue) == saved_final, "editing final text overwrote shared source")
	history.undo()
	check(str(giver.get("completed_script_id")) == completed_route, "editing final text Undo failed")
	check(not actions.bind_quest_conversation(npc, Store.event_token(quest_id, "objective", str(quest.objectives[3].id)), "", authored, quest, null, Vector3.ZERO, {}, {}, {"after_completion": true, "text": "Финал", "rewards": {"coin": 3}}), "final reply accepted rewards")
	workspace.accept_quest_binding_save("", true)
	var capture := OS.get_environment("EMBER_SHORT_REPLY_CAPTURE")
	if not capture.is_empty():
		press("QuestCompletedConversationToggle_3")
		root.size = Vector2i(1600, 1700)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	var npc_path := authored.get_path_to(npc)
	var crate_path := authored.get_path_to(placement.get_node("Crate"))
	var packed := PackedScene.new()
	check(packed.pack(authored) == OK and ResourceSaver.save(packed, "user://quest-journey.tscn") == OK, "authored scene save failed")
	workspace.set_scene_root(null)
	history.clear_history()
	history.free()
	authored.free()
	var reopened := (ResourceLoader.load("user://quest-journey.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	scene.add_child(reopened)
	giver = reopened.get_node(npc_path).get_node("Talk")
	check(giver.get("objective_scripts") == routes, "scene reopen lost stage routing")
	check(str(giver.get("completed_script_id")) == completed_route, "scene reopen lost final routing")
	var crate = reopened.get_node(crate_path)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(240, 2, 240)
	floor_body.position.y = -1
	floor_body.add_child(shape)
	scene.add_child(floor_body)
	var player := EmberPlayer.new()
	player.progress_state = state
	player.position = Vector3(0, 0, -16)
	scene.add_child(player)
	player.set_physics_process(false)
	var ui := EmberInteractionUi.new()
	ui.economy_state = state
	root.add_child(ui)
	player.interaction_ui = ui
	ui.activate(giver)
	finish(ui)
	check(state.flags.get(str(quest.objectives[0].flagId), false), "initial conversation failed")
	ui.activate(giver)
	finish(ui)
	check(not state.flags.get(str(quest.objectives[1].flagId), false), "reminder completed travel goal")
	player.position = Vector3(0, 0, 36)
	await frames()
	check(state.flags.get(str(quest.objectives[1].flagId), false), "travel goal failed")
	ui.activate(giver)
	finish(ui)
	check(not state.flags.get(str(quest.objectives[2].flagId), false), "reminder completed crate goal")
	check(player.activate_interact(crate.get_node("Pickup")) and crate.is_carried(), "F did not lift crate")
	player.position = Vector3(40, 0, 48)
	player.set("_interaction_forward", Vector3.RIGHT)
	await frames()
	check(player.activate_interact(crate.get_node("Pickup")) and not crate.is_carried(), "F did not place crate")
	await frames(65)
	check(state.flags.get(str(quest.objectives[2].flagId), false), "crate goal failed")
	var coins := int(state.inventory.get("coin", 0))
	ui.activate(giver)
	ui.close()
	check(int(state.inventory.get("coin", 0)) == coins, "cancelled dialogue gave reward")
	ui.activate(giver)
	finish(ui)
	check(int(state.inventory.get("coin", 0)) == coins + 3, "reward count incorrect")
	check(EmberQuestCatalog.projection(EmberQuestCatalog.definition(quest_id), state.flags).status == "done", "generated quest did not finish")
	ui.activate(giver)
	check(ui.view_state().body == "Спасибо, груз уже на месте!", "NPC did not use final reply after completion")
	finish(ui)
	check(int(state.inventory.get("coin", 0)) == coins + 3, "repeat gave reward again")
	ui.activate(giver)
	ui.close()
	check(int(state.inventory.get("coin", 0)) == coins + 3, "closing final conversation gave reward")
	state.persistence_enabled = true
	state.set_world_context("journey", player, 16.0)
	check(state.save_slot(1), "completed journey save failed")
	var cold := EmberExploreState.new()
	root.add_child(cold)
	check(cold.load_slot(1) and giver.routed_script_id(cold.flags) == completed_route, "cold load lost final conversation")
	check(int(cold.inventory.get("coin", 0)) == coins + 3, "cold load lost exact reward")
	cold.free()
	state.persistence_enabled = false
	ui.queue_free()
	workspace.queue_free()
	scene.queue_free()
	await process_frame
	Fixture.verify_sources(errors)
	if errors.is_empty():
		print("PASS quest authoring journey: own short replies/create NPC/reach/crate/reminders/reward/final conversation, Undo/Redo, scene reopen, playable chain, no manual quest flags or routes")
		quit(0)
	else:
		for error in errors:
			printerr("FAIL ", error)
		quit(1)
