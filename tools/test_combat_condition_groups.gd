extends SceneTree
## Flat AND/OR authoring and the actual shared combat/AI resolver, disposable only.
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Conditions = preload("res://scripts/prototypes/ember_combat_action_conditions.gd")
const Action = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const ID := "condition_groups_fixture"
var _errors: Array[String] = []
var _history := UndoRedo.new()
var _session
var _form: Control
var _action: Resource

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL group gate refused non-disposable project")
		quit.call_deferred(2)
		return
	Maps.prepare(self, "user://condition-groups-%d" % OS.get_process_id())
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: _errors.append(message)

func _rows(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(values)
	return result

func _run() -> void:
	_validation()
	_authoring()
	if _action != null: _runtime()
	if _form != null: _form.free()
	_history.clear_history(false)
	_history.free()
	Store.restore({"path": Store.path_for("action", ID), "exists": false})
	if _errors.is_empty(): print("PASS game systems condition groups: flat ALL/ANY, mixed actor-target predicates, status/HP/MP/gear, validation/SELF/CELL, actual form/Undo/Redo/Discard/Save/reopen/UID/links/deep isolation, eligible/preview/commit/approach/AI/stale rules and unchanged legacy defaults")
	else: printerr("FAIL condition groups: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _validation() -> void:
	var alternative := {"mode": "any", "target_required_status_ids": ["wet", "burning"]}
	_check(Conditions.validation_errors({"condition_groups": [alternative]}, "enemy").is_empty(), "valid status alternatives rejected")
	for group in [{}, {"mode": "bad"}, {"mode": "any"}, {"mode": "any", "condition_groups": []}, {"mode": "any", "target_required_status_ids": ["wet", "missing"]}, {"mode": "any", "value_conditions": 2}, {"mode": "any", "target_required_status_ids": ["wet", "wet"]}]:
		_check(not Conditions.validation_errors({"condition_groups": [group]}, "enemy").is_empty(), "malformed group accepted: " + str(group))
	_check(not Conditions.validation_errors({"condition_groups": "bad"}, "enemy").is_empty(), "malformed groups list accepted")
	_check(not Conditions.validation_errors({"condition_groups": [alternative]}, "cell").is_empty(), "CELL target alternative accepted")
	var opposing := {"mode": "any", "actor_required_status_ids": ["wet"], "target_forbidden_status_ids": ["wet"]}
	_check(Conditions.validation_errors({"condition_groups": [opposing]}, "self").is_empty(), "SELF alternatives incorrectly require both")
	opposing.mode = "all"
	_check(not Conditions.validation_errors({"condition_groups": [opposing]}, "self").is_empty(), "SELF ALL contradiction accepted")
	var thresholds := {"mode": "any", "value_conditions": [{"subject": "actor", "stat": "hp", "comparison": "gte", "unit": "percent", "value": 80}, {"subject": "actor", "stat": "hp", "comparison": "lte", "unit": "percent", "value": 20}]}
	_check(Conditions.validation_errors({"condition_groups": [thresholds]}, "enemy").is_empty(), "disjoint numeric alternatives rejected")
	thresholds.mode = "all"
	_check(not Conditions.validation_errors({"condition_groups": [thresholds]}, "enemy").is_empty(), "ALL numeric contradiction accepted")
	var gear := {"mode": "any", "equipment_conditions": [{"subject": "actor", "slot": "weapon", "mode": "empty", "item_id": ""}, {"subject": "actor", "slot": "weapon", "mode": "occupied", "item_id": ""}]}
	_check(Conditions.validation_errors({"condition_groups": [gear]}, "enemy").is_empty(), "disjoint gear alternatives rejected")
	gear.mode = "all"
	_check(not Conditions.validation_errors({"condition_groups": [gear]}, "enemy").is_empty(), "ALL gear contradiction accepted")

func _mount() -> void:
	if _form != null: _form.free()
	_form = Form.new()
	root.add_child(_form)
	_form.setup(_session)

func _pick(name: String, value: Variant) -> void:
	var choice := _form.find_child(name, true, false) as OptionButton
	for index in choice.item_count:
		if choice.get_item_metadata(index) == value:
			choice.select(index)
			choice.item_selected.emit(index)
			return
	_check(false, "picker value missing: " + name + "/" + str(value))

func _add_status(id: String) -> void:
	var subject := _form.find_child("DraftConditionSubject", true, false) as OptionButton
	subject.select(1)
	subject.item_selected.emit(1)
	_pick("DraftConditionStatus", id)
	var add := _form.find_child("DraftAddCondition", true, false) as Button
	_check(not add.disabled, "valid group status disabled: " + id)
	if not add.disabled: add.pressed.emit()

func _authoring() -> void:
	_session = Session.new()
	_session.configure(_history)
	_check(_session.create("action", ID, "Удар по мокрой или горящей цели", Store.Catalog.Actions.resource("strike")), "draft create failed")
	_session.set_value("mp_cost", 2)
	_session.set_value("value_conditions", _rows([{"subject": "actor", "stat": "mp", "comparison": "gte", "unit": "points", "value": 10}]))
	_session.set_value("condition_groups", _rows([{"mode": "any", "target_required_status_ids": [7], "value_conditions": 1}]))
	_mount()
	var selector := _form.find_child("DraftConditionGroup", true, false) as OptionButton
	selector.select(1)
	selector.item_selected.emit(1)
	_check(not _session.save() and _session.draft.condition_groups[0].value_conditions == 1, "malformed saved group hidden/coerced/published")
	(_form.find_child("DraftRemoveConditionGroup", true, false) as Button).pressed.emit()
	(_form.find_child("DraftAddConditionGroup", true, false) as Button).pressed.emit()
	_check(not _session.save(), "empty group Save accepted")
	_add_status("wet")
	_add_status("burning")
	_pick("DraftConditionGroupMode", "all")
	_check(_session.draft.condition_groups[0].mode == "all", "group mode edit failed")
	_form.call("_undo_draft")
	_check(_session.draft.condition_groups[0].mode == "any", "group mode Undo failed")
	_form.call("_redo_draft")
	_check(_session.draft.condition_groups[0].mode == "all", "group mode Redo failed")
	_pick("DraftConditionGroupMode", "any")
	(_form.find_child("DraftRemoveConditionGroup", true, false) as Button).pressed.emit()
	_check(_session.draft.condition_groups.is_empty(), "group Delete failed")
	_form.call("_undo_draft")
	_check(_session.draft.condition_groups[0].target_required_status_ids == PackedStringArray(["wet", "burning"]), "group Delete Undo lost content")
	_check(_session.save(), "group Save failed: " + _session.last_error)
	var path := Store.path_for("action", ID)
	var sha := Store.signature(path)
	var uid := ResourceLoader.get_resource_uid(path)
	_history.undo()
	_check(not FileAccess.file_exists(path), "group publication Undo failed")
	_history.redo()
	_check(Store.signature(path) == sha and ResourceLoader.get_resource_uid(path) == uid, "publication Redo lost exact bytes/UID")
	_check(_session.open("action", {"path": path, "resource": null}) and _session.draft.condition_groups[0].mode == "any", "group reopen failed")
	_action = Store.Catalog.Actions.resource(ID)
	var projected: Dictionary = _action.application_conditions()
	projected.condition_groups[0].target_required_status_ids.append("frozen")
	_check(_action.condition_groups[0].target_required_status_ids.size() == 2, "group projection aliases authored data")
	var copied := Store.clone(_action)
	copied.condition_groups[0].mode = "all"
	_check(_action.condition_groups[0].mode == "any", "copy aliases source group")
	var incoming := Store.Catalog.incoming_links("status", Store.Catalog.saved_record("status", Store.Catalog.Statuses.resource("wet").resource_path, Store.SPECS), Store.SPECS)
	var confirmed := false
	for link in incoming:
		if link.path == path and link.confirmed: confirmed = true
	_check(confirmed, "group status usage not confirmed")
	_session.set_value("condition_groups", _rows([]))
	_session.discard()
	_check(Store.signature(path) == sha and _action.condition_groups.size() == 1, "Discard changed saved groups")

func _state() -> Dictionary:
	var state := Grid.initial_state(null, 17)
	for id in state.units:
		state.units[id].nextAt = 0.0 if id == "mira" else 1000.0
		state.units[id].statuses = {}
		if id not in ["mira", "orik", "wisp"]: state.units[id].hp = 0
	state.units.mira.actions = [ID, "defend"]
	state.units.mira.cell = Vector2i(0, 2)
	state.units.mira.mp = 20
	state.units.orik.cell = Vector2i(2, 3)
	state.units.wisp.cell = Vector2i(1, 2)
	return state

func _runtime() -> void:
	var saved: Array[Dictionary] = _action.condition_groups.duplicate(true)
	var state := _state()
	for statuses in [{"wet": 2}, {"burning": 2}, {"wet": 2, "burning": 2}]:
		state.units.wisp.statuses = statuses
		var before := state.duplicate(true)
		var preview := Combat.preview(state, ID, "wisp")
		_check(preview.get("ok", false) and state == before and "wisp" in Combat.valid_target_ids(state, ID), "OR branch failed/polluted preview: " + str(statuses))
		var after := Combat.commit(state, preview)
		_check(after.turn == state.turn + 1 and after.units.mira.mp == 18, "OR commit/cost failed")
		_check(Grid.action_plan(state, ID, state.units.wisp.cell).ok, "OR approach rejected valid target")
	state.units.wisp.statuses = {}
	var invalid := Combat.preview(state, ID, "wisp")
	_check(not invalid.get("ok", true) and "ИЛИ" in str(invalid.get("error", "")) and Combat.commit(state, invalid) == state, "failed OR lost explanation/consumed turn")
	_check("wisp" not in Combat.eligible_target_ids(state, ID) and not Grid.action_plan(state, ID, state.units.wisp.cell).ok, "failed OR left legal target/approach")
	state.units.wisp.statuses = {"wet": 2}
	var preview := Combat.preview(state, ID, "wisp")
	_action.condition_groups[0].mode = "all"
	_check(Combat.commit(state, preview) == state and not Combat.preview(state, ID, "wisp").get("ok", true), "changed group mode bypassed stale guard/AND")
	_action.condition_groups = saved.duplicate(true)
	state.units.mira.mp = 9
	_check(not Combat.preview(state, ID, "wisp").get("ok", true), "OR bypassed mandatory MP")
	state = _state()
	_action.condition_groups = _rows([{"mode": "any", "actor_required_status_ids": ["wet"], "target_required_status_ids": ["burning"]}])
	state.units.wisp.statuses = {"burning": 2}
	_check(Combat.preview(state, ID, "wisp").get("ok", false), "mixed OR prematurely rejected dry actor")
	state.units.wisp.statuses.clear()
	state.units.mira.statuses = {"wet": 2}
	_check(Combat.preview(state, ID, "wisp").get("ok", false), "mixed OR prematurely rejected dry target")
	state.units.mira.statuses.clear()
	_check(not Combat.preview(state, ID, "wisp").get("ok", true), "mixed OR accepted neither branch")
	_action.condition_groups = saved.duplicate(true)
	# Same saved predicates and target filtering drive the actual enemy planner.
	state.units.wisp.nextAt = 0.0
	state.units.mira.nextAt = 1000.0
	state.units.wisp.mp = 20
	state.units.wisp.actions = [ID, "defend"]
	state.units.mira.statuses = {"burning": 2}
	var ai := Combat.enemy_command(state)
	_check(ai.get("ok", false) and ai.get("actionId", "") == ID and ai.get("targetId", "") == "mira", "AI ignored eligible OR target")
	state.units.mira.statuses.clear()
	_check(Combat.enemy_command(state).get("actionId", "") != ID, "AI selected action with neither OR branch")
	_action.condition_groups = _rows([{"mode": "all", "actor_forbidden_status_ids": ["frozen"]}, saved[0]])
	state = _state()
	state.units.wisp.statuses = {"wet": 2}
	state.units.mira.statuses = {"frozen": 2}
	_check(not Combat.preview(state, ID, "wisp").get("ok", true), "OR bypassed another AND group")
	_action.condition_groups = saved
	_mixed_and_cell_self()

func _mixed_and_cell_self() -> void:
	var state := _state()
	_action.condition_groups = _rows([{"mode": "any", "value_conditions": [{"subject": "actor", "stat": "hp", "comparison": "lte", "unit": "percent", "value": 20}], "equipment_conditions": [{"subject": "actor", "slot": "armor", "mode": "item", "item_id": "traveler_tunic"}]}])
	state.units.mira.equipment = {}
	state.units.mira.hp = state.units.mira.maxHp
	_check(not Combat.preview(state, ID, "wisp").get("ok", true), "numeric/gear OR accepted no branch")
	state.units.mira.hp = 1
	_check(Combat.preview(state, ID, "wisp").get("ok", false), "numeric OR branch failed")
	state.units.mira.hp = state.units.mira.maxHp
	state.inventory = {"traveler_tunic": 1}
	_check(not Combat.preview(state, ID, "wisp").get("ok", true), "group gear counted bag item")
	state.units.mira.equipment.armor = "traveler_tunic"
	state.units.mira.mp = 10
	var preview := Combat.preview(state, ID, "wisp")
	_check(preview.get("ok", false) and Combat.commit(state, preview).units.mira.mp == 8, "gear OR branch/pre-cost check failed")
	_action.condition_groups[0].mode = "all"
	_check(not Combat.preview(state, ID, "wisp").get("ok", true), "ALL accepted one of numeric/gear branches")
	state.units.mira.hp = 1
	_check(Combat.preview(state, ID, "wisp").get("ok", false), "ALL rejected both numeric/gear branches")
	# SELF pairs the actor with itself; CELL has no target unit to satisfy a branch.
	_action.target = Action.Target.SELF
	_action.effect = Action.Effect.GUARD
	_action.condition_groups = _rows([{"mode": "any", "actor_required_status_ids": ["wet"], "target_required_status_ids": ["burning"]}])
	state = _state()
	state.units.mira.statuses = {"burning": 2}
	_check(Combat.preview(state, ID, "mira").get("ok", false), "SELF target OR branch failed")
	state.units.mira.statuses = {}
	_check(not Combat.preview(state, ID, "mira").get("ok", true), "SELF accepted neither OR branch")
	_action.target = Action.Target.CELL
	_action.effect = Action.Effect.EFFECT_CHAIN
	_action.effect_steps = Store.Catalog.Actions.resource("earth_wall").effect_steps
	_action.condition_groups = _rows([{"mode": "any", "actor_required_status_ids": ["wet", "burning"]}])
	state.units.mira.statuses = {"burning": 2}
	_check(not Combat.eligible_target_cells(state, ID).is_empty(), "CELL actor OR branch failed")
	var cell: Vector2i = Combat.valid_target_cells(state, ID)[0]
	var plan := Combat.preview(state, ID, "", Combat.INVALID_CELL, cell)
	_check(plan.get("ok", false), "CELL OR preview failed")
	state.units.mira.statuses.clear()
	var stale := plan.duplicate(true)
	stale.erase("stateHash")
	stale.erase("actionConditionsHash")
	_check(Combat.eligible_target_cells(state, ID).is_empty() and Combat.commit(state, stale) == state, "CELL stale group bypassed independent recheck")
