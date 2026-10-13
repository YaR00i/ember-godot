extends SceneTree
const Store = preload("res://addons/ember_import/ember_game_systems_lab_preset_store.gd")
const Dialog = preload("res://addons/ember_import/ember_game_systems_lab_setup_dialog.gd")
const Setup = preload("res://scripts/prototypes/ember_combat_lab_setup.gd")
const Lab = preload("res://scenes/combat_lab.tscn")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const ENCOUNTER := "res://content/combat/encounters/colored_crossing_demo.tres"
const MANIFEST := "res://.lab-presets-gate.json"
var _errors: Array[String] = []
var _encounter: EmberEncounterResource
var _directory: String
var _raw := {"party": {"mira": {"level": 9, "equipment": {"weapon": null, "armor": "traveler_tunic", "shoes": null, "accessory1": null, "accessory2": null}}}, "inventory": {"herb": 3}}

func _init() -> void:
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if actual != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not actual.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL Lab presets refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	_directory = "user://ember-tests/lab-presets/" + actual.get_file()
	_run.call_deferred()

func _run() -> void:
	_encounter = load(ENCOUNTER)
	var args := OS.get_cmdline_user_args()
	if "--preset-play" in args: await _play()
	elif "--preset-reopen" in args: await _reopen()
	else:
		_test_store()
		await _test_dialog()
		var store := Store.new(_directory.path_join("persisted.json"))
		var saved: Dictionary = store.save(_encounter, "Мира 9 · травы", _raw, "")
		_check(saved.get("ok", false), "cold fixture Save failed")
		if saved.get("ok", false):
			var manifest := FileAccess.open(MANIFEST, FileAccess.WRITE)
			manifest.store_string(JSON.stringify({"id": saved.id, "path": store.path, "writerPid": OS.get_process_id()}))
			manifest.close()
	_finish()

func _test_store() -> void:
	var store := Store.new(_directory.path_join("store.json"))
	_check(store.read().get("ok", false) and not FileAccess.file_exists(store.path), "read created preference data")
	var saved: Dictionary = store.save(_encounter, "  Комплект / β  ", _raw, "")
	_check(saved.get("ok", false), "valid preset refused: " + str(saved.get("error", "")))
	if not saved.get("ok", false): return
	var id: String = saved.id
	var initial: Dictionary = store.read()
	_check(initial.records.size() == 1 and initial.records[0].name == "Комплект / β" and initial.records[0].setup == _raw, "name/level/five slots/count JSON roundtrip failed")
	var detached: Dictionary = initial.records[0].setup
	detached.party.mira.level = 2
	_check(store.read().records[0].setup.party.mira.level == 9, "read mutated disk")
	_check(not store.save(_encounter, "КОМПЛЕКТ / β", _raw, saved.hash).get("ok", true), "duplicate name silently overwritten")
	for bad_name in ["", "in\nvalid", "x".repeat(81)]:
		_check(not store.save(_encounter, bad_name, _raw, saved.hash).get("ok", true), "invalid name accepted")
	var bad := _raw.duplicate(true)
	bad.party.mira.level = 0
	_check(not store.save(_encounter, "Invalid", bad, saved.hash).get("ok", true), "invalid setup saved")
	var changed := _raw.duplicate(true)
	changed.party.mira.level = 12
	var updated: Dictionary = store.save(_encounter, "После правки", changed, saved.hash, id)
	_check(updated.get("ok", false) and updated.id == id and Store.new(store.path).read().records[0].setup == changed, "update/rename/id/fresh store failed")
	_check(not store.save(_encounter, "Stale", _raw, saved.hash, id).get("ok", true) and not store.remove(id, saved.hash).get("ok", true), "stale editor overwrote/deleted a new version")
	var other := _encounter.duplicate() as EmberEncounterResource
	other.party_unit_ids = PackedStringArray(["mira"])
	_check(not store.save(other, "Wrong group", _raw, updated.hash, id).get("ok", true), "updated another roster's preset")
	var cross: Dictionary = store.save(other, "После правки", _raw, updated.hash)
	_check(cross.get("ok", false), "same name on another roster incorrectly blocked")
	var second := _encounter.duplicate() as EmberEncounterResource
	second.encounter_id = "another_encounter_same_party"
	second.party_unit_ids = _encounter.party_unit_ids.duplicate()
	second.party_unit_ids.reverse()
	_check(Store.roster(second) == Store.roster(_encounter) and Setup.prepare(second, changed).get("ok", false), "preset cannot transfer across same roster encounters")
	var deleted: Dictionary = store.remove(id, cross.hash)
	_check(deleted.get("ok", false) and store.read().records.size() == 1, "Delete failed")
	var restored: Dictionary = store.undo_delete(deleted.hash)
	_check(restored.get("ok", false) and store.read().records.size() == 2, "Delete cannot undo")
	var no_op: Dictionary = store.save(_encounter, "После правки", changed, restored.hash, id)
	_check(no_op.get("ok", false) and no_op.hash != restored.hash and not store.undo_delete(restored.hash).get("ok", true), "no-op Save left another window's backup undo active")
	restored = no_op
	var before := FileAccess.get_file_as_bytes(store.path)
	for fault in ["preserve", "publish", "rollback"]:
		store.rename_override = func(from: String, to: String) -> Error:
			if fault == "preserve" and from == store.path: return ERR_FILE_CANT_WRITE
			if from.ends_with(".tmp") or (fault == "rollback" and from.ends_with(".previous")): return ERR_FILE_CANT_WRITE
			return DirAccess.rename_absolute(from, to)
		_check(not store.save(_encounter, "Failed write", _raw, restored.hash, id).get("ok", true), "injected publication failure reported success")
		var recovered: Dictionary = store.read()
		_check(recovered.get("ok", false) and recovered.hash == restored.hash, "publication failure destroyed old records")
		store.rename_override = Callable()
		if not FileAccess.file_exists(store.path):
			_check(recovered.recovered, "missing main file did not expose backup")
			DirAccess.rename_absolute(store.path + ".previous", store.path)
	_check(FileAccess.get_file_as_bytes(store.path) == before, "failed writes changed file bytes")
	var document: Dictionary = JSON.parse_string(before.get_string_from_utf8())
	var malformed := document.duplicate(true)
	malformed.presets[0].setup.party.mira = "wrong member"
	for text in ["{broken", JSON.stringify({"version": 2, "presets": []}), JSON.stringify(malformed), " ".repeat(Store.MAX_BYTES + 1)]:
		_write(store.path, text)
		var bytes := FileAccess.get_file_as_bytes(store.path)
		_check(not store.read().get("ok", true) and not store.save(_encounter, "Repair", _raw, "").get("ok", true), "corrupt/version/type/oversized data overwritten")
		_check(FileAccess.get_file_as_bytes(store.path) == bytes, "error silently repaired file")
	_write(store.path, before.get_string_from_utf8())
	_check(not Store.new("res://content/presets.json").save(_encounter, "Outside", _raw, "").get("ok", true), "preset store wrote author files")

func _test_dialog() -> void:
	var store := Store.new(_directory.path_join("ui.json"))
	var dialog := Dialog.new()
	dialog.preset_store = store
	root.add_child(dialog)
	dialog.open_setup(_encounter, _raw)
	await process_frame
	_set_name(dialog, "Проверочный набор")
	(dialog.find_child("LabPresetSave", true, false) as Button).pressed.emit()
	var id: String = dialog.get("_preset_id")
	_check(not id.is_empty() and store.read().records.size() == 1, "native Save button did not publish")
	(dialog.find_child("LabSetupLevel", true, false) as SpinBox).value = 13
	(dialog.find_child("LabPresetLoad", true, false) as Button).pressed.emit()
	_check(dialog.snapshot() == _raw, "native Load failed")
	dialog.undo()
	_check(dialog.snapshot().party.mira.level == 13, "Load not undoable")
	dialog.redo()
	_check(dialog.snapshot() == _raw, "Load not redoable")
	_set_name(dialog, "Переименованный")
	(dialog.find_child("LabPresetUpdate", true, false) as Button).pressed.emit()
	_check(store.read().records[0].id == id and store.read().records[0].name == "Переименованный", "native Update/rename lost identity")
	var original := dialog.snapshot()
	(dialog.find_child("LabPresetDelete", true, false) as Button).pressed.emit()
	var confirmation := dialog.find_child("LabPresetDeleteConfirmation", true, false) as ConfirmationDialog
	_check(confirmation != null and store.read().records.size() == 1, "Delete published before confirmation")
	confirmation.hide()
	await process_frame
	(dialog.find_child("LabPresetDelete", true, false) as Button).pressed.emit()
	confirmation = dialog.find_child("LabPresetDeleteConfirmation", true, false)
	confirmation.confirmed.emit()
	confirmation.hide()
	_check(store.read().records.is_empty() and dialog.snapshot() == original, "Delete modified current test setup")
	(dialog.find_child("LabPresetRestore", true, false) as Button).pressed.emit()
	_check(store.read().records.size() == 1 and dialog.snapshot() == original, "native delete restoration failed")
	var bytes := FileAccess.get_file_as_bytes(store.path)
	dialog.hide()
	dialog.free()
	dialog = Dialog.new()
	dialog.preset_store = Store.new(store.path)
	root.add_child(dialog)
	dialog.open_setup(_encounter)
	_check(dialog.snapshot().is_empty(), "new dialog auto-applied preset")
	_select(dialog, id)
	(dialog.find_child("LabPresetLoad", true, false) as Button).pressed.emit()
	_check(dialog.snapshot() == _raw, "new dialog lost persisted setup")
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	progress.set_process(false)
	var baseline := _progress_snapshot(progress)
	(dialog.find_child("LabSetupLevel", true, false) as SpinBox).value = 18
	dialog.hide()
	dialog.open_setup(_encounter)
	_check(dialog.snapshot().is_empty() and FileAccess.get_file_as_bytes(store.path) == bytes, "Cancel/open persisted transient edits")
	_select(dialog, id)
	var newer := _raw.duplicate(true)
	newer.inventory.herb = 4
	store.save(_encounter, "В другом окне", newer, store.read().hash, id)
	(dialog.find_child("LabPresetLoad", true, false) as Button).pressed.emit()
	_check(dialog.snapshot().is_empty(), "stale selection applied newer preset without Refresh")
	(dialog.find_child("LabPresetRefresh", true, false) as Button).pressed.emit()
	_select(dialog, id)
	(dialog.find_child("LabPresetLoad", true, false) as Button).pressed.emit()
	_check(dialog.snapshot() == newer, "Refresh lost source update")
	var missing: Dictionary = store.read()
	missing.records[0].setup.party.mira.equipment.weapon = "missing_preset_weapon"
	_write(store.path, JSON.stringify({"version": 1, "presets": missing.records}))
	dialog.open_setup(_encounter)
	_select(dialog, id)
	(dialog.find_child("LabPresetLoad", true, false) as Button).pressed.emit()
	_check(dialog.snapshot().party.mira.equipment.weapon == "missing_preset_weapon" and dialog.get_ok_button().disabled and (dialog.find_child("LabPresetSave", true, false) as Button).disabled, "missing item silently dropped or launch/save enabled")
	_check((dialog.find_child("LabSetupSlot_weapon", true, false) as OptionButton).text.contains("Недоступно"), "missing item not visible for correction")
	_check(_progress_snapshot(progress) == baseline, "preset UI changed gameplay progress")
	dialog.hide()
	dialog.free()

func _reopen() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	_check(int(manifest.writerPid) != OS.get_process_id(), "cold reopen reused writer process")
	var store := Store.new(str(manifest.path))
	var fresh: Dictionary = store.read()
	_check(fresh.get("ok", false) and fresh.records.size() == 1 and fresh.records[0].setup == _raw, "fresh process lost named preset")
	var dialog := Dialog.new()
	dialog.preset_store = store
	root.add_child(dialog)
	dialog.open_setup(_encounter)
	_select(dialog, str(manifest.id))
	(dialog.find_child("LabPresetLoad", true, false) as Button).pressed.emit()
	_check(dialog.snapshot() == _raw, "fresh process native selection/load failed")
	var emitted := {}
	dialog.launch_requested.connect(func(setup: Dictionary) -> void: emitted.merge(setup, true))
	dialog.confirmed.emit()
	_check(emitted == _raw, "launch signal did not use loaded preset")
	var written := Setup.write_request(ENCOUNTER, emitted)
	_check(written.get("ok", false), "loaded preset transport failed")
	manifest["request"] = written.get("path", "")
	manifest["readerPid"] = OS.get_process_id()
	_write(MANIFEST, JSON.stringify(manifest))
	dialog.hide()
	dialog.free()

func _play() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	_check(int(manifest.writerPid) != OS.get_process_id() and int(manifest.readerPid) != OS.get_process_id(), "runtime was not a third fresh process")
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	progress.set_process(false)
	var baseline := _progress_snapshot(progress)
	var store := Store.new(str(manifest.path))
	var before := FileAccess.get_file_as_bytes(store.path)
	var lab := Lab.instantiate()
	root.add_child(lab)
	current_scene = lab
	for i in 16: await process_frame
	var hud := lab.get_node("CombatHUDLayer/CombatHUD")
	var state: Dictionary = hud.state_snapshot()
	_check(hud.get("_library_test") and state.units.mira.level == 9 and state.units.mira.equipment.armor == "traveler_tunic" and state.inventory == {"herb": 3}, "runtime did not apply saved level/gear/bag")
	var initial := state.duplicate(true)
	for id in state.units: state.units[id].nextAt = 0 if id == "mira" else 100
	state.units.mira.hp -= 4
	var preview := Combat.preview(state, "item:herb", "mira")
	_check(preview.get("ok", false), "loaded preset bag cannot use consumable")
	state = Combat.commit(state, preview)
	_check(state.inventory.get("herb") == 2, "consumption did not use loaded count")
	hud.set("_state", state)
	hud.call("_retry_encounter")
	state = hud.state_snapshot()
	_check(state.units.mira == initial.units.mira and state.inventory == initial.inventory, "Retry did not restore preset initial state")
	_check(FileAccess.get_file_as_bytes(store.path) == before and _progress_snapshot(progress) == baseline and not progress.persistence_enabled, "battle wrote preset/gameplay state")
	lab.free()

func _set_name(dialog: Node, value: String) -> void:
	var edit := dialog.find_child("LabPresetName", true, false) as LineEdit
	edit.text = value
	edit.text_changed.emit(value)

func _select(dialog: Node, id: String) -> void:
	var picker := dialog.find_child("LabPresetPicker", true, false) as OptionButton
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == id:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	_check(false, "preset selection not found: " + id)

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _progress_snapshot(progress: EmberExploreState) -> Dictionary:
	var snapshot := progress.capture_save()
	snapshot.erase("savedAtMs")
	return snapshot

func _check(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)

func _finish() -> void:
	if _errors.is_empty(): print("PASS game systems Lab presets ", OS.get_cmdline_user_args(), ": CRUD/rename/roster, detached data, publication recovery/stale/corruption, native Load Undo/Redo/Cancel/delete restore, cold persistence and runtime isolation")
	else: printerr("FAIL Lab presets: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)
