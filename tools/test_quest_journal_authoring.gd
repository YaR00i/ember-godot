extends SceneTree
## Quest description/editor/journal vertical slice over the existing flag owner.

const Catalog = preload("res://scripts/ember_quest_catalog.gd")
const Store = preload("res://addons/ember_import/ember_quest_store.gd")
const QuestEditor = preload("res://addons/ember_import/ember_quest_editor.gd")
const ActionEditor = preload("res://addons/ember_import/ember_action_chain_editor.gd")
const Journal = preload("res://scripts/ember_quest_journal_ui.gd")
const InspectorPanel = preload("res://addons/ember_import/ember_object_inspector_panel.gd")
const SOURCE_SCENE := "res://scenes/agent_sandbox.tscn"
const TEMP_ID := "ember_test_quest_authoring"


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var source_hash := FileAccess.get_sha256(SOURCE_SCENE)
	var old_snapshot := Store.snapshot(TEMP_ID)
	Catalog.delete_native(TEMP_ID)
	_test_projection(errors)
	_test_sequence_contract(errors)
	_test_combat_counter_contract(errors)
	_test_editor_and_journal(errors)
	_test_inspector_undo(errors)
	_test_graph_document_undo(errors)
	if FileAccess.get_sha256(SOURCE_SCENE) != source_hash:
		errors.append("quest authoring changed source agent_sandbox.tscn")
	Store.restore_snapshot(old_snapshot)
	if not errors.is_empty():
		printerr("FAIL quest journal authoring")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS quest journal authoring")
	print("  Resource stores description/objectives while typed flags own progress")
	print("  journal projects available/active/done and objective completion")
	print("  quest-marker editor save + binding use one Undo/Redo action")
	print("  standalone quest graph save uses the same Resource Undo owner")
	print("  objective dependencies lock early writes and unlock in sequence")
	print("  source scene stays unchanged")
	return 0


func _test_combat_counter_contract(errors: Array[String]) -> void:
	var fixture := {
		"id": TEMP_ID,
		"statusFlagId": "%s_status" % TEMP_ID,
		"titleRu": "Боевой счётчик",
		"showWhenAvailable": true,
		"objectives": [
			{
				"id": "first_win",
				"textRu": "Победить первую встречу",
				"flagId": "%s_first_win" % TEMP_ID,
				"progressMode": "counter",
				"counterEventId": "combat_victories",
				"requiredCount": 1,
				"optional": false,
				"requiresObjectiveIds": [],
			},
			{
				"id": "second_win",
				"textRu": "Победить следующую встречу",
				"flagId": "%s_second_win" % TEMP_ID,
				"progressMode": "counter",
				"counterEventId": "combat_victories",
				"requiredCount": 1,
				"optional": false,
				"requiresObjectiveIds": ["first_win"],
			},
		],
	}
	if Store.write_document(fixture) != OK:
		errors.append("could not write combat counter quest fixture")
		return
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.restore_enabled = false
	state.reset_new_game()
	state.apply_combat_counters({"combat_victories": 1}, false)
	if int(state.flags.get("%s_first_win" % TEMP_ID, 0)) != 1:
		errors.append("available combat objective did not receive its event")
	if state.flags.has("%s_second_win" % TEMP_ID):
		errors.append("locked sequential combat objective accumulated progress early")
	state.apply_combat_counters({"combat_victories": 1}, false)
	if int(state.flags.get("%s_second_win" % TEMP_ID, 0)) != 1:
		errors.append("combat objective did not receive events after its prerequisite unlocked")
	var done := Catalog.projection(fixture, state.flags)
	if str(done.get("status", "")) != "done":
		errors.append("sequential combat counter objectives did not complete the quest")
	var normalized := Store.normalized_document(fixture)
	var saved_objective: Dictionary = (normalized.get("objectives", []) as Array)[0]
	if (
		str(saved_objective.get("progressMode", "")) != "counter"
		or str(saved_objective.get("counterEventId", "")) != "combat_victories"
		or int(saved_objective.get("requiredCount", 0)) != 1
	):
		errors.append("quest Resource normalization lost combat counter authoring")
	state.free()
	Catalog.delete_native(TEMP_ID)


func _test_projection(errors: Array[String]) -> void:
	var demo := Catalog.definition("sandbox_notice_quest")
	if str(demo.get("titleRu", "")) != "Записка у ворот":
		errors.append("sandbox quest Resource is unavailable")
	var available := Catalog.projection(demo, {})
	var active := Catalog.projection(demo, {"sandbox_notice_status": "active"})
	var completed_flags := {}
	for raw_objective in demo.get("objectives", []):
		if typeof(raw_objective) == TYPE_DICTIONARY:
			completed_flags[str((raw_objective as Dictionary).get("flagId", ""))] = true
	var done := Catalog.projection(demo, completed_flags)
	if str(available.get("status", "")) != "available":
		errors.append("missing status flag did not project available")
	if str(active.get("status", "")) != "active":
		errors.append("typed active status did not project active")
	if (
		str(done.get("status", "")) != "done"
		or int(done.get("completed", 0)) != int(done.get("required", -1))
	):
		errors.append("true quest/objective flag did not project completion")
	if Store.validation_errors({"id": "bad id", "titleRu": "", "objectives": []}).size() < 3:
		errors.append("quest writer accepted invalid identity/title/objectives")
	var references := Store.flag_reference_entries()
	var reference_ids: Array[String] = []
	for reference in references:
		reference_ids.append(str(reference.get("id", "")))
	if "sandbox_notice_status" not in reference_ids or "sandbox_notice_read" not in reference_ids:
		errors.append("quest flag reference library lost status/objective entries")
	var events := Store.event_reference_entries()
	var start := Store.action_for_event(Store.event_token("sandbox_notice_quest", "start"))
	var objective := Store.action_for_event(
		Store.event_token("sandbox_notice_quest", "objective", "read_notice")
	)
	var complete := Store.action_for_event(Store.event_token("sandbox_notice_quest", "complete"))
	if events.size() < 3:
		errors.append("quest event library lost start/objective/complete presets")
	if start.get("flag", "") != "sandbox_notice_status" or start.get("value") != "active":
		errors.append("start preset did not compile to the canonical active status flag")
	if objective.get("flag", "") != "sandbox_notice_read" or objective.get("value") != true:
		errors.append("objective preset did not compile to its canonical completion flag")
	if complete.get("flag", "") != "sandbox_notice_status" or complete.get("value") != "done":
		errors.append("complete preset did not compile to the canonical done status flag")


func _test_sequence_contract(errors: Array[String]) -> void:
	var fixture := {
		"id": TEMP_ID,
		"statusFlagId": "%s_status" % TEMP_ID,
		"titleRu": "Последовательное тестовое задание",
		"summaryRu": "",
		"showWhenAvailable": true,
		"objectives": [
			{
				"id": "first",
				"textRu": "Первая цель",
				"flagId": "%s_first" % TEMP_ID,
				"optional": false,
				"requiresObjectiveIds": [],
			},
			{
				"id": "second",
				"textRu": "Вторая цель",
				"flagId": "%s_second" % TEMP_ID,
				"optional": false,
				"requiresObjectiveIds": ["first"],
			},
		],
	}
	if Store.write_document(fixture) != OK:
		errors.append("could not write sequential quest fixture")
		return
	var initial := Catalog.projection(Store.document(TEMP_ID), {})
	var initial_objectives: Array = initial.get("objectives", [])
	if (
		initial_objectives.size() != 2
		or not bool((initial_objectives[0] as Dictionary).get("available", false))
		or not bool((initial_objectives[1] as Dictionary).get("locked", false))
	):
		errors.append("quest projection did not expose current + locked objectives")
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.restore_enabled = false
	state.reset_new_game()
	var early := state.apply_authored_flag("%s_second" % TEMP_ID, true, false)
	if bool(early.get("allowed", true)) or state.flags.has("%s_second" % TEMP_ID):
		errors.append("authored event completed a locked objective early")
	var ui := EmberInteractionUi.new()
	ui.economy_state = state
	root.add_child(ui)
	if ui.get("_body") == null:
		ui.call("_ready")
	ui._script_queue = [{
		"type": "set_flag",
		"flag": "%s_second" % TEMP_ID,
		"value": true,
	}]
	ui._script_active = true
	ui.call("_advance_script_queue")
	if (
		str(ui.view_state().get("mode", "")) != EmberInteractionUi.MODE_NOTICE
		or not str(ui.view_state().get("body", "")).contains("Первая цель")
	):
		errors.append("blocked action event did not show its prerequisite notice: %s" % [ui.view_state()])
	ui.close()
	state.apply_authored_flag("%s_first" % TEMP_ID, true, false)
	var unlocked := Catalog.projection(Store.document(TEMP_ID), state.flags)
	var unlocked_objectives: Array = unlocked.get("objectives", [])
	if not bool((unlocked_objectives[1] as Dictionary).get("available", false)):
		errors.append("second objective did not unlock after its prerequisite")
	var accepted := state.apply_authored_flag("%s_second" % TEMP_ID, true, false)
	if not bool(accepted.get("allowed", false)) or state.flags.get("%s_second" % TEMP_ID) != true:
		errors.append("unlocked objective event was rejected")
	ui.free()
	state.free()
	var cycle := fixture.duplicate(true)
	(cycle.objectives[0] as Dictionary)["requiresObjectiveIds"] = ["second"]
	var cycle_errors := Store.validation_errors(cycle)
	if not "Последовательность целей содержит цикл." in cycle_errors:
		errors.append("quest validation accepted a dependency cycle")
	Catalog.delete_native(TEMP_ID)


func _test_editor_and_journal(errors: Array[String]) -> void:
	var editor := QuestEditor.new() as EmberQuestEditor
	root.add_child(editor)
	editor.setup("sandbox_notice_quest", "sandbox_notice_quest", "sandbox_notice_status")
	if editor.find_child("QuestTitle", true, false) == null:
		errors.append("quest editor has no title field")
	if editor.find_child("AddQuestObjective", true, false) == null:
		errors.append("quest editor has no objective authoring action")
	if (
		editor.find_child("ObjectiveProgressMode", true, false) == null
		or editor.find_child("ObjectiveCombatCounter", true, false) == null
		or editor.find_child("ObjectiveRequiredCount", true, false) == null
	):
		errors.append("quest editor has no guided combat counter controls")
	var document: Dictionary = editor.call("_document")
	if (
		str(document.get("id", "")) != "sandbox_notice_quest"
		or str(document.get("statusFlagId", "")) != "sandbox_notice_status"
		or (document.get("objectives", []) as Array).size() != (Catalog.definition("sandbox_notice_quest").get("objectives", []) as Array).size()
	):
		errors.append("quest editor did not preserve canonical definition")
	editor.free()
	var action_editor := ActionEditor.new() as EmberActionChainEditor
	root.add_child(action_editor)
	action_editor.setup("", "quest_event_chain", {
		"id": "quest_event_chain",
		"nameRu": "Quest event fixture",
		"steps": [{"type": "wait", "sec": 0.0}],
	})
	if action_editor.find_child("AddQuestEventStep", true, false) == null:
		errors.append("object/action editor has no guided quest-event action")
	action_editor.call(
		"_choose_quest_event", Store.event_token("sandbox_notice_quest", "start")
	)
	var action_document: Dictionary = action_editor.call("_document")
	var action_steps: Array = action_document.get("steps", [])
	var authored_event: Dictionary = action_steps[-1] if not action_steps.is_empty() else {}
	if authored_event.get("flag", "") != "sandbox_notice_status" or authored_event.get("value") != "active":
		errors.append("guided action editor did not author the quest start as set_flag")
	action_editor.free()

	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.restore_enabled = false
	state.reset_new_game()
	var journal := Journal.new() as EmberQuestJournalUi
	journal.progress_state = state
	root.add_child(journal)
	journal.open()
	var card := journal.find_child("Quest_sandbox_notice_quest", true, false)
	if card == null:
		errors.append("available sandbox quest is absent from journal")
	else:
		var title := card.find_child("QuestJournalTitle", true, false) as Label
		if title == null or "Записка у ворот" not in title.text:
			errors.append("journal card lost the authored title")
	state.set_flag("sandbox_notice_status", "active", false)
	state.set_flag("sandbox_notice_read", true, false)
	journal.open()
	card = journal.find_child("Quest_sandbox_notice_quest", true, false)
	var objective := card.find_child("QuestObjective_read_notice", true, false) as Label if card != null else null
	if objective == null or not objective.text.begins_with("✓"):
		errors.append("journal did not refresh objective completion from flags")
	var source := card.find_child("QuestProgressSource", true, false) as Label if card != null else null
	if source == null or "sandbox_notice_read = true" not in source.text:
		errors.append("journal does not explain which saved flag completed the quest")
	var reset := card.find_child("ResetQuestProgress_sandbox_notice_quest", true, false) as Button if card != null else null
	if reset == null:
		errors.append("debug journal has no scoped quest reset")
	else:
		reset.pressed.emit()
		if state.flags.has("sandbox_notice_read") or state.flags.has("sandbox_notice_status"):
			errors.append("scoped quest reset did not clear its status/objective flags")
	var player := EmberPlayer.new()
	player.quest_journal_ui = journal
	if not bool(player.call("_ui_blocks_movement")):
		errors.append("open journal does not block explore movement")
	journal.free()
	state.free()
	player.free()


func _test_inspector_undo(errors: Array[String]) -> void:
	var packed := ResourceLoader.load(SOURCE_SCENE, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var scene := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) if packed != null else null
	if scene == null:
		errors.append("agent_sandbox fixture is unavailable")
		return
	var prop := scene.get_node_or_null("Map/Props/sbx_quest_sign") as EmberVoxelProp
	var interact := prop.get_node_or_null("Interact") as EmberInteract if prop != null else null
	if interact == null:
		errors.append("sandbox quest marker fixture is unavailable")
		scene.free()
		return
	var panel := InspectorPanel.new() as EmberObjectInspectorPanel
	panel.setup(prop, EmberObjectInspectorModel.snapshot(prop))
	if panel.find_child("EditQuestButton", true, false) == null:
		errors.append("quest marker Inspector has no quest authoring button")
	if panel.find_child("EditActionChainButton", true, false) == null:
		errors.append("quest marker Inspector has no separate action-chain button")
	var bind_event := panel.find_child("BindQuestEventButton", true, false) as Button
	if bind_event == null:
		errors.append("quest marker Inspector has no direct quest-event shortcut")
	else:
		bind_event.pressed.emit()
		if panel.find_child("ActionChainEditor", true, false) == null:
			errors.append("quest-event shortcut did not create the marker action-chain editor")
	panel.free()
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var previous_quest_id := interact.quest_id
	var previous_script_id := interact.script_id
	var document := {
		"id": TEMP_ID,
		"statusFlagId": "%s_status" % TEMP_ID,
		"titleRu": "Тестовое задание",
		"summaryRu": "Проверка общего флага.",
		"showWhenAvailable": false,
		"objectives": [{
			"id": "finish",
			"textRu": "Завершить проверку",
			"flagId": "%s_done" % TEMP_ID,
			"optional": false,
		}],
	}
	if not actions.save_quest_for_interact(interact, document, scene):
		errors.append("quest save rejected a valid marker/document")
	elif (
		Catalog.definition(TEMP_ID).is_empty()
		or Catalog.definition_for_status_flag("%s_status" % TEMP_ID).is_empty()
		or interact.quest_id != TEMP_ID
		or interact.script_id != previous_script_id
	):
		errors.append("quest save did not write Resource and bind marker atomically: definition=%s status=%s quest=%s script=%s" % [
			Catalog.definition(TEMP_ID),
			Catalog.definition_for_status_flag("%s_status" % TEMP_ID),
			interact.quest_id,
			interact.script_id,
		])
	else:
		history.undo()
		if (
			not Catalog.definition(TEMP_ID).is_empty()
			or not Catalog.definition_for_status_flag("%s_status" % TEMP_ID).is_empty()
			or interact.quest_id != previous_quest_id
			or interact.script_id != previous_script_id
		):
			errors.append("quest Undo did not restore Resource + marker binding")
		history.redo()
		if Catalog.definition(TEMP_ID).is_empty() or interact.quest_id != TEMP_ID or interact.script_id != previous_script_id:
			errors.append("quest Redo did not restore Resource + marker binding")
		var action_id := "%s_actions" % TEMP_ID
		# Simulate an existing display-only marker: choosing a guided quest event
		# must bind it to the same quest when the chain is saved.
		interact.quest_id = ""
		interact.script_id = ""
		var chain := {
			"id": action_id,
			"nameRu": "Цель с объекта",
			"steps": [Store.action_for_event(Store.event_token(TEMP_ID, "objective", "finish"))],
			"_editorQuestId": TEMP_ID,
		}
		if not actions.save_chain(prop, chain, scene):
			errors.append("quest marker rejected its separate action chain")
		elif interact.quest_id != TEMP_ID or interact.script_id != action_id:
			errors.append("quest marker action chain overwrote its quest binding")
		elif Store.document(action_id).has("_editorQuestId"):
			errors.append("editor-only quest binding leaked into the action Resource")
		else:
			history.undo()
			if not interact.quest_id.is_empty() or not interact.script_id.is_empty():
				errors.append("quest marker chain Undo did not restore the unbound marker")
			history.redo()
			if interact.quest_id != TEMP_ID or interact.script_id != action_id:
				errors.append("quest marker chain Redo did not restore automatic quest binding")
			history.undo()
			interact.quest_id = TEMP_ID
		history.undo()
	history.clear_history(false)
	history.free()
	scene.free()


func _test_graph_document_undo(errors: Array[String]) -> void:
	Catalog.delete_native(TEMP_ID)
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	root.add_child(context)
	var document := {
		"id": TEMP_ID,
		"statusFlagId": "%s_status" % TEMP_ID,
		"titleRu": "Граф задания",
		"summaryRu": "Сохраняется без привязки к marker-ноде.",
		"showWhenAvailable": true,
		"objectives": [{
			"id": "main",
			"textRu": "Проверить сохранение",
			"flagId": "%s_done" % TEMP_ID,
			"optional": false,
		}],
	}
	if not actions.save_quest_document(document, context):
		errors.append("standalone quest graph save rejected a valid Resource")
	elif str(Catalog.definition(TEMP_ID).get("titleRu", "")) != "Граф задания":
		errors.append("standalone quest graph save did not write the Resource")
	else:
		history.undo()
		if not Catalog.definition(TEMP_ID).is_empty():
			errors.append("standalone quest graph Undo did not remove the Resource")
		history.redo()
		if str(Catalog.definition(TEMP_ID).get("titleRu", "")) != "Граф задания":
			errors.append("standalone quest graph Redo did not restore the Resource")
		history.undo()
	history.clear_history(false)
	history.free()
	context.free()
