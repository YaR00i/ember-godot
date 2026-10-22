@tool
extends EditorPlugin
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const StatusType = preload("res://scripts/prototypes/ember_combat_status_resource.gd")
const EffectType = preload("res://scripts/prototypes/ember_combat_effect_resource.gd")
const ActionType = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const Filesystem = preload("res://addons/ember_import/ember_editor_filesystem.gd")
const LabPresets = preload("res://addons/ember_import/ember_game_systems_lab_preset_store.gd")
var _errors: Array[String] = []

func _enter_tree() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for frame in count: await get_tree().process_frame

func _capture(label: String, surface: Viewport = null) -> void:
	await _frames(8)
	RenderingServer.force_draw(false)
	var path := "user://game-systems-%s-%d.png" % [label, OS.get_process_id()]
	var target := surface if surface != null else EditorInterface.get_base_control().get_viewport()
	var error := target.get_texture().get_image().save_png(path)
	if error != OK: _errors.append("capture failed: " + label)
	print("GAME_SYSTEMS_CAPTURE ", ProjectSettings.globalize_path(path))

func _run() -> void:
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if actual != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not actual.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL game systems editor refused non-disposable project")
		get_tree().quit(2)
		return
	await _frames(60)
	EditorInterface.set_main_screen_editor("Ember Graph")
	var workspace := EditorInterface.get_editor_main_screen().find_child("EmberGraphWorkspace", true, false)
	if workspace == null:
		printerr("FAIL game systems real plugin not mounted")
		get_tree().quit(1)
		return
	workspace.open_resource("systems", "systems_library")
	await _frames(10)
	var hub := workspace.get("_game_systems_workspace") as Control
	if OS.get_environment("EMBER_GAME_SYSTEMS_EDITOR_FOCUS") == "effect-picker":
		await _effect_picker_forms(hub)
		await _settle_filesystem()
		if _errors.is_empty(): print("PASS game systems native effect search/selection/preview/conditions/empty/used/Undo/Redo/Save/reopen/Discard and width")
		else: printerr("FAIL effect picker: ", "; ".join(_errors))
		get_tree().quit(0 if _errors.is_empty() else 1)
		return
	if OS.get_environment("EMBER_GAME_SYSTEMS_EDITOR_FOCUS") in ["periodic", "stacks"]:
		await _periodic_forms(hub)
		await _settle_filesystem()
		if _errors.is_empty(): print("PASS game systems focused periodic status authoring/Undo/Redo/Discard/Save/reopen/UID/global publication")
		else: printerr("FAIL periodic editor: ", "; ".join(_errors))
		get_tree().quit(0 if _errors.is_empty() else 1)
		return
	if OS.get_environment("EMBER_GAME_SYSTEMS_EDITOR_FOCUS") == "start":
		await _start_forms(hub)
		await _settle_filesystem()
		if _errors.is_empty(): print("PASS game systems focused Forward+ start/levels/gear/bag/preview/Undo/Redo/Discard/Save/reopen/UID/publication")
		else: printerr("FAIL focused start: ", "; ".join(_errors))
		get_tree().quit(0 if _errors.is_empty() else 1)
		return
	if OS.get_environment("EMBER_GAME_SYSTEMS_EDITOR_FOCUS") == "presets":
		await _encounter_forms(hub)
		await _settle_filesystem()
		if _errors.is_empty(): print("PASS game systems focused Forward+ named presets/forms/Save/recreated dialog/Load/actual child launch")
		else: printerr("FAIL focused presets: ", "; ".join(_errors))
		get_tree().quit(0 if _errors.is_empty() else 1)
		return
	for module in Catalog.MODULES:
		hub.call("select_module", str(module[0]))
		await _frames(2)
		if not hub.is_visible_in_tree(): _errors.append("module disappeared: " + str(module[0]))
		if hub.get_combined_minimum_size().x > hub.size.x + 1: _errors.append("module overflows editor width: " + str(module[0]))
	hub.call("select_module", "item", "herb")
	await _capture("items")
	hub.call("select_module", "equipment", "traveler_tunic")
	await _capture("equipment")
	hub.call("select_module", "action", "earth_wall")
	await _capture("action")
	hub.call("_open_existing_editor")
	await _frames(10)
	if workspace.get("_current_kind") != "combat_content": _errors.append("native action route failed")
	workspace.open_resource("systems", "systems_library")
	hub.call("select_module", "item", "herb")
	hub.call("_open_existing_editor")
	await _frames(10)
	var window := workspace.find_child("GameSystemsItemWindow", true, false) as Window
	if window == null: _errors.append("native item form failed")
	else:
		await _capture("item-editor", window)
		window.close_requested.emit()
	await _frames(5)
	# Native common authoring: create a test copy, edit its fields, publish globally.
	hub.call("select_module", "action", "earth_wall")
	var session = hub.get("_session")
	var path := Store.path_for("action", "operations_editor_action")
	if not session.create("action", "operations_editor_action", "Черновик каменного заслона", Catalog.Actions.resource("earth_wall")):
		_errors.append("native copy draft failed")
	else:
		hub.call("_mount_draft")
		await _frames(8)
		var form := hub.get("_draft_editor") as Control
		var name := form.find_child("DraftField_display_name", true, false) as LineEdit
		name.text = "Проверочная копия заслона"
		name.text_changed.emit(name.text)
		if FileAccess.file_exists(path): _errors.append("native draft wrote before Save")
		form.call("_undo_draft")
		if session.draft.display_name != "Черновик каменного заслона": _errors.append("native draft Undo failed")
		form.call("_redo_draft")
		await _capture("draft")
		hub.call("_save_draft")
		await _frames(8)
		if not FileAccess.file_exists(path): _errors.append("native draft Save failed: " + session.last_error)
		else:
			var saved_hash := Store.signature(path)
			var history_id := get_undo_redo().get_object_history_id(session._publication_context)
			if history_id != EditorUndoRedoManager.GLOBAL_HISTORY: _errors.append("publication assigned to a scene history")
			var history := get_undo_redo().get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
			print("GAME_SYSTEMS_HISTORY ", history_id, " / ", history.get_current_action_name())
			history.undo()
			if FileAccess.file_exists(path): _errors.append("native global publication Undo failed")
			history.redo()
			if Store.signature(path) != saved_hash: _errors.append("native publication Redo changed bytes")
			hub.call("select_module", "action", "operations_editor_action")
			hub.call("begin_edit")
			await _frames(4)
			if hub.get("_session").draft.display_name != "Проверочная копия заслона": _errors.append("native Save/reopen failed")
			hub.call("discard_changes")
			Store.restore({"path": path, "exists": false})
			get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)
	hub.call("select_module", "item", "herb")
	hub.call("begin_edit")
	await _frames(8)
	await _capture("item-draft")
	hub.call("discard_changes")
	hub.call("select_module", "equipment", "traveler_tunic")
	hub.call("begin_edit")
	await _frames(8)
	var item_form := hub.find_child("GameSystemsItemDraft", true, false) as EmberItemEditor
	if item_form == null: _errors.append("unified armor form missing")
	else:
		(item_form.find_child("ItemHpBonus", true, false) as SpinBox).value = 15
		(item_form.find_child("ItemMpBonus", true, false) as SpinBox).value = -3
		var allowed := item_form.find_child("ItemAllowedHeroes", true, false) as LineEdit
		allowed.text = "mira"
		allowed.text_changed.emit(allowed.text)
		if hub.get("_session").draft.definition.get("allowedHeroIds") != ["mira"]: _errors.append("native compatibility input did not update draft")
		await _frames(6)
		if item_form.get_combined_minimum_size().x > item_form.size.x + 1: _errors.append("native item form overflows detail width")
		if hub.get_combined_minimum_size().x > hub.size.x + 1: _errors.append("native draft overflows editor width")
		await _capture("equipment-draft")
		var scroll := hub.get("_detail").get_parent() as ScrollContainer
		scroll.scroll_vertical = 300
		await _capture("equipment-properties")
		item_form.call("_show_preview", true)
		var preview := item_form.get("_preview") as Control
		var hero := preview.find_child("EquipmentPreviewHero", true, false) as OptionButton
		for index in hero.item_count:
			if str(hero.get_item_metadata(index)) == "mira":
				hero.select(index)
				hero.item_selected.emit(index)
		var armor := preview.find_child("EquipmentPreviewSlot_armor", true, false) as OptionButton
		for index in armor.item_count:
			if str(armor.get_item_metadata(index)) == "traveler_tunic":
				armor.select(index)
				armor.item_selected.emit(index)
		if preview.get("_comparison").changes.maxHp != 15: _errors.append("native fitting did not calculate unsaved HP delta")
		scroll.scroll_vertical = 0
		await _capture("fitting")
		scroll.scroll_vertical = 110
		await _capture("fitting-stats")
		hub.get("_draft_editor").call("_undo_draft")
		await _frames(6)
		item_form = hub.find_child("GameSystemsItemDraft", true, false) as EmberItemEditor
		if not item_form.get("_preview").visible or item_form.get("_preview").get("_comparison").hero != "mira": _errors.append("native Undo lost fitting view/hero")
		hub.call("discard_changes")
	await _start_forms(hub)
	await _status_forms(hub)
	await _action_forms(hub)
	await _encounter_forms(hub)
	await _library_check(hub)
	await _usage_navigation(hub)
	await _settle_filesystem()
	# Actual unload/reload, without touching the author checkout or scene drafts.
	EditorInterface.set_main_screen_editor("3D")
	EditorInterface.set_plugin_enabled("ember_import", false)
	await _frames(20)
	EditorInterface.set_plugin_enabled("ember_import", true)
	await _frames(30)
	workspace = EditorInterface.get_editor_main_screen().find_child("EmberGraphWorkspace", true, false)
	if workspace == null: _errors.append("plugin did not remount")
	else:
		workspace.open_resource("systems", "systems_library")
		EditorInterface.set_main_screen_editor("Ember Graph")
		await _frames(10)
		if not workspace.get("_game_systems_workspace").is_visible_in_tree(): _errors.append("remounted hub is hidden")
	EditorInterface.set_main_screen_editor("3D")
	EditorInterface.set_plugin_enabled("ember_import", false)
	await _frames(20)
	await _settle_filesystem()
	if not _errors.is_empty(): printerr("FAIL game systems editor: ", "; ".join(_errors))
	else: print("PASS game systems actual Forward+ modules, draft fields/Undo/Save/reopen, global publication Undo/Redo, item form, unload/reload")
	get_tree().quit(0 if _errors.is_empty() else 1)


func _effect_picker_forms(hub: Control) -> void:
	const EFFECT_ID := "editor_picker_conditional"
	const ACTION_ID := "editor_picker_action"
	var effect_path := Store.path_for("effect", EFFECT_ID)
	var action_path := Store.path_for("action", ACTION_ID)
	var effect := Store.clone(Catalog.Effects.resource("apply_frozen"))
	effect.effect_id = EFFECT_ID
	effect.display_name = "Заморозка мокрой цели"
	effect.description = "Дополнительный холодный шаг для проверки подбора."
	effect.target_required_status_ids = PackedStringArray(["wet"])
	if Store.write("effect", effect, effect_path) != OK:
		_errors.append("native picker fixture write failed")
		return
	hub.call("select_module", "action", "strike")
	var session = hub.get("_session")
	if not session.create("action", ACTION_ID, "Удар с условным холодом", Catalog.Actions.resource("strike")):
		_errors.append("native picker action draft failed")
		Store.restore({"path": effect_path, "exists": false})
		return
	hub.call("_mount_draft")
	var form := hub.get("_draft_editor") as Control
	var original: String = session.draft.content_signature()
	for query in [EFFECT_ID, "заморозка мокрой", "холодный шаг", "есть все: wet"]:
		var search := form.find_child("DraftEffectSearch", true, false) as LineEdit
		search.text = query
		search.text_changed.emit(query)
		var choice := form.find_child("DraftEffectChoice", true, false) as OptionButton
		var preview := form.find_child("DraftEffectPreview", true, false) as Label
		if choice.item_count != 1 or choice.selected != 0 or choice.get_item_metadata(0).effect_id != EFFECT_ID:
			_errors.append("native picker query failed: " + query)
		if "wet" not in preview.text or "Проверка до применения" not in preview.text or preview.tooltip_text != effect_path:
			_errors.append("native preview lost shared conditions/path")
	var all_search := form.find_child("DraftEffectSearch", true, false) as LineEdit
	all_search.text = ""
	all_search.text_changed.emit("")
	var all_choice := form.find_child("DraftEffectChoice", true, false) as OptionButton
	for index in all_choice.item_count:
		if str(all_choice.get_item_metadata(index).effect_id) == "apply_wet":
			all_choice.select(index)
			all_choice.item_selected.emit(index)
	if "apply_wet" not in (form.find_child("DraftEffectPreview", true, false) as Label).text: _errors.append("selection did not update effect preview")
	all_search.text = EFFECT_ID
	all_search.text_changed.emit(EFFECT_ID)
	if session.draft.content_signature() != original or session.can_undo(): _errors.append("search/selection changed Resource/history")
	await _frames(5)
	var scroll := hub.get("_detail").get_parent() as ScrollContainer
	var search := form.find_child("DraftEffectSearch", true, false) as LineEdit
	scroll.scroll_vertical += roundi(search.global_position.y - scroll.global_position.y - 55)
	await _capture("effect-picker-preview")
	if form.get_combined_minimum_size().x > form.size.x + 1: _errors.append("native picker width overflow")
	search.text = "nothing_matches_this_query"
	search.text_changed.emit(search.text)
	if not (form.find_child("DraftAddEffect", true, false) as Button).disabled or (form.find_child("DraftEffectChoice", true, false) as OptionButton).item_count != 0:
		_errors.append("empty search left actionable selection")
	await _capture("effect-picker-empty")
	search.text = EFFECT_ID
	search.text_changed.emit(search.text)
	(form.find_child("DraftAddEffect", true, false) as Button).pressed.emit()
	if session.draft.effect_steps.size() != 1 or session.draft.effect_steps[0].effect_id != EFFECT_ID: _errors.append("filtered Add used wrong shared effect")
	if (form.find_child("DraftEffectSearch", true, false) as LineEdit).text != EFFECT_ID or not (form.find_child("DraftAddEffect", true, false) as Button).disabled:
		_errors.append("Add lost filter or duplicate guard")
	await _capture("effect-picker-used")
	form.call("_undo_draft")
	if not session.draft.effect_steps.is_empty() or (form.find_child("DraftAddEffect", true, false) as Button).disabled: _errors.append("filtered Add Undo failed")
	form.call("_redo_draft")
	if session.draft.effect_steps.size() != 1 or not (form.find_child("DraftAddEffect", true, false) as Button).disabled: _errors.append("filtered Add Redo failed")
	hub.call("_save_draft")
	await _frames(5)
	var sha := Store.signature(action_path)
	var uid := ResourceLoader.get_resource_uid(action_path)
	hub.call("begin_edit")
	if session.draft == null or session.draft.effect_steps.size() != 1 or session.draft.effect_steps[0].target_required_status_ids != PackedStringArray(["wet"]):
		_errors.append("filtered shared step Save/reopen failed")
	if session.draft != null: session.set_value("display_name", "Несохранённое название")
	hub.call("discard_changes")
	if Store.signature(action_path) != sha or ResourceLoader.get_resource_uid(action_path) != uid: _errors.append("Discard changed saved action/UID")
	Store.restore({"path": action_path, "exists": false})
	Store.restore({"path": effect_path, "exists": false})
	get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)


func _start_forms(hub: Control) -> void:
	var path := Store.path_for("start", "default")
	var before := Store.snapshot(path)
	var uid := ResourceLoader.get_resource_uid(path)
	hub.call("select_module", "start", "default")
	hub.call("begin_edit")
	await _frames(6)
	var session = hub.get("_session")
	var form := hub.get("_draft_editor") as Control
	var tabs := form.find_child("StartHeroTabs", true, false) as TabContainer
	if tabs == null:
		_errors.append("native start form missing")
		return
	tabs.current_tab = 1
	(form.find_child("StartLevel_mira", true, false) as SpinBox).value = 7
	var armor := form.find_child("StartGear_mira_armor", true, false) as OptionButton
	for index in armor.item_count:
		if armor.get_item_metadata(index) == "traveler_tunic":
			armor.select(index)
			armor.item_selected.emit(index)
	(form.find_child("StartBagCount_coin", true, false) as SpinBox).value = 37
	var bag := form.find_child("StartBagAddItem", true, false) as OptionButton
	for index in bag.item_count:
		if bag.get_item_metadata(index) == "herb":
			bag.select(index)
			bag.item_selected.emit(index)
	(form.find_child("StartBagAdd", true, false) as Button).pressed.emit()
	(form.find_child("StartBagCount_herb", true, false) as SpinBox).value = 2
	form.call("_undo_draft")
	if session.draft.inventory.get("herb") != 1: _errors.append("native start Undo failed")
	form.call("_redo_draft")
	if session.draft.inventory.get("herb") != 2: _errors.append("native start Redo failed")
	(form.find_child("StartHeroTabs", true, false) as TabContainer).current_tab = 1
	await _frames(5)
	if form.get_combined_minimum_size().x > form.size.x + 1: _errors.append("native start form width overflow")
	if hub.get_combined_minimum_size().x > hub.size.x + 1: _errors.append("native start workspace width overflow")
	if (form.find_child("StartLevel_mira", true, false) as SpinBox).size.y > 60: _errors.append("native start grid labels forced tall rows")
	await _capture("start-game")
	var scroll := hub.get("_detail").get_parent() as ScrollContainer
	scroll.scroll_vertical = 400
	await _capture("start-game-bag")
	scroll.scroll_vertical = 0
	var saved: Resource = Store.clone(session.draft)
	var save := hub.find_child("GameSystemsDraftSave", true, false) as Button
	if save.disabled: _errors.append("native start Save disabled for valid recipe")
	else: save.pressed.emit()
	await _frames(5)
	if ResourceLoader.get_resource_uid(path) != uid: _errors.append("native start Save changed UID")
	hub.call("select_module", "start", "default")
	hub.call("begin_edit")
	await _frames(4)
	session = hub.get("_session")
	if session.draft.hero_levels != saved.hero_levels or session.draft.hero_equipment != saved.hero_equipment or session.draft.inventory != saved.inventory: _errors.append("native start Save/reopen lost data")
	form = hub.get("_draft_editor") as Control
	(form.find_child("StartLevel_mira", true, false) as SpinBox).value = 8
	hub.call("discard_changes")
	if preload("res://scripts/ember_game_start_resource.gd").saved().hero_levels.mira != 7: _errors.append("native start Discard wrote data")
	var history := get_undo_redo().get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	history.undo()
	if FileAccess.get_file_as_bytes(path) != before.bytes: _errors.append("native start publication Undo did not restore bytes")
	history.redo()
	if preload("res://scripts/ember_game_start_resource.gd").saved().inventory.get("herb") != 2: _errors.append("native start publication Redo lost bag")
	Store.restore(before)
	get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)
	hub.call("select_module", "start", "default")

func _settle_filesystem() -> void:
	# Fixture deletion and quit must not race an editor dependency scan.
	Filesystem.request()
	var deadline := Time.get_ticks_msec() + 10000
	var filesystem := EditorInterface.get_resource_filesystem()
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if Filesystem.diagnostics().pending == 0 and not filesystem.is_scanning() and not filesystem.is_importing(): return
	_errors.append("editor filesystem did not settle after fixture cleanup")

func _usage_navigation(hub: Control) -> void:
	var source_path := "res://content/combat/actions/editor_usage_duplicate.tres"
	var source := Store.clone(Catalog.Actions.resource("strike"))
	source.display_name = "Проверочный приём с тем же ID"
	source.effect_steps.assign([Catalog.Effects.resource("apply_wet")])
	if ResourceSaver.save(source, source_path) != OK:
		_errors.append("native usage source fixture failed")
		return
	Filesystem.request()
	Catalog.refresh()
	hub.call("select_module", "effect", "apply_wet")
	(hub.find_child("GameSystemsUsage", true, false) as Button).pressed.emit()
	var panel := hub.get("_usage_panel") as ConfirmationDialog
	await _frames(8)
	var search := panel.find_child("UsageSearch", true, false) as LineEdit
	search.text = "editor_usage_duplicate"
	search.text_changed.emit(search.text)
	var tree := panel.find_child("UsageRecords", true, false) as Tree
	var row := tree.get_root().get_first_child()
	if row == null:
		_errors.append("native usage filter lost exact incoming file")
	else:
		row.select(0)
		panel.call("_select")
		await _capture("usage-links", panel)
		if panel.size.y > 850 or panel.size.x > 1500: _errors.append("native usage dialog exceeds window")
		(panel.find_child("UsageOpen", true, false) as Button).pressed.emit()
		await _frames(4)
		if hub.call("selected_record").get("path") != source_path: _errors.append("native usage opened same-ID alias")
		if (hub.get("_detail").get_parent() as ScrollContainer).scroll_vertical != 0: _errors.append("usage destination kept previous card scroll")
		await _capture("usage-destination")
		(hub.find_child("GameSystemsUsageBack", true, false) as Button).pressed.emit()
		if hub.call("selected_record").get("id") != "apply_wet": _errors.append("native usage Back failed")
		hub.call("begin_edit")
		hub.get("_session").set_value("display_name", "Несохранённый эффект переходов")
		var consumer: Dictionary = row.get_metadata(0)
		hub.call("_show_usage", hub.call("selected_record"))
		hub.call("_open_usage_record", consumer)
		if not hub.has_unsaved_changes() or not panel.visible or not "В черновике" in str(panel.get("_detail").text): _errors.append("native usage navigation dropped dirty draft")
		await _capture("usage-dirty", panel)
		hub.call("discard_changes")
		panel.hide()
	panel.hide()
	# FileSystem route is exact and keeps the library selected, even for external consumers.
	hub.call("select_module", "effect", "apply_wet")
	hub.call("_show_usage", hub.call("selected_record"))
	var before := str(hub.call("selected_record").path)
	var file_source := {"path": source_path, "hash": FileAccess.get_sha256(source_path)}
	hub.call("_open_usage_file", file_source)
	await _frames(5)
	if source_path not in EditorInterface.get_selected_paths() or str(hub.call("selected_record").path) != before: _errors.append("native usage FileSystem route changed library or selected wrong file")
	await _settle_filesystem()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))
	Catalog.refresh()
	await _settle_filesystem()

func _periodic_forms(hub: Control) -> void:
	const ID := "periodic_fixture_poison"
	var path := Store.path_for("status", ID)
	hub.call("begin_new", "status", Catalog.Statuses.resource("poison"))
	hub.get("_create_id").text = ID
	hub.get("_create_name").text = "Яд проверки"
	hub.get("_create_dialog").confirmed.emit()
	hub.get("_create_dialog").hide()
	var session = hub.get("_session")
	var form := hub.get("_draft_editor") as Control
	var amount := form.find_child("DraftField_turn_end_hp_change", true, false) as SpinBox
	if amount == null:
		_errors.append("native periodic amount missing")
		return
	amount.value = -6
	form.call("_undo_draft")
	if session.draft.turn_end_hp_change != -5: _errors.append("native periodic Undo failed")
	form.call("_redo_draft")
	if session.draft.turn_end_hp_change != -6: _errors.append("native periodic Redo failed")
	if OS.get_environment("EMBER_GAME_SYSTEMS_EDITOR_FOCUS") == "stacks":
		(form.find_child("DraftField_max_stacks", true, false) as SpinBox).value = 3
		form.call("_undo_draft")
		if session.draft.max_stacks != 1: _errors.append("native dose limit Undo failed")
		form.call("_redo_draft")
		if session.draft.max_stacks != 3: _errors.append("native dose limit Redo failed")
	var scroll := hub.get("_detail").get_parent() as ScrollContainer
	await _frames(5)
	if OS.get_environment("EMBER_GAME_SYSTEMS_EDITOR_FOCUS") == "stacks":
		var limit := form.find_child("DraftField_max_stacks", true, false) as Control
		scroll.scroll_vertical += roundi(limit.global_position.y - scroll.global_position.y - 150)
		await _capture("status-dose-limit")
	amount = form.find_child("DraftField_turn_end_hp_change", true, false) as SpinBox
	scroll.scroll_vertical += roundi(amount.global_position.y - scroll.global_position.y - 230)
	await _frames(5)
	if form.get_combined_minimum_size().x > form.size.x + 1: _errors.append("periodic form width overflow")
	await _capture("periodic-status-form")
	hub.call("_save_draft")
	await _frames(5)
	var sha := Store.signature(path)
	var uid := ResourceLoader.get_resource_uid(path)
	hub.call("select_module", "status", ID)
	hub.call("begin_edit")
	form = hub.get("_draft_editor") as Control
	if session.draft == null or session.draft.turn_end_hp_change != -6: _errors.append("native periodic Save/reopen failed")
	if OS.get_environment("EMBER_GAME_SYSTEMS_EDITOR_FOCUS") == "stacks" and session.draft.max_stacks != 3: _errors.append("native stack limit lost at Save/reopen")
	(form.find_child("DraftField_turn_end_hp_change", true, false) as SpinBox).value = -9
	hub.call("discard_changes")
	if Store.signature(path) != sha: _errors.append("periodic Discard changed file")
	var history := get_undo_redo().get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	history.undo()
	if FileAccess.file_exists(path): _errors.append("periodic publication Undo did not remove new file")
	history.redo()
	if Store.signature(path) != sha or ResourceLoader.get_resource_uid(path) != uid: _errors.append("periodic publication Redo changed bytes/UID")
	get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)
	hub.call("select_module", "status", ID)

func _status_forms(hub: Control) -> void:
	hub.call("select_module", "status", "wet")
	var session = hub.get("_session")
	var path := Store.path_for("status", "editor_status_rules_fixture")
	if not session.create("status", "editor_status_rules_fixture", "Проверочный защитный статус"):
		_errors.append("native status rule draft could not start")
		return
	for pair in [["description", "Щит для проверки общих настроек поведения."], ["kind", StatusType.Kind.BUFF], ["reapply", StatusType.Reapply.EXTEND], ["max_duration", 6]]:
		session.set_value(pair[0], pair[1])
	hub.call("_mount_draft")
	var form := hub.get("_draft_editor") as Control
	var percent := form.find_child("DraftField_incoming_damage_percent", true, false) as SpinBox
	percent.value = 50
	if session.draft.incoming_damage_percent != 50: _errors.append("native rule field did not update draft")
	form.call("_undo_draft")
	if session.draft.incoming_damage_percent != 100: _errors.append("native rule Undo failed")
	form.call("_redo_draft")
	var scroll := hub.get("_detail").get_parent() as ScrollContainer
	scroll.scroll_vertical = 0
	await _capture("status-rules")
	scroll.scroll_vertical = 800
	await _capture("status-modifiers")
	hub.call("_save_draft")
	await _frames(5)
	hub.call("begin_edit")
	if session.draft == null or session.draft.incoming_damage_percent != 50 or session.draft.reapply != StatusType.Reapply.EXTEND:
		_errors.append("native status rules Save/reopen failed")
	hub.call("discard_changes")
	Store.restore({"path": path, "exists": false})
	get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)
	hub.call("select_module", "effect", "apply_wet")
	hub.call("begin_edit")
	form = hub.get("_draft_editor") as Control
	var picker := form.find_child("DraftField_status_id", true, false) as OptionButton
	if picker == null or str(picker.get_item_metadata(picker.selected)) != "wet": _errors.append("native effect lost named status picker")
	if (form.find_child("DraftField_force", true, false) as Control).visible: _errors.append("native status effect showed push fields")
	scroll.scroll_vertical = 320
	await _capture("effect-status")
	var operation := form.find_child("DraftField_operation", true, false) as OptionButton
	operation.select(EffectType.Operation.REMOVE_STATUS)
	operation.item_selected.emit(EffectType.Operation.REMOVE_STATUS)
	var choices := form.find_child("DraftField_remove_status_ids", true, false) as VBoxContainer
	(choices.find_child("DraftStatusChoice_wet", true, false) as CheckBox).button_pressed = true
	if "wet" not in session.draft.remove_status_ids or picker.visible: _errors.append("native removal checklist/conditional fields failed")
	scroll.scroll_vertical = 420
	await _capture("effect-remove")
	hub.call("discard_changes")


func _library_check(hub: Control) -> void:
	var path := "res://content/combat/statuses/editor_duplicate_wet.tres"
	var duplicate := Store.clone(Catalog.Statuses.resource("wet"))
	duplicate.display_name = "Проверочный дубликат Wet"
	if ResourceSaver.save(duplicate, path) != OK:
		_errors.append("native diagnostic duplicate fixture failed")
		return
	preload("res://addons/ember_import/ember_editor_filesystem.gd").request()
	hub.call("select_module", "status", "wet")
	hub.call("begin_edit")
	var session = hub.get("_session")
	session.set_value("display_name", "Несохранённый статус редактора")
	hub.call("_open_library_check")
	var panel := hub.get("_check_panel") as ConfirmationDialog
	for attempt in 200:
		await get_tree().create_timer(0.1).timeout
		if not panel.get("_service").running(): break
	var report: Dictionary = panel.get("_report")
	if not report.get("ok", false):
		_errors.append("native saved report failed: " + str(panel.get("_summary").text))
	else:
		if session.draft.display_name != "Несохранённый статус редактора" or not session.has_changes(): _errors.append("native scan changed dirty draft")
		var search := panel.find_child("LibraryCheckSearch", true, false) as LineEdit
		search.text = "editor_duplicate_wet"
		search.text_changed.emit(search.text)
		var tree := panel.find_child("LibraryCheckIssues", true, false) as Tree
		var row := tree.get_root().get_first_child()
		if row == null: _errors.append("native report filter lost duplicate file")
		else:
			row.select(0)
			panel.call("_select_issue")
			panel.call("_open_issue")
			if not session.has_changes() or not panel.visible: _errors.append("native diagnostic navigation dropped dirty draft")
			await _capture("library-check-dirty", panel)
			if panel.size.y > 900: _errors.append("native diagnostic feedback grew beyond viewport")
			var detail := panel.find_child("LibraryCheckDetail", true, false) as RichTextLabel
			var repeat := panel.find_child("LibraryCheckRepeat", true, false) as Button
			if not detail.text.contains("В черновике есть изменения") or repeat.get_global_rect().end.y > panel.size.y - 45:
				_errors.append("native diagnostic feedback or actions outside dialog")
			hub.call("discard_changes")
			panel.call("_select_issue")
			panel.call("_show_file")
			await _frames(5)
			if path not in EditorInterface.get_selected_paths(): _errors.append("native file route did not select exact duplicate path")
			panel.call("_open_issue")
			await _frames(6)
			var inspected := EditorInterface.get_inspector().get_edited_object() as Resource
			if inspected == null or inspected.resource_path != path: _errors.append("native Inspector opened an ID alias instead of exact source")
			panel.call("open_report")
			await _capture("library-check-report", panel)
	panel.hide()
	hub.call("discard_changes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Catalog.refresh()


func _action_forms(hub: Control) -> void:
	hub.call("select_module", "action", "douse")
	var session = hub.get("_session")
	var action_path := Store.path_for("action", "editor_action_constructor")
	var unit_path := Store.path_for("unit", "editor_action_assignment")
	if not session.create("action", "editor_action_constructor", "Лечебная вода"):
		_errors.append("native action constructor did not start")
		return
	for pair in [["hint", "Лечит союзника и накладывает Мокрый."], ["requirements_text", "Живой союзник в пределах дальности."], ["menu_group", ActionType.MenuGroup.MAGIC], ["element", ActionType.Element.WATER], ["effect", ActionType.Effect.EFFECT_CHAIN], ["target", ActionType.Target.ALLY], ["scaling", ActionType.Scaling.NONE], ["mp_cost", 2], ["delay", 145], ["range_cells", 2]]:
		session.set_value(pair[0], pair[1])
	hub.call("_mount_draft")
	var form := hub.get("_draft_editor") as Control
	for id in ["restore_major_hp", "apply_wet"]:
		var choice := form.find_child("DraftEffectChoice", true, false) as OptionButton
		for index in choice.item_count:
			if str(choice.get_item_metadata(index).effect_id) == id: choice.select(index)
		(form.find_child("DraftAddEffect", true, false) as Button).pressed.emit()
	(form.find_child("DraftRowUp_effect_steps_1", true, false) as Button).pressed.emit()
	if session.draft.effect_steps[0].effect_id != "apply_wet": _errors.append("native action step reorder failed")
	form.call("_undo_draft")
	if session.draft.effect_steps[0].effect_id != "restore_major_hp": _errors.append("native action step Undo failed")
	form.call("_redo_draft")
	var scroll := hub.get("_detail").get_parent() as ScrollContainer
	for subject_index in [0, 1]:
		var subject := form.find_child("DraftConditionSubject", true, false) as OptionButton
		subject.select(subject_index)
		subject.item_selected.emit(subject_index)
		var presence := form.find_child("DraftConditionPresence", true, false) as OptionButton
		presence.select(1)
		presence.item_selected.emit(1)
		var status := form.find_child("DraftConditionStatus", true, false) as OptionButton
		for index in status.item_count:
			if str(status.get_item_metadata(index)) == "frozen":
				status.select(index)
				status.item_selected.emit(index)
		(form.find_child("DraftAddCondition", true, false) as Button).pressed.emit()
	if session.draft.actor_forbidden_status_ids != PackedStringArray(["frozen"]) or session.draft.target_forbidden_status_ids != PackedStringArray(["frozen"]): _errors.append("native named predicates failed")
	(form.find_child("DraftRemoveCondition_target_forbidden_status_ids_frozen", true, false) as Button).pressed.emit()
	form.call("_undo_draft")
	if session.draft.target_forbidden_status_ids != PackedStringArray(["frozen"]): _errors.append("native predicate Undo failed")
	form.call("_redo_draft")
	if not session.draft.target_forbidden_status_ids.is_empty(): _errors.append("native predicate Redo failed")
	form.call("_undo_draft")
	await _frames(5)
	var numeric_stat := form.find_child("DraftValueStat", true, false) as OptionButton
	numeric_stat.select(1)
	numeric_stat.item_selected.emit(1)
	var numeric_measure := form.find_child("DraftValueUnit", true, false) as OptionButton
	numeric_measure.select(0)
	numeric_measure.item_selected.emit(0)
	(form.find_child("DraftValueThreshold", true, false) as SpinBox).value = 10
	(form.find_child("DraftAddValueCondition", true, false) as Button).pressed.emit()
	(form.find_child("DraftValueThreshold_0", true, false) as SpinBox).value = 12
	form.call("_undo_draft")
	if session.draft.value_conditions.size() != 1 or session.draft.value_conditions[0].value != 10: _errors.append("native numeric input Undo failed")
	form.call("_redo_draft")
	if session.draft.value_conditions[0].value != 12: _errors.append("native numeric input Redo failed")
	form.call("_undo_draft")
	var numeric_subject := form.find_child("DraftValueSubject", true, false) as OptionButton
	numeric_subject.select(1)
	numeric_subject.item_selected.emit(1)
	var numeric_compare := form.find_child("DraftValueComparison", true, false) as OptionButton
	numeric_compare.select(1)
	numeric_compare.item_selected.emit(1)
	(form.find_child("DraftValueThreshold", true, false) as SpinBox).value = 30
	(form.find_child("DraftAddValueCondition", true, false) as Button).pressed.emit()
	var conditions := form.find_child("DraftStatusConditions", true, false) as Control
	scroll.scroll_vertical += int(conditions.global_position.y - scroll.global_position.y) - 65
	await _capture("action-status-conditions")
	var numeric := form.find_child("DraftValueConditions", true, false) as Control
	scroll.scroll_vertical += int(numeric.global_position.y - scroll.global_position.y) - 65
	await _capture("action-value-conditions")
	var gear_item := form.find_child("DraftEquipmentItem", true, false) as OptionButton
	for index in gear_item.item_count:
		if str(gear_item.get_item_metadata(index)) == "traveler_tunic":
			gear_item.select(index)
			gear_item.item_selected.emit(index)
	(form.find_child("DraftAddEquipmentCondition", true, false) as Button).pressed.emit()
	var gear_slot := form.find_child("DraftEquipmentSlot_0", true, false) as OptionButton
	for index in gear_slot.item_count:
		if str(gear_slot.get_item_metadata(index)) == "armor":
			gear_slot.select(index)
			gear_slot.item_selected.emit(index)
	form.call("_undo_draft")
	if session.draft.equipment_conditions.size() != 1 or not session.draft.equipment_conditions[0].slot.is_empty(): _errors.append("native gear edit Undo failed")
	form.call("_redo_draft")
	if session.draft.equipment_conditions[0].slot != "armor": _errors.append("native gear edit Redo failed")
	var gear_mode := form.find_child("DraftEquipmentMode", true, false) as OptionButton
	gear_mode.select(2)
	gear_mode.item_selected.emit(2)
	gear_slot = form.find_child("DraftEquipmentSlot", true, false) as OptionButton
	for index in gear_slot.item_count:
		if str(gear_slot.get_item_metadata(index)) == "shoes":
			gear_slot.select(index)
			gear_slot.item_selected.emit(index)
	(form.find_child("DraftAddEquipmentCondition", true, false) as Button).pressed.emit()
	await _frames(5)
	var gear := form.find_child("DraftEquipmentConditions", true, false) as Control
	scroll.scroll_vertical += int(gear.global_position.y - scroll.global_position.y) - 65
	await _capture("action-equipment-conditions")
	scroll.scroll_vertical = 0
	await _capture("action-constructor")
	var steps := form.find_child("DraftField_effect_steps", true, false) as Control
	scroll.scroll_vertical += int(steps.global_position.y - scroll.global_position.y) - 45
	await _capture("action-steps")
	if form.get_combined_minimum_size().x > form.size.x + 1: _errors.append("native action constructor exceeds width")
	hub.call("_save_draft")
	await _frames(5)
	hub.call("begin_edit")
	if session.draft == null or session.draft.effect_steps.size() != 2 or session.draft.effect_steps[0].effect_id != "apply_wet": _errors.append("native ordered steps Save/reopen failed")
	if session.draft == null or session.draft.actor_forbidden_status_ids != PackedStringArray(["frozen"]) or session.draft.target_forbidden_status_ids != PackedStringArray(["frozen"]): _errors.append("native predicates Save/reopen failed")
	if session.draft == null or session.draft.value_conditions.size() != 2 or session.draft.value_conditions[0].stat != "mp" or session.draft.value_conditions[0].value != 10 or session.draft.value_conditions[1].unit != "percent" or session.draft.value_conditions[1].value != 30: _errors.append("native numeric rules Save/reopen failed")
	if session.draft == null or session.draft.equipment_conditions.size() != 2 or session.draft.equipment_conditions[0].item_id != "traveler_tunic" or session.draft.equipment_conditions[0].slot != "armor" or session.draft.equipment_conditions[1].mode != "empty": _errors.append("native gear rules Save/reopen failed")
	hub.call("discard_changes")
	hub.call("select_module", "unit", "mira")
	if not session.create("unit", "editor_action_assignment", "Автор лечебной воды", Catalog.Units.resource("mira")):
		_errors.append("native assignment draft did not start")
		return
	hub.call("_mount_draft")
	form = hub.get("_draft_editor") as Control
	var choice := form.find_child("DraftActionChoice", true, false) as OptionButton
	for index in choice.item_count:
		if str(choice.get_item_metadata(index)) == "editor_action_constructor": choice.select(index)
	(form.find_child("DraftAddAction", true, false) as Button).pressed.emit()
	if "editor_action_constructor" not in session.draft.action_ids: _errors.append("native action assignment failed")
	form.call("_undo_draft")
	if "editor_action_constructor" in session.draft.action_ids: _errors.append("native assignment Undo failed")
	form.call("_redo_draft")
	await _frames(5)
	var list := form.find_child("DraftField_action_ids", true, false) as Control
	scroll.scroll_vertical += int(list.global_position.y - scroll.global_position.y) - 45
	await _capture("action-assignment")
	if form.get_combined_minimum_size().x > form.size.x + 1: _errors.append("native assignment exceeds width")
	hub.call("_save_draft")
	await _frames(5)
	hub.call("begin_edit")
	if session.draft == null or "editor_action_constructor" not in session.draft.action_ids: _errors.append("native assignment Save/reopen failed")
	hub.call("discard_changes")
	Store.restore({"path": unit_path, "exists": false})
	Store.restore({"path": action_path, "exists": false})
	get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)

func _encounter_forms(hub: Control) -> void:
	hub.call("select_module", "loot", "swamp_spirit_drops")
	var session = hub.get("_session")
	var loot_id := "editor_loot_constructor"
	var enemy_id := "editor_enemy_constructor"
	var encounter_id := "editor_encounter_constructor"
	if not session.create("loot", loot_id, "Награды проверочного врага"):
		_errors.append("native loot draft failed")
		return
	hub.call("_mount_draft")
	var form := hub.get("_draft_editor") as Control
	(form.find_child("DraftAddLootRow", true, false) as Button).pressed.emit()
	var item := form.find_child("DraftLootItem_0", true, false) as OptionButton
	for index in item.item_count:
		if str(item.get_item_metadata(index)) == "herb":
			item.select(index)
			item.item_selected.emit(index)
	(form.find_child("DraftLoot_minimum_count_0", true, false) as SpinBox).value = 2
	(form.find_child("DraftLoot_maximum_count_0", true, false) as SpinBox).value = 2
	(form.find_child("DraftLoot_chance_percent_0", true, false) as SpinBox).value = 50
	form.call("_undo_draft")
	if session.draft.entries[0].chance_percent != 100: _errors.append("native loot chance Undo failed")
	form.call("_redo_draft")
	var scroll := hub.get("_detail").get_parent() as ScrollContainer
	await _frames(5)
	var entries := form.find_child("DraftField_entries", true, false) as Control
	scroll.scroll_vertical += int(entries.global_position.y - scroll.global_position.y) - 45
	await _capture("loot-rows")
	if form.get_combined_minimum_size().x > form.size.x + 1: _errors.append("loot form exceeds width")
	hub.call("_save_draft")
	await _frames(5)
	hub.call("begin_edit")
	if session.draft == null or session.draft.entries[0].chance_percent != 50 or session.draft.entries[0].item_id != "herb": _errors.append("native loot Save/reopen failed")
	hub.call("discard_changes")
	hub.call("select_module", "unit", "wisp")
	if not session.create("unit", enemy_id, "Проверочный враг", Catalog.Units.resource("wisp")):
		_errors.append("native enemy draft failed")
		return
	hub.call("_mount_draft")
	form = hub.get("_draft_editor") as Control
	var loot := form.find_child("DraftField_loot_table", true, false) as OptionButton
	for index in loot.item_count:
		var table := loot.get_item_metadata(index) as Resource
		if table != null and str(table.get("table_id")) == loot_id:
			loot.select(index)
			loot.item_selected.emit(index)
	if session.draft.loot_table == null or session.draft.loot_table.table_id != loot_id: _errors.append("native shared loot assignment failed")
	if form.find_child("DraftField_ai_profile_id", true, false) is not OptionButton: _errors.append("native AI assignment is not a library picker")
	await _frames(5)
	scroll.scroll_vertical += int(loot.global_position.y - scroll.global_position.y) - 145
	await _capture("enemy-links")
	hub.call("_save_draft")
	await _frames(5)
	hub.call("begin_edit")
	if session.draft == null or session.draft.loot_table.table_id != loot_id: _errors.append("native enemy Save/reopen failed")
	hub.call("discard_changes")
	var source := Catalog.Encounters.definition("colored_crossing_demo")
	hub.call("select_module", "encounter", "colored_crossing_demo")
	if not session.create("encounter", encounter_id, "Проверочная встреча", source):
		_errors.append("native encounter draft failed")
		return
	session.set_value("party_unit_ids", PackedStringArray(["mira", "orik"]))
	session.set_value("enemy_unit_ids", PackedStringArray())
	session.set_value("victory_xp", 11)
	hub.call("_mount_draft")
	form = hub.get("_draft_editor") as Control
	var enemies := form.find_child("DraftRoster_enemy_unit_idsChoice", true, false) as OptionButton
	for index in enemies.item_count:
		if str(enemies.get_item_metadata(index)) == enemy_id: enemies.select(index)
	(form.find_child("DraftAddRoster_enemy_unit_ids", true, false) as Button).pressed.emit()
	(form.find_child("DraftRoster_party_unit_idsUp_1", true, false) as Button).pressed.emit()
	form.call("_undo_draft")
	if session.draft.party_unit_ids[0] != "mira": _errors.append("native roster Undo failed")
	form.call("_redo_draft")
	scroll.scroll_vertical = 0
	await _capture("encounter-summary")
	var roster := form.find_child("DraftField_party_unit_ids", true, false) as Control
	scroll.scroll_vertical += int(roster.global_position.y - scroll.global_position.y) - 120
	await _capture("encounter-roster")
	if form.get_combined_minimum_size().x > form.size.x + 1: _errors.append("encounter form exceeds width")
	hub.call("_save_draft")
	await _frames(5)
	hub.call("begin_edit")
	if session.draft == null or session.draft.enemy_unit_ids != PackedStringArray([enemy_id]) or session.draft.party_unit_ids[0] != "orik" or session.draft.victory_xp != 11: _errors.append("native encounter Save/reopen lost composition")
	hub.call("discard_changes")
	# The actual editor route launches this saved fixture in a separate process.
	hub.call("select_module", "encounter", encounter_id)
	if hub.find_child("GameSystemsRunEncounter", true, false) == null: _errors.append("native encounter Lab button missing")
	await _capture("lab-launch")
	(hub.find_child("GameSystemsRunEncounter", true, false) as Button).pressed.emit()
	await _frames(5)
	var setup_dialog := hub.get("_lab_setup_dialog") as ConfirmationDialog
	if setup_dialog == null:
		_errors.append("native Lab setup dialog missing")
		return
	var hero_picker := setup_dialog.find_child("LabSetupHero", true, false) as OptionButton
	for index in hero_picker.item_count:
		if str(hero_picker.get_item_metadata(index)) == "mira":
			hero_picker.select(index)
			hero_picker.item_selected.emit(index)
	(setup_dialog.find_child("LabSetupCustom", true, false) as CheckBox).button_pressed = true
	(setup_dialog.find_child("LabSetupLevel", true, false) as SpinBox).value = 9
	var armor_picker := setup_dialog.find_child("LabSetupSlot_armor", true, false) as OptionButton
	for index in armor_picker.item_count:
		if str(armor_picker.get_item_metadata(index)) == "traveler_tunic":
			armor_picker.select(index)
			armor_picker.item_selected.emit(index)
	(setup_dialog.find_child("LabSetupCount_herb", true, false) as SpinBox).value = 3
	var test_setup: Dictionary = setup_dialog.call("snapshot")
	(setup_dialog.find_child("LabSetupUndo", true, false) as Button).pressed.emit()
	if setup_dialog.call("snapshot").get("inventory", {}).has("herb"): _errors.append("native Lab bag Undo failed")
	(setup_dialog.find_child("LabSetupRedo", true, false) as Button).pressed.emit()
	if setup_dialog.call("snapshot") != test_setup: _errors.append("native Lab bag Redo failed")
	var preset_path := "user://ember-tests/native-presets-%s.json" % ProjectSettings.globalize_path("res://").rstrip("/").get_file()
	setup_dialog.set("preset_store", LabPresets.new(preset_path))
	setup_dialog.call("_refresh_presets", "")
	var preset_name := setup_dialog.find_child("LabPresetName", true, false) as LineEdit
	preset_name.text = "Мира 9 · проверка снаряжения"
	preset_name.text_changed.emit(preset_name.text)
	(setup_dialog.find_child("LabPresetSave", true, false) as Button).pressed.emit()
	var preset_id := str(setup_dialog.get("_preset_id"))
	if preset_id.is_empty() or LabPresets.new(preset_path).read().records.size() != 1: _errors.append("native named preset Save failed")
	await _capture("lab-presets", setup_dialog)
	await _capture("lab-setup", setup_dialog)
	var setup_feedback := setup_dialog.find_child("LabSetupFeedback", true, false) as Label
	if setup_feedback.get_global_rect().end.y > setup_dialog.get_ok_button().global_position.y - 2:
		_errors.append("preset/body/feedback overlap the native launch/cancel buttons")
	if setup_dialog.size.x > 1500 or setup_dialog.size.y > 830: _errors.append("native Lab setup exceeds editor window")
	setup_dialog.hide()
	hub.call("_configure_selected_encounter")
	if not setup_dialog.call("snapshot").is_empty(): _errors.append("canceled Lab setup was remembered")
	# Recreate the dialog, load by saved ID, then launch that restored snapshot.
	setup_dialog.hide()
	setup_dialog.free()
	hub.set("_lab_setup_dialog", null)
	hub.call("_configure_selected_encounter")
	setup_dialog = hub.get("_lab_setup_dialog")
	setup_dialog.set("preset_store", LabPresets.new(preset_path))
	setup_dialog.call("_refresh_presets", "")
	var preset_picker := setup_dialog.find_child("LabPresetPicker", true, false) as OptionButton
	for index in preset_picker.item_count:
		if str(preset_picker.get_item_metadata(index)) == preset_id:
			preset_picker.select(index)
			preset_picker.item_selected.emit(index)
	(setup_dialog.find_child("LabPresetLoad", true, false) as Button).pressed.emit()
	if setup_dialog.call("snapshot") != test_setup: _errors.append("fresh native preset dialog lost saved party/bag")
	var launched: Dictionary = hub.call("_launch_configured_encounter", setup_dialog.call("snapshot"))
	if not launched.get("ok", false):
		_errors.append("native editor could not launch saved Lab: " + str(launched.get("error", "")))
	else:
		if setup_dialog.visible or hub.has_unsaved_changes(): _errors.append("launch left settings open or modified author draft")
		hub.call("_configure_selected_encounter")
		if setup_dialog.call("snapshot") != test_setup: _errors.append("launched Lab setup not remembered during editor session")
		setup_dialog.hide()
		var ready := false
		var ready_deadline := Time.get_ticks_msec() + 15000
		while Time.get_ticks_msec() < ready_deadline:
			await get_tree().process_frame
			if FileAccess.file_exists(launched.log) and ("EMBER_LIBRARY_LAB_READY " + encounter_id) in FileAccess.get_file_as_string(launched.log):
				ready = true
				break
		var repeated: Dictionary = hub.call("_run_selected_encounter")
		if repeated.get("ok", false): _errors.append("native launch allowed two simultaneous Lab processes")
		if OS.is_process_running(int(launched.pid)): OS.kill(int(launched.pid))
		# Godot's active log can be buffered/locked on Windows; verify again after
		# stopping only this test-owned child, when its file handle is closed.
		var log_text := ""
		var close_deadline := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < close_deadline:
			await get_tree().process_frame
			if FileAccess.file_exists(launched.log): log_text = FileAccess.get_file_as_string(launched.log)
			if ("EMBER_LIBRARY_LAB_READY " + encounter_id) in log_text and "EMBER_LIBRARY_LAB_SETUP " in log_text:
				ready = true
				break
		if not ready: _errors.append("spawned Lab did not consume selected saved encounter")
		if not "EMBER_LIBRARY_LAB_SETUP " in log_text: _errors.append("native editor child lost test settings")
		if not ready: print("LAB_CHILD_LOG_DIAGNOSTIC ", launched, " length=", log_text.length(), " text=", log_text)
	for pair in [["encounter", encounter_id], ["unit", enemy_id], ["loot", loot_id]]:
		Store.restore({"path": Store.path_for(pair[0], pair[1]), "exists": false})
	get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)
