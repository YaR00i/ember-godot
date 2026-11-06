extends SceneTree
## Real adapters/transactions + both authoring forms; never writes author maps.
const Fixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const Editor = preload("res://addons/ember_import/ember_quest_editor.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
const Item = preload("res://scripts/ember_world_item_3d.gd")
const Leaves = preload("res://scripts/ember_leaf_pile.gd")
const Grass = preload("res://scripts/ember_cuttable_grass.gd")
const Bush = preload("res://scripts/ember_berry_bush.gd")
var errors: Array[String] = []
var state: EmberExploreState
var stage: Node3D

func _init() -> void:
	if not Fixture.prepare(self): quit(2); return
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message); printerr("CHECK FAIL ", message)

func select(picker: OptionButton, id: String) -> void:
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == id:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	check(false, "missing choice " + id)

func goal(id: String, action: String, target: String, amount: int, prerequisites: Array = []) -> Dictionary:
	return {"id":id,"textRu":id,"flagId":"world_"+id,"progressMode":"world_action", "worldAction":action,"worldTargetId":target,"requiredCount":amount,"requiresObjectiveIds":prerequisites}

func body(id: String, item_id: String) -> RigidBody3D:
	# Real body/hit adapter on an isolated stage, never an author map.
	var result := Item.new()
	result.pickup_id = id; result.item_id = item_id; result.progress_state = state
	result.map_id = "fixture"
	result.breakable = true
	state.ensure_authored_item(id, item_id, "fixture", Transform3D.IDENTITY)
	stage.add_child(result)
	return result

func cover(script: Script, flag: String) -> Area3D:
	var result := Area3D.new()
	result.set_script(script)
	result.revealed_flag_id = flag; result.progress_state = state
	root.add_child(result)
	return result

func _run() -> void:
	state = root.get_node("EmberExploreProgress")
	state.persistence_enabled = false; state.restore_enabled = false
	state.flags.clear(); state.world_items.clear(); state.inventory.clear()
	stage = Node3D.new(); root.add_child(stage); current_scene = stage
	var document := {"id":"world_actions", "titleRu":"Проверка действий в мире", "statusFlagId":"world_status", "objectives":[
		goal("break", "destroy", "quest_crate", 3),
		goal("leaves", "reveal_leaves", "", 2, ["break"]),
		goal("grass", "cut_grass", "", 1, ["leaves"]),
		goal("apples", "collect", "apple", 2, ["grass"]),
		goal("berries", "collect", "forest_berry", 3, ["apples"]),
		goal("craft", "craft", "chapter1_practice_assembly", 2, ["berries"]),
		{"id":"return","textRu":"Вернуться за наградой","flagId":"world_return","requiresObjectiveIds":["craft"]},
	]}
	check(Store.write_document(document) == OK, "valid action quest rejected")
	document = Store.document("world_actions")
	for action in ["destroy", "collect", "craft"]:
		var invalid: Dictionary = document.duplicate(true)
		invalid.objectives[0] = goal("bad", action, "missing_target", 1)
		check(not Store.validation_errors(invalid).is_empty(), "unknown target accepted " + action)
	var invalid: Dictionary = document.duplicate(true)
	invalid.objectives[0].worldAction = "missing_action"
	check(not Store.validation_errors(invalid).is_empty(), "unknown action accepted")
	# No progress from actions before acceptance or while prerequisites are locked.
	var early := body("early", "quest_crate")
	check(early.receive_world_hit(null, Vector3.RIGHT), "early physical hit failed")
	check(not state.flags.has("world_break"), "inactive quest counted hit")
	await process_frame
	state.apply_authored_flag("world_status", "active", false)
	var leaves := cover(Leaves, "early_leaves")
	check(leaves.receive_world_hit(null, Vector3.RIGHT), "early cover failed")
	check(not state.flags.has("world_leaves"), "locked leaves counted")
	check(not state.apply_authored_flag("world_break", true, false).changed, "set_flag bypassed world goal")
	state.combat_party_locked = true
	check(not state.destroy_world_item("locked") and not leaves.receive_world_hit(null, Vector3.RIGHT), "locked action accepted")
	state.combat_party_locked = false
	# Real hit adapter commits exactly once. Three distinct objects, wrong type ignored.
	var wrong := body("wrong", "apple")
	check(wrong.receive_world_hit(null, Vector3.RIGHT), "wrong-type object hit failed")
	await process_frame
	for index in 3:
		var crate := body("crate_%d" % index, "quest_crate")
		check(crate.receive_world_hit(null, Vector3.RIGHT), "crate hit failed")
		check(not crate.receive_world_hit(null, Vector3.RIGHT), "double break accepted")
		check(int(state.flags.get("world_break", 0)) == index + 1, "break count incorrect")
		await process_frame
	for index in 2:
		var pile := cover(Leaves, "leaf_%d" % index)
		check(pile.receive_world_hit(null, Vector3.RIGHT), "leaves failed")
		check(not pile.receive_world_hit(null, Vector3.RIGHT), "leaves counted twice")
	check(int(state.flags.get("world_leaves", 0)) == 2, "leaves count incorrect")
	check(not state.flags.has("world_grass"), "leaves counted as grass")
	var grass := cover(Grass, "grass_once")
	check(grass.receive_world_hit(null, Vector3.RIGHT), "cut failed")
	check(not grass.receive_world_hit(null, Vector3.RIGHT), "grass counted twice")
	check(state.flags.get("world_grass", 0) == 1, "grass count incorrect")
	state.grant_item("apple", 1, false)
	check(not state.flags.has("world_apples"), "reward counted as collection")
	state.world_items["drop_self"] = {"itemId":"apple","count":1,"mapId":"fixture"}
	check(state.pickup_world_item("drop_self", false).ok and not state.flags.has("world_apples"), "own drop farmed progress")
	state.ensure_authored_item("apple_tree", "apple", "fixture", Transform3D.IDENTITY)
	state.inventory.apple = int(EmberItemCatalog.definition("apple").stackMax)
	check(not state.pickup_world_item("apple_tree", false).ok and not state.flags.has("world_apples"), "full bag counted")
	state.inventory.erase("apple")
	# First pickup, inventory and progress must already agree in the first save callback.
	var output := "user://ember-tests/world-actions-%d" % Time.get_ticks_usec()
	state.storage_root = output.path_join("saves"); state.set_meta("world_canvas_storage_root", state.storage_root)
	state.persistence_enabled = true
	var saves: Array[String] = []
	state.saved.connect(func(path: String) -> void: saves.append(path))
	check(state.pickup_world_item("apple_tree").ok, "first apple pickup failed")
	check(saves.size() == 1 and state.flags.get("world_apples", 0) == 1, "pickup save count/progress incorrect")
	var tracker := preload("res://scripts/ember_quest_tracker_ui.gd").new()
	tracker.progress_state = state; tracker._tracked_id = "world_actions"; root.add_child(tracker)
	check("1/2" in tracker._objective.text, "HUD lost world action count")
	var journal := EmberQuestJournalUi.new(); journal.progress_state = state; root.add_child(journal); journal.open()
	check("1/2" in journal.find_child("QuestObjective_apples", true, false).text, "journal lost world action count")
	tracker.queue_free(); journal.queue_free()
	var cold := EmberExploreState.new()
	cold.persistence_enabled = false; cold.restore_enabled = false; cold.storage_root = state.storage_root
	check(cold.load_autosave(), "cold load failed")
	check(cold.flags.get("world_apples", 0) == 1 and int(cold.inventory.get("apple", 0)) == 1, "cold load lost atomic collection")
	check(not cold.pickup_world_item("apple_tree", false).ok and cold.flags.get("world_apples", 0) == 1, "reload replayed pickup")
	cold.free()
	state.ensure_authored_item("apple_second", "apple", "fixture", Transform3D.IDENTITY)
	check(state.pickup_world_item("apple_second").ok and state.flags.get("world_apples", 0) == 2, "second apple failed")
	var bush := Bush.new()
	bush.completion_flag_id = "bush_once"
	bush.harvest_count = 5
	root.add_child(bush)
	# _progress resolves the same autoload, and null actor avoids purely visual feedback.
	state.inventory.forest_berry = int(EmberItemCatalog.definition("forest_berry").stackMax)
	check("Получено" not in bush.activate_from(null) and not state.flags.has("world_berries") and not state.flags.has("bush_once"), "full bag consumed bush/progress")
	state.inventory.erase("forest_berry")
	check("Получено" in bush.activate_from(null), "berry harvest failed")
	check(state.flags.get("world_berries", 0) == 3, "berry quantity not counted")
	check(int(state.inventory.get("forest_berry", 0)) == 5, "goal clamping changed harvest quantity")
	bush.activate_from(null)
	check(state.flags.get("world_berries", 0) == 3, "berry harvest repeated")
	var recipe: Resource = load("res://content/recipes/chapter1_practice_assembly.tres")
	check(not state.craft_recipe(recipe).ok and not state.flags.has("world_craft"), "failed craft counted")
	state.inventory.herb = 6
	var before := saves.size()
	check(state.craft_recipe(recipe).ok and state.flags.get("world_craft", 0) == 1, "first craft failed")
	check(saves.size() == before + 1, "craft saved more than once")
	check(state.craft_recipe(recipe).ok and state.flags.get("world_craft", 0) == 2, "second craft failed")
	check(state.craft_recipe(recipe).ok and state.flags.get("world_craft", 0) == 2, "completed craft grew")
	# Journal/HUD receive numeric projection from the existing owner.
	var projection := EmberQuestCatalog.projection(document, state.flags)
	check(projection.objectives[5].done and projection.objectives[6].available, "return goal not unlocked")
	check(projection.status == "active", "quest finished before return")
	state.apply_authored_flag("world_return", true, false)
	check(EmberQuestCatalog.projection(document, state.flags).status == "done", "return did not finish quest")
	# Snapshot routing: an event completes only the first of two sequential goals.
	var sequential := {"id":"world_sequence","titleRu":"Sequence","statusFlagId":"sequence_status","objectives":[goal("seq1","collect","herb",1),goal("seq2","collect","herb",1,["seq1"])]}
	check(Store.write_document(sequential) == OK, "sequence write failed")
	state.flags.sequence_status = "active"
	state.ensure_authored_item("seq_herb", "herb", "fixture", Transform3D.IDENTITY)
	check(state.pickup_world_item("seq_herb").ok, "sequence pickup failed")
	check(state.flags.get("world_seq1", 0) == 1 and not state.flags.has("world_seq2"), "one pickup completed sequential goals")
	var restored := EmberExploreState.new()
	restored.persistence_enabled = false; restored.restore_enabled = false; restored.storage_root = state.storage_root
	check(restored.load_autosave(), "final cold load failed")
	check(restored.flags.get("world_craft", 0) == 2 and restored.flags.get("world_break", 0) == 3 and restored.flags.get("world_leaves", 0) == 2, "final load lost counters")
	check(restored.flags.get("bush_once", false) and restored.flags.get("leaf_0", false) and restored.world_items.get("crate_0", {}).get("count", 1) == 0, "final load lost consumed world state")
	check(restored.inventory == state.inventory, "final load changed inventory")
	restored.free()
	# Author choices survive both forms, native write, history and discard.
	var form := Editor.new(); root.add_child(form); form.setup("world_actions", "")
	check(form._document() == Store.normalized_document(document), "full form lost fields")
	var panel := form._objectives.get_child(0)
	check(panel.find_child("QuestWorldActionFields", true, false).visible, "world fields hidden")
	select(panel.find_child("WorldAction", true, false), "collect")
	select(panel.find_child("WorldActionTarget", true, false), "apple")
	check(form._document().objectives[0].worldTargetId == "apple", "full form selection lost")
	var workspace := Workspace.new(); root.add_child(workspace)
	workspace._current_kind = "quest"; workspace._current_id = "world_actions"; workspace._reset_quest_draft(document)
	var holder := VBoxContainer.new(); root.add_child(holder)
	workspace._add_quest_objective_progress(holder, 0, document.objectives[0])
	select(holder.find_child("WorldActionTarget", true, false), "apple")
	check(workspace._quest_draft.objectives[0].worldTargetId == "apple", "graph target selection lost")
	workspace._undo_action_draft()
	check(workspace._quest_draft.objectives[0].worldTargetId == "quest_crate", "graph Undo failed")
	workspace._redo_action_draft()
	check(workspace._quest_draft.objectives[0].worldTargetId == "apple", "graph Redo failed")
	var edited: Dictionary = workspace._quest_draft.duplicate(true)
	check(Store.write_document(edited) == OK and Store.document("world_actions").objectives[0].worldTargetId == "apple", "reopen lost target")
	workspace._reset_quest_draft(edited); workspace._push_quest_draft(document)
	workspace._request_navigation("quest", "world_actions", true); workspace._confirm_discard_navigation()
	check(workspace._quest_draft.objectives[0].worldTargetId == "apple", "discard lost saved value")
	# Capture a real native author form; optional output is outside the checkout.
	var capture := OS.get_environment("EMBER_QUEST_WORLD_CAPTURE")
	if not capture.is_empty():
		for window in root.find_children("*", "Window", true, false): window.hide()
		workspace.hide(); holder.hide()
		form.size = Vector2(720, 780)
		await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	state.persistence_enabled = false
	form.queue_free(); workspace.queue_free(); holder.queue_free(); bush.queue_free()
	stage.queue_free()
	for node in root.get_children():
		if node is Area3D: node.queue_free()
	await process_frame
	if errors.is_empty():
		print("QUEST WORLD ACTIONS PASS: adapters, filters, once-only, sequence, atomic save/load, both forms, Undo/Redo/reopen/discard")
		quit(0)
	else: quit(1)
