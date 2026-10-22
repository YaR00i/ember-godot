@tool
extends EditorPlugin
const Fixture = preload("res://tools/fixtures/ember_game_systems_cycle_fixture.gd")
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Action = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const Filesystem = preload("res://addons/ember_import/ember_editor_filesystem.gd")
var _errors: Array[String] = []
var _hub: Control
var _session
var _form: Control

func _enter_tree() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for index in count: await get_tree().process_frame

func _new(module: String, id: String, title: String, source: Resource = null) -> void:
	_hub.call("begin_new", module, source)
	_hub.get("_create_id").text = id
	_hub.get("_create_name").text = title
	_hub.get("_create_dialog").confirmed.emit()
	_hub.get("_create_dialog").hide()
	_session = _hub.get("_session")
	_form = _hub.get("_draft_editor")
	_check(_session.draft != null and _session.is_new and not FileAccess.file_exists(Store.path_for(module, id)), "Create route failed: " + id)
	var description := _form.find_child("DraftField_description", true, false) as TextEdit
	if description != null:
		description.text = "Создано в общей библиотеке для сквозной проверки: " + title
		description.text_changed.emit()

func _number(name: String, value: float) -> void:
	var control := _form.find_child(name, true, false) as SpinBox
	if control == null:
		_check(false, "numeric control missing: " + name)
		return
	control.value = value

func _pick(name: String, id: String, resource_property := "") -> void:
	var control := _form.find_child(name, true, false) as OptionButton
	if control == null:
		_check(false, "picker missing: " + name)
		return
	for index in control.item_count:
		var metadata: Variant = control.get_item_metadata(index)
		var key := str(metadata.get(resource_property)) if metadata is Resource and not resource_property.is_empty() else str(metadata)
		if key == id:
			control.select(index)
			control.item_selected.emit(index)
			return
	_check(false, "picker choice missing: " + id)

func _save_reopen(module: String, id: String) -> bool:
	var errors := Store.validation(module, _session.draft)
	if not errors.is_empty():
		_check(false, "invalid author fixture " + id + ": " + "; ".join(errors))
		return false
	var save := _hub.find_child("GameSystemsDraftSave", true, false) as Button
	if save == null:
		_check(false, "native Save button missing: " + id)
		return false
	save.pressed.emit()
	var path := Store.path_for(module, id)
	if not FileAccess.file_exists(path):
		_check(false, "Save failed " + id + ": " + _session.last_error)
		return false
	var sha := Store.signature(path)
	var uid := ResourceLoader.get_resource_uid(path)
	_check(uid >= 0 and not _hub.has_unsaved_changes(), "Save lost UID/clean state " + id)
	_hub.call("select_module", module, id)
	_hub.call("begin_edit")
	_session = _hub.get("_session")
	_form = _hub.get("_draft_editor")
	_check(_session.draft != null and Store.id_for(module, _session.draft) == id and not _session.has_changes(), "Reopen failed " + id)
	_check(Store.signature(path) == sha and ResourceLoader.get_resource_uid(path) == uid, "Reopen wrote source " + id)
	print("CYCLE_AUTHOR_RECORD ", module, "/", id)
	return true

func _close() -> void:
	_hub.call("discard_changes")

func _capture(label: String) -> void:
	await _frames(8)
	RenderingServer.force_draw(false)
	var path := Fixture.DIRECTORY.path_join("author-" + label + ".png")
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
	print("CYCLE_CAPTURE ", ProjectSettings.globalize_path(path))

func _run() -> void:
	if not Fixture.guarded():
		printerr("FAIL cycle editor refused non-disposable project")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Fixture.DIRECTORY))
	await _frames(60)
	EditorInterface.set_main_screen_editor("Ember Graph")
	var workspace := EditorInterface.get_editor_main_screen().find_child("EmberGraphWorkspace", true, false)
	workspace.open_resource("systems", "systems_library")
	_hub = workspace.get("_game_systems_workspace")
	_new("equipment", Fixture.WEAPON, "Клинок проверки")
	_pick("ItemKind", "weapon_jrpg")
	_number("ItemAtk", 7)
	_number("ItemHpBonus", 6)
	_session.undo()
	_check(_session.draft.definition.get("hpBonus", 0) == 0, "weapon field Undo failed")
	_session.redo()
	if not _save_reopen("equipment", Fixture.WEAPON):
		await _finish()
		return
	_check(_session.draft.definition.kind == "weapon_jrpg" and int(_session.draft.definition.atk) == 7 and int(_session.draft.definition.hpBonus) == 6, "weapon values lost at reopen")
	await _capture("weapon")
	_close()
	_new("equipment", Fixture.SHOES, "Сапоги проверки")
	_pick("ItemKind", "shoes")
	_number("ItemMoveBonus", 1)
	_number("ItemJumpBonus", 1)
	_number("ItemPushResistanceBonus", 2)
	_number("ItemWetResistanceBonus", 1)
	await _frames(5)
	var scroll := _hub.get("_detail").get_parent() as ScrollContainer
	var number := _form.find_child("ItemMoveBonus", true, false) as SpinBox
	scroll.scroll_vertical += roundi(number.global_position.y - scroll.global_position.y - 90)
	await _capture("shoes-fields")
	_form.find_child("GameSystemsItemDraft", true, false).call("_show_preview", true)
	var fitting := _form.find_child("ItemEquipmentPreview", true, false)
	var changes: Dictionary = fitting.get("_comparison").changes
	_check(changes.get("moveRange") == 1 and changes.get("jumpHeight") == 1 and changes.get("pushResistance") == 2 and changes.get("statusResistances.wet") == 1, "footwear fitting differs from draft")
	await _frames(5)
	var table := fitting.find_child("EquipmentPreviewStats", true, false) as Control
	scroll.scroll_vertical += roundi(table.global_position.y + table.size.y - scroll.global_position.y - scroll.size.y + 50)
	await _capture("shoes-fitting")
	if not _save_reopen("equipment", Fixture.SHOES):
		await _finish()
		return
	_check(_session.draft.definition.moveBonus == 1 and _session.draft.definition.wetResistanceBonus == 1, "footwear properties lost at Save/reopen")
	_close()
	_new("item", Fixture.POTION, "Настой проверки", load("res://content/items/herb.tres"))
	_number("ItemHpRestore", 4)
	_number("ItemStackMax", 9)
	if not _save_reopen("item", Fixture.POTION):
		await _finish()
		return
	_check(int(_session.draft.definition.stackMax) == 9 and int(_session.draft.definition.hpRestore) == 4, "consumable values lost at reopen")
	_close()
	_hub.call("select_module", "start", "default")
	_hub.call("begin_edit")
	_session = _hub.get("_session")
	_form = _hub.get("_draft_editor")
	_pick("StartGear_mira_weapon", Fixture.WEAPON)
	_pick("StartGear_mira_shoes", Fixture.SHOES)
	_number("StartBagCount_coin", 27)
	_pick("StartBagAddItem", Fixture.POTION)
	(_form.find_child("StartBagAdd", true, false) as Button).pressed.emit()
	_number("StartBagCount_" + Fixture.POTION, 3)
	if not _save_reopen("start", "default"):
		await _finish()
		return
	_check(_session.draft.hero_equipment.mira.weapon == Fixture.WEAPON and _session.draft.inventory.get(Fixture.POTION) == 3, "start recipe lost at reopen")
	await _capture("start")
	_close()
	_new("status", Fixture.STATUS, "Метка проверки")
	_number("DraftField_default_duration", 3)
	_number("DraftField_incoming_damage_percent", 125)
	_number("DraftField_turn_end_hp_change", -1)
	_number("DraftField_max_stacks", 2)
	if not _save_reopen("status", Fixture.STATUS):
		await _finish()
		return
	_close()
	_new("effect", Fixture.EFFECT, "Наложить метку проверки")
	_pick("DraftField_status_id", Fixture.STATUS)
	var conditional := _form.find_child("DraftField_target_forbidden_status_ids", true, false).find_child("DraftStatusChoice_burning", true, false) as CheckBox
	conditional.button_pressed = true
	_form.call("_undo_draft")
	_check(_session.draft.target_forbidden_status_ids.is_empty(), "effect condition Undo failed")
	_form.call("_redo_draft")
	_check(_session.draft.target_forbidden_status_ids == PackedStringArray(["burning"]), "effect condition Redo failed")
	var condition_field := _form.find_child("DraftField_target_required_status_ids", true, false) as Control
	var condition_scroll := _hub.get("_detail").get_parent() as ScrollContainer
	await _frames(5)
	condition_scroll.scroll_vertical += roundi(condition_field.global_position.y - condition_scroll.global_position.y - 150)
	await _capture("effect-conditions")
	var forbidden_field := _form.find_child("DraftField_target_forbidden_status_ids", true, false) as Control
	condition_scroll.scroll_vertical += roundi(forbidden_field.global_position.y - condition_scroll.global_position.y - 150)
	await _capture("effect-conditions-forbidden")
	_check(_form.get_combined_minimum_size().x <= _form.size.x + 1, "effect conditions form width overflow")
	if not _save_reopen("effect", Fixture.EFFECT):
		await _finish()
		return
	_check(_session.draft.status_id == Fixture.STATUS and _session.draft.target_forbidden_status_ids == PackedStringArray(["burning"]), "effect/status predicate reference lost")
	_close()
	_new("action", Fixture.ACTION, "Удар с меткой", Catalog.Actions.resource("strike"))
	_number("DraftField_power", 8)
	_number("DraftField_mp_cost", 2)
	_number("DraftField_range_cells", 6)
	_number("DraftField_accuracy_modifier", 50)
	_pick("DraftEffectChoice", Fixture.EFFECT, "effect_id")
	(_form.find_child("DraftAddEffect", true, false) as Button).pressed.emit()
	var presence := _form.find_child("DraftConditionPresence", true, false) as OptionButton
	presence.select(1)
	presence.item_selected.emit(1)
	_pick("DraftConditionStatus", "frozen")
	(_form.find_child("DraftAddCondition", true, false) as Button).pressed.emit()
	_number("DraftValueThreshold", 1)
	(_form.find_child("DraftAddValueCondition", true, false) as Button).pressed.emit()
	_pick("DraftEquipmentItem", Fixture.WEAPON)
	(_form.find_child("DraftAddEquipmentCondition", true, false) as Button).pressed.emit()
	(_form.find_child("DraftAddConditionGroup", true, false) as Button).pressed.emit()
	var group_subject := _form.find_child("DraftConditionSubject", true, false) as OptionButton
	group_subject.select(1)
	group_subject.item_selected.emit(1)
	_pick("DraftConditionStatus", "wet")
	(_form.find_child("DraftAddCondition", true, false) as Button).pressed.emit()
	group_subject = _form.find_child("DraftConditionSubject", true, false)
	group_subject.select(1)
	group_subject.item_selected.emit(1)
	var group_presence := _form.find_child("DraftConditionPresence", true, false) as OptionButton
	group_presence.select(1)
	group_presence.item_selected.emit(1)
	_pick("DraftConditionStatus", "frozen")
	(_form.find_child("DraftAddCondition", true, false) as Button).pressed.emit()
	_pick("DraftConditionGroupMode", "all")
	_form.call("_undo_draft")
	_check(_session.draft.condition_groups[0].mode == "any", "native group mode Undo failed")
	_form.call("_redo_draft")
	_check(_session.draft.condition_groups[0].mode == "all", "native group mode Redo failed")
	_pick("DraftConditionGroupMode", "any")
	await _frames(4)
	var group_control := _form.find_child("DraftStatusConditions", true, false) as Control
	var group_scroll := _hub.get("_detail").get_parent() as ScrollContainer
	group_scroll.scroll_vertical += roundi(group_control.global_position.y - group_scroll.global_position.y - 30)
	_check(group_control.size.x <= group_scroll.size.x + 2 and _hub.get_combined_minimum_size().x <= _hub.size.x + 1, "native group controls overflow form width")
	await _capture("condition-groups")
	if not _save_reopen("action", Fixture.ACTION):
		await _finish()
		return
	_check(_session.draft.effect_steps.size() == 1 and _session.draft.effect_steps[0].effect_id == Fixture.EFFECT and _session.draft.mp_cost == 2, "shared action chain lost at reopen")
	_check(_session.draft.actor_forbidden_status_ids == PackedStringArray(["frozen"]), "saved action predicate lost at reopen")
	_check(_session.draft.value_conditions.size() == 1 and _session.draft.value_conditions[0].value == 1, "saved numeric predicate lost at reopen")
	_check(_session.draft.equipment_conditions.size() == 1 and _session.draft.equipment_conditions[0].item_id == Fixture.WEAPON, "saved gear predicate lost at reopen")
	_check(_session.draft.condition_groups.size() == 1 and _session.draft.condition_groups[0].mode == "any" and _session.draft.condition_groups[0].target_required_status_ids == PackedStringArray(["wet"]), "native saved OR group lost at reopen")
	await _capture("action")
	_number("DraftField_mp_cost", 99)
	_close()
	_check(Catalog.Actions.resource(Fixture.ACTION).mp_cost == 2, "Discard changed published action")
	_new("ai", Fixture.AI, "ИИ проверки")
	if not _save_reopen("ai", Fixture.AI):
		await _finish()
		return
	_close()
	_new("loot", Fixture.LOOT, "Лут проверки")
	(_form.find_child("DraftAddLootRow", true, false) as Button).pressed.emit()
	_pick("DraftLootItem_0", Fixture.POTION)
	_number("DraftLoot_maximum_count_0", 2)
	_number("DraftLoot_minimum_count_0", 2)
	if not _save_reopen("loot", Fixture.LOOT):
		await _finish()
		return
	_check(_session.draft.entries[0].item_id == Fixture.POTION and _session.draft.entries[0].minimum_count == 2, "loot row lost at reopen")
	_close()
	_new("unit", Fixture.ENEMY, "Страж проверки", Catalog.Units.resource("wisp"))
	_number("DraftField_max_hp", 40)
	_session.set_value("action_ids", PackedStringArray(["defend"]))
	_hub.call("_mount_draft")
	_form = _hub.get("_draft_editor")
	_pick("DraftField_ai_profile_id", Fixture.AI)
	_pick("DraftField_loot_table", Fixture.LOOT, "table_id")
	if not _save_reopen("unit", Fixture.ENEMY):
		await _finish()
		return
	_check(_session.draft.loot_table.table_id == Fixture.LOOT and _session.draft.ai_profile_id == Fixture.AI, "enemy links lost at reopen")
	_close()
	_hub.call("select_module", "unit", "mira")
	_hub.call("begin_edit")
	_session = _hub.get("_session")
	_form = _hub.get("_draft_editor")
	_pick("DraftActionChoice", Fixture.ACTION)
	(_form.find_child("DraftAddAction", true, false) as Button).pressed.emit()
	if not _save_reopen("unit", "mira"):
		await _finish()
		return
	_check(Fixture.ACTION in _session.draft.action_ids, "hero assignment lost at reopen")
	_close()
	_new("field", Fixture.FIELD, "Поле проверки")
	if not _save_reopen("field", Fixture.FIELD):
		await _finish()
		return
	_close()
	_new("encounter", Fixture.ENCOUNTER, "Встреча полного цикла", Catalog.Encounters.definition("colored_crossing_demo"))
	for pair in [["party_unit_ids", PackedStringArray(["mira"])], ["enemy_unit_ids", PackedStringArray([Fixture.ENEMY])], ["victory_action_script_id", ""], ["victory_flag_id", "cycle_won"], ["repeatable", false]]: _session.set_value(pair[0], pair[1])
	_hub.call("_mount_draft")
	_form = _hub.get("_draft_editor")
	_pick("DraftField_battlefield", Fixture.FIELD, "field_id")
	_pick("DraftField_arena_scene", Fixture.ARENA, "resource_path")
	_number("DraftField_victory_xp", 35)
	for index in 2:
		_pick("DraftRoster_enemy_unit_idsChoice", Fixture.ENEMY)
		(_form.find_child("DraftAddRoster_enemy_unit_ids", true, false) as Button).pressed.emit()
	_form.call("_undo_draft")
	_check(_session.draft.enemy_unit_ids.size() == 2, "duplicate enemy Undo failed")
	_form.call("_redo_draft")
	_check(_session.draft.enemy_unit_ids.size() == 3, "duplicate enemy Redo failed")
	await _frames(4)
	var roster_control := _form.find_child("DraftField_enemy_unit_ids", true, false) as Control
	var roster_scroll := _hub.get("_detail").get_parent() as ScrollContainer
	roster_scroll.scroll_vertical += roundi(roster_control.global_position.y - roster_scroll.global_position.y - 40)
	_check(_hub.get_combined_minimum_size().x <= _hub.size.x + 1, "enemy roster exceeds workspace width")
	await _capture("enemy-instances")
	if not _save_reopen("encounter", Fixture.ENCOUNTER):
		await _finish()
		return
	_check(_session.draft.battlefield.field_id == Fixture.FIELD and _session.draft.enemy_unit_ids == PackedStringArray([Fixture.ENEMY, Fixture.ENEMY, Fixture.ENEMY]) and _session.draft.victory_xp == 35, "encounter composition lost at reopen")
	_check(_session.draft.arena_scene.resource_path == Fixture.ARENA, "selected arena lost at Save/reopen")
	await _capture("encounter")
	_close()
	var manifest := {"hashes": {}, "uids": {}, "editorPid": OS.get_process_id()}
	for pair in Fixture.RECORDS:
		var path := Store.path_for(pair[0], pair[1])
		manifest.hashes[path] = Store.signature(path)
		manifest.uids[path] = str(ResourceLoader.get_resource_uid(path))
	manifest.hashes[Fixture.ARENA] = Store.signature(Fixture.ARENA)
	manifest.uids[Fixture.ARENA] = str(ResourceLoader.get_resource_uid(Fixture.ARENA))
	_check(Fixture.write_json(Fixture.MANIFEST, manifest) == OK, "author manifest write failed")
	await _finish()

func _finish() -> void:
	Filesystem.request()
	var deadline := Time.get_ticks_msec() + 10000
	var filesystem := EditorInterface.get_resource_filesystem()
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if Filesystem.diagnostics().pending == 0 and not filesystem.is_scanning() and not filesystem.is_importing(): break
	if _errors.is_empty(): print("PASS game systems cycle author: native Create/forms/Save/Discard/reopen, shared refs/assignment and saved UID/hash manifest")
	else: printerr("FAIL cycle author: ", "; ".join(_errors))
	get_tree().quit(0 if _errors.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)
