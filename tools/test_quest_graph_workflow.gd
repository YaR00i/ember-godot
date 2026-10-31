extends SceneTree
## Author workflow: ordered goals are one undoable edit of the existing Resource.
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const ActionStore = preload("res://addons/ember_import/ember_action_script_store.gd")
const Usage = preload("res://addons/ember_import/ember_quest_usage_index.gd")
const Giver = preload("res://scripts/ember_quest_giver_interact.gd")
const DialogueStore = preload("res://addons/ember_import/ember_dialogue_store.gd")
var _save_count := 0
var _created_npc: Node3D

class PlacementMap extends EmberMapLoader:
	var test_solid := true
	var test_submerged := false
	func _ready() -> void:
		pass
	func surface_floor_sample(point: Vector3) -> Dictionary:
		return {"solid": test_solid, "submerged": test_submerged, "position": Vector3(point.x, 10, point.z)}

func _init() -> void:
	if not Fixture.prepare(self):
		quit(2)
		return
	root.size = Vector2i(1600, 900)
	_run.call_deferred()

func _run() -> void:
	var errors: Array[String] = []
	var workspace := Workspace.new()
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	workspace.open_resource("quest", "interaction_quest")
	(workspace.find_child("GraphNewQuest", true, false) as Button).pressed.emit()
	var original: Dictionary = workspace.get("_quest_draft").duplicate(true)
	var quest_id := str(original.id)
	var snapshot := Store.snapshot(quest_id)
	workspace.quest_save_requested.connect(func(document: Dictionary) -> void:
		_save_count += 1
		if Store.write_document(document) != OK:
			errors.append("Resource save failed")
	)
	var advanced := workspace.find_child("QuestAdvanced", true, false) as Control
	if advanced == null or advanced.visible:
		errors.append("service keys are not collapsed by default")
	var toggle := workspace.find_child("QuestAdvancedToggle", true, false) as Button
	toggle.button_pressed = true
	if not advanced.visible:
		errors.append("advanced keys cannot be opened")
	toggle.button_pressed = false
	workspace.call("_begin_quest_inline_edit")
	workspace.call("_set_quest_document_field", "Послание на берегу", "titleRu")
	workspace.call("_set_quest_objective_field", "Прочитать послание", 0, "textRu")
	workspace.call("_commit_quest_inline_edit")
	workspace.call("_set_quest_focus", "main")
	(workspace.find_child("QuestNextObjective_0", true, false) as Button).pressed.emit()
	var draft: Dictionary = workspace.get("_quest_draft")
	if draft.objectives.size() != 2 or draft.objectives[1].requiresObjectiveIds != ["main"]:
		errors.append("Next goal did not create the prerequisite automatically")
	if workspace.find_child("InlineQuestObjective_1_textRu", true, false) == null:
		errors.append("Next goal was created but its card is not visible")
	(workspace.find_child("GraphDraftUndo", true, false) as Button).pressed.emit()
	if (workspace.get("_quest_draft") as Dictionary).objectives.size() != 1:
		errors.append("Next goal is not a single Undo step")
	(workspace.find_child("GraphDraftRedo", true, false) as Button).pressed.emit()
	draft = workspace.get("_quest_draft")
	if draft.objectives.size() != 2 or draft.objectives[1].requiresObjectiveIds != ["main"]:
		errors.append("Redo lost the ordered goal")
	workspace.call("_begin_quest_inline_edit")
	workspace.call("_set_quest_objective_field", "Поговорить с хранителем", 1, "textRu")
	workspace.call("_commit_quest_inline_edit")
	(workspace.find_child("QuestNextObjective_1", true, false) as Button).pressed.emit()
	draft = workspace.get("_quest_draft")
	if draft.objectives[2].requiresObjectiveIds != [draft.objectives[1].id]:
		errors.append("third goal does not wait for the chosen second goal")
	workspace.call("_save_quest_graph")
	var stored := Store.document(quest_id)
	if _save_count != 1 or stored.objectives.size() != 3 or bool(workspace.call("_has_unsaved_draft")):
		errors.append("save/reopen lost goals or retained dirty state")
	# Invalid dependencies must still block the existing save owner.
	workspace.call("_add_quest_objective", "missing")
	if workspace.get("_quest_draft") != stored:
		errors.append("unknown prerequisite changed the draft")
	workspace.call("_begin_quest_inline_edit")
	workspace.call("_set_quest_document_field", "", "statusFlagId")
	workspace.call("_commit_quest_inline_edit")
	workspace.call("_save_quest_graph")
	if _save_count != 1:
		errors.append("invalid quest reached the save signal")
	workspace.call("_request_navigation", "quest", "interaction_quest", false)
	if not bool(workspace.call("_has_unsaved_draft")):
		errors.append("navigation discarded changes without confirmation")
	workspace.call("_confirm_discard_navigation")
	(workspace.get("_discard_draft_dialog") as ConfirmationDialog).hide()
	workspace.open_resource("quest", quest_id)
	if workspace.get("_quest_draft") != stored:
		errors.append("discard/reopen changed the saved quest")
	_test_conversation(errors, workspace, stored)
	_test_create_conversation(errors, workspace)
	# Capture the real native UI, optionally requested by a Forward+ probe.
	var capture := OS.get_environment("EMBER_QUEST_WORKFLOW_CAPTURE")
	if not capture.is_empty():
		workspace.call("_set_quest_focus", "main")
		var graph := workspace.find_child("EmberGraphEdit", true, false) as GraphEdit
		graph.zoom = 0.8
		graph.scroll_offset = Vector2.ZERO
		for index in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
		if is_instance_valid(_created_npc):
			workspace.visible = false
			var camera := Camera3D.new()
			_created_npc.get_parent().add_child(camera)
			camera.global_position = _created_npc.global_position + Vector3(40, 28, 50)
			camera.look_at(_created_npc.global_position + Vector3.UP * 12)
			camera.current = true
			var light := DirectionalLight3D.new()
			_created_npc.get_parent().add_child(light)
			light.rotation_degrees = Vector3(-45, -35, 0)
			var floor_mesh := MeshInstance3D.new()
			floor_mesh.mesh = PlaneMesh.new()
			(floor_mesh.mesh as PlaneMesh).size = Vector2(120, 120)
			_created_npc.get_parent().add_child(floor_mesh)
			floor_mesh.global_position = _created_npc.global_position
			for index in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture.get_basename() + "-npc.png")
	Store.restore_snapshot(snapshot)
	workspace.queue_free()
	await process_frame
	if errors.is_empty():
		print("PASS quest workflow: next goal, Undo/Redo, advanced keys, save/reopen, discard, validation")
	else:
		for error in errors:
			push_error(error)
	quit(0 if errors.is_empty() else 1)


func _test_conversation(errors: Array[String], workspace: EmberGraphWorkspace, quest: Dictionary) -> void:
	var scene := Node3D.new()
	scene.name = "ConversationFixture"
	root.add_child(scene)
	var map := PlacementMap.new()
	map.name = "Map"
	scene.add_child(map)
	var start := Node3D.new()
	start.name = "player_start"
	scene.add_child(start)
	start.global_position = Vector3(16, 100, 48)
	var placement := EmberSceneAuthoring.quest_npc_position(scene)
	if not placement.get("ok", false) or not (placement.get("position", Vector3.ZERO) as Vector3).is_equal_approx(Vector3(32, 10, 48)):
		errors.append("NPC placement did not use player start and the physical floor height")
	map.test_submerged = true
	if EmberSceneAuthoring.quest_npc_position(scene).get("ok", false):
		errors.append("NPC placement accepted underwater ground")
	map.test_submerged = false
	map.test_solid = false
	if EmberSceneAuthoring.quest_npc_position(scene).get("ok", false):
		errors.append("NPC placement accepted missing ground")
	map.test_solid = true
	var npc := Node3D.new()
	npc.name = "Хранитель"
	scene.add_child(npc)
	npc.owner = scene
	var giver := Giver.new() as EmberInteract
	giver.name = "Talk"
	giver.kind = "talk"
	npc.add_child(giver)
	giver.owner = scene
	workspace.set_scene_root(scene)
	workspace.set_scene_selection(npc)
	workspace.call("_set_quest_focus", "main")
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	var bind_handler := func(path: NodePath, token: String, dialogue: String, draft: Dictionary, costs: Dictionary, choice: Dictionary, options: Dictionary) -> void:
		if not actions.bind_quest_conversation(scene.get_node(path), token, dialogue, scene, draft, null, Vector3.ZERO, costs, choice, options):
			errors.append("conversation UI binding was rejected")
	workspace.quest_conversation_bind_requested.connect(bind_handler)
	var picker := workspace.find_child("QuestConversationDialogue_0", true, false) as OptionButton
	if picker == null or picker.item_count == 0:
		errors.append("conversation UI has no dialogue picker")
		scene.queue_free()
		return
	var selected_dialogue := str(picker.get_selected_metadata())
	if (workspace.find_child("BindQuestConversation_0", true, false) as Button).disabled:
		errors.append("conversation UI is disabled for the selected NPC")
	(workspace.find_child("BindQuestConversation_0", true, false) as Button).pressed.emit()
	var routes: Dictionary = giver.get("objective_scripts")
	var first_id := str(routes.get("main", ""))
	if first_id.is_empty():
		errors.append("conversation UI did not assign the objective route")
		scene.queue_free()
		return
	var first_chain := ActionStore.document(first_id)
	if first_chain.steps.size() != 2 or first_chain.steps[0].dialogueId != selected_dialogue or first_chain.steps[1].flag != quest.objectives[0].flagId:
		errors.append("conversation does not precede objective completion")
	history.undo()
	if giver.quest_id != "" or not (giver.get("objective_scripts") as Dictionary).is_empty() or ActionStore.exists(first_id):
		errors.append("conversation Undo did not restore the NPC and remove its new chain")
	history.redo()
	if giver.quest_id != str(quest.id) or not ActionStore.exists(first_id):
		errors.append("conversation Redo did not restore the binding")
	var objective_two := str(quest.objectives[1].id)
	if not actions.bind_quest_conversation(npc, Store.event_token(str(quest.id), "objective", objective_two), selected_dialogue, scene, quest):
		errors.append("second conversation stage was rejected")
	routes = giver.get("objective_scripts")
	var second_id := str(routes.get(objective_two, ""))
	var event_entries := Usage.entries(quest)
	var scene_entries := Usage.scene_entries(scene, quest, event_entries)
	if scene_entries.size() != 1 or (scene_entries[0].eventIds as Array).size() != 2:
		errors.append("conversation stages have no scene backlinks")
	for entry in event_entries:
		if str(entry.get("documentId", "")) == first_id:
			if actions.remove_unbound_quest_event(entry, scene).get("ok", false):
				errors.append("orphan cleanup deleted a conversation still used by the NPC")
			if not actions.unbind_quest_event(giver, entry, scene).get("ok", false) or (giver.get("objective_scripts") as Dictionary).has("main"):
				errors.append("conversation could not be unbound through its backlink")
			history.undo()
			if giver.get("objective_scripts") != routes:
				errors.append("conversation unbind Undo lost the stage routes")
	# Pack/reopen the scene: per-stage routing must be serialized, not UI state.
	var packed := PackedScene.new()
	var scene_path := "user://quest-conversation-roundtrip.tscn"
	if packed.pack(scene) != OK or ResourceSaver.save(packed, scene_path) != OK:
		errors.append("conversation scene did not save")
	else:
		var reopened := (ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var reopened_giver := reopened.get_node("Хранитель/Talk") as EmberInteract
		if reopened_giver.get("objective_scripts") != routes or reopened_giver.quest_id != giver.quest_id:
			errors.append("scene reopen lost conversation stages")
		reopened.free()
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	progress.persistence_enabled = false
	progress.flags.clear()
	progress.flags[str(quest.statusFlagId)] = "active"
	var ui := EmberInteractionUi.new()
	ui.economy_state = progress
	root.add_child(ui)
	ui.activate(giver)
	if progress.flags.get(str(quest.objectives[0].flagId), false):
		errors.append("conversation completed its objective before reading")
	ui.close()
	if progress.flags.get(str(quest.objectives[0].flagId), false):
		errors.append("cancelled conversation completed its objective")
	ui.activate(giver)
	for index in 32:
		if not ui.is_open():
			break
		ui.advance()
	if not progress.flags.get(str(quest.objectives[0].flagId), false):
		errors.append("completed conversation did not advance its objective")
	if str(giver.runtime_route(progress.flags).get("scriptId", "")) != second_id:
		errors.append("NPC did not select the next conversation stage")
	ui.queue_free()
	# A different quest and a missing dialogue must not alter the NPC/resources.
	var before := routes.duplicate(true)
	giver.quest_id = "another_quest"
	if actions.bind_quest_conversation(npc, Store.event_token(str(quest.id), "objective", "main"), selected_dialogue, scene, quest):
		errors.append("conversation overwrote an NPC belonging to a different quest")
	giver.quest_id = str(quest.id)
	if actions.bind_quest_conversation(npc, Store.event_token(str(quest.id), "objective", "main"), "missing_dialogue", scene, quest) or giver.get("objective_scripts") != before:
		errors.append("invalid dialogue changed the NPC")
	var alternate := ""
	for dialogue_id in EmberInteractionContent.dialogue_ids():
		if dialogue_id != selected_dialogue:
			alternate = dialogue_id
			break
	if not alternate.is_empty():
		var other := Giver.new() as EmberInteract
		other.name = "OtherNPC"
		other.quest_id = str(quest.id)
		other.set("objective_scripts", {"main": first_id})
		scene.add_child(other)
		if not actions.bind_quest_conversation(npc, Store.event_token(str(quest.id), "objective", "main"), alternate, scene, quest):
			errors.append("replacement conversation was rejected")
		elif str((giver.get("objective_scripts") as Dictionary).get("main", "")) == first_id or ActionStore.document(first_id) != first_chain:
			errors.append("replacement conversation modified a shared authored chain")
		history.undo()
		if giver.get("objective_scripts") != before:
			errors.append("replacement conversation Undo did not restore the old route")
		other.free()
	workspace.refresh_quest_scene_projection()
	# Keep the native capture's selected NPC until the workspace is destroyed.
	# Canonical fixture Resources remain until the disposable project is removed,
	# so the native screenshot can show their real backlinks and chosen dialogue.
	history.clear_history()
	workspace.quest_conversation_bind_requested.disconnect(bind_handler)
	history.free()
	print("  conversation UI, two stages, backlinks, Undo/Redo, scene roundtrip, cancel/completion PASS")


func _test_create_conversation(errors: Array[String], workspace: EmberGraphWorkspace) -> void:
	var scene := Node3D.new()
	scene.name = "NewNPCFixture"
	scene.position = Vector3(5, 2, -7)
	root.add_child(scene)
	workspace.set_scene_root(scene)
	workspace.set_scene_selection(null)
	(workspace.find_child("GraphNewQuest", true, false) as Button).pressed.emit()
	workspace.call("_set_quest_focus", "main")
	var quest: Dictionary = workspace.get("_quest_draft")
	var quest_id := str(quest.id)
	var history := UndoRedo.new()
	var actions := Actions.new()
	actions.configure(history)
	var created: Array[Node3D] = []
	var destination := Vector3(32, 10, 48)
	workspace.quest_conversation_create_requested.connect(func(_anchor: NodePath, display_name: String, token: String, dialogue: String, draft: Dictionary, costs: Dictionary, choice: Dictionary, options: Dictionary) -> void:
		var npc := actions.create_quest_conversation(scene, destination, display_name, token, dialogue, draft, costs, choice, options)
		if npc != null:
			created.append(npc)
	)
	var name_input := workspace.find_child("QuestConversationName_0", true, false) as LineEdit
	var create := workspace.find_child("CreateQuestConversation_0", true, false) as Button
	if name_input == null or create == null or create.disabled:
		errors.append("new NPC authoring is not available in the objective card")
		scene.queue_free()
		return
	name_input.text = "Искатель ракушек"
	create.pressed.emit()
	if created.size() != 1:
		errors.append("new NPC UI did not create a scene actor")
		scene.queue_free()
		return
	var npc := created[0]
	_created_npc = npc
	var giver := EmberObjectInspectorModel.quest_conversation_target(npc)
	var route_id := str((giver.get("objective_scripts") as Dictionary).get("main", ""))
	if giver.quest_id != quest_id or str(giver.get("display_name")) != "Искатель ракушек" or route_id.is_empty():
		errors.append("new NPC did not receive the human name, quest and dialogue route")
	if not npc.global_position.is_equal_approx(destination) or npc.owner != scene:
		errors.append("new NPC placement/scene ownership is wrong")
	if npc.get_node_or_null("Visual") == null or npc.get_node_or_null("Body/Shape") == null:
		errors.append("new NPC has no visible model or body collision")
	history.undo()
	if npc.get_parent() != null or not Store.document(quest_id).is_empty() or ActionStore.exists(route_id):
		errors.append("one Undo did not remove NPC, new quest and action together")
	history.redo()
	if npc.get_parent() != scene or Store.document(quest_id).is_empty() or not ActionStore.exists(route_id):
		errors.append("one Redo did not restore the complete NPC authoring")
	var packed := PackedScene.new()
	var path := "user://created-quest-npc.tscn"
	if packed.pack(scene) != OK or ResourceSaver.save(packed, path) != OK:
		errors.append("created NPC scene did not save")
	else:
		var reopened := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		var saved_npc := reopened.get_node_or_null(NodePath(str(npc.name))) as Node3D
		var saved_giver := EmberObjectInspectorModel.quest_conversation_target(saved_npc)
		if saved_giver == null or saved_giver.quest_id != quest_id or saved_npc.get_node_or_null("Visual") == null or not saved_npc.transform.is_equal_approx(npc.transform):
			errors.append("new NPC lost appearance, placement or quest on scene reopen")
		reopened.free()
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	progress.flags.clear()
	var ui := EmberInteractionUi.new()
	ui.economy_state = progress
	root.add_child(ui)
	ui.activate(giver)
	for index in 32:
		if not ui.is_open():
			break
		ui.advance()
	if not progress.flags.get(str(quest.objectives[0].flagId), false):
		errors.append("newly created NPC conversation did not complete its quest objective")
	ui.queue_free()
	var before_count := scene.get_child_count()
	if actions.create_quest_conversation(scene, destination, "Другой", Store.event_token(quest_id, "objective", "main"), "missing_dialogue", quest) != null or scene.get_child_count() != before_count:
		errors.append("failed NPC creation left an actor in the scene")
	# Selection + draft acknowledgement follows the same route as the editor plugin.
	workspace.accept_quest_binding_save("", true)
	workspace.set_scene_selection(npc)
	workspace.call("_set_quest_focus", "main")
	var delivery_handler := func(path: NodePath, token: String, dialogue: String, draft: Dictionary, costs: Dictionary, choice: Dictionary, options: Dictionary) -> void:
		if not actions.bind_quest_conversation(scene.get_node(path), token, dialogue, scene, draft, null, Vector3.ZERO, costs, choice, options):
			errors.append("delivery UI binding was rejected")
	workspace.quest_conversation_bind_requested.connect(delivery_handler)
	var enabled := workspace.find_child("QuestHandoverEnabled_0", true, false) as CheckBox
	var item_picker := workspace.find_child("QuestHandoverItem_0", true, false) as OptionButton
	var required := workspace.find_child("QuestHandoverCount_0", true, false) as SpinBox
	for index in item_picker.item_count:
		if str(item_picker.get_item_metadata(index)) == "shore_shell":
			item_picker.select(index)
	enabled.button_pressed = true
	required.value = 3
	(workspace.find_child("BindQuestConversation_0", true, false) as Button).pressed.emit()
	var delivery_id := str((giver.get("objective_scripts") as Dictionary).get("main", ""))
	var delivery := ActionStore.document(delivery_id)
	if delivery.get("steps", []).size() != 3 or delivery.steps[1].get("costs", {}) != {"shore_shell": 3}:
		errors.append("delivery UI did not compile talk/exchange/completion")
	history.undo()
	if str((giver.get("objective_scripts") as Dictionary).get("main", "")) != route_id or ActionStore.exists(delivery_id):
		errors.append("delivery Undo did not restore the original conversation")
	history.redo()
	progress.flags.clear()
	progress.inventory.clear()
	progress.grant_item("shore_shell", 2, false)
	var delivery_ui := EmberInteractionUi.new()
	delivery_ui.economy_state = progress
	root.add_child(delivery_ui)
	delivery_ui.activate(giver)
	for index in 32:
		if not delivery_ui.is_open():
			break
		delivery_ui.advance()
	if int(progress.inventory.get("shore_shell", 0)) != 2 or progress.flags.get(str(quest.objectives[0].flagId), false):
		errors.append("insufficient delivery consumed items or completed its objective")
	delivery_ui.close()
	progress.grant_item("shore_shell", 2, false)
	delivery_ui.activate(giver)
	delivery_ui.close()
	if int(progress.inventory.get("shore_shell", 0)) != 4 or progress.flags.get(str(quest.objectives[0].flagId), false):
		errors.append("cancelled delivery consumed items or completed its objective")
	delivery_ui.activate(giver)
	for index in 32:
		if not delivery_ui.is_open():
			break
		delivery_ui.advance()
	if int(progress.inventory.get("shore_shell", 0)) != 1 or not progress.flags.get(str(quest.objectives[0].flagId), false):
		errors.append("successful delivery did not consume exactly three items and finish")
	delivery_ui.activate(giver)
	if int(progress.inventory.get("shore_shell", 0)) != 1:
		errors.append("repeated interaction charged the completed delivery again")
	delivery_ui.queue_free()
	workspace.accept_quest_binding_save("", true)
	if not (workspace.find_child("QuestHandoverEnabled_0", true, false) as CheckBox).button_pressed or int((workspace.find_child("QuestHandoverCount_0", true, false) as SpinBox).value) != 3:
		errors.append("delivery fields did not reopen from the saved Action")
	_test_choice_outcome(errors, workspace, actions, history, scene, npc, giver, quest, progress)
	workspace.quest_conversation_bind_requested.disconnect(delivery_handler)
	history.clear_history()
	if not is_instance_valid(npc) or npc.get_parent() != scene:
		errors.append("clearing editor history deleted the committed NPC")
	history.free()
	print("  create NPC UI: model/name/quest/route, one Undo/Redo, scene roundtrip, runtime conversation PASS")
	print("  delivery UI: 3 shells, insufficient/cancel unchanged, exact charge, repeat safe, Undo/Redo/reopen PASS")


func _test_choice_outcome(errors: Array[String], workspace: EmberGraphWorkspace, actions: EmberObjectInspectorActions, history: UndoRedo, scene: Node3D, npc: Node3D, giver: EmberInteract, quest: Dictionary, progress: EmberExploreState) -> void:
	var source := {
		"id": "quest_outcome_fixture", "nameRu": "Помощь хранителю", "uses": ["talk"], "startStepId": "question",
		"steps": [
			{"id": "question", "type": "choice", "promptRu": "Поможешь хранителю?", "options": [
				{"id": "yes", "labelRu": "Согласен", "next": "yes_reply", "setFlags": {"unrelated_reply_flag": true}},
				{"id": "no", "labelRu": "Не сейчас", "next": "no_reply"},
			]},
			{"id": "yes_reply", "type": "dialogue", "speaker": "guard", "nameRu": "Хранитель", "textRu": "Спасибо!", "next": "end"},
			{"id": "no_reply", "type": "dialogue", "speaker": "guard", "nameRu": "Хранитель", "textRu": "До встречи.", "next": "end"},
			{"id": "end", "type": "end"},
		],
	}
	if DialogueStore.write_graph_document(source) != OK:
		errors.append("choice dialogue fixture could not save")
		return
	var original := DialogueStore.document(str(source.id)).duplicate(true)
	var old_routes: Dictionary = giver.get("objective_scripts").duplicate(true)
	workspace.refresh_quest_scene_projection()
	var picker := workspace.find_child("QuestConversationDialogue_0", true, false) as OptionButton
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == str(source.id):
			picker.select(index)
			picker.item_selected.emit(index)
	var outcome := workspace.find_child("QuestConversationOutcome_0", true, false) as OptionButton
	if outcome == null or outcome.item_count != 3:
		errors.append("quest card does not list the actual dialogue answers")
		return
	outcome.select(1)
	outcome.item_selected.emit(1)
	if (workspace.find_child("QuestHandoverEnabled_0", true, false) as CheckBox).button_pressed:
		errors.append("choice goal still has an unconditional item handover")
	(workspace.find_child("BindQuestConversation_0", true, false) as Button).pressed.emit()
	var route_id := str((giver.get("objective_scripts") as Dictionary).get("main", ""))
	var chain := ActionStore.document(route_id)
	if chain.get("steps", []).size() != 1:
		errors.append("choice goal retained unconditional completion")
		return
	var private_id := str(chain.steps[0].dialogueId)
	if private_id == str(source.id) or DialogueStore.document(str(source.id)) != original:
		errors.append("choice binding modified the shared source dialogue")
	history.undo()
	if giver.get("objective_scripts") != old_routes or DialogueStore.exists(private_id):
		errors.append("choice Undo did not restore the route and remove its private dialogue")
	history.redo()
	if not DialogueStore.exists(private_id) or not ActionStore.exists(route_id):
		errors.append("choice Redo did not restore its documents")
	var flag := str(quest.objectives[0].flagId)
	var reopened := ResourceLoader.load(DialogueStore.source_path(private_id), "", ResourceLoader.CACHE_MODE_IGNORE) as EmberDialogueResource
	if reopened == null or not reopened.document.steps[0].options[0].setFlags.get(flag, false):
		errors.append("saved choice dialogue lost its outcome")
	progress.flags.clear()
	var ui := EmberInteractionUi.new()
	ui.economy_state = progress
	root.add_child(ui)
	ui.activate(giver)
	ui.choose(0)
	if progress.flags.get(flag, false):
		errors.append("choice completed before the reply ended")
	ui.close()
	if progress.flags.get(flag, false):
		errors.append("cancelled choice completed the objective")
	ui.activate(giver)
	ui.choose(1)
	ui.advance()
	if progress.flags.get(flag, false):
		errors.append("declining completed the objective")
	ui.activate(giver)
	ui.choose(0)
	ui.advance()
	if not progress.flags.get(flag, false) or not progress.flags.get("unrelated_reply_flag", false):
		errors.append("accepted completed reply lost the objective or unrelated authored flags")
	ui.queue_free()
	var entries := Usage.scene_entries(scene, quest, Usage.entries(quest))
	if entries.size() != 1 or (entries[0].eventIds as Array).size() != 2:
		errors.append("dialogue outcome has no NPC backlink through its talk action")
	workspace.accept_quest_binding_save("", true)
	if (workspace.find_child("QuestConversationOutcome_0", true, false) as OptionButton).selected != 1:
		errors.append("outcome picker did not reopen the saved choice")
	if actions.bind_quest_conversation(npc, Store.event_token(str(quest.id), "objective", "main"), str(source.id), scene, quest, null, Vector3.ZERO, {"shore_shell": 3}, {"stepId": "question", "optionIndex": 0}):
		errors.append("choice binding accepted unsafe unconditional handover")
	var loop_source := source.duplicate(true)
	loop_source.steps[1].next = "question"
	var loop := DialogueStore.GraphModel.with_quest_choice_outcome(loop_source, {"stepId": "question", "optionIndex": 0}, flag)
	var session := EmberDialogueSession.new()
	session.start(loop)
	session.choose(0)
	session.advance()
	session.choose(1)
	session.advance()
	if session.flags().get(flag, true) != false:
		errors.append("revisited choice did not retain the final refusal")
	print("  outcome UI: selected answer/private copy/cancel/decline/accept/loop/Undo/Redo/reopen/backlink PASS")
