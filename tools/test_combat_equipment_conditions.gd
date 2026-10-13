extends SceneTree
## Guarded disposable equipment authoring -> shared Combat/Grid/AI/commit.
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Action = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const Rules = preload("res://scripts/prototypes/ember_combat_action_conditions.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const ID := "gear_action_fixture"
const ITEMS := ["gear_sword_a", "gear_sword_b", "gear_ring_a", "gear_ring_b", "gear_ring_c"]
var _errors: Array[String] = []
var _history := UndoRedo.new()
var _session
var _form: Control
var _action: Resource

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL gear gate refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1280, 720)
	Maps.prepare(self, "user://gear-conditions-%d" % OS.get_process_id())
	_run.call_deferred()

func _run() -> void:
	for id in ITEMS:
		var item := Store.blank("item", id, "Предмет проверки " + id)
		item.definition = Store.ItemStore.normalized_document({"id": id, "nameRu": item.definition.nameRu, "kind": "weapon_jrpg" if "sword" in id else "accessory"})
		_check(Store.validation("item", item).is_empty() and Store.write("item", item, Store.path_for("item", id)) == OK, "gear item fixture publication failed")
	_session = Session.new()
	_session.configure(_history)
	_validation()
	_authoring()
	if _action != null: _runtime()
	_session.discard()
	if _form != null: _form.free()
	_history.clear_history(false)
	_history.free()
	Store.restore({"path": Store.path_for("action", ID), "exists": false})
	for id in ITEMS: Store.restore({"path": Store.path_for("item", id), "exists": false})
	if _errors.is_empty(): print("PASS game systems equipment conditions: worn item/any or exact slot/occupied/empty, five-slot matching/SELF/CELL/conflicts, native pickers/edit/Undo/Redo/Discard/Save/reopen/UID/item links, bag-only refusal/AND/pure preview/approach/AI and stale independent commit guards")
	else: printerr("FAIL equipment conditions: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok: _errors.append(message)

func _row(subject: String, slot: String, mode: String, item := "") -> Dictionary:
	return {"subject": subject, "slot": slot, "mode": mode, "item_id": item}

func _rows(raw: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(raw)
	return result

func _validation() -> void:
	for bad in [
		[_row("actor", "", "occupied")], [_row("actor", "head", "empty")], [_row("missing", "weapon", "empty")],
		[_row("actor", "weapon", "item", "missing_item")], [_row("actor", "weapon", "item", "herb")],
		[_row("actor", "weapon", "item", "traveler_tunic")], [_row("actor", "armor", "empty", "traveler_tunic")],
		[_row("actor", "armor", "empty"), _row("actor", "armor", "occupied")],
		[_row("actor", "weapon", "item", ITEMS[0]), _row("actor", "weapon", "item", ITEMS[1])],
		[_row("actor", "", "item", ITEMS[0]), _row("actor", "", "item", ITEMS[1])],
		[_row("actor", "", "item", ITEMS[2]), _row("actor", "", "item", ITEMS[3]), _row("actor", "", "item", ITEMS[4])],
		[_row("actor", "", "item", "traveler_tunic"), _row("actor", "armor", "empty")],
		[_row("actor", "armor", "empty"), _row("actor", "armor", "empty")], [{"bad": 1}],
	]: _check(not Rules.validation_errors({"equipment_conditions": bad}, "enemy").is_empty(), "invalid gear accepted: " + str(bad))
	_check(not Rules.validation_errors({"equipment_conditions": 1}, "enemy").is_empty(), "non-array gear accepted")
	_check(not Rules.validation_errors({"equipment_conditions": [_row("actor", "armor", "empty"), _row("target", "armor", "occupied")]}, "self").is_empty(), "SELF gear contradiction accepted")
	_check(not Rules.validation_errors({"equipment_conditions": [_row("target", "armor", "empty")]}, "cell").is_empty(), "CELL target gear accepted")
	for valid in [
		[_row("actor", "", "item", ITEMS[2]), _row("actor", "", "item", ITEMS[3])],
		[_row("actor", "accessory1", "item", ITEMS[2]), _row("actor", "accessory2", "item", ITEMS[2]), _row("actor", "", "item", ITEMS[2])],
		[_row("actor", "weapon", "item", ITEMS[0]), _row("actor", "weapon", "occupied")],
		[_row("actor", "weapon", "empty"), _row("target", "weapon", "occupied")],
	]: _check(Rules.validation_errors({"equipment_conditions": valid}, "enemy").is_empty(), "valid gear conjunction rejected")

func _mount() -> void:
	if _form != null: _form.free()
	_form = Form.new()
	root.add_child(_form)
	_form.setup(_session)

func _pick(name: String, id: String) -> void:
	var choice := _form.find_child(name, true, false) as OptionButton
	for index in choice.item_count:
		if choice.get_item_metadata(index) == id:
			choice.select(index)
			choice.item_selected.emit(index)
			return
	_check(false, "gear picker missing " + name + "/" + id)

func _input(data: Dictionary) -> Button:
	for pair in [["DraftEquipmentSubject", data.subject], ["DraftEquipmentMode", data.mode], ["DraftEquipmentSlot", data.slot], ["DraftEquipmentItem", data.item_id]]:
		if pair[0] == "DraftEquipmentItem" and data.mode != "item": continue
		_pick(pair[0], pair[1])
	return _form.find_child("DraftAddEquipmentCondition", true, false) as Button

func _authoring() -> void:
	_check(_session.create("action", ID, "Удар в экипировке", Catalog.Actions.resource("strike")), "gear draft create failed")
	_session.set_value("mp_cost", 2)
	_session.set_value("actor_required_status_ids", PackedStringArray(["wet"]))
	_session.set_value("value_conditions", _rows([{"subject": "actor", "stat": "mp", "comparison": "gte", "unit": "points", "value": 10}]))
	_mount()
	var rows := _rows([_row("actor", "", "item", "traveler_tunic"), _row("actor", "weapon", "occupied"), _row("actor", "shoes", "empty")])
	for data in rows:
		var add := _input(data)
		_check(not add.disabled, "valid gear Add disabled")
		add.pressed.emit()
	_check(_session.draft.equipment_conditions == rows, "gear picker lost data")
	_check(_input(rows[2]).disabled, "duplicate gear Add enabled")
	_check(_input(_row("actor", "weapon", "empty")).disabled, "contradictory gear Add enabled")
	_pick("DraftEquipmentSlot_0", "armor")
	_check(_session.draft.equipment_conditions[0].slot == "armor", "existing gear row not editable")
	_form.call("_undo_draft")
	_check(_session.draft.equipment_conditions == rows, "gear edit Undo failed")
	_form.call("_redo_draft")
	_check(_session.draft.equipment_conditions[0].slot == "armor", "gear edit Redo failed")
	_form.call("_undo_draft")
	(_form.find_child("DraftRemoveEquipmentCondition_2", true, false) as Button).pressed.emit()
	_form.call("_undo_draft")
	_check(_session.draft.equipment_conditions == rows, "gear removal Undo failed")
	_session.set_value("equipment_conditions", _rows([_row("target", "armor", "item", "missing_saved_item")]))
	_mount()
	_check(not _session.save() and _form.find_child("DraftEquipmentItem_0", true, false) != null, "unknown saved gear hidden/published")
	_session.set_value("target", Action.Target.CELL)
	_mount()
	_check((_form.find_child("DraftEquipmentSubject", true, false) as OptionButton).is_item_disabled(1) and _form.find_child("DraftRemoveEquipmentCondition_0", true, false) != null, "CELL saved target gear unreachable")
	(_form.find_child("DraftRemoveEquipmentCondition_0", true, false) as Button).pressed.emit()
	_session.set_value("target", Action.Target.ENEMY)
	_session.set_value("equipment_conditions", rows.duplicate(true))
	var path := Store.path_for("action", ID)
	_check(_session.save(), "gear Save failed: " + _session.last_error)
	var sha := Store.signature(path)
	var uid := ResourceLoader.get_resource_uid(path)
	_history.undo()
	_check(not FileAccess.file_exists(path), "gear publication Undo failed")
	_history.redo()
	_check(Store.signature(path) == sha and ResourceLoader.get_resource_uid(path) == uid, "gear publication Redo changed bytes/UID")
	var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	_check(reopened.equipment_conditions == rows and reopened.validation_errors().is_empty(), "gear Save/reopen lost rows")
	_action = Catalog.Actions.resource(ID)
	var projected: Dictionary = _action.application_conditions()
	projected.equipment_conditions[0].slot = "weapon"
	_check(_action.equipment_conditions == rows, "projection shared gear dictionary")
	var incoming := Catalog.incoming_links("item", Catalog.saved_record("item", Store.path_for("item", "traveler_tunic"), Store.SPECS), Store.SPECS)
	var found := false
	for row in incoming:
		if row.path == path and row.confirmed: found = true
	_check(found, "worn item condition missing from confirmed usage links")
	_session.set_value("equipment_conditions", _rows([]))
	_session.discard()
	_check(Store.signature(path) == sha and _action.equipment_conditions == rows, "Discard changed gear publication")

func _state() -> Dictionary:
	var state := Grid.initial_state(null, 17)
	for id in state.units:
		state.units[id].nextAt = 0.0 if id == "mira" else 1000.0
		state.units[id].equipment = Rules.Equipment.empty()
		if id not in ["mira", "orik", "wisp"]: state.units[id].hp = 0
	state.units.mira.actions = [ID, "defend"]
	state.units.mira.cell = Vector2i(0, 2)
	state.units.mira.mp = 20
	state.units.mira.statuses = {"wet": 3}
	state.units.mira.equipment.weapon = ITEMS[0]
	state.units.mira.equipment.armor = "traveler_tunic"
	state.units.wisp.cell = Vector2i(1, 2)
	state.units.orik.cell = Vector2i(2, 3)
	return state

func _runtime() -> void:
	var state := _state()
	var before := state.duplicate(true)
	var preview := Combat.preview(state, ID, "wisp")
	_check(preview.get("ok", false) and state == before, "gear preview failed/mutated source")
	var after := Combat.commit(state, preview)
	_check(after.turn == state.turn + 1 and after.units.mira.mp == 18 and Combat.commit(after, preview) == after, "gear action failed or repeated cost/turn")
	for slot in ["armor", "weapon"]:
		var blocked := state.duplicate(true)
		blocked.units.mira.equipment[slot] = null
		blocked = Combat.with_inventory(blocked, {"traveler_tunic": 1, ITEMS[0]: 1}, Rules.Items.definitions())
		var failed := Combat.preview(blocked, ID, "wisp")
		var plan := Grid.action_plan(blocked, ID, blocked.units.wisp.cell)
		_check(not failed.get("ok", true) and "wisp" not in Combat.eligible_target_ids(blocked, ID), "bag-only/empty slot satisfied gear")
		_check(not plan.ok and not plan.fallbackDefend and plan.resolved.is_empty(), "gear failure substituted approach/Defend")
		var no_state_hash := preview.duplicate(true)
		no_state_hash.erase("stateHash")
		_check(Combat.commit(blocked, no_state_hash) == blocked, "commit skipped current gear recheck")
	var changed := state.duplicate(true)
	changed.units.mira.mp = 9
	_check(not Combat.preview(changed, ID, "wisp").get("ok", true), "gear/MP AND skipped")
	changed = state.duplicate(true)
	changed.units.mira.statuses.clear()
	_check(not Combat.preview(changed, ID, "wisp").get("ok", true), "gear/status AND skipped")
	_action.equipment_conditions.append(_row("actor", "accessory1", "empty"))
	_check(Combat.commit(state, preview) == state, "changed gear rule committed old result")
	_action.actor_required_status_ids = PackedStringArray()
	_action.value_conditions.clear()
	_action.equipment_conditions = _rows([_row("actor", "", "item", ITEMS[2])])
	state.units.mira.equipment.accessory2 = ITEMS[2]
	_check(Combat.preview(state, ID, "wisp").get("ok", false), "any-slot ring did not find accessory2")
	_action.equipment_conditions[0].slot = "accessory1"
	_check(not Combat.preview(state, ID, "wisp").get("ok", true), "exact slot accepted ring from another slot")
	_action.equipment_conditions = _rows([_row("target", "armor", "empty")])
	state.units.wisp.erase("equipment")
	_check(Combat.preview(state, ID, "wisp").get("ok", false), "unarmed enemy absent equipment not empty")
	_action.target = Action.Target.SELF
	_action.effect = Action.Effect.DEFEND
	_action.element = Action.Element.SUPPORT
	_action.scaling = Action.Scaling.NONE
	_action.equipment_conditions = _rows([_row("actor", "weapon", "occupied"), _row("target", "armor", "item", "traveler_tunic")])
	_check(Combat.preview(state, ID, "mira").get("ok", false), "SELF combined actor/target gear rejected")
	var unarmored := state.duplicate(true)
	unarmored.units.mira.equipment.armor = null
	_check(not Combat.preview(unarmored, ID, "mira").get("ok", true), "SELF target gear skipped")
	_action.equipment_conditions = _rows([_row("actor", "weapon", "occupied")])
	_action.target = Action.Target.CELL
	_action.effect = Action.Effect.EFFECT_CHAIN
	_action.effect_steps = Catalog.Actions.resource("earth_wall").effect_steps
	_check(not Combat.eligible_target_cells(state, ID).is_empty(), "CELL actor gear rejected")
	state.units.mira.equipment.weapon = null
	_check(Combat.eligible_target_cells(state, ID).is_empty(), "CELL gear condition skipped")
	_action.target = Action.Target.ENEMY
	_action.effect = Action.Effect.DAMAGE
	_action.element = Action.Element.PHYSICAL
	_action.effect_steps.clear()
	_action.equipment_conditions = _rows([_row("target", "", "item", "traveler_tunic")])
	state = _state()
	state.units.wisp.nextAt = -1
	state.units.wisp.actions = [ID, "defend"]
	state.units.wisp.mp = 20
	_check(Combat.eligible_target_ids(state, ID) == ["mira"], "AI gear target eligibility incorrect")
	var ai := Combat.enemy_command(state)
	_check(ai.get("ok", false) and ai.get("actionId") == ID and ai.get("targetId") == "mira", "AI ignored worn item target")
	state.units.mira.equipment.armor = null
	_check(Combat.enemy_command(state).get("actionId", "") != ID and not Combat.action_condition_reason(state, ID).is_empty(), "AI/menu accepted missing target gear")
	_action.equipment_conditions = _rows([_row("actor", "weapon", "occupied")])
	_check(Combat.enemy_command(state).get("actionId", "") != ID, "AI skipped own gear condition")
