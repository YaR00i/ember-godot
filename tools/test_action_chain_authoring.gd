extends SceneTree
## Editor-first contract: one Undo action authors a canonical action document and
## a scene-owned trigger using the same EmberInteract/runtime schema.

const SOURCE_SCENE := "res://scenes/fan_town.tscn"
const TEMP_SCRIPT_ID := "ember_test_action_chain_authoring"
const TEMP_BIND_SCRIPT_ID := "ember_test_quest_binding_actions"
const TEMP_BIND_QUEST_ID := "ember_test_quest_binding_quest"
const TEMP_SHARED_SCRIPT_ID := "ember_test_shared_quest_actions"
const TEMP_ORPHAN_SCRIPT_ID := "ember_test_orphaned_quest_actions"
const Store = preload("res://addons/ember_import/ember_action_script_store.gd")
const QuestStore = preload("res://addons/ember_import/ember_quest_store.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var source_hash := FileAccess.get_sha256(SOURCE_SCENE)
	var old_document: Dictionary = Store.document(TEMP_SCRIPT_ID)
	var old_binding_document: Dictionary = Store.document(TEMP_BIND_SCRIPT_ID)
	var old_shared_document: Dictionary = Store.document(TEMP_SHARED_SCRIPT_ID)
	var old_orphan_document: Dictionary = Store.document(TEMP_ORPHAN_SCRIPT_ID)
	var old_binding_quest := QuestStore.snapshot(TEMP_BIND_QUEST_ID)
	Store.delete_document(TEMP_SCRIPT_ID)
	Store.delete_document(TEMP_BIND_SCRIPT_ID)
	Store.delete_document(TEMP_SHARED_SCRIPT_ID)
	Store.delete_document(TEMP_ORPHAN_SCRIPT_ID)
	QuestStore.restore_snapshot({"id": TEMP_BIND_QUEST_ID, "native": {}})
	var packed := ResourceLoader.load(SOURCE_SCENE, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) if packed else null
	if root == null:
		printerr("FAIL action-chain authoring: fan_town unavailable")
		_restore_fixture(old_document)
		_restore_binding_fixture(old_binding_document)
		_restore_document(TEMP_SHARED_SCRIPT_ID, old_shared_document)
		_restore_document(TEMP_ORPHAN_SCRIPT_ID, old_orphan_document)
		QuestStore.restore_snapshot(old_binding_quest)
		return 1
	var prop := root.get_node_or_null("Map/Props/ft_fountain") as EmberVoxelProp
	if prop == null or prop.get_node_or_null("Interact") != null:
		errors.append("clean fountain fixture unavailable")
	else:
		_run_history(errors, root, prop)
		_test_quest_event_binding(errors, root)
		_test_shared_quest_event_unbind(errors, root)
		_test_orphaned_quest_event_removal(errors, root)
	root.free()
	if FileAccess.get_sha256(SOURCE_SCENE) != source_hash:
		errors.append("authoring changed source fan_town.tscn")
	_restore_fixture(old_document)
	_restore_binding_fixture(old_binding_document)
	_restore_document(TEMP_SHARED_SCRIPT_ID, old_shared_document)
	_restore_document(TEMP_ORPHAN_SCRIPT_ID, old_orphan_document)
	QuestStore.restore_snapshot(old_binding_quest)
	if not errors.is_empty():
		printerr("FAIL action-chain authoring")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS action-chain authoring")
	print("  canonical action document + scene-owned Interact share one Undo action")
	print("  chain-only delete preserves Interact; Undo/Redo restores document + binding")
	print("  runtime queue resolves all authored steps")
	print("  Quest Flow binding compiles events into one Undoable scene + action change")
	print("  shared quest action chains use copy-on-write during event unbind")
	print("  orphaned quest writers can be removed from Quest Flow with Undo/Redo")
	print("  source scene stays unchanged and temporary script is cleaned")
	return 0


func _run_history(errors: Array[String], root: Node, prop: EmberVoxelProp) -> void:
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	if Store.validation_errors({
		"id": "bad id",
		"nameRu": "Broken",
		"steps": [{"type": "talk", "dialogueId": "missing_dialogue"}],
	}).size() < 2:
		errors.append("writer validation did not reject invalid id and missing reference")
	if Store.STEP_TYPES != ["talk", "give_item", "set_flag", "wait", "open_shop", "change_map", "start_battle", "run_script"]:
		errors.append("editor step palette does not cover the canonical eight action types")
	if Store.validation_errors({
		"id": "bad_map_order",
		"nameRu": "Broken map order",
		"steps": [
			{"type": "change_map", "targetMapId": "agent_sandbox_interior", "targetRegionId": "start"},
			{"type": "set_flag", "flag": "unreachable", "value": true},
		],
	}).is_empty():
		errors.append("writer accepted steps after terminal change_map")
	var document := {
		"id": TEMP_SCRIPT_ID,
		"nameRu": "Тестовая цепочка редактора",
		"steps": [
			{"type": "talk", "dialogueId": "sandbox_notice_talk"},
			{"type": "give_item", "itemId": "coin", "count": 2},
			{"type": "set_flag", "flag": "editor_chain_done", "value": true},
			{"type": "wait", "sec": 0.1},
			{"type": "open_shop", "shopId": "village_kiosk"},
			{"type": "change_map", "targetMapId": "agent_sandbox_interior", "targetRegionId": "start"},
		],
	}
	if not actions.save_chain(prop, document, root):
		errors.append("save_chain rejected a valid document")
		history.free()
		return
	var interact := prop.get_node_or_null("Interact") as EmberInteract
	if interact == null or interact.kind != "trigger" or interact.script_id != TEMP_SCRIPT_ID:
		errors.append("quick authoring did not create trigger bound to chain")
	elif interact.owner != root or interact.get_node_or_null("Shape") == null:
		errors.append("quick trigger/shape is not scene-owned")
	var saved: Dictionary = Store.document(TEMP_SCRIPT_ID)
	if str(saved.get("nameRu", "")) != "Тестовая цепочка редактора":
		errors.append("canonical action document was not written")
	var queue := EmberActionScript.queue_for(TEMP_SCRIPT_ID)
	var queued_steps: Array = queue.get("steps", [])
	if not bool(queue.get("ok", false)) or queued_steps.size() != 6:
		errors.append("runtime could not resolve authored action-list")
	elif str(queued_steps[4].get("type", "")) != "open_shop" or str(queued_steps[5].get("type", "")) != "change_map":
		errors.append("runtime dropped shop/map actions authored by Inspector")
	history.undo()
	if prop.get_node_or_null("Interact") != null or Store.exists(TEMP_SCRIPT_ID):
		errors.append("undo did not remove both trigger and newly created action document")
	history.redo()
	interact = prop.get_node_or_null("Interact") as EmberInteract
	if interact == null or not Store.exists(TEMP_SCRIPT_ID):
		errors.append("redo did not restore both trigger and action document")
	elif not actions.remove_chain(prop, root):
		errors.append("remove_chain rejected an existing authored chain")
	else:
		var remaining := prop.get_node_or_null("Interact") as EmberInteract
		if remaining == null:
			errors.append("remove_chain deleted the whole Interact")
		elif not remaining.script_id.is_empty() or remaining.kind != "trigger":
			errors.append("remove_chain changed fields beyond the action binding")
		if Store.exists(TEMP_SCRIPT_ID):
			errors.append("remove_chain left its canonical action document behind")
		history.undo()
		remaining = prop.get_node_or_null("Interact") as EmberInteract
		if remaining == null or remaining.script_id != TEMP_SCRIPT_ID or not Store.exists(TEMP_SCRIPT_ID):
			errors.append("undo did not restore removed chain + binding")
		history.redo()
		remaining = prop.get_node_or_null("Interact") as EmberInteract
		if remaining == null or not remaining.script_id.is_empty() or Store.exists(TEMP_SCRIPT_ID):
			errors.append("redo did not remove chain while preserving Interact")
	history.clear_history(false)
	history.free()


func _restore_fixture(old_document: Dictionary) -> void:
	if old_document.is_empty():
		Store.delete_document(TEMP_SCRIPT_ID)
	else:
		Store.write_document(old_document)


func _test_quest_event_binding(errors: Array[String], root: Node) -> void:
	var prop := EmberVoxelProp.new()
	prop.name = "QuestBindingFixture"
	prop.placement_id = "ember_test_quest_binding"
	root.add_child(prop)
	prop.owner = root
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var quest_draft := {
		"id": TEMP_BIND_QUEST_ID,
		"statusFlagId": "ember_test_quest_binding_status",
		"titleRu": "Несохранённое тестовое задание",
		"summaryRu": "Проверка атомарного bind из локального Quest Flow draft.",
		"showWhenAvailable": true,
		"objectives": [{
			"id": "draft_goal",
			"textRu": "Новая цель из черновика",
			"flagId": "ember_test_quest_binding_goal",
			"optional": false,
			"requiresObjectiveIds": [],
		}],
	}
	var start_token := QuestStore.event_token(TEMP_BIND_QUEST_ID, "start")
	if not actions.bind_quest_event(prop, start_token, root, quest_draft):
		errors.append("Quest Flow rejected a valid selected voxel/event binding")
	else:
		var interact := prop.get_node_or_null("Interact") as EmberInteract
		var document := Store.document(TEMP_BIND_SCRIPT_ID)
		var steps: Array = document.get("steps", [])
		if (
			interact == null
			or interact.kind != "quest_marker"
			or interact.quest_id != TEMP_BIND_QUEST_ID
			or interact.script_id != TEMP_BIND_SCRIPT_ID
		):
			errors.append("first Quest Flow binding did not create a bound quest marker")
		elif (
			steps.size() != 1
			or str((steps[0] as Dictionary).get("flag", "")) != "ember_test_quest_binding_status"
			or (steps[0] as Dictionary).get("value") != "active"
		):
			errors.append("quest start binding did not compile to canonical set_flag")
		elif QuestStore.document(TEMP_BIND_QUEST_ID).is_empty():
			errors.append("guided bind did not persist the current unsaved quest draft")
		history.undo()
		if (
			prop.get_node_or_null("Interact") != null
			or Store.exists(TEMP_BIND_SCRIPT_ID)
			or not QuestStore.document(TEMP_BIND_QUEST_ID).is_empty()
		):
			errors.append("Quest Flow binding Undo did not restore scene, action and quest Resources")
		history.redo()
		interact = prop.get_node_or_null("Interact") as EmberInteract
		if interact == null or not Store.exists(TEMP_BIND_SCRIPT_ID):
			errors.append("Quest Flow binding Redo did not restore both scene and Resource")
		else:
			var objective_token := QuestStore.event_token(
				TEMP_BIND_QUEST_ID, "objective", "draft_goal"
			)
			if not actions.bind_quest_event(prop, objective_token, root, quest_draft):
				errors.append("Quest Flow rejected a second objective binding")
			else:
				document = Store.document(TEMP_BIND_SCRIPT_ID)
				steps = document.get("steps", [])
				if steps.size() != 2 or str((steps[1] as Dictionary).get("flag", "")) != "ember_test_quest_binding_goal":
					errors.append("objective binding did not append to the object's canonical chain")
				history.undo()
				if (Store.document(TEMP_BIND_SCRIPT_ID).get("steps", []) as Array).size() != 1:
					errors.append("objective binding Undo did not restore the previous chain")
				history.redo()
				if not actions.bind_quest_event(prop, objective_token, root, quest_draft):
					errors.append("duplicate objective binding was rejected instead of treated idempotently")
				elif (Store.document(TEMP_BIND_SCRIPT_ID).get("steps", []) as Array).size() != 2:
					errors.append("duplicate objective binding added a second identical set_flag")
				else:
					var unbind_result := actions.unbind_quest_event(prop, {
						"documentKind": "action",
						"documentId": TEMP_BIND_SCRIPT_ID,
						"writerIndex": 1,
						"flag": "ember_test_quest_binding_goal",
						"value": true,
					}, root)
					if not bool(unbind_result.get("ok", false)):
						errors.append("Quest Flow rejected a valid objective unbind")
					elif (Store.document(TEMP_BIND_SCRIPT_ID).get("steps", []) as Array).size() != 1:
						errors.append("quest event unbind removed more than its exact set_flag step")
					else:
						history.undo()
						if (Store.document(TEMP_BIND_SCRIPT_ID).get("steps", []) as Array).size() != 2:
							errors.append("quest event unbind Undo did not restore the removed step")
						history.redo()
						if (Store.document(TEMP_BIND_SCRIPT_ID).get("steps", []) as Array).size() != 1:
							errors.append("quest event unbind Redo did not remove the exact step again")
	history.clear_history(false)
	history.free()
	root.remove_child(prop)
	prop.free()
	Store.delete_document(TEMP_BIND_SCRIPT_ID)
	QuestStore.restore_snapshot({"id": TEMP_BIND_QUEST_ID, "native": {}})


func _restore_binding_fixture(old_document: Dictionary) -> void:
	_restore_document(TEMP_BIND_SCRIPT_ID, old_document)


func _restore_document(document_id: String, old_document: Dictionary) -> void:
	if old_document.is_empty():
		Store.delete_document(document_id)
	else:
		Store.write_document(old_document)


func _test_shared_quest_event_unbind(errors: Array[String], root: Node) -> void:
	Store.write_document({
		"id": TEMP_SHARED_SCRIPT_ID,
		"nameRu": "Общая тестовая цепочка",
		"steps": [
			{"type": "set_flag", "flag": "ember_shared_status", "value": "active"},
			{"type": "set_flag", "flag": "ember_shared_goal", "value": true},
		],
	})
	var first := EmberVoxelProp.new()
	first.name = "SharedQuestFirst"
	first.placement_id = "ember_test_shared_first"
	root.add_child(first)
	var first_interact := EmberInteract.new()
	first_interact.name = "Interact"
	first_interact.kind = "quest_marker"
	first_interact.quest_id = TEMP_BIND_QUEST_ID
	first_interact.script_id = TEMP_SHARED_SCRIPT_ID
	first.add_child(first_interact)
	var second := EmberVoxelProp.new()
	second.name = "SharedQuestSecond"
	second.placement_id = "ember_test_shared_second"
	root.add_child(second)
	var second_interact := EmberInteract.new()
	second_interact.name = "Interact"
	second_interact.kind = "quest_marker"
	second_interact.quest_id = TEMP_BIND_QUEST_ID
	second_interact.script_id = TEMP_SHARED_SCRIPT_ID
	second.add_child(second_interact)
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var result := actions.unbind_quest_event(first, {
		"documentKind": "action",
		"documentId": TEMP_SHARED_SCRIPT_ID,
		"writerIndex": 1,
		"flag": "ember_shared_goal",
		"value": true,
	}, root)
	var clone_id := first_interact.script_id
	if not bool(result.get("ok", false)):
		errors.append("shared quest-event unbind was rejected")
	elif clone_id == TEMP_SHARED_SCRIPT_ID or clone_id.is_empty():
		errors.append("shared quest-event unbind did not create an object-owned copy")
	elif second_interact.script_id != TEMP_SHARED_SCRIPT_ID:
		errors.append("shared quest-event unbind changed the other scene consumer")
	elif (Store.document(TEMP_SHARED_SCRIPT_ID).get("steps", []) as Array).size() != 2:
		errors.append("copy-on-write mutated the original shared action chain")
	elif (Store.document(clone_id).get("steps", []) as Array).size() != 1:
		errors.append("copy-on-write clone did not remove only the selected event")
	else:
		history.undo()
		if first_interact.script_id != TEMP_SHARED_SCRIPT_ID or Store.exists(clone_id):
			errors.append("shared quest-event Undo did not restore binding and remove its clone")
		history.redo()
		if first_interact.script_id != clone_id or not Store.exists(clone_id):
			errors.append("shared quest-event Redo did not restore the private clone")
	history.clear_history(false)
	history.free()
	if not clone_id.is_empty() and clone_id != TEMP_SHARED_SCRIPT_ID:
		Store.delete_document(clone_id)
	root.remove_child(first)
	root.remove_child(second)
	first.free()
	second.free()
	Store.delete_document(TEMP_SHARED_SCRIPT_ID)


func _test_orphaned_quest_event_removal(errors: Array[String], root: Node) -> void:
	Store.write_document({
		"id": TEMP_ORPHAN_SCRIPT_ID,
		"nameRu": "Осиротевшая тестовая цепочка",
		"steps": [
			{"type": "set_flag", "flag": "ember_orphan_goal_a", "value": true},
			{"type": "set_flag", "flag": "ember_orphan_goal_b", "value": true},
		],
	})
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var active_consumer := EmberInteract.new()
	active_consumer.kind = "trigger"
	active_consumer.script_id = TEMP_ORPHAN_SCRIPT_ID
	root.add_child(active_consumer)
	var blocked_result := actions.remove_unbound_quest_event({
		"documentKind": "action",
		"documentId": TEMP_ORPHAN_SCRIPT_ID,
		"writerIndex": 0,
		"flag": "ember_orphan_goal_a",
		"value": true,
	}, root)
	if bool(blocked_result.get("ok", false)):
		errors.append("orphan cleanup mutated a chain still referenced by the open scene")
	root.remove_child(active_consumer)
	active_consumer.free()
	var first_result := actions.remove_unbound_quest_event({
		"documentKind": "action",
		"documentId": TEMP_ORPHAN_SCRIPT_ID,
		"writerIndex": 0,
		"flag": "ember_orphan_goal_a",
		"value": true,
	}, root)
	var remaining: Array = Store.document(TEMP_ORPHAN_SCRIPT_ID).get("steps", [])
	if not bool(first_result.get("ok", false)):
		errors.append("orphaned quest writer removal was rejected")
	elif remaining.size() != 1 or str((remaining[0] as Dictionary).get("flag", "")) != "ember_orphan_goal_b":
		errors.append("orphaned quest writer removal changed more than the selected step")
	else:
		history.undo()
		if (Store.document(TEMP_ORPHAN_SCRIPT_ID).get("steps", []) as Array).size() != 2:
			errors.append("orphaned quest writer Undo did not restore the chain")
		history.redo()
		if (Store.document(TEMP_ORPHAN_SCRIPT_ID).get("steps", []) as Array).size() != 1:
			errors.append("orphaned quest writer Redo did not remove the step")
		var final_result := actions.remove_unbound_quest_event({
			"documentKind": "action",
			"documentId": TEMP_ORPHAN_SCRIPT_ID,
			"writerIndex": 0,
			"flag": "ember_orphan_goal_b",
			"value": true,
		}, root)
		if not bool(final_result.get("ok", false)) or Store.exists(TEMP_ORPHAN_SCRIPT_ID):
			errors.append("removing the final orphaned writer did not delete the empty chain")
		else:
			history.undo()
			if not Store.exists(TEMP_ORPHAN_SCRIPT_ID):
				errors.append("empty orphaned chain deletion is not reversible")
	history.clear_history(false)
	history.free()
	Store.delete_document(TEMP_ORPHAN_SCRIPT_ID)
