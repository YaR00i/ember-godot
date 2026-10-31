extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
var errors: Array[String] = []
var saves := 0

func _init() -> void:
	if not Fixture.prepare(self):
		quit(2)
		return
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func _run() -> void:
	var scene := Node3D.new()
	scene.name = "DraftFixture"
	root.add_child(scene)
	current_scene = scene
	var npc := (load("res://prefabs/items/shore_keeper.tscn") as PackedScene).instantiate()
	scene.add_child(npc)
	var giver := npc.get_node("Talk") as EmberInteract
	giver.quest_id = ""
	giver.set("objective_scripts", {})
	giver.set("completed_script_id", "")
	var anchor := Node3D.new()
	anchor.name = "Anchor"
	scene.add_child(anchor)
	var workspace := Workspace.new()
	root.add_child(workspace)
	workspace.set_scene_root(scene)
	workspace.open_resource("quest", "interaction_quest")
	workspace.quest_save_requested.connect(func(document: Dictionary) -> void:
		saves += 1
		check(Store.write_document(document) == OK, "save fixture failed")
	)
	(workspace.find_child("GraphNewQuest", true, false) as Button).pressed.emit()
	workspace.call("_add_quest_objective", "main")
	workspace.call("_save_quest_graph")
	var quest: Dictionary = workspace.get("_quest_draft").duplicate(true)
	var quest_id := str(quest.id)
	var second_id := str(quest.objectives[1].id)
	var saved := Store.document(quest_id)
	workspace.call("_set_quest_focus", "main")
	(workspace.find_child("QuestConversationOwnText_0", true, false) as CheckBox).button_pressed = true
	(workspace.find_child("QuestConversationText_0", true, false) as TextEdit).text = "Сначала выбери меня в сцене"
	(workspace.find_child("QuestCompletedConversationText_0", true, false) as TextEdit).text = "Это финальный черновик"
	var mode := workspace.find_child("QuestConversationMode_0", true, false) as OptionButton
	mode.select(1)
	mode.item_selected.emit(1)
	workspace.set_scene_selection(npc)
	check((workspace.find_child("QuestConversationText_0", true, false) as TextEdit).text == "Сначала выбери меня в сцене", "NPC selection erased short reply")
	check((workspace.find_child("QuestCompletedConversationText_0", true, false) as TextEdit).text == "Это финальный черновик", "NPC selection erased final reply")
	check((workspace.find_child("QuestConversationMode_0", true, false) as OptionButton).selected == 1, "NPC selection changed reminder mode")
	workspace.call("_set_quest_focus", second_id)
	workspace.call("_set_quest_focus", "main")
	check((workspace.find_child("QuestConversationText_0", true, false) as TextEdit).text == "Сначала выбери меня в сцене", "goal navigation erased reply")
	check(Store.document(quest_id) == saved and (giver.get("objective_scripts") as Dictionary).is_empty(), "draft leaked into Quest or NPC")
	workspace.call("_set_quest_focus", second_id)
	(workspace.find_child("QuestConversationOwnText_1", true, false) as CheckBox).button_pressed = true
	(workspace.find_child("QuestConversationText_1", true, false) as TextEdit).text = "Вот твоя награда"
	(workspace.find_child("QuestRewardEnabled_1", true, false) as CheckBox).button_pressed = true
	workspace.find_child("QuestRewardItems_1", true, false).add_row("coin", 3)
	workspace.set_scene_selection(anchor)
	workspace.set_scene_selection(npc)
	check((workspace.find_child("QuestConversationText_1", true, false) as TextEdit).text == "Вот твоя награда", "selection erased reward reply")
	check((workspace.find_child("QuestRewardEnabled_1", true, false) as CheckBox).button_pressed and workspace.find_child("QuestRewardItems_1", true, false).value() == {"coin": 3}, "selection erased reward settings")
	var save_count := saves
	workspace.call("_save_quest_graph")
	check(saves == save_count, "Quest save claimed to save unapplied conversation")
	workspace.call("_request_navigation", "quest", "interaction_quest", false)
	var discard := workspace.find_child("DiscardGraphDraftDialog", true, false) as ConfirmationDialog
	check(discard.visible and str(workspace.get("_current_id")) == quest_id, "navigation did not warn about unapplied conversation")
	discard.hide()
	discard.canceled.emit()
	check((workspace.find_child("QuestConversationText_1", true, false) as TextEdit).text == "Вот твоя награда", "cancel navigation erased draft")
	var capture := OS.get_environment("EMBER_PENDING_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(1600, 1500)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	workspace.quest_conversation_bind_requested.connect(func(path: NodePath, token: String, dialogue_id: String, document: Dictionary, costs: Dictionary, choice: Dictionary, options: Dictionary) -> void:
		check(actions.bind_quest_conversation(scene.get_node(path), token, dialogue_id, scene, document, null, Vector3.ZERO, costs, choice, options), "draft could not be assigned")
	)
	(workspace.find_child("BindQuestConversation_1", true, false) as Button).pressed.emit()
	workspace.accept_quest_binding_save("", true)
	var pending: Dictionary = workspace.get("_quest_conversation_drafts")
	check(not pending.has(quest_id + ":" + second_id) and pending.has(quest_id + ":main") and pending.has(quest_id + ":__completed__"), "assignment cleared another goal/final draft")
	workspace.call("_set_quest_focus", "main")
	(workspace.find_child("DiscardQuestConversation_0", true, false) as Button).pressed.emit()
	check((workspace.get("_quest_conversation_drafts") as Dictionary).is_empty(), "reset did not drop unassigned fields")
	check(not bool(workspace.call("_has_unsaved_draft")), "reset left a ghost unsaved state")
	workspace.call("_set_quest_focus", second_id)
	check((workspace.find_child("QuestConversationText_1", true, false) as TextEdit).text == "Вот твоя награда", "reset erased the committed reply")
	check(workspace.find_child("QuestRewardItems_1", true, false).value() == {"coin": 3}, "reset erased committed rewards")
	(workspace.find_child("QuestConversationText_1", true, false) as TextEdit).text = "Отбросить только это изменение"
	workspace.call("_request_navigation", "quest", "interaction_quest", false)
	check(discard.visible, "second navigation did not warn")
	discard.hide()
	discard.confirmed.emit()
	check(str(workspace.get("_current_id")) == "interaction_quest" and (workspace.get("_quest_conversation_drafts") as Dictionary).is_empty(), "explicit discard did not navigate and clear drafts")
	workspace.open_resource("quest", quest_id)
	workspace.call("_set_quest_focus", second_id)
	check((workspace.find_child("QuestConversationText_1", true, false) as TextEdit).text == "Вот твоя награда", "discard damaged committed dialogue")
	history.clear_history()
	history.free()
	workspace.queue_free()
	scene.queue_free()
	await process_frame
	Fixture.verify_sources(errors)
	if errors.is_empty():
		print("PASS quest conversation drafts: NPC/goal selection preserves text/mode/rewards/final, no Resource writes, save warning, cancel/discard/reset, assignment clears only its part")
		quit(0)
	else:
		for error in errors:
			printerr("FAIL ", error)
		quit(1)
