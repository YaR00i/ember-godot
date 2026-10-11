extends SceneTree
## Native action constructor -> ordered shared effects -> unit assignment -> battle.
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Action = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const ACTION_ID := "constructor_fixture_action"
const UNIT_ID := "constructor_fixture_unit"
var _errors: Array[String] = []
var _history := UndoRedo.new()
var _session
var _form: Control

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL action constructor refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1280, 720)
	Maps.prepare(self, "user://action-authoring-%d" % OS.get_process_id())
	_run.call_deferred()

func _run() -> void:
	_session = Session.new()
	_session.configure(_history)
	_test_action_form()
	_test_assignment()
	_test_battle()
	_session.discard()
	if _form != null: _form.free()
	_history.clear_history(false)
	_history.free()
	Store.restore({"path": Store.path_for("unit", UNIT_ID), "exists": false})
	Store.restore({"path": Store.path_for("action", ACTION_ID), "exists": false})
	if _errors.is_empty(): print("PASS game systems action constructor: named shared steps/order/duplicates/hidden correction, unit assignment/order/missing IDs, Undo/Discard/publication UID/reopen, real cost/range/target/menu/effects/commit")
	else: printerr("FAIL action constructor: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _mount() -> void:
	if _form != null: _form.free()
	_form = Form.new()
	root.add_child(_form)
	_form.setup(_session)

func _pick(name: String, id: String, resource := false) -> bool:
	var choice := _form.find_child(name, true, false) as OptionButton
	for index in choice.item_count:
		var value: Variant = choice.get_item_metadata(index)
		if (str(value.get("effect_id")) if resource else str(value)) == id:
			choice.select(index)
			return not choice.is_item_disabled(index)
	_check(false, "picker missing " + id)
	return false

func _test_action_form() -> void:
	_check(_session.create("action", ACTION_ID, "Лечебная вода"), "create action failed")
	for pair in [["hint", "Лечит союзника и накладывает Мокрый."], ["requirements_text", "Союзник рядом; текст не исполняет условия."], ["menu_group", Action.MenuGroup.MAGIC], ["element", Action.Element.WATER], ["effect", Action.Effect.EFFECT_CHAIN], ["target", Action.Target.ALLY], ["scaling", Action.Scaling.NONE], ["mp_cost", 2], ["delay", 145], ["range_cells", 2]]:
		_session.set_value(pair[0], pair[1])
	_mount()
	_check(not (_form.find_child("DraftField_partner_unit_id", true, false) as Control).visible, "non-duo form showed partner")
	_check(not (_form.find_child("DraftField_throw_range_cells", true, false) as Control).visible, "non-lift form showed throw range")
	var preset := _form.find_child("DraftField_effect", true, false) as OptionButton
	preset.select(Action.Effect.LIFT_THROW)
	preset.item_selected.emit(Action.Effect.LIFT_THROW)
	_check((_form.find_child("DraftField_throw_range_cells", true, false) as Control).visible and not (_form.find_child("DraftField_partner_unit_id", true, false) as Control).visible, "lift context fields incorrect")
	preset.select(Action.Effect.DUO_PULSE)
	preset.item_selected.emit(Action.Effect.DUO_PULSE)
	_check((_form.find_child("DraftField_partner_unit_id", true, false) as Control).visible and not (_form.find_child("DraftField_throw_range_cells", true, false) as Control).visible, "duo context fields incorrect")
	preset.select(Action.Effect.EFFECT_CHAIN)
	preset.item_selected.emit(Action.Effect.EFFECT_CHAIN)
	_check(_session.draft.mp_cost == 2 and _session.draft.range_cells == 2, "preset switch changed unrelated parameters")
	for id in ["restore_major_hp", "apply_wet"]:
		_check(_pick("DraftEffectChoice", id, true), "could not select new shared step")
		(_form.find_child("DraftAddEffect", true, false) as Button).pressed.emit()
	_check(_session.draft.effect_steps.size() == 2 and _session.draft.effect_steps[0] == Catalog.Effects.resource("restore_major_hp"), "shared references lost")
	_check(not _pick("DraftEffectChoice", "apply_wet", true), "duplicate step enabled")
	(_form.find_child("DraftAddEffect", true, false) as Button).pressed.emit()
	_check(_session.draft.effect_steps.size() == 2, "duplicate step appended")
	(_form.find_child("DraftRowUp_effect_steps_1", true, false) as Button).pressed.emit()
	_check(_session.draft.effect_steps[0].effect_id == "apply_wet", "step reorder failed")
	_form.call("_undo_draft")
	_check(_session.draft.effect_steps[0].effect_id == "restore_major_hp", "step reorder Undo failed")
	_form.call("_redo_draft")
	(_form.find_child("DraftRowRemove_effect_steps_0", true, false) as Button).pressed.emit()
	_check(_session.draft.effect_steps.size() == 1, "remove step failed")
	_form.call("_undo_draft")
	_session.set_value("force", 1)
	_mount()
	_check((_form.find_child("DraftField_force", true, false) as Control).visible, "incompatible stored force became unreachable")
	_check(not _session.save(), "invalid force published")
	(_form.find_child("DraftField_force", true, false) as SpinBox).value = 0
	_check(not (_form.find_child("DraftField_force", true, false) as Control).visible, "corrected force did not hide")
	_check("подсказка" in (_form.find_child("DraftRulesSummary", true, false) as Label).text, "text conditions not distinguished")
	var path := Store.path_for("action", ACTION_ID)
	_check(not FileAccess.file_exists(path), "draft wrote before Save")
	_check(_session.save(), "action Save failed: " + _session.last_error)
	var sha := Store.signature(path)
	var uid := ResourceLoader.get_resource_uid(path)
	_history.undo()
	_check(not FileAccess.file_exists(path), "action publication Undo failed")
	_history.redo()
	_check(Store.signature(path) == sha and ResourceLoader.get_resource_uid(path) == uid, "action publication Redo changed bytes/UID")
	var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	_check(reopened.effect_steps.size() == 2 and reopened.effect_steps[0].effect_id == "apply_wet" and reopened.effect_steps[1].resource_path == Catalog.Effects.resource("restore_major_hp").resource_path, "step order/shared reference failed reopen")
	_session.set_value("mp_cost", 99)
	_session.discard()
	_check(Catalog.Actions.resource(ACTION_ID).mp_cost == 2, "Discard changed published MP")

func _test_assignment() -> void:
	_check(_session.create("unit", UNIT_ID, "Автор лечебной воды", Catalog.Units.resource("mira")), "create unit failed")
	_mount()
	_check(_pick("DraftActionChoice", ACTION_ID), "new action missing from assignment")
	(_form.find_child("DraftAddAction", true, false) as Button).pressed.emit()
	var original := PackedStringArray(_session.draft.action_ids)
	_check(ACTION_ID in original, "assignment lost action ID")
	var last := original.size() - 1
	(_form.find_child("DraftActionUp_%d" % last, true, false) as Button).pressed.emit()
	_check(_session.draft.action_ids[last - 1] == ACTION_ID, "assignment reorder failed")
	_form.call("_undo_draft")
	_check(_session.draft.action_ids == original, "assignment Undo failed")
	(_form.find_child("DraftActionRemove_%d" % last, true, false) as Button).pressed.emit()
	_check(ACTION_ID not in _session.draft.action_ids, "assignment removal failed")
	_form.call("_undo_draft")
	var missing := PackedStringArray(_session.draft.action_ids)
	missing.append("missing_saved_action")
	_session.set_value("action_ids", missing)
	_mount()
	_check(_session.draft.action_ids == missing and not _session.save(), "unknown saved ID dropped or published")
	(_form.find_child("DraftActionRemove_%d" % (missing.size() - 1), true, false) as Button).pressed.emit()
	_check(_session.save(), "assigned unit Save failed: " + _session.last_error)
	var reopened := ResourceLoader.load(Store.path_for("unit", UNIT_ID), "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	_check(reopened.action_ids == original and reopened.to_definition().actions.has(ACTION_ID), "unit assignment failed reopen/runtime projection")

func _test_battle() -> void:
	var state := Grid.initial_state(null, 17)
	_check(state.units.has(UNIT_ID), "new native unit absent from battle snapshot")
	for id in state.units: state.units[id].nextAt = 1000.0
	state.units[UNIT_ID].nextAt = 0.0
	state.units[UNIT_ID].cell = Vector2i(0, 0)
	state.units[UNIT_ID].mp = 8
	state.units.orik.cell = Vector2i(1, 0)
	state.units.orik.hp = 1
	var before := state.duplicate(true)
	var preview := Combat.preview(state, ACTION_ID, "orik")
	_check(preview.get("ok", false) and state == before, "authored preview failed or mutated source")
	_check(preview.get("mpCost") == 2 and preview.get("setStatuses", {}).get("orik", {}).get("wet") == 2 and preview.get("restoreHp", {}).get("orik", 0) > 1, "shared effects/cost not in real preview")
	var after := Combat.commit(state, preview)
	_check(after.units[UNIT_ID].mp == 6 and after.units[UNIT_ID].nextAt > 0 and after.units.orik.hp > 1 and after.units.orik.statuses.get("wet") == 2, "authored result did not commit effects/cost/delay")
	_check(Combat.command_definition(state, ACTION_ID).menuGroup == "magic", "authored menu group missing")
	state.units[UNIT_ID].mp = 1
	_check(not Combat.preview(state, ACTION_ID, "orik").get("ok", true), "insufficient MP accepted")
	state.units[UNIT_ID].mp = 8
	state.units.orik.cell = Vector2i(6, 4)
	_check(not Combat.preview(state, ACTION_ID, "orik").get("ok", true), "out of range target accepted")
	_check(not Combat.preview(state, ACTION_ID, "wisp").get("ok", true), "hostile target accepted for ally action")

func _check(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)
