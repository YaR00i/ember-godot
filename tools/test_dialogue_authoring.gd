extends SceneTree
## Editor-first dialogue contract: the Inspector card UI projects the existing
## dialogue graph, writes its canonical owner through Undo/Redo, and runtime
## resolves the same native-or-legacy document.

const TEMP_DIALOGUE_ID := "ember_test_dialogue_authoring"
const Store = preload("res://addons/ember_import/ember_dialogue_store.gd")
const DialogueEditor = preload("res://addons/ember_import/ember_dialogue_editor.gd")
const ActionChainEditor = preload("res://addons/ember_import/ember_action_chain_editor.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var old_document := Store.document(TEMP_DIALOGUE_ID)
	Store.delete_document(TEMP_DIALOGUE_ID)
	_test_projection(errors)
	var document := _test_document()
	_test_roundtrip_and_history(errors, document)
	_test_editor_bridge(errors, document)
	_restore_fixture(old_document)
	if not errors.is_empty():
		printerr("FAIL dialogue authoring")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS dialogue authoring")
	print("  existing linear/choice scenes project into lossless cards")
	print("  card compiler + runtime preserve converging choice and typed flag")
	print("  one Undo/Redo action owns the canonical dialogue document write")
	print("  action-chain talk step opens the dialogue editor and adopts its ID")
	return 0


func _test_projection(errors: Array[String]) -> void:
	var guard := Store.projection(Store.document("sandbox_guard_talk"))
	var guard_cards: Array = guard.get("cards", [])
	if not bool(guard.get("ok", false)) or guard_cards.size() != 3:
		errors.append("three-line sandbox dialogue did not project to three cards")
	var branch := Store.projection(Store.document("sandbox_branch"))
	var branch_cards: Array = branch.get("cards", [])
	if not bool(branch.get("ok", false)) or branch_cards.size() != 1:
		errors.append("simple sandbox choice did not project to one card")
	elif (branch_cards[0] as Dictionary).get("options", []).size() != 2:
		errors.append("choice projection lost an option")
	var complex := Store.projection(Store.document("hu_tao_clear_demo"))
	if bool(complex.get("ok", false)):
		errors.append("complex staged scene was not protected from the simple editor")
	var blocked := DialogueEditor.new() as EmberDialogueEditor
	blocked.setup("hu_tao_clear_demo", "unused")
	if blocked.find_child("DialogueUnsupported", true, false) == null:
		errors.append("unsupported dialogue UI did not explain its read-only state")
	if blocked.find_child("SaveDialogue", true, false) != null:
		errors.append("unsupported dialogue UI still exposed a destructive save button")
	blocked.free()


func _test_document() -> Dictionary:
	var cards: Array[Dictionary] = [
		{
			"kind": "line",
			"speaker": "guide",
			"portraitKey": "neutral",
			"nameRu": "Проводник",
			"textRu": "Сначала выбери ответ.",
		},
		{
			"kind": "choice",
			"promptRu": "Куда пойдём?",
			"options": [
				{
					"labelRu": "К реке",
					"speaker": "guide",
					"portraitKey": "happy",
					"nameRu": "Проводник",
					"textRu": "Тогда берём лодку.",
					"flag": "route_name",
					"value": "river",
				},
				{
					"labelRu": "В лес",
					"speaker": "guide",
					"portraitKey": "neutral",
					"nameRu": "Проводник",
					"textRu": "Тогда ищем тропу.",
					"flag": "route_name",
					"value": "forest",
				},
			],
		},
		{
			"kind": "line",
			"speaker": "hero",
			"portraitKey": "neutral",
			"nameRu": "Герой",
			"textRu": "Решено.",
		},
	]
	return Store.document_from_cards({
		"id": TEMP_DIALOGUE_ID,
		"nameRu": "Тест карточек",
		"use": "talk",
	}, cards)


func _test_roundtrip_and_history(errors: Array[String], document: Dictionary) -> void:
	var validation := Store.validation_errors(document)
	if not validation.is_empty():
		errors.append("compiled dialogue failed validation: %s" % "; ".join(validation))
		return
	var projected := Store.projection(document)
	if not bool(projected.get("ok", false)) or projected.get("cards", []).size() != 3:
		errors.append("compiled dialogue could not be projected back to the same cards")
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	if not actions.save_dialogue(document, context):
		errors.append("save_dialogue rejected a valid card document")
	else:
		var saved := Store.document(TEMP_DIALOGUE_ID)
		if str(saved.get("nameRu", "")) != "Тест карточек":
			errors.append("canonical dialogue document was not written")
		_test_runtime(errors, saved)
		history.undo()
		if Store.exists(TEMP_DIALOGUE_ID):
			errors.append("undo did not remove a newly authored dialogue")
		history.redo()
		if not Store.exists(TEMP_DIALOGUE_ID):
			errors.append("redo did not restore the authored dialogue")
	history.clear_history(false)
	history.free()
	context.free()


func _test_runtime(errors: Array[String], document: Dictionary) -> void:
	var session := EmberDialogueSession.new()
	if not session.start(document) or session.current_text() != "Сначала выбери ответ.":
		errors.append("runtime did not start the authored first line")
		return
	session.advance()
	if session.current_kind() != "choice" or session.choice_labels() != ["К реке", "В лес"]:
		errors.append("runtime did not expose the authored choice")
		return
	session.choose(1)
	if session.current_text() != "Тогда ищем тропу." or session.flags().get("route_name") != "forest":
		errors.append("runtime lost the selected reply or typed choice flag")
	session.advance()
	if session.current_text() != "Решено.":
		errors.append("choice branches did not converge into the next card")
	session.advance()
	if not session.is_finished():
		errors.append("authored dialogue did not reach end")


func _test_editor_bridge(errors: Array[String], document: Dictionary) -> void:
	var chain := ActionChainEditor.new() as EmberActionChainEditor
	root.add_child(chain)
	chain.setup("", "test_chain")
	chain.call("_add_step", {"type": "talk", "dialogueId": "sandbox_branch"})
	var edit := chain.find_child("EditDialogue", true, false) as Button
	if edit == null:
		errors.append("talk step did not expose dialogue authoring")
		chain.free()
		return
	edit.pressed.emit()
	var editor := chain.find_child("DialogueEditor", true, false) as EmberDialogueEditor
	if editor == null or editor.find_child("DialogueCards", true, false).get_child_count() != 1:
		errors.append("talk step did not open the selected dialogue as cards")
	else:
		var flag_input := editor.find_child("ChoiceFlagId", true, false) as LineEdit
		var flag_library := editor.find_child("OpenChoiceQuestFlagLibrary", true, false) as Button
		if flag_input == null or flag_library == null:
			errors.append("dialogue choice did not expose the quest flag reference library")
		else:
			editor.set("_quest_flag_target", flag_input)
			editor.call("_choose_quest_flag_value", "sandbox_notice_read")
			if flag_input.text != "sandbox_notice_read":
				errors.append("quest flag library did not fill the dialogue choice")
		var emitted: Array[Dictionary] = []
		chain.dialogue_save_requested.connect(func(value: Dictionary) -> void: emitted.append(value))
		editor.save_requested.emit(document)
		var option := chain.find_child("StepField_dialogueId", true, false) as OptionButton
		var selected := "" if option == null or option.selected < 0 else str(option.get_item_metadata(option.selected))
		if emitted.size() != 1 or selected != TEMP_DIALOGUE_ID:
			errors.append("saved dialogue ID was not routed back into the talk step")
	chain.free()


func _restore_fixture(old_document: Dictionary) -> void:
	if old_document.is_empty():
		Store.delete_document(TEMP_DIALOGUE_ID)
	else:
		Store.write_document(old_document)
