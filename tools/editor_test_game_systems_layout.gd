@tool
extends EditorPlugin
## Native 125% layout evidence, disposable settings/project only.
const Filesystem = preload("res://addons/ember_import/ember_editor_filesystem.gd")
var _errors: Array[String] = []
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
var _hub: Control

func _enter_tree() -> void:
	_run.call_deferred()

func _frames(count := 6) -> void:
	for frame in count: await get_tree().process_frame

func _capture(label: String, viewport: Viewport = null) -> void:
	await _frames()
	RenderingServer.force_draw(false)
	var path := OS.get_environment("EMBER_UI_EVIDENCE").path_join("editor-" + label + ".png")
	var surface := viewport if viewport != null else EditorInterface.get_base_control().get_viewport()
	if surface.get_texture().get_image().save_png(path) != OK: _errors.append("capture failed: " + label)
	print("LAYOUT_CAPTURE ", path)

func _check(node: Control, label: String, container: Control = null) -> void:
	if node == null:
		_errors.append(label + ": missing control")
		return
	var limit := container.get_global_rect() if container != null else EditorInterface.get_editor_main_screen().get_global_rect()
	if not limit.grow(2).encloses(node.get_global_rect()):
		_errors.append(label + ": outside visible area " + str(node.get_global_rect()) + " / " + str(limit))

func _run() -> void:
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if actual != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not actual.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		get_tree().quit(2)
		return
	await _frames(60)
	print("LAYOUT_SCALE ", EditorInterface.get_editor_scale(), " settings ", OS.get_config_dir(), " window ", get_tree().root.size)
	if not is_equal_approx(EditorInterface.get_editor_scale(), 1.25): _errors.append("editor scale is not 125 percent")
	EditorInterface.set_main_screen_editor("Ember Graph")
	var workspace := EditorInterface.get_editor_main_screen().find_child("EmberGraphWorkspace", true, false)
	workspace.open_resource("systems", "systems_library")
	await _frames()
	_hub = workspace.get("_game_systems_workspace")
	_hub.call("select_module", "action", "strike")
	_hub.call("_open_create", false)
	await _frames()
	var create := _hub.get("_create_dialog") as ConfirmationDialog
	_check_dialog(create, "create")
	await _capture("create", create)
	create.get_cancel_button().pressed.emit()
	create.hide()
	await _frames()
	_check(_hub, "workspace")
	for name in ["GameSystemsNew", "GameSystemsCopy", "GameSystemsCheckLibrary"]:
		_check(_hub.find_child(name, true, false), name)
	await _capture("library")
	for pair in [["status", "poison"], ["effect", "apply_frozen"], ["action", "strike"], ["unit", "mira"], ["ai", ""], ["loot", ""], ["encounter", "colored_crossing_demo"], ["start", "default"], ["item", "herb"]]:
		_hub.call("select_module", pair[0], pair[1])
		_hub.call("begin_edit")
		await _frames()
		var form := _hub.get("_draft_editor") as Control
		if form != null:
			if form.get_combined_minimum_size().x > form.size.x + 2: _errors.append(str(pair[0]) + ": form overflow " + str(form.get_combined_minimum_size()) + " / " + str(form.size))
			var clip := EditorInterface.get_editor_main_screen().get_global_rect()
			if form.get_global_rect().end.x > clip.end.x + 2: _errors.append(str(pair[0]) + ": form outside editor width")
			for button in ["GameSystemsDraftSave", "GameSystemsDraftDiscard"]: _check(_hub.find_child(button, true, false), str(pair[0]) + "/" + button)
			if pair[0] in ["action", "item", "start"]: await _capture("form-" + str(pair[0]))
		_hub.call("discard_changes")
	await _authoring()
	_hub.call("select_module", "effect", "apply_wet")
	_hub.call("_show_usage", _hub.call("selected_record"))
	await _frames()
	var usage := _hub.get("_usage_panel") as Window
	print("LAYOUT_USAGE ", usage.size, " screen ", get_tree().root.size)
	if usage.size.x > get_tree().root.size.x or usage.size.y > get_tree().root.size.y: _errors.append("usage dialog exceeds editor")
	await _capture("usage", usage)
	usage.hide()
	_hub.call("select_module", "encounter", "colored_crossing_demo")
	_hub.call("_configure_selected_encounter")
	await _frames()
	var setup := _hub.get("_lab_setup_dialog") as Window
	if setup != null:
		print("LAYOUT_SETUP ", setup.size, " screen ", get_tree().root.size)
		if setup.size.x > get_tree().root.size.x or setup.size.y > get_tree().root.size.y: _errors.append("Lab setup exceeds editor")
		await _capture("lab-setup", setup)
		for button in [setup.get_ok_button(), setup.get_cancel_button()]:
			if not Rect2(Vector2.ZERO, Vector2(setup.size)).grow(2).encloses(button.get_global_rect()): _errors.append("Lab OK/Cancel outside dialog")
		setup.get_cancel_button().pressed.emit()
		setup.hide()
	_hub.call("_open_library_check")
	var report := _hub.get("_check_panel") as ConfirmationDialog
	var report_deadline := Time.get_ticks_msec() + 15000
	while report.get("_service").running() and Time.get_ticks_msec() < report_deadline: await _frames(1)
	_check_dialog(report, "library check")
	await _capture("check", report)
	report.hide()
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(15)
	_hub.call("select_module", "action", "strike")
	await _frames()
	_check(_hub, "wide workspace")
	(_hub.get("_detail").get_parent() as ScrollContainer).scroll_vertical = 0
	await _capture("wide-library")
	Filesystem.request()
	var deadline := Time.get_ticks_msec() + 10000
	var filesystem := EditorInterface.get_resource_filesystem()
	while Time.get_ticks_msec() < deadline:
		await _frames(1)
		if Filesystem.diagnostics().pending == 0 and not filesystem.is_scanning() and not filesystem.is_importing(): break
	if filesystem.is_scanning() or filesystem.is_importing(): _errors.append("layout fixture cleanup did not settle")
	for error in _errors: printerr("FAIL layout: ", error)
	if _errors.is_empty(): print("PASS game systems native editor 125 percent narrow layout")
	get_tree().quit(0 if _errors.is_empty() else 1)


func _authoring() -> void:
	const ID := "layout_action_fixture"
	var session = _hub.get("_session")
	_hub.call("select_module", "action", "strike")
	if not session.create("action", ID, "Проверочный приём с длинным названием и общим дополнительным эффектом", Store.Catalog.Actions.resource("strike")):
		_errors.append("layout fixture create failed")
		return
	session.draft.value_conditions.assign([{"subject": "actor", "stat": "hp", "comparison": "gte", "unit": "percent", "value": 1}])
	session.draft.equipment_conditions.assign([{"subject": "actor", "slot": "weapon", "mode": "occupied", "item_id": ""}])
	session.draft.condition_groups.assign([{"mode": "any", "target_required_status_ids": PackedStringArray(["wet"]), "target_forbidden_status_ids": PackedStringArray(["burning"])}])
	_hub.call("_mount_draft")
	await _frames()
	var form := _hub.get("_draft_editor") as Control
	var search := form.find_child("DraftEffectSearch", true, false) as LineEdit
	search.text = "apply_wet"
	search.text_changed.emit(search.text)
	var scroll := _hub.get("_detail").get_parent() as ScrollContainer
	var add := form.find_child("DraftAddEffect", true, false) as Button
	await _frames()
	scroll.ensure_control_visible(add)
	await _frames()
	_check(add, "scrolled Add", scroll)
	await _capture("effect-picker")
	add.pressed.emit()
	(_hub.find_child("GameSystemsDraftUndo", true, false) as Button).pressed.emit()
	if not session.draft.effect_steps.is_empty(): _errors.append("layout Add Undo failed")
	(_hub.find_child("GameSystemsDraftRedo", true, false) as Button).pressed.emit()
	if session.draft.effect_steps.size() != 1: _errors.append("layout Add Redo failed")
	var save := _hub.find_child("GameSystemsDraftSave", true, false) as Button
	_check(save, "enabled Save")
	if save.disabled: _errors.append("valid layout draft cannot Save")
	save.pressed.emit()
	await _frames()
	var path := Store.path_for("action", ID)
	var sha := Store.signature(path)
	_hub.call("_request_delete", _hub.call("selected_record"))
	await _frames()
	var deletion := _hub.get("_delete_dialog") as ConfirmationDialog
	_check_dialog(deletion, "delete")
	await _capture("delete", deletion)
	deletion.get_cancel_button().pressed.emit()
	deletion.hide()
	_hub.call("begin_edit")
	if session.draft == null or session.draft.effect_steps.size() != 1: _errors.append("layout Save/reopen lost effect")
	if session.draft != null: session.set_value("display_name", "Несохранённый черновик")
	var picker := _hub.find_child("GameSystemsModulePicker", true, false) as OptionButton
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == "status":
			picker.select(index)
			picker.item_selected.emit(index)
	await _frames()
	if _hub.get("_module") != "action" or not session.has_changes() or str(picker.get_item_metadata(picker.selected)) != "action": _errors.append("compact navigation bypassed dirty guard")
	var discard := _hub.get("_discard_dialog") as ConfirmationDialog
	_check_dialog(discard, "dirty navigation")
	await _capture("dirty-cancel", discard)
	discard.get_cancel_button().pressed.emit()
	discard.hide()
	_hub.call("discard_changes")
	if Store.signature(path) != sha: _errors.append("layout discard wrote saved file")
	_hub.call("select_module", "item", "herb")
	await _frames()
	Store.restore({"path": path, "exists": false})
	get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)


func _check_dialog(dialog: ConfirmationDialog, label: String) -> void:
	if dialog.size.x > get_tree().root.size.x or dialog.size.y > get_tree().root.size.y: _errors.append(label + " dialog exceeds window")
	for button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
		if button.visible and not Rect2(Vector2.ZERO, Vector2(dialog.size)).grow(2).encloses(button.get_global_rect()): _errors.append(label + " dialog button outside body")
