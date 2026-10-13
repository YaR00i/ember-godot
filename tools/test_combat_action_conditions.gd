extends SceneTree
## Disposable authoring and real-resolver gate; never edits authored project data.
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Action = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const Conditions = preload("res://scripts/prototypes/ember_combat_action_conditions.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const ID := "conditions_fixture"
const VALUE_ID := "value_conditions_fixture"
var _errors: Array[String] = []
var _history := UndoRedo.new()
var _session
var _form: Control
var _action: Resource
var _value_action: Resource

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL conditions gate refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1280, 720)
	Maps.prepare(self, "user://conditions-%d" % OS.get_process_id())
	_run.call_deferred()

func _run() -> void:
	_session = Session.new()
	_session.configure(_history)
	_test_validation()
	_test_authoring()
	if _action != null:
		_test_runtime()
		_test_cells_self_ai()
	_test_value_authoring()
	if _value_action != null: _test_value_runtime()
	_session.discard()
	if _form != null: _form.free()
	_history.clear_history(false)
	_history.free()
	Store.restore({"path": Store.path_for("action", ID), "exists": false})
	Store.restore({"path": Store.path_for("action", VALUE_ID), "exists": false})
	if _errors.is_empty(): print("PASS game systems application conditions: status and HP/MP predicates, points/percent exact boundaries/zero maximum, AND/SELF/CELL/AI/approach, typed saved rows/Undo/Redo/Discard/UID/deep isolation, pre-cost/pre-effect and changed-rule commit guards")
	else: printerr("FAIL action status conditions: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok: _errors.append(message)

func _mount() -> void:
	if _form != null: _form.free()
	_form = Form.new()
	root.add_child(_form)
	_form.setup(_session)

func _choose(subject: int, presence: int, id: String) -> Button:
	for pair in [["DraftConditionSubject", subject], ["DraftConditionPresence", presence]]:
		var choice := _form.find_child(pair[0], true, false) as OptionButton
		choice.select(pair[1])
		choice.item_selected.emit(pair[1])
	var status := _form.find_child("DraftConditionStatus", true, false) as OptionButton
	for index in status.item_count:
		if str(status.get_item_metadata(index)) == id:
			status.select(index)
			status.item_selected.emit(index)
	return _form.find_child("DraftAddCondition", true, false) as Button

func _test_validation() -> void:
	for bad in [
		{"actor_required_status_ids": ["wet", "wet"]},
		{"actor_required_status_ids": ["wet"], "actor_forbidden_status_ids": ["wet"]},
		{"target_required_status_ids": ["wet"], "target_forbidden_status_ids": ["wet"]},
		{"target_required_status_ids": ["absent_status"]},
		{"target_forbidden_status_ids": 1},
		{"actor_required_status_ids": [7]},
	]: _check(not Conditions.validation_errors(bad, "enemy").is_empty(), "invalid rule accepted: " + str(bad))
	_check(not Conditions.validation_errors({"actor_required_status_ids": ["wet"], "target_forbidden_status_ids": ["wet"]}, "self").is_empty(), "SELF contradiction accepted")
	_check(not Conditions.validation_errors({"target_required_status_ids": ["wet"]}, "cell").is_empty(), "CELL target statuses accepted")
	_check(Conditions.validation_errors({"actor_required_status_ids": ["wet"], "target_forbidden_status_ids": ["wet"]}, "enemy").is_empty(), "independent actor/target rejected")
	_check(Conditions.validation_errors({}, "cell").is_empty() and not Conditions.validation_errors([], "enemy").is_empty(), "empty/malformed rules incorrect")

func _test_authoring() -> void:
	_check(_session.create("action", ID, "Условный удар", Catalog.Actions.resource("strike")), "fixture draft failed")
	_session.set_value("mp_cost", 2)
	_mount()
	for row in [[0, 0, "wet"], [0, 1, "frozen"], [1, 0, "burning"], [1, 1, "wet"]]:
		var add := _choose(row[0], row[1], row[2])
		_check(not add.disabled, "valid predicate disabled: " + str(row))
		add.pressed.emit()
	_check(_choose(0, 0, "wet").disabled, "duplicate predicate enabled")
	_check(_choose(0, 1, "wet").disabled, "contradictory predicate enabled")
	var original: Dictionary = _session.draft.application_conditions()
	(_form.find_child("DraftRemoveCondition_target_forbidden_status_ids_wet", true, false) as Button).pressed.emit()
	_check(_session.draft.target_forbidden_status_ids.is_empty(), "remove predicate failed")
	_form.call("_undo_draft")
	_check(_session.draft.application_conditions() == original, "predicate Undo failed")
	_form.call("_redo_draft")
	_check(_session.draft.target_forbidden_status_ids.is_empty(), "predicate Redo failed")
	_form.call("_undo_draft")
	_session.set_value("target_required_status_ids", PackedStringArray(["burning", "missing_saved_status"]))
	_mount()
	_check(not _session.save(), "missing status published")
	(_form.find_child("DraftRemoveCondition_target_required_status_ids_missing_saved_status", true, false) as Button).pressed.emit()
	_check(_session.draft.application_conditions() == original, "missing predicate not correctable")
	_session.set_value("target", Action.Target.CELL)
	_mount()
	_check((_form.find_child("DraftConditionSubject", true, false) as OptionButton).is_item_disabled(1) and not _session.save(), "CELL target picker/validation failed")
	_check(_form.find_child("DraftRemoveCondition_target_required_status_ids_burning", true, false) != null, "incompatible saved rule hidden")
	_session.set_value("target", Action.Target.ENEMY)
	_mount()
	var path := Store.path_for("action", ID)
	_check(not FileAccess.file_exists(path) and _session.save(), "valid predicates Save failed: " + _session.last_error)
	var sha := Store.signature(path)
	var uid := ResourceLoader.get_resource_uid(path)
	_history.undo()
	_check(not FileAccess.file_exists(path), "predicate publication Undo failed")
	_history.redo()
	_check(Store.signature(path) == sha and ResourceLoader.get_resource_uid(path) == uid, "predicate publication Redo changed bytes/UID")
	var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	_check(reopened.application_conditions() == original and reopened.validation_errors().is_empty(), "saved rules did not reopen")
	_action = Catalog.Actions.resource(ID)
	_check(_action.to_definition().applicationConditions == original, "runtime rule projection lost data")
	var links := Catalog.relations("action", {"resource": reopened})
	for id in ["wet", "frozen", "burning"]:
		var found := false
		for link in links:
			if link.module == "status" and link.id == id: found = true
		_check(found, "missing status usage link: " + id)
	var incoming := Catalog.incoming_links("status", Catalog.saved_record("status", Catalog.Statuses.resource("wet").resource_path, Store.SPECS), Store.SPECS)
	var confirmed := false
	for link in incoming:
		if link.path == path and link.confirmed: confirmed = true
	_check(confirmed, "status use not confirmed by saved predicate")
	_session.set_value("actor_required_status_ids", PackedStringArray())
	_session.discard()
	_check(_action.actor_required_status_ids == original.actor_required_status_ids and Store.signature(path) == sha, "Discard changed published predicates")

func _state() -> Dictionary:
	var state := Grid.initial_state(null, 17)
	for id in state.units:
		state.units[id].nextAt = 0.0 if id == "mira" else 1000.0
		state.units[id].statuses = {}
		if id not in ["mira", "orik", "wisp"]: state.units[id].hp = 0
	state.units.mira.actions = [ID, "defend"]
	state.units.mira.cell = Vector2i(0, 2)
	state.units.mira.mp = 20
	state.units.mira.statuses = {"wet": 3}
	state.units.orik.cell = Vector2i(2, 3)
	state.units.wisp.cell = Vector2i(1, 2)
	state.units.wisp.statuses = {"burning": 3}
	return state

func _blocked(state: Dictionary, message: String) -> void:
	var before := state.duplicate(true)
	var preview := Combat.preview(state, ID, "wisp")
	var plan := Grid.action_plan(state, ID, state.units.wisp.cell)
	_check(not preview.get("ok", true) and not str(preview.get("error", "")).is_empty(), message + " preview")
	_check("wisp" not in Combat.eligible_target_ids(state, ID) and "wisp" not in Combat.valid_target_ids(state, ID), message + " eligible/valid")
	_check(not plan.ok and not plan.fallbackDefend and plan.resolved.is_empty() and not plan.reason.is_empty(), message + " approach substituted movement/Defend")
	_check(state == before and Combat.commit(state, preview) == before, message + " consumed state/cost/turn")

func _test_runtime() -> void:
	var state := _state()
	var before := state.duplicate(true)
	var preview := Combat.preview(state, ID, "wisp")
	_check(preview.get("ok", false) and state == before, "valid predicates failed or preview mutated source")
	var after := Combat.commit(state, preview)
	_check(after.turn == state.turn + 1 and after.units.mira.mp == 18, "valid predicate commit/cost failed")
	_check(Combat.commit(after, preview) == after, "result committed twice")
	for mutation in [["mira", "wet", 0], ["mira", "frozen", 2], ["wisp", "burning", 0], ["wisp", "wet", 2]]:
		var blocked := state.duplicate(true)
		blocked.units[mutation[0]].statuses[mutation[1]] = mutation[2]
		_blocked(blocked, str(mutation))
		_check(Combat.commit(blocked, preview) == blocked, "stale predicates committed")
	_action.actor_required_status_ids.append("burning")
	_blocked(state, "all required statuses must match")
	_action.actor_required_status_ids = PackedStringArray(["wet"])
	_action.actor_forbidden_status_ids.append("burning") # Still true, but authored command changed.
	_check(Combat.commit(state, preview) == state, "changed rule committed old preview")
	_action.actor_forbidden_status_ids = PackedStringArray(["frozen"])
	var no_guard := preview.duplicate(true)
	no_guard.erase("stateHash")
	no_guard.erase("actionConditionsHash")
	var blocked := state.duplicate(true)
	blocked.units.wisp.statuses.wet = 2
	_check(Combat.commit(blocked, no_guard) == blocked, "commit failed independent predicate recheck")
	no_guard = preview.duplicate(true)
	no_guard.actionConditionsHash = "invalid"
	_check(Combat.commit(state, no_guard) == state, "malformed rule guard committed")
	_action.actor_required_status_ids = PackedStringArray(["absent_status"])
	_blocked(state, "unknown runtime status")
	_action.actor_required_status_ids = PackedStringArray(["wet"])
	state.units.mira.statuses.clear()
	state.grid.cells[Grid.cell_key(state.units.mira.cell)]["tags"] = ["wet"]
	_blocked(state, "wet cell is not active unit status")

func _test_cells_self_ai() -> void:
	_action.actor_required_status_ids = PackedStringArray(["wet"])
	_action.actor_forbidden_status_ids = PackedStringArray(["frozen"])
	_action.target_required_status_ids = PackedStringArray()
	_action.target_forbidden_status_ids = PackedStringArray()
	_action.target = Action.Target.SELF
	_action.effect = Action.Effect.GUARD
	var state := _state()
	_check(Combat.preview(state, ID, "mira").get("ok", false), "SELF actor rules rejected")
	_action.target_required_status_ids = PackedStringArray(["burning"])
	_check(not Combat.preview(state, ID, "mira").get("ok", true), "SELF target rules skipped")
	state.units.mira.statuses.burning = 2
	_check(Combat.preview(state, ID, "mira").get("ok", false), "SELF conjunction failed")
	_action.target_required_status_ids = PackedStringArray()
	_action.target = Action.Target.CELL
	_action.effect = Action.Effect.EFFECT_CHAIN
	_action.effect_steps = Catalog.Actions.resource("earth_wall").effect_steps
	_check(not Combat.eligible_target_cells(state, ID).is_empty(), "CELL actor predicates rejected")
	var cell := Combat.valid_target_cells(state, ID)[0]
	_check(Combat.preview(state, ID, "", Combat.INVALID_CELL, cell).get("ok", false), "CELL preview predicates rejected")
	state.units.mira.statuses.wet = 0
	_check(Combat.eligible_target_cells(state, ID).is_empty() and not Combat.preview(state, ID, "", Combat.INVALID_CELL, cell).get("ok", true), "CELL actor predicates skipped")
	_action.target = Action.Target.ENEMY
	_action.effect = Action.Effect.DAMAGE
	_action.effect_steps.clear()
	_action.actor_required_status_ids = PackedStringArray()
	_action.target_required_status_ids = PackedStringArray(["wet"])
	state = _state()
	state.units.wisp.nextAt = -1.0
	state.units.wisp.actions = [ID, "defend"]
	state.units.wisp.mp = 20
	state.units.mira.statuses = {"wet": 2}
	state.units.orik.statuses = {}
	_check(Combat.eligible_target_ids(state, ID) == ["mira"], "multiple targets not filtered by statuses")
	var ai := Combat.enemy_command(state)
	_check(ai.get("ok", false) and ai.get("actionId") == ID and ai.get("targetId") == "mira", "AI ignored legal target predicate")
	state.units.mira.statuses.clear()
	ai = Combat.enemy_command(state)
	_check(ai.get("actionId", "") != ID, "AI selected action without eligible status target")
	_check(not Combat.action_condition_reason(state, ID).is_empty(), "no-target menu lost missing status explanation")

func _rows(values: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(values)
	return result

func _value(subject: String, stat: String, comparison: String, measure: String, threshold: int) -> Dictionary:
	return {"subject": subject, "stat": stat, "comparison": comparison, "unit": measure, "value": threshold}

func _pick_value(name: String, id: String) -> void:
	var choice := _form.find_child(name, true, false) as OptionButton
	for index in choice.item_count:
		if choice.get_item_metadata(index) == id:
			choice.select(index)
			choice.item_selected.emit(index)

func _input_value(data: Dictionary) -> Button:
	for pair in [["DraftValueSubject", data.subject], ["DraftValueStat", data.stat], ["DraftValueComparison", data.comparison], ["DraftValueUnit", data.unit]]: _pick_value(pair[0], pair[1])
	(_form.find_child("DraftValueThreshold", true, false) as SpinBox).value = data.value
	return _form.find_child("DraftAddValueCondition", true, false) as Button

func _test_value_authoring() -> void:
	_check(_session.create("action", VALUE_ID, "Удар по ослабленной цели", Catalog.Actions.resource("strike")), "value fixture create failed")
	_session.set_value("mp_cost", 2)
	_session.set_value("actor_required_status_ids", PackedStringArray(["wet"]))
	_mount()
	var rows: Array[Dictionary] = [_value("actor", "mp", "gte", "points", 10), _value("target", "hp", "lte", "percent", 30)]
	for data in rows:
		var add := _input_value(data)
		_check(not add.disabled, "valid numeric row disabled")
		add.pressed.emit()
	_check(_input_value(rows[1]).disabled, "duplicate numeric row allowed")
	_check(_input_value(_value("target", "hp", "gte", "percent", 40)).disabled, "contradictory numeric row allowed")
	var changed := _form.find_child("DraftValueThreshold_0", true, false) as SpinBox
	changed.value = 12
	changed.value = 14
	_check(_session.draft.value_conditions[0].value == 14, "numeric editor did not change draft")
	_form.call("_undo_draft")
	_check(_session.draft.value_conditions == rows, "numeric input not one Undo")
	_form.call("_redo_draft")
	_check(_session.draft.value_conditions[0].value == 14, "numeric Redo failed")
	_form.call("_undo_draft")
	_pick_value("DraftValueComparison_1", "gte")
	_check(_session.draft.value_conditions[1].comparison == "gte", "saved row comparison edit failed")
	_form.call("_undo_draft")
	_pick_value("DraftValueUnit_1", "points")
	_check(_session.draft.value_conditions[1].unit == "points", "saved row measure edit failed")
	_form.call("_undo_draft")
	(_form.find_child("DraftRemoveValueCondition_1", true, false) as Button).pressed.emit()
	_check(_session.draft.value_conditions.size() == 1, "numeric remove failed")
	_form.call("_undo_draft")
	_session.set_value("target", Action.Target.CELL)
	_mount()
	_check((_form.find_child("DraftValueSubject", true, false) as OptionButton).is_item_disabled(1) and not _session.save(), "CELL numeric target guard failed")
	_check(_form.find_child("DraftRemoveValueCondition_1", true, false) != null, "CELL saved numeric target hidden")
	_session.set_value("target", Action.Target.ENEMY)
	_session.set_value("value_conditions", _rows([{"unexpected": 1}]))
	_mount()
	_check(not _session.save(), "malformed saved row published")
	(_form.find_child("DraftRemoveValueCondition_0", true, false) as Button).pressed.emit()
	_check(_session.draft.value_conditions.is_empty(), "malformed row not removable")
	_session.set_value("value_conditions", rows.duplicate(true))
	var path := Store.path_for("action", VALUE_ID)
	_check(_session.save(), "numeric Save failed: " + _session.last_error)
	var sha := Store.signature(path)
	var uid := ResourceLoader.get_resource_uid(path)
	_history.undo()
	_check(not FileAccess.file_exists(path), "numeric publication Undo failed")
	_history.redo()
	_check(Store.signature(path) == sha and ResourceLoader.get_resource_uid(path) == uid, "numeric publication Redo bytes/UID changed")
	var reopened := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	_check(reopened.value_conditions == rows and typeof(reopened.value_conditions[0].value) == TYPE_INT, "numeric save/reopen lost rows/integer")
	_value_action = Catalog.Actions.resource(VALUE_ID)
	var projected: Dictionary = _value_action.application_conditions()
	projected.value_conditions[0].value = 999
	_check(_value_action.value_conditions == rows, "projection shared authored nested dictionary")
	_session.set_value("value_conditions", _rows())
	_session.discard()
	_check(Store.signature(path) == sha and _value_action.value_conditions == rows, "numeric Discard changed publication")

func _value_state() -> Dictionary:
	var state := _state()
	state.units.mira.actions = [VALUE_ID, "defend"]
	state.units.mira.hp = 20
	state.units.mira.maxHp = 100
	state.units.mira.mp = 10
	state.units.mira.maxMp = 20
	state.units.wisp.hp = 30
	state.units.wisp.maxHp = 100
	return state

func _test_value_runtime() -> void:
	var state := _value_state()
	var preview := Combat.preview(state, VALUE_ID, "wisp")
	_check(preview.get("ok", false), "inclusive numeric boundary failed")
	var after := Combat.commit(state, preview)
	_check(after.units.mira.mp == 8 and after.turn == state.turn + 1, "MP predicate rechecked after paying cost")
	for row in [_value("actor", "mp", "gte", "percent", 50), _value("actor", "hp", "gte", "points", 20), _value("target", "mp", "lte", "points", 0)]:
		_value_action.value_conditions = _rows([row])
		state.units.wisp.mp = 0
		_check(Combat.preview(state, VALUE_ID, "wisp").get("ok", false), "points/percent comparison failed: " + str(row))
	_value_action.value_conditions = _rows([_value("actor", "mp", "gte", "points", 10), _value("target", "hp", "lte", "percent", 30)])
	for pair in [["mira", "mp", 9], ["wisp", "hp", 31]]:
		var blocked := state.duplicate(true)
		blocked.units[pair[0]][pair[1]] = pair[2]
		var before := blocked.duplicate(true)
		var plan := Grid.action_plan(blocked, VALUE_ID, blocked.units.wisp.cell)
		_check(not Combat.preview(blocked, VALUE_ID, "wisp").get("ok", true) and "wisp" not in Combat.eligible_target_ids(blocked, VALUE_ID), "numeric eligibility/preview mismatch")
		_check(not plan.ok and not plan.fallbackDefend and blocked == before, "numeric failure consumed movement/turn")
		var no_state_hash := preview.duplicate(true)
		no_state_hash.erase("stateHash")
		_check(Combat.commit(blocked, no_state_hash) == blocked, "commit skipped numeric recheck")
	var near_boundary := state.duplicate(true)
	near_boundary.units.wisp.maxHp = 101
	near_boundary.units.wisp.hp = 31
	_check(not Combat.preview(near_boundary, VALUE_ID, "wisp").get("ok", true), "30.69 percent rounded down to 30")
	_value_action.value_conditions[1].value = 40
	_check(Combat.commit(state, preview) == state, "changed numeric rule committed old result")
	_value_action.value_conditions[1].value = 30
	state.units.mira.statuses.clear()
	_check(not Combat.preview(state, VALUE_ID, "wisp").get("ok", true), "numeric/status AND failed")
	state = _value_state()
	state.units.wisp.maxMp = 0
	state.units.wisp.mp = 0
	_value_action.value_conditions = _rows([_value("target", "mp", "lte", "percent", 100)])
	_check("очках" in Combat.action_condition_reason(state, VALUE_ID, "wisp"), "zero maximum percentage not explained")
	_value_action.value_conditions[0].unit = "points"
	_value_action.value_conditions[0].value = 0
	_check(Combat.preview(state, VALUE_ID, "wisp").get("ok", false), "zero MP points unavailable")
	for threshold in [-1, 101]:
		_check(not Conditions.validation_errors({"value_conditions": [_value("actor", "hp", "gte", "percent", threshold)]}, "enemy").is_empty(), "invalid percentage accepted")
	for bad in [{}, _value("actor", "xp", "gte", "points", 10), {"subject": "actor", "stat": "hp", "comparison": "lte", "unit": "percent", "value": 30.5}]:
		_check(not Conditions.validation_errors({"value_conditions": [bad]}, "enemy").is_empty(), "malformed value condition accepted")
	_check(not Conditions.validation_errors({"value_conditions": [_value("actor", "hp", "gte", "percent", 40), _value("target", "hp", "lte", "percent", 30)]}, "self").is_empty(), "SELF numeric conflict accepted")
	_value_action.actor_required_status_ids = PackedStringArray()
	_value_action.target = Action.Target.SELF
	_value_action.effect = Action.Effect.EFFECT_CHAIN
	_value_action.element = Action.Element.SUPPORT
	_value_action.scaling = Action.Scaling.NONE
	_value_action.effect_steps.append(Catalog.Effects.resource("restore_major_hp"))
	_value_action.value_conditions = _rows([_value("target", "hp", "lte", "percent", 30)])
	var healing := Combat.preview(state, VALUE_ID, "mira")
	_check(healing.get("ok", false), "SELF target HP rule skipped/rejected")
	_check(Combat.commit(state, healing).units.mira.hp == 32, "HP predicate rechecked after healing effect")
	_value_action.target = Action.Target.CELL
	_value_action.effect = Action.Effect.EFFECT_CHAIN
	_value_action.effect_steps = Catalog.Actions.resource("earth_wall").effect_steps
	_value_action.value_conditions = _rows([_value("actor", "mp", "gte", "points", 10)])
	_check(not Combat.eligible_target_cells(state, VALUE_ID).is_empty(), "CELL actor MP rule rejected")
	state.units.mira.mp = 9
	_check(Combat.eligible_target_cells(state, VALUE_ID).is_empty(), "CELL actor MP rule skipped")
	_value_action.target = Action.Target.ENEMY
	_value_action.effect = Action.Effect.DAMAGE
	_value_action.effect_steps.clear()
	_value_action.value_conditions = _rows([_value("target", "hp", "lte", "percent", 30)])
	state = _value_state()
	state.units.wisp.nextAt = -1
	state.units.wisp.actions = [VALUE_ID, "defend"]
	state.units.wisp.mp = 20
	state.units.orik.hp = state.units.orik.maxHp
	_check(Combat.eligible_target_ids(state, VALUE_ID) == ["mira"], "AI numeric target eligibility incorrect")
	var ai := Combat.enemy_command(state)
	_check(ai.get("ok", false) and ai.get("actionId") == VALUE_ID and ai.get("targetId") == "mira", "AI failed numeric target selection")
	state.units.mira.hp = state.units.mira.maxHp
	_check(Combat.enemy_command(state).get("actionId", "") != VALUE_ID, "AI selected target above HP threshold")
