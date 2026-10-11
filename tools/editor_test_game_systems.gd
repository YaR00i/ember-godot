@tool
extends EditorPlugin
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const StatusType = preload("res://scripts/prototypes/ember_combat_status_resource.gd")
const EffectType = preload("res://scripts/prototypes/ember_combat_effect_resource.gd")
const ActionType = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
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
	await _status_forms(hub)
	await _action_forms(hub)
	await _encounter_forms(hub)
	await _library_check(hub)
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
	if not _errors.is_empty(): printerr("FAIL game systems editor: ", "; ".join(_errors))
	else: print("PASS game systems actual Forward+ modules, draft fields/Undo/Save/reopen, global publication Undo/Redo, item form, unload/reload")
	get_tree().quit(0 if _errors.is_empty() else 1)

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
	var launched: Dictionary = hub.call("_run_selected_encounter")
	if not launched.get("ok", false):
		_errors.append("native editor could not launch saved Lab: " + str(launched.get("error", "")))
	else:
		var ready := false
		for attempt in 120:
			await get_tree().create_timer(0.1).timeout
			if FileAccess.file_exists(launched.log) and ("EMBER_LIBRARY_LAB_READY " + encounter_id) in FileAccess.get_file_as_string(launched.log):
				ready = true
				break
		var repeated: Dictionary = hub.call("_run_selected_encounter")
		if repeated.get("ok", false): _errors.append("native launch allowed two simultaneous Lab processes")
		if OS.is_process_running(int(launched.pid)): OS.kill(int(launched.pid))
		await _frames(10)
		# Godot's active log can be buffered/locked on Windows; verify again after
		# stopping only this test-owned child, when its file handle is closed.
		if not ready and FileAccess.file_exists(launched.log): ready = ("EMBER_LIBRARY_LAB_READY " + encounter_id) in FileAccess.get_file_as_string(launched.log)
		if not ready: _errors.append("spawned Lab did not consume selected saved encounter")
	for pair in [["encounter", encounter_id], ["unit", enemy_id], ["loot", loot_id]]:
		Store.restore({"path": Store.path_for(pair[0], pair[1]), "exists": false})
	get_undo_redo().clear_history(EditorUndoRedoManager.GLOBAL_HISTORY, false)
