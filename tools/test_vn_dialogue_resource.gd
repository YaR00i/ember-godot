extends SceneTree
## Native dialogue create/edit/Undo contract; no legacy reads or writes.

const Fixture = preload("res://tools/fixtures/ember_story_test_fixture.gd")
var _setup: Dictionary

const TEMP_ID := "ember_test_native_dialogue"
const Catalog = preload("res://scripts/ember_dialogue_catalog.gd")
const Store = preload("res://addons/ember_import/ember_dialogue_store.gd")


func _init() -> void:
	_setup = Fixture.prepare(self)
	if _setup.refused:
		quit.call_deferred(2)
		return
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	if _setup.error != OK or not _setup.progress_isolated:
		printerr("FAIL native story fixture preparation")
		return 1
	var previous := Catalog.snapshot(TEMP_ID)
	Catalog.delete_native(TEMP_ID)
	var initial := _document("Начальный native документ")
	var path: String = _setup.directory.path_join("poison/scenes/" + TEMP_ID + ".json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(initial))
	file.close()
	var poison_sha := FileAccess.get_sha256(path)
	var old_snapshot := {"id": TEMP_ID, "native": {}, "legacy": initial, "legacy_text": "overwritten"}
	if Catalog.restore(old_snapshot) != OK or FileAccess.get_sha256(path) != poison_sha:
		errors.append("old snapshot fields rewrote legacy bytes")
	ProjectSettings.set_setting("ember/pack_path", _setup.directory.path_join("poison"))
	_test_native_history(errors, initial)
	if FileAccess.get_sha256(path) != poison_sha: errors.append("native operations changed legacy poison bytes")
	ProjectSettings.set_setting("ember/pack_path", _setup.directory.path_join("absent-pack"))
	_test_missing_pack(errors)
	Catalog.restore(previous)
	Fixture.verify_sources(_setup, errors)
	if not errors.is_empty():
		printerr("FAIL VN dialogue Resource authoring")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS VN dialogue Resource authoring")
	print("  native create makes res://content/dialogues/<id>.tres canonical")
	print("  editor save and runtime resolve the same native Resource")
	print("  poisoned/missing JSON ignored; Undo/Redo never reads/writes old content")
	return 0


func _test_native_history(errors: Array[String], initial: Dictionary) -> void:
	if Store.owner(TEMP_ID) != "" or not Catalog.document(TEMP_ID).is_empty() or TEMP_ID in Catalog.ids():
		errors.append("legacy poison leaked into native story catalog")
	if Store.source_path(TEMP_ID) != "" or Catalog.snapshot(TEMP_ID).keys().size() != 2:
		errors.append("missing story source or snapshot retained legacy state")
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	if not actions.save_dialogue_graph(initial, context):
		errors.append("editor action rejected a valid new native dialogue")
	else:
		_assert_native_runtime(errors, "Начальный native документ")
		var edited := _document("Сохранено в Resource")
		if not actions.save_dialogue_graph(edited, context):
			errors.append("native dialogue save was rejected")
		else:
			_assert_native_runtime(errors, "Сохранено в Resource")
			history.undo()
			_assert_native_runtime(errors, "Начальный native документ")
			history.undo()
			if Store.owner(TEMP_ID) != "" or not Catalog.document(TEMP_ID).is_empty() or TEMP_ID in Catalog.ids():
				errors.append("Undo create exposed legacy fallback")
			history.redo()
			_assert_native_runtime(errors, "Начальный native документ")
			history.redo()
			_assert_native_runtime(errors, "Сохранено в Resource")
	history.clear_history(false)
	history.free()
	context.free()


func _test_missing_pack(errors: Array[String]) -> void:
	var document := _document("Absent pack")
	if Store.write_document(document) != OK: errors.append("native writer depended on missing pack")
	var snapshot := Catalog.snapshot(TEMP_ID)
	if Catalog.document(TEMP_ID).is_empty(): errors.append("native reader depended on missing pack")
	if Store.delete_document(TEMP_ID) != OK or not Catalog.document(TEMP_ID).is_empty(): errors.append("native delete did not remove document")
	if Catalog.restore(snapshot) != OK or Catalog.document(TEMP_ID).is_empty(): errors.append("native snapshot restore failed without pack")


func _assert_native_runtime(errors: Array[String], expected_name: String) -> void:
	if Store.owner(TEMP_ID) != "native":
		errors.append("native Resource did not become the canonical owner")
		return
	if not FileAccess.file_exists(Catalog.native_path(TEMP_ID)):
		errors.append("creation did not create the native .tres")
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
