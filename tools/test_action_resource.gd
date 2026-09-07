extends SceneTree
## Native action-chain migration contract: editor and executor share one
## native-first catalog while legacy JSON remains an untouched backup.

const TEMP_ID := "ember_test_native_action"
const Catalog = preload("res://scripts/ember_action_catalog.gd")
const Store = preload("res://addons/ember_import/ember_action_script_store.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var previous := Catalog.snapshot(TEMP_ID)
	Catalog.delete_native(TEMP_ID)
	Catalog.delete_legacy(TEMP_ID)
	var legacy := _document("Только legacy", 1)
	if Catalog.write_legacy(legacy) != OK:
		errors.append("could not create the isolated legacy action fixture")
	else:
		_test_migration(errors, legacy)
	Catalog.restore(previous)
	if not errors.is_empty():
		printerr("FAIL action-chain Resource migration")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS action-chain Resource migration")
	print("  explicit migration makes res://content/action_scripts/<id>.tres canonical")
	print("  editor save and runtime executor resolve the same native Resource")
	print("  legacy JSON stays unchanged; Undo/Redo restores the exact owner state")
	return 0


func _test_migration(errors: Array[String], legacy: Dictionary) -> void:
	if Store.owner(TEMP_ID) != "legacy" or str(Store.document(TEMP_ID).get("nameRu", "")) != str(legacy.get("nameRu", "")):
		errors.append("legacy action chain was not the initial canonical owner")
		return
	var legacy_path := EmberPack.script_path(TEMP_ID)
	var legacy_text := FileAccess.get_file_as_string(legacy_path)
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	if not actions.migrate_action_script(TEMP_ID, context):
		errors.append("editor action rejected a valid legacy action migration")
	else:
		_assert_native_runtime(errors, "Только legacy", 1)
		var edited := _document("Сохранено в Resource", 3)
		if not actions.save_action_script(edited, context):
			errors.append("native action-chain save was rejected")
		else:
			_assert_native_runtime(errors, "Сохранено в Resource", 3)
			if FileAccess.get_file_as_string(legacy_path) != legacy_text:
				errors.append("saving the native action chain mutated its legacy backup")
			history.undo()
			_assert_native_runtime(errors, "Только legacy", 1)
			history.undo()
			if Store.owner(TEMP_ID) != "legacy" or FileAccess.file_exists(Catalog.native_path(TEMP_ID)):
				errors.append("Undo migration did not restore the legacy-only owner")
			if FileAccess.get_file_as_string(legacy_path) != legacy_text:
				errors.append("Undo migration did not restore the exact legacy action document")
			history.redo()
			_assert_native_runtime(errors, "Только legacy", 1)
			history.redo()
			_assert_native_runtime(errors, "Сохранено в Resource", 3)
	history.clear_history(false)
	history.free()
	context.free()


func _assert_native_runtime(errors: Array[String], expected_name: String, expected_count: int) -> void:
	if Store.owner(TEMP_ID) != "native":
		errors.append("native action Resource did not become the canonical owner")
		return
	if not FileAccess.file_exists(Catalog.native_path(TEMP_ID)):
		errors.append("migration did not create the native action .tres")
	var editor_document := Store.document(TEMP_ID)
	var queue := EmberActionScript.queue_for(TEMP_ID)
	var steps: Array = queue.get("steps", [])
	if str(editor_document.get("nameRu", "")) != expected_name:
		errors.append("editor store did not reopen the expected native action document")
	if not bool(queue.get("ok", false)) or steps.size() != 2:
		errors.append("runtime executor did not resolve the native action document")
	elif int((steps[0] as Dictionary).get("count", 0)) != expected_count:
		errors.append("runtime executor read stale legacy action fields")
	if TEMP_ID not in EmberInteractionContent.action_script_ids():
		errors.append("native action chain is missing from runtime/editor catalog IDs")


func _document(display_name: String, count: int) -> Dictionary:
	return {
		"id": TEMP_ID,
		"nameRu": display_name,
		"steps": [
			{"type": "give_item", "itemId": "coin", "count": count},
			{"type": "set_flag", "flag": "native_action_done", "value": true},
		],
	}
