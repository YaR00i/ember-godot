extends SceneTree
## Native dialogue migration contract: one explicit editor action changes the
## canonical owner from legacy JSON to a Godot Resource, and runtime follows it.

const TEMP_ID := "ember_test_native_dialogue"
const Catalog = preload("res://scripts/ember_dialogue_catalog.gd")
const Store = preload("res://addons/ember_import/ember_dialogue_store.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var previous := Catalog.snapshot(TEMP_ID)
	Catalog.delete_native(TEMP_ID)
	Catalog.delete_legacy(TEMP_ID)
	var legacy := _document("Только legacy")
	if Catalog.write_legacy(legacy) != OK:
		errors.append("could not create the isolated legacy fixture")
	else:
		_test_migration(errors, legacy)
	Catalog.restore(previous)
	if not errors.is_empty():
		printerr("FAIL VN dialogue Resource migration")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS VN dialogue Resource migration")
	print("  explicit migration makes res://content/dialogues/<id>.tres canonical")
	print("  editor save and runtime resolve the same native Resource")
	print("  legacy JSON stays unchanged; Undo/Redo restores the exact owner state")
	return 0


func _test_migration(errors: Array[String], legacy: Dictionary) -> void:
	if Store.owner(TEMP_ID) != "legacy" or Store.document(TEMP_ID) != legacy:
		errors.append("legacy dialogue was not the initial canonical owner")
		return
	var legacy_path := EmberPack.scene_path(TEMP_ID)
	var legacy_text := FileAccess.get_file_as_string(legacy_path)
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	if not actions.migrate_dialogue(TEMP_ID, context):
		errors.append("editor action rejected a valid legacy dialogue migration")
	else:
		_assert_native_runtime(errors, "Только legacy")
		var edited := _document("Сохранено в Resource")
		if not actions.save_dialogue_graph(edited, context):
			errors.append("native dialogue save was rejected")
		else:
			_assert_native_runtime(errors, "Сохранено в Resource")
			if FileAccess.get_file_as_string(legacy_path) != legacy_text:
				errors.append("saving the native dialogue mutated its legacy backup")
			history.undo()
			_assert_native_runtime(errors, "Только legacy")
			history.undo()
			if Store.owner(TEMP_ID) != "legacy" or FileAccess.file_exists(Catalog.native_path(TEMP_ID)):
				errors.append("Undo migration did not restore the legacy-only owner")
			if Store.document(TEMP_ID) != legacy:
				errors.append("Undo migration did not restore the exact legacy document")
			history.redo()
			_assert_native_runtime(errors, "Только legacy")
			history.redo()
			_assert_native_runtime(errors, "Сохранено в Resource")
	history.clear_history(false)
	history.free()
	context.free()


func _assert_native_runtime(errors: Array[String], expected_name: String) -> void:
	if Store.owner(TEMP_ID) != "native":
		errors.append("native Resource did not become the canonical owner")
		return
	if not FileAccess.file_exists(Catalog.native_path(TEMP_ID)):
		errors.append("migration did not create the native .tres")
	var editor_document := Store.document(TEMP_ID)
	var runtime_document := EmberInteractionContent.dialogue_for_id(TEMP_ID)
	if str(editor_document.get("nameRu", "")) != expected_name:
		errors.append("editor store did not reopen the expected native document")
	if str(runtime_document.get("nameRu", "")) != expected_name:
		errors.append("runtime did not resolve the same native document")
	if TEMP_ID not in EmberInteractionContent.dialogue_ids():
		errors.append("native dialogue is missing from runtime/editor catalog IDs")


func _document(display_name: String) -> Dictionary:
	return {
		"id": TEMP_ID,
		"nameRu": display_name,
		"use": "talk",
		"startStepId": "line",
		"steps": [
			{
				"id": "line",
				"type": "dialogue",
				"speaker": "guide",
				"portraitKey": "neutral",
				"nameRu": "Проводник",
				"textRu": display_name,
				"next": "end",
			},
			{"id": "end", "type": "end"},
		],
		"editorLayout": {
			"line": {"x": 40.0, "y": 80.0},
			"end": {"x": 360.0, "y": 80.0},
		},
	}
