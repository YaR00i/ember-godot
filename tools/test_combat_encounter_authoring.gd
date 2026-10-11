extends SceneTree
## Detached authoring of loot -> enemy -> encounter; native state/AI/result projection.
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Result = preload("res://scripts/prototypes/ember_combat_result.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const LOOT_ID := "authoring_fixture_loot"
const UNIT_ID := "authoring_fixture_enemy"
const ENCOUNTER_ID := "authoring_fixture_encounter"
var _errors: Array[String] = []
var _history := UndoRedo.new()
var _session
var _form: Control

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL encounter authoring refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1280, 720)
	Maps.prepare(self, "user://encounter-authoring-%d" % OS.get_process_id())
	_run.call_deferred()

func _run() -> void:
	_session = Session.new()
	_session.configure(_history)
	_test_loot()
	_test_enemy()
	_test_encounter()
	_session.discard()
	_form.free()
	_history.clear_history(false)
	_history.free()
	for pair in [["encounter", ENCOUNTER_ID], ["unit", UNIT_ID], ["loot", LOOT_ID]]:
		Store.restore({"path": Store.path_for(pair[0], pair[1]), "exists": false})
	if _errors.is_empty(): print("PASS game systems encounter authoring: named loot/AI/field/arena/rosters, missing/shared refs, row/roster Undo/Redo/validation/UID/save/reopen/discard, native deployment/AI and deterministic victory XP/loot")
	else: printerr("FAIL encounter authoring: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _mount() -> void:
	if _form != null: _form.free()
	_form = Form.new()
	root.add_child(_form)
	_form.setup(_session)

func _pick(name: String, value: Variant, resource := false) -> void:
	var choice := _form.find_child(name, true, false) as OptionButton
	if choice == null:
		_check(false, "missing picker " + name)
		return
	for index in choice.item_count:
		var actual: Variant = choice.get_item_metadata(index)
		if actual == value or (resource and actual != null and value != null and actual.resource_path == value.resource_path):
			choice.select(index)
			choice.item_selected.emit(index)
			return
	_check(false, "missing choice in " + name)

func _number(name: String, value: float) -> void:
	(_form.find_child(name, true, false) as SpinBox).value = value

func _test_loot() -> void:
	_check(_session.create("loot", LOOT_ID, "Награды проверочного врага"), "create loot failed")
	_mount()
	(_form.find_child("DraftAddLootRow", true, false) as Button).pressed.emit()
	_pick("DraftLootItem_0", "herb")
	_number("DraftLoot_minimum_count_0", 2)
	_number("DraftLoot_maximum_count_0", 2)
	_number("DraftLoot_chance_percent_0", 50)
	_form.call("_undo_draft")
	_check(_session.draft.entries[0].chance_percent == 100, "chance Undo failed")
	_form.call("_redo_draft")
	_number("DraftLoot_chance_percent_0", 100)
	(_form.find_child("DraftAddLootRow", true, false) as Button).pressed.emit()
	_pick("DraftLootItem_1", "coin")
	_number("DraftLoot_minimum_count_1", 3)
	_number("DraftLoot_maximum_count_1", 3)
	(_form.find_child("DraftRowUp_entries_1", true, false) as Button).pressed.emit()
	_check(_session.draft.entries[0].item_id == "coin", "loot reorder failed")
	_form.call("_undo_draft")
	_number("DraftLoot_minimum_count_0", 5)
	_check(not _session.save(), "invalid quantity published")
	_form.call("_undo_draft")
	_check(_session.draft.entries[0].minimum_count == 2, "quantity Undo lost previous row")
	var missing := Store.clone(_session.draft.entries[0])
	missing.item_id = "missing_saved_item"
	var rows: Array = _session.draft.entries.duplicate()
	rows[0] = missing
	_session.set_value("entries", rows)
	_mount()
	var picker := _form.find_child("DraftLootItem_0", true, false) as OptionButton
	_check(picker.get_item_metadata(picker.selected) == "missing_saved_item" and not _session.save(), "missing item dropped or published")
	_pick("DraftLootItem_0", "herb")
	_check(_session.save(), "loot Save failed: " + _session.last_error)
	var path := Store.path_for("loot", LOOT_ID)
	var sha := Store.signature(path)
	var uid := ResourceLoader.get_resource_uid(path)
	_history.undo()
	_check(not FileAccess.file_exists(path), "loot publication Undo failed")
	_history.redo()
	_check(Store.signature(path) == sha and ResourceLoader.get_resource_uid(path) == uid, "loot publication Redo changed bytes/UID")
	var table := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberCombatLootTableResource
	_check(table.entries[0].item_id == "herb" and table.entries[0].minimum_count == 2 and table.roll("fixed") == table.roll("fixed"), "loot reopen/determinism failed")
	_session.discard()

func _test_enemy() -> void:
	_check(_session.create("unit", UNIT_ID, "Проверочный враг", Catalog.Units.resource("wisp")), "create enemy failed")
	_mount()
	var profile := Catalog.Ai.resources()[0]
	_pick("DraftField_ai_profile_id", profile.profile_id)
	_pick("DraftField_loot_table", Catalog.Loot.resource(LOOT_ID), true)
	_check(_session.draft.loot_table.table_id == LOOT_ID, "loot assignment failed")
	_form.call("_undo_draft")
	_check(_session.draft.loot_table.table_id != LOOT_ID, "shared loot Undo failed")
	_form.call("_redo_draft")
	var external := Store.clone(_session.draft.loot_table)
	_session.set_value("loot_table", external)
	_mount()
	var choice := _form.find_child("DraftField_loot_table", true, false) as OptionButton
	_check(choice.get_item_metadata(choice.selected) == external, "inline shared ref dropped by picker")
	_pick("DraftField_loot_table", Catalog.Loot.resource(LOOT_ID), true)
	_check(_session.save(), "enemy Save failed: " + _session.last_error)
	var enemy := Catalog.Units.resource(UNIT_ID)
	_check(enemy.ai_profile_id == profile.profile_id and enemy.loot_table.resource_path == Store.path_for("loot", LOOT_ID), "enemy native refs failed reopen")
	_session.set_value("max_hp", 300)
	_session.discard()
	_check(Catalog.Units.resource(UNIT_ID).max_hp != 300, "Discard wrote enemy HP")

func _test_encounter() -> void:
	var source := Catalog.Encounters.definition("colored_crossing_demo")
	_check(_session.create("encounter", ENCOUNTER_ID, "Проверочная встреча", source), "create encounter failed")
	_session.set_value("party_unit_ids", PackedStringArray(["mira", "orik"]))
	_session.set_value("enemy_unit_ids", PackedStringArray())
	_session.set_value("victory_xp", 7)
	_session.set_value("victory_action_script_id", "")
	_mount()
	_pick("DraftRoster_enemy_unit_idsChoice", UNIT_ID)
	(_form.find_child("DraftAddRoster_enemy_unit_ids", true, false) as Button).pressed.emit()
	var enemies := _form.find_child("DraftRoster_enemy_unit_idsChoice", true, false) as OptionButton
	for index in enemies.item_count:
		_check(Catalog.Units.resource(str(enemies.get_item_metadata(index))).team_id() == "enemy" and str(enemies.get_item_metadata(index)) != UNIT_ID, "roster offered wrong side or duplicate")
	(_form.find_child("DraftRoster_party_unit_idsUp_1", true, false) as Button).pressed.emit()
	_check(_session.draft.party_unit_ids[0] == "orik", "party order failed")
	_form.call("_undo_draft")
	_form.call("_redo_draft")
	_pick("DraftField_battlefield", source.battlefield, true)
	_pick("DraftField_arena_scene", source.arena_scene, true)
	_check(_session.draft.battlefield == source.battlefield and _session.draft.arena_scene == source.arena_scene, "field/arena refs changed")
	_session.set_value("victory_rule", 8)
	_mount()
	_check(not _session.save(), "unsupported outcome rule published")
	var rule := _form.find_child("DraftField_victory_rule", true, false) as OptionButton
	rule.select(0)
	rule.item_selected.emit(0)
	_check(_session.save(), "encounter Save failed: " + _session.last_error)
	var encounter := ResourceLoader.load(Store.path_for("encounter", ENCOUNTER_ID), "", ResourceLoader.CACHE_MODE_IGNORE) as EmberEncounterResource
	var state := encounter.initial_state({}, 77)
	_check(state.units.size() == 3 and state.units.orik.cell == source.battlefield.party_deployment_cells[0] and state.units.mira.cell == source.battlefield.party_deployment_cells[1], "native roster deployment lost order")
	for id in state.units: state.units[id].nextAt = 1000.0
	state.units[UNIT_ID].nextAt = 0.0
	var before := state.duplicate(true)
	var command := Grid.enemy_command(state)
	_check(command.get("ok", false) and state == before, "authored AI command invalid or mutated state")
	state.units[UNIT_ID].hp = 0
	var report := Result.build(encounter, state, "victory")
	_check(report == Result.build(encounter, state, "victory") and report.xpReward == 7, "reward preview changed or lost XP")
	_check(report.xpRows.size() == 2, "XP projection omitted active heroes")
	for row in report.xpRows: _check(row.xpGained == 7, "XP was split instead of granted equally")
	var counts := {}
	for row in report.lootRewards: counts[row.itemId] = row.count
	_check(counts.get("herb", 0) == 2 and counts.get("coin", 0) == 3, "new enemy did not use authored guaranteed loot")
	var defeat := Result.build(encounter, state, "defeat")
	_check(defeat.lootRewards.is_empty() and defeat.xpReward == 0, "defeat granted victory rewards")

func _check(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)
