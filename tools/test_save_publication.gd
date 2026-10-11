extends SceneTree
## Save failure/restart gate uses unique user:// fixtures only.
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")


class FaultState extends EmberExploreState:
	var fault := ""
	var destination := ""


	func _store_staged_save(path: String, bytes: PackedByteArray) -> Error:
		if fault == "open":
			return ERR_FILE_CANT_OPEN
		if fault == "short":
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(bytes.slice(0, 7))
			file.close()
			return OK # Simulate a failed backend that incorrectly reports success.
		return super._store_staged_save(path, bytes)


	func _rename_save_file(from: String, to: String) -> Error:
		if fault == "preserve" and from == destination:
			return ERR_FILE_CANT_WRITE
		if from.ends_with(".tmp") and fault in ["publish", "rollback"]:
			return ERR_FILE_CANT_WRITE
		if fault == "rollback" and from.ends_with(".previous"):
			return ERR_FILE_CANT_WRITE
		return super._rename_save_file(from, to)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors: Array[String] = []
	var fixture := "user://ember-tests/save-publication-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	Maps.prepare(self, fixture)
	var target_map := "publication_destination_%d" % OS.get_process_id()
	if Maps.save_map(target_map, fixture, [], [], [], 16.0) == null:
		printerr("FAIL save publication native map fixture")
		quit(2)
		return
	for kind in ["manual", "autosave"]:
		var state := FaultState.new()
		state.storage_root = fixture.path_join(kind)
		state.legacy_storage_root = fixture.path_join("no-legacy")
		state.reset_new_game()
		state.destination = state.save_path(0) if kind == "manual" else state.autosave_path()
		var signals: Array[String] = []
		state.saved.connect(func(path: String) -> void: signals.append(path))
		if not _save(state, kind):
			errors.append("%s initial write failed" % kind)
		var original := FileAccess.get_file_as_bytes(state.destination)
		var remembered := state._saved_map_id
		state._map_id = target_map
		for fault in ["open", "short", "preserve", "publish", "rollback"]:
			state.fault = fault
			var count := signals.size()
			print("EXPECTED SAVE FAILURE: ", kind, "/", fault)
			if _save(state, kind) or signals.size() != count:
				errors.append("%s/%s reported saved after failure" % [kind, fault])
			if state._saved_map_id != remembered:
				errors.append("failed save updated remembered progress")
			var survivor := state.destination + ".previous" if fault == "rollback" else state.destination
			if FileAccess.get_file_as_bytes(survivor) != original:
				errors.append("%s/%s changed the previous bytes" % [kind, fault])
			var reopened := EmberExploreState.new()
			reopened.storage_root = state.storage_root
			reopened.legacy_storage_root = state.legacy_storage_root
			var metadata := reopened.slot_metadata(0) if kind == "manual" else reopened.autosave_metadata()
			if not bool(metadata.get("exists", false)) or not _load(reopened, kind):
				errors.append("%s/%s previous save did not recover/reopen" % [kind, fault])
			reopened.free()
			for filename in DirAccess.get_files_at(state.destination.get_base_dir()):
				if filename.ends_with(".tmp"):
					errors.append("failed save left a staging file")
		state.fault = ""
		if not _save(state, kind) or signals.size() != 2:
			errors.append("%s replacement did not publish exactly once" % kind)
		# Restart in the gap between preserving old data and publishing new data.
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(state.destination), ProjectSettings.globalize_path(state.destination + ".previous")) != OK:
			errors.append("could not set up interrupted publication fixture")
		var restarted := EmberExploreState.new()
		restarted.storage_root = state.storage_root
		restarted.legacy_storage_root = state.legacy_storage_root
		if not restarted.load_latest_available() or restarted._saved_map_id != target_map:
			errors.append("%s restart lost the last complete save" % kind)
		# A crash after publish can leave an older recovery file; deletion must
		# archive/remove both so the slot cannot resurrect on the next read.
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(state.destination), ProjectSettings.globalize_path(state.destination + ".previous")) != OK:
			errors.append("could not set up leftover recovery fixture")
		var deletion := restarted.delete_slot(0) if kind == "manual" else restarted.delete_autosave()
		if not bool(deletion.get("ok", false)) or _load(restarted, kind):
			errors.append("deleted %s save resurrected from recovery data" % kind)
		if (deletion.get("archivedPaths", []) as Array).size() != 2:
			errors.append("deletion did not archive both current and recovery files")
		state.free()
		restarted.free()
	if not errors.is_empty():
		printerr("FAIL save publication: ", "; ".join(errors))
		quit(1)
		return
	print("PASS save publication: manual/autosave, open/short-write/preserve/publish/rollback failures, restart, delete")
	quit(0)


func _save(state: EmberExploreState, kind: String) -> bool:
	return state.save_slot(0) if kind == "manual" else state.save_autosave()


func _load(state: EmberExploreState, kind: String) -> bool:
	return state.load_slot(0) if kind == "manual" else state.load_autosave()
