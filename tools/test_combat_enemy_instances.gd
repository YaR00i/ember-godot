extends SceneTree
## One saved template, three independently targetable enemies and per-instance loot.
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Result = preload("res://scripts/prototypes/ember_combat_result.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Inspector = preload("res://addons/ember_import/ember_encounter_inspector_panel.gd")
const ID := "instances_fixture_enemy"
const ENCOUNTER := "instances_fixture_encounter"
var _errors: Array[String] = []
var _paths: Array[String] = []
var _history := UndoRedo.new()
var _encounter: EmberEncounterResource

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL instance gate refused non-disposable project")
		quit.call_deferred(2)
		return
	Maps.prepare(self, "user://instances-%d" % OS.get_process_id())
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: _errors.append(message)

func _pick(form: Control, id: String) -> void:
	var choice := form.find_child("DraftRoster_enemy_unit_idsChoice", true, false) as OptionButton
	for index in choice.item_count:
		if str(choice.get_item_metadata(index)) == id:
			choice.select(index)
			return
	_check(false, "existing enemy template missing from picker")

func _run() -> void:
	_authoring()
	if _encounter != null: _runtime()
	_history.clear_history(false)
	_history.free()
	_paths.reverse()
	for path in _paths: Store.restore({"path": path, "exists": false})
	if _errors.is_empty(): print("PASS game systems enemy instances: saved repeated template rows, form/Inspector/Undo/Redo/Discard/Save/reopen/UID/usage, deterministic collision-safe local IDs, independent HP/MP/status/cells/turns, AI/preview/commit, per-instance loot/counters, unchanged unique roster and hero guards")
	else: printerr("FAIL enemy instances: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _authoring() -> void:
	var template := Store.clone(Store.Catalog.Units.resource("wisp"))
	template.unit_id = ID
	template.display_name = "Огонёк экземпляров"
	var table = preload("res://scripts/prototypes/ember_combat_loot_table_resource.gd").new()
	table.table_id = "instances_fixture_loot"
	table.display_name = "Лут экземпляров"
	table.description = "Гарантированно две монеты с каждого врага."
	var entry = preload("res://scripts/prototypes/ember_combat_loot_entry_resource.gd").new()
	entry.item_id = "coin"
	entry.minimum_count = 2
	entry.maximum_count = 2
	table.entries.append(entry)
	_paths.append(Store.path_for("loot", table.table_id))
	_check(Store.write("loot", table, _paths.back()) == OK, "loot fixture failed")
	template.loot_table = Store.Catalog.Loot.resource(table.table_id)
	_paths.append(Store.path_for("unit", ID))
	_check(Store.write("unit", template, _paths.back()) == OK, "unit fixture failed")
	var session := Session.new()
	session.configure(_history)
	_check(session.create("encounter", ENCOUNTER, "Три одинаковых врага", Store.Catalog.Encounters.definition("colored_crossing_demo")), "encounter draft failed")
	_paths.append(session.path)
	session.set_value("party_unit_ids", PackedStringArray(["mira"]))
	session.set_value("enemy_unit_ids", PackedStringArray())
	var form := Form.new()
	root.add_child(form)
	form.setup(session)
	for index in 3:
		_pick(form, ID)
		(form.find_child("DraftAddRoster_enemy_unit_ids", true, false) as Button).pressed.emit()
	_check(session.draft.enemy_unit_ids == PackedStringArray([ID, ID, ID]), "three rows lost repeated template")
	(form.find_child("DraftRoster_enemy_unit_idsRemove_1", true, false) as Button).pressed.emit()
	_check(session.draft.enemy_unit_ids.size() == 2, "remove instance affected wrong count")
	form.call("_undo_draft")
	_check(session.draft.enemy_unit_ids.size() == 3, "instance remove Undo failed")
	form.call("_redo_draft")
	_check(session.draft.enemy_unit_ids.size() == 2, "instance remove Redo failed")
	form.call("_undo_draft")
	_check(session.save(), "repeated enemy Save failed: " + session.last_error)
	var sha := Store.signature(session.path)
	var uid := ResourceLoader.get_resource_uid(session.path)
	_check(session.open("encounter", {"path": session.path, "resource": null}) and session.draft.enemy_unit_ids.size() == 3, "repeated rows lost at reopen")
	_encounter = Store.Catalog.Encounters.definition(ENCOUNTER)
	var copied := Store.clone(_encounter)
	copied.enemy_unit_ids.remove_at(0)
	_check(_encounter.enemy_unit_ids.size() == 3, "draft copy aliases saved rows")
	session.set_value("enemy_unit_ids", PackedStringArray([ID]))
	session.discard()
	_check(Store.signature(Store.path_for("encounter", ENCOUNTER)) == sha and ResourceLoader.get_resource_uid(Store.path_for("encounter", ENCOUNTER)) == uid and _encounter.enemy_unit_ids.size() == 3, "Discard changed published roster/UID")
	form.free()
	var incoming := Store.Catalog.incoming_links("unit", Store.Catalog.saved_record("unit", Store.path_for("unit", ID), Store.SPECS), Store.SPECS)
	var confirmed := 0
	for link in incoming:
		if link.path == Store.path_for("encounter", ENCOUNTER) and link.confirmed: confirmed += 1
	_check(confirmed == 1, "usage lost shared-template ref or duplicated its file row")
	# The pre-existing Inspector route also keeps the template available for Add.
	var panel := Inspector.new()
	root.add_child(panel)
	panel.setup(_encounter, null, null)
	var picker := panel.find_child("EncounterUnitPicker_enemy", true, false) as OptionButton
	var found := false
	for index in picker.item_count:
		if picker.get_item_metadata(index) == ID: found = true
	_check(found, "Inspector still forbids existing enemy template")
	panel.free()
	var invalid := Store.clone(_encounter)
	invalid.party_unit_ids = PackedStringArray(["mira", "mira"])
	_check(not invalid.validation_errors().is_empty(), "duplicate heroes accepted")
	invalid = Store.clone(_encounter)
	invalid.enemy_unit_ids.append(ID)
	_check(not invalid.validation_errors().is_empty(), "insufficient deployment points accepted")
	invalid = Store.clone(_encounter)
	invalid.enemy_unit_ids = PackedStringArray(["missing_instance_template", "missing_instance_template"])
	_check(not invalid.validation_errors().is_empty(), "missing repeated template accepted")

func _runtime() -> void:
	var rows := _encounter.enemy_instances()
	var state := _encounter.initial_state({}, 17)
	_check(rows == _encounter.enemy_instances() and state == _encounter.initial_state({}, 17), "runtime IDs or fresh state nondeterministic")
	_check(state.units.size() == 4 and state.units.has(ID) and rows[0].id == ID, "first ID changed or repeated enemy overwritten")
	var a: String = rows[0].id
	var b: String = rows[1].id
	var c: String = rows[2].id
	_check(state.units[b].templateId == ID and state.units[c].templateId == ID and state.units[b].id == b and state.units[c].id == c, "instance/template identity lost")
	_check(state.units[a].cell != state.units[b].cell and state.units[b].cell != state.units[c].cell and state.units[a].name != state.units[b].name, "instances share deployment/name")
	var hp := int(state.units[b].hp)
	state.units[a].hp = 1
	state.units[a].mp = 0
	state.units[a].statuses.wet = 2
	state.units[a].nextAt = 42.0
	_check(state.units[b].hp == hp and state.units[b].statuses.is_empty() and state.units[b].nextAt != 42.0, "instance mutable state aliases sibling")
	var fresh := _encounter.initial_state({}, 17)
	_check(fresh.units[a].hp == hp and fresh.units[a].statuses.is_empty(), "Retry-style fresh state retained previous damage/status")
	# Shared template edits affect new battles, never already created unit instances.
	var source := Store.clone(Store.Catalog.Units.resource(ID))
	source.max_hp += 7
	_check(Store.write("unit", source, Store.path_for("unit", ID)) == OK, "shared template edit failed")
	var updated := _encounter.initial_state({}, 17)
	for row in rows: _check(updated.units[row.id].maxHp == hp + 7, "new battle missed shared template edit")
	_check(fresh.units[b].maxHp == hp, "shared edit mutated live battle")
	for id in fresh.units: fresh.units[id].nextAt = 0.0 if id == a else 1000.0
	fresh.units[a].actions = ["strike", "defend"]
	var ai := Combat.enemy_command(fresh)
	var after := Combat.commit(fresh, ai)
	_check(ai.get("ok", false) and ai.actorId == a and after.turn == fresh.turn + 1, "first instance AI failed")
	for id in fresh.units: fresh.units[id].nextAt = 0.0 if id == b else 1000.0
	fresh.units[b].actions = ["strike", "defend"]
	ai = Combat.enemy_command(fresh)
	_check(ai.get("ok", false) and ai.actorId == b, "aliased enemy instance AI failed")
	for id in fresh.units: fresh.units[id].nextAt = 0.0 if id == "mira" else 1000.0
	fresh.units.mira.actions = ["strike", "defend"]
	for row in rows:
		_check(row.id in Combat.eligible_target_ids(fresh, "strike"), "instance absent from target list")
		_check(Grid.action_plan(fresh, "strike", fresh.units[row.id].cell).ok, "instance approach target failed")
	# Every defeated instance gets its own roll/context and tag counter.
	for row in rows: fresh.units[row.id].hp = 0
	var report := Result.build(_encounter, fresh, "victory")
	_check(report.defeatedEnemyIds.size() == 3 and report.counterDeltas.combat_defeated_total == 3 and report.lootRewards.size() == 1 and report.lootRewards[0].count == 6, "instance loot/counter missing or duplicated")
	_check(Result.build(_encounter, fresh, "victory") == report, "instance loot nondeterministic")
	_check(Result.build(_encounter, fresh, "defeat").lootRewards.is_empty(), "defeat issued instance loot")
	# Reserve authored IDs even when a real template resembles an instance suffix.
	var collision := Store.clone(_encounter)
	collision.enemy_unit_ids.append(ID + "__instance_2")
	var collision_rows: Array[Dictionary] = collision.enemy_instances()
	var ids := {}
	for row in collision_rows: ids[row.id] = true
	_check(ids.size() == 4 and collision_rows[3].id == ID + "__instance_2" and collision_rows[1].id != collision_rows[3].id, "generated ID overwrote an authored participant")
	var original := Store.Catalog.Encounters.definition("colored_crossing_demo")
	var baseline := original.initial_state({}, 17)
	for id in original.enemy_unit_ids:
		_check(baseline.units.has(id) and not baseline.units[id].has("templateId"), "unique legacy roster identity changed")
