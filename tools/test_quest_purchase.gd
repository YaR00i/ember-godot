extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_interaction_test_fixture.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const Editor = preload("res://addons/ember_import/ember_quest_editor.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
var setup: Dictionary

func _initialize() -> void:
	setup = Fixture.prepare(self)
	if setup.refused:
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	assert(setup.error == OK)
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.restore_enabled = false
	state.inventory = {"coin": 200}
	# Buying before acceptance, picking up and selling are not buying for this goal.
	assert(state.buy("story_tea_shop", "qingxin_tea").ok)
	assert(not state.flags.has("story_tea_bought"))
	state.flags["story_tea_status"] = "active"
	assert(state.buy("story_tea_shop", "qingxin_tea").ok)
	assert(not state.flags.has("story_tea_bought")) # prerequisite still locked
	state.flags["story_tea_meet"] = true
	state.grant_item("qingxin_tea", 1, false)
	assert(state.sell("story_tea_shop", "qingxin_tea").ok)
	assert(state.buy("interaction_shop", "qingxin_tea").ok)
	assert(state.buy("story_tea_shop", "herb").ok)
	assert(not state.flags.has("story_tea_bought"))
	state.inventory["coin"] = 0
	assert(not state.buy("story_tea_shop", "qingxin_tea").ok)
	state.inventory = {"coin": 200, "qingxin_tea": 10}
	var stock := state.shop_stock.duplicate(true)
	assert(state.buy("story_tea_shop", "qingxin_tea").reason == "stack_full")
	assert(state.inventory.coin == 200 and state.shop_stock == stock)
	assert(not state.flags.has("story_tea_bought"))
	state.storage_root = str(setup.directory).path_join("purchase-save")
	state.persistence_enabled = true
	var saved_paths: Array[String] = []
	state.saved.connect(func(path: String): saved_paths.append(path))
	state.inventory.erase("qingxin_tea")
	assert(state.buy("story_tea_shop", "qingxin_tea").ok)
	assert(state.flags.story_tea_bought == 1)
	assert(saved_paths.size() == 1)
	# The canonical save stores inventory, stock and progress; loading is not a new event.
	var tracker := preload("res://scripts/ember_quest_tracker_ui.gd").new()
	tracker.progress_state = state
	root.add_child(tracker)
	assert("1/2" in tracker._objective.text)
	var journal := EmberQuestJournalUi.new()
	journal.progress_state = state
	root.add_child(journal)
	journal.open()
	assert("1/2" in journal.find_child("QuestObjective_buy", true, false).text)
	tracker.queue_free()
	journal.queue_free()
	var restored := EmberExploreState.new()
	restored.persistence_enabled = false
	restored.restore_enabled = false
	restored.storage_root = state.storage_root
	assert(restored.load_autosave())
	assert(restored.flags.story_tea_bought == 1)
	assert(restored.inventory == state.inventory and restored.shop_stock == state.shop_stock)
	assert(restored.buy("story_tea_shop", "qingxin_tea").ok)
	assert(restored.flags.story_tea_bought == 2)
	assert(restored.buy("story_tea_shop", "qingxin_tea").ok)
	assert(restored.flags.story_tea_bought == 2)
	var document := Store.document("story_tea_errand")
	assert(Store.validation_errors(document).is_empty())
	var invalid := document.duplicate(true)
	invalid.objectives[1].purchaseItemId = "meat_bun"
	assert(not Store.validation_errors(invalid).is_empty())
	var sequential := {
		"id": "purchase_sequence", "titleRu": "Последовательные покупки", "statusFlagId": "purchase_sequence_status",
		"objectives": [
			{"id": "one", "textRu": "Первая", "flagId": "purchase_first", "progressMode": "purchase", "purchaseShopId": "story_tea_shop", "purchaseItemId": "herb", "requiredCount": 1},
			{"id": "two", "textRu": "Вторая", "flagId": "purchase_second", "progressMode": "purchase", "purchaseShopId": "story_tea_shop", "purchaseItemId": "herb", "requiredCount": 1, "requiresObjectiveIds": ["one"]},
		]}
	assert(Store.write_document(sequential) == OK)
	var sequence_state := EmberExploreState.new()
	sequence_state.persistence_enabled = false
	sequence_state.inventory = {"coin": 100}
	assert(sequence_state.buy("story_tea_shop", "herb").ok)
	assert(not sequence_state.flags.has("purchase_first")) # root goal, quest not accepted
	sequence_state.flags.purchase_sequence_status = "active"
	assert(sequence_state.buy("story_tea_shop", "herb").ok)
	assert(sequence_state.flags.purchase_first == 1 and not sequence_state.flags.has("purchase_second"))
	assert(sequence_state.buy("story_tea_shop", "herb").ok)
	assert(sequence_state.flags.purchase_second == 1)
	sequence_state.free()
	var form := Editor.new()
	root.add_child(form)
	form.setup("story_tea_errand", "")
	assert(form._document() == Store.normalized_document(document))
	var fields := form._objectives.get_child(1).find_child("QuestPurchaseFields", true, false)
	assert(fields.visible)
	assert(fields.get_node("PurchaseItem").item_count == 3)
	# Native Graph draft: one dropdown command, Undo/Redo, native save/reload and discard.
	var workspace := Workspace.new()
	root.add_child(workspace)
	workspace._current_kind = "quest"
	workspace._current_id = "story_tea_errand"
	workspace._reset_quest_draft(document)
	var holder := VBoxContainer.new()
	root.add_child(holder)
	workspace._add_quest_objective_progress(holder, 1, document.objectives[1])
	var picker := holder.find_child("PurchaseItem", true, false) as OptionButton
	_select(picker, "herb")
	picker.item_selected.emit(picker.selected)
	assert(workspace._quest_draft.objectives[1].purchaseItemId == "herb")
	workspace._undo_action_draft()
	assert(workspace._quest_draft.objectives[1].purchaseItemId == "qingxin_tea")
	workspace._redo_action_draft()
	assert(workspace._quest_draft.objectives[1].purchaseItemId == "herb")
	var edited: Dictionary = workspace._quest_draft.duplicate(true)
	assert(Store.write_document(edited) == OK)
	assert(Store.document("story_tea_errand").objectives[1].purchaseItemId == "herb")
	workspace._reset_quest_draft(edited)
	workspace._push_quest_draft(document)
	assert(workspace._quest_draft.objectives[1].purchaseItemId == "qingxin_tea")
	workspace._request_navigation("quest", "story_tea_errand", true)
	assert(not workspace._pending_navigation.is_empty())
	workspace._cancel_discard_navigation()
	assert(workspace._quest_draft.objectives[1].purchaseItemId == "qingxin_tea")
	workspace._request_navigation("quest", "story_tea_errand", true)
	workspace._confirm_discard_navigation()
	assert(workspace._quest_draft.objectives[1].purchaseItemId == "herb")
	assert(Store.write_document(document) == OK)
	# Existing real scene -> NPC -> shop -> two purchases -> presentation -> reward.
	var stage: Node3D = load("res://scenes/prototypes/camera_preset_study.tscn").instantiate()
	root.add_child(stage)
	await process_frame
	stage.reset_tea_trial()
	var progress: EmberExploreState = stage._preview_state
	var ui: EmberInteractionUi = stage.get_node("QuestLayer/InteractionUi")
	stage.start_tea_trial()
	assert(ui.view_state().mode == "dialogue")
	ui.advance()
	assert(progress.flags.get("story_tea_meet", false))
	stage.open_tea_shop()
	ui.close() # cancel is never a purchase
	assert(not progress.flags.has("story_tea_bought"))
	stage.open_tea_shop()
	ui.advance()
	assert(progress.flags.story_tea_bought == 1)
	ui.advance()
	assert(progress.flags.story_tea_bought == 2)
	ui.close()
	stage.start_tea_trial()
	assert(ui.view_state().mode == "presentation" and not progress.flags.has("story_tea_reward"))
	stage.get_node("StoryPreview").skip()
	await process_frame
	# Skip visuals preserves the real dialogue checkpoint and its choice.
	var story_ui: EmberInteractionUi = stage.get_node("DialogueLayer/InteractionUi")
	story_ui.advance()
	story_ui.choose(0)
	story_ui.advance()
	for i in 5: await process_frame
	assert(progress.flags.get("story_tea_reward", false))
	assert(progress.inventory.coin == 21) # 30 - 12 + 3
	stage.start_tea_trial()
	ui.advance()
	assert(progress.inventory.coin == 21)
	stage.queue_free()
	form.queue_free()
	workspace.queue_free()
	holder.queue_free()
	state.free()
	restored.free()
	await process_frame
	print("PASS purchase quest: transaction filters, stack full, save/load, both editors, Graph Undo/Redo/reopen/discard, NPC/shop/presentation/reward once")
	quit()

func _select(picker: OptionButton, value: String) -> void:
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == value:
			picker.select(index)
			return
	assert(false, "missing choice " + value)
