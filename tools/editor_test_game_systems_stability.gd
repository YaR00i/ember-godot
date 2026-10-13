@tool
extends EditorPlugin
## Native publication lifecycle reproduction, only in a guarded disposable project.
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Filesystem = preload("res://addons/ember_import/ember_editor_filesystem.gd")
var _errors: Array[String] = []
var _rapid := false

func _enter_tree() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for index in count: await get_tree().process_frame

func _run() -> void:
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if actual != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not actual.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL stability gate refused author project")
		get_tree().quit(2)
		return
	await _frames(60)
	EditorInterface.set_main_screen_editor("Ember Graph")
	var workspace := EditorInterface.get_editor_main_screen().find_child("EmberGraphWorkspace", true, false)
	workspace.open_resource("systems", "systems_library")
	var hub := workspace.get("_game_systems_workspace") as Control
	var count := clampi(int(OS.get_environment("EMBER_STABILITY_CYCLES")), 1, 100)
	await _settle()
	var scans_before := int(Filesystem.diagnostics().scans)
	for cycle in count:
		_rapid = cycle % 2 == 0
		var id := "stability_action_%02d" % cycle
		var path := Store.path_for("action", id)
		hub.call("select_module", "action", "earth_wall")
		var session = hub.get("_session")
		if not session.create("action", id, "Stability action", Catalog.Actions.resource("earth_wall")):
			_errors.append("create failed")
			break
		hub.call("_mount_draft")
		await _frames(2)
		print("STABILITY_STEP ", cycle, " save")
		hub.call("_save_draft")
		if not FileAccess.file_exists(path):
			_errors.append("save failed: " + session.last_error)
			break
		var saved := Store.signature(path)
		var uid := ResourceLoader.get_resource_uid(path)
		if _rapid: await _frames(8)
		else: await _indexed(path, true)
		var history := get_undo_redo().get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
		print("STABILITY_STEP ", cycle, " undo")
		history.undo()
		if FileAccess.file_exists(path): _errors.append("Undo kept created file")
		await _indexed(path, false)
		print("STABILITY_STEP ", cycle, " redo")
		history.redo()
		if Store.signature(path) != saved: _errors.append("Redo changed bytes")
		await _indexed(path, true)
		if ResourceLoader.get_resource_uid(path) != uid: _errors.append("Redo lost UID")
		print("STABILITY_STEP ", cycle, " reopen")
		hub.call("select_module", "action", id)
		hub.call("begin_edit")
		await _frames(4)
		if hub.get("_session").draft.display_name != "Stability action": _errors.append("reopen changed draft")
		var live := ResourceLoader.load(path) as EmberCombatActionResource
		var before_cost := live.mp_cost
		session.set_value("mp_cost", before_cost + 1)
		hub.call("_save_draft")
		await _indexed(path, true)
		if live.mp_cost != before_cost + 1 or ResourceLoader.get_resource_uid(path) != uid: _errors.append("edit lost cached values/UID")
		history.undo()
		await _indexed(path, true)
		if Store.signature(path) != saved or live.mp_cost != before_cost: _errors.append("edit Undo lost bytes/cache")
		history.redo()
		await _indexed(path, true)
		if live.mp_cost != before_cost + 1: _errors.append("edit Redo lost cache")
		hub.call("discard_changes")
		print("STABILITY_STEP ", cycle, " delete")
		Store.restore({"path": path, "exists": false})
		get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)
		_rapid = false
		await _indexed(path, false)
		if not _errors.is_empty(): break
	if int(Filesystem.diagnostics().scans) != scans_before: _errors.append("library publication launched background full scan")
	await _settle()
	if _errors.is_empty(): print("PASS game systems stability: ", count, " native Save/Undo/Redo/reopen/edit/delete cycles, FileSystem/UID/cache and no background full scans")
	else: printerr("FAIL stability: ", "; ".join(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _indexed(path: String, exists: bool) -> void:
	# Rapid cycles reproduce immediate Undo/Redo during the old background scan.
	# Only their final index state must survive coalesced discovery updates.
	if _rapid: return
	await _settle()
	var indexed := not EditorInterface.get_resource_filesystem().get_file_type(path).is_empty()
	if indexed != exists: _errors.append("native FileSystem stale: " + path)

func _settle() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	var filesystem := EditorInterface.get_resource_filesystem()
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if Filesystem.diagnostics().pending == 0 and not filesystem.is_scanning() and not filesystem.is_importing(): return
	_errors.append("native FileSystem did not settle")
