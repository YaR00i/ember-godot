extends SceneTree
## Composition foundation gate: statuses are canonical content, effect validation
## resolves their IDs, runtime presentation reads the catalog and malformed
## dictionary snapshots are rejected at the resolver boundary.

const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")
const StatusCatalog := preload("res://scripts/prototypes/ember_combat_status_catalog.gd")
const StatusScript := preload("res://scripts/prototypes/ember_combat_status_resource.gd")
const EffectScript := preload("res://scripts/prototypes/ember_combat_effect_resource.gd")
const StatusPanel := preload("res://addons/ember_import/ember_combat_status_inspector_panel.gd")
const ContentWorkspace := preload("res://addons/ember_import/ember_combat_content_library_workspace.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	_test_catalog(errors)
	_test_effect_validation(errors)
	_test_runtime_boundary(errors)
	_test_editor(errors)
	if not errors.is_empty():
		printerr("FAIL combat status Resource")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS combat status Resource")
	print("  five canonical status .tres definitions own name, kind and visuals")
	print("  effect validation rejects unknown status IDs")
	print("  resolver facade rejects malformed runtime snapshots without mutation")
	print("  native combat library exposes status cards and relations")
	return 0


func _test_catalog(errors: Array[String]) -> void:
	StatusCatalog.refresh()
	var expected := PackedStringArray(["burning", "frozen", "guard", "overheated", "wet"])
	if StatusCatalog.ids() != expected:
		errors.append("status catalog does not expose the five canonical fixtures")
	for status in StatusCatalog.resources():
		var validation: Array = status.call("validation_errors")
		if not validation.is_empty():
			errors.append("status %s is invalid: %s" % [
				str(status.get("status_id")), " | ".join(validation),
			])
	var wet := StatusCatalog.resource("wet")
	if wet == null or str(Combat.status_definition("wet").get("name", "")) != "Мокрый":
		errors.append("resolver status projection does not read the authored catalog")
		return
	var path := "user://combat_status_roundtrip.tres"
	if ResourceSaver.save(wet, path) != OK:
		errors.append("status Resource could not be saved")
	else:
		var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as Resource
		if reopened == null or str(reopened.call("content_signature")) != str(wet.call("content_signature")):
			errors.append("status Resource changed after save/reopen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_effect_validation(errors: Array[String]) -> void:
	var effect := EffectScript.new() as Resource
	effect.set("effect_id", "test_unknown_status")
	effect.set("display_name", "Проверка неизвестного статуса")
	effect.set("description", "Негативная проверка каталога статусов.")
	effect.set("status_id", "missing_status")
	effect.set("status_duration", 2)
	var validation: Array = effect.call("validation_errors")
	if not validation.any(func(message: String) -> bool: return "отсутствует в боевом каталоге" in message):
		errors.append("effect validation accepted an unknown status ID")
	effect.set("status_id", "wet")
	if not (effect.call("validation_errors") as Array).is_empty():
		errors.append("effect validation rejected a known status ID")


func _test_runtime_boundary(errors: Array[String]) -> void:
	var valid := Combat.initial_state(7)
	if not Combat.state_validation_errors(valid).is_empty():
		errors.append("canonical initial state failed runtime schema validation")
	var malformed := valid.duplicate(true)
	(malformed.get("units", {}) as Dictionary)["mira"].erase("statuses")
	var before := malformed.duplicate(true)
	var preview := Combat.preview(malformed, "strike", "wisp")
	if bool(preview.get("ok", true)) or "statuses" not in str(preview.get("error", "")):
		errors.append("preview did not explain malformed unit state")
	if malformed != before:
		errors.append("schema rejection mutated malformed source state")
	var unknown_status := valid.duplicate(true)
	((unknown_status.get("units", {}) as Dictionary)["mira"] as Dictionary)["statuses"] = {
		"missing_status": 2,
	}
	if not Combat.state_validation_errors(unknown_status).any(
		func(message: String) -> bool: return "неизвестный статус" in message
	):
		errors.append("runtime schema accepted an unknown status ID")


func _test_editor(errors: Array[String]) -> void:
	var status := StatusCatalog.resource("wet")
	var panel := StatusPanel.new() as VBoxContainer
	panel.call("setup", status)
	if (
		panel.find_child("CombatStatusSummary", true, false) == null
		or panel.find_child("CombatStatusValidation", true, false) == null
		or panel.find_child("CombatStatusGlyph", true, false) == null
	):
		errors.append("status Inspector lost summary, validation or glyph projection")
	panel.free()
	var undo := UndoRedo.new()
	var workspace := ContentWorkspace.new() as VBoxContainer
	workspace.call("setup", null, undo)
	var tabs := workspace.find_child("CombatContentKinds", true, false) as TabBar
	if tabs == null or tabs.tab_count != 4 or tabs.get_tab_title(0) != "Статусы":
		errors.append("central combat library does not expose the status category")
	workspace.call("_open_related", "status", "wet")
	if str(workspace.get("_kind")) != "status" or str(workspace.get("_selected_id")) != "wet":
		errors.append("combat library could not navigate to a canonical status")
	workspace.free()
	undo.clear_history(false)
	undo.free()
