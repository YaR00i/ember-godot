extends SceneTree
## Guarded native authoring -> resolver -> serialization/Undo gate.
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Status = preload("res://scripts/prototypes/ember_combat_status_resource.gd")
const Effect = preload("res://scripts/prototypes/ember_combat_effect_resource.gd")
const Action = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const DraftEditor = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const STATUS_ID := "authoring_fixture_status"
const APPLY_ID := "authoring_fixture_apply"
const REMOVE_ID := "authoring_fixture_remove"
const ACTION_ID := "authoring_fixture_action"
var _errors: Array[String] = []
var _created: Array[String] = []
var _undo := UndoRedo.new()
var _status: Resource

func _init() -> void:
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if actual != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not actual.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL status authoring refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	Maps.prepare(self, "user://status-authoring-%d" % OS.get_process_id())
	_run.call_deferred()

func _run() -> void:
	_test_publication()
	_test_reapplication()
	_test_damage_rules()
	_test_order_and_stale()
	ResourceLoader.load(Store.path_for("status", STATUS_ID), "", ResourceLoader.CACHE_MODE_REPLACE)
	Catalog.refresh()
	await _test_ui()
	_undo.clear_history(false)
	_undo.free()
	_created.reverse()
	for path in _created: Store.restore({"path": path, "exists": false})
	if not _errors.is_empty(): printerr("FAIL status authoring: ", "; ".join(_errors))
	else: print("PASS game systems status authoring: native new status/effects/action, default duration/reapply/resistance/expiry, power/outgoing/incoming/removal, ordered chain, stale/invalid guards, UI operations/pickers/hidden fields/Undo and exact save/reopen")
	quit(0 if _errors.is_empty() else 1)

func _test_publication() -> void:
	var session := Session.new()
	session.configure(_undo)
	_check(session.create("status", STATUS_ID, "Проверочный боевой статус"), "new status could not start")
	_created.append(session.path)
	var values := {"description": "Авторский статус для проверки реального боя.", "kind": Status.Kind.BUFF, "default_duration": 3, "reapply": Status.Reapply.EXTEND, "max_duration": 6, "power_bonus": 4, "outgoing_damage_percent": 125, "incoming_damage_percent": 50, "remove_on_damage": true}
	for key in values:
		session.set_value(key, values[key])
	_check(not FileAccess.file_exists(session.path), "status wrote before Save")
	session.undo()
	_check(not session.draft.remove_on_damage, "new rule Undo failed")
	session.redo()
	_check(session.save(), "new status could not Save: " + session.last_error)
	var sha := Store.signature(session.path)
	var uid := ResourceLoader.get_resource_uid(session.path)
	_undo.undo()
	_check(not FileAccess.file_exists(session.path), "publication Undo did not remove status")
	_undo.redo()
	_check(Store.signature(session.path) == sha and ResourceLoader.get_resource_uid(session.path) == uid, "status publication Redo changed bytes/UID")
	_status = Catalog.Statuses.resource(STATUS_ID)
	_check(_status.default_duration == 3 and _status.max_duration == 6 and _status.power_bonus == 4 and _status.incoming_damage_percent == 50 and _status.remove_on_damage, "new status rules failed native reopen")
	var apply := Effect.new()
	apply.effect_id = APPLY_ID
	apply.display_name = "Наложить авторский статус"
	apply.description = "Длительность из карточки статуса."
	apply.status_id = STATUS_ID
	apply.status_duration = 0
	var remove := Effect.new()
	remove.effect_id = REMOVE_ID
	remove.display_name = "Снять авторский статус"
	remove.description = "Удаление авторского статуса."
	remove.operation = Effect.Operation.REMOVE_STATUS
	remove.remove_status_ids = PackedStringArray([STATUS_ID])
	for effect in [apply, remove]:
		var path := Store.path_for("effect", effect.effect_id)
		_created.append(path)
		_check(Store.write("effect", effect, path) == OK, "could not publish fixture effect")
	var action := Action.new()
	action.action_id = ACTION_ID
	action.display_name = "Проверочный приём"
	action.hint = "Наложение без изменения боевого владельца."
	action.requirements_text = "Союзник в дальности выбранного приёма."
	action.element = Action.Element.SUPPORT
	action.target = Action.Target.ALLY
	action.effect = Action.Effect.EFFECT_CHAIN
	action.scaling = Action.Scaling.NONE
	action.range_cells = 99
	action.effect_steps = [Catalog.Effects.resource(APPLY_ID)]
	var path := Store.path_for("action", ACTION_ID)
	_created.append(path)
	_check(Store.write("action", action, path) == OK, "could not publish composed fixture action: " + " | ".join(Store.validation("action", action)))
	session.discard()

func _state(actor_id := "mira") -> Dictionary:
	var state := Combat.initial_state(17)
	for id in state.units:
		state.units[id].nextAt = 1000.0
		state.units[id].statuses = {}
	state.units[actor_id].nextAt = 0.0
	state.units[actor_id].actions.append(ACTION_ID)
	if "defend" not in state.units[actor_id].actions: state.units[actor_id].actions.append("defend")
	return state

func _test_reapplication() -> void:
	_status.power_bonus = 0
	_status.outgoing_damage_percent = 100
	_status.incoming_damage_percent = 100
	_status.remove_on_damage = false
	for mode in [Status.Reapply.REFRESH, Status.Reapply.KEEP_LONGEST, Status.Reapply.EXTEND, Status.Reapply.IGNORE]:
		_status.reapply = mode
		var state := _state()
		state.units.orik.statuses[STATUS_ID] = 5
		var before := state.duplicate(true)
		var preview := Combat.preview(state, ACTION_ID, "orik")
		var expected: int = [3, 5, 6, 5][mode]
		_check(bool(preview.get("ok", false)) and preview.get("setStatuses", {}).get("orik", {}).get(STATUS_ID) == expected, "reapply did not use existing counter: " + str(mode))
		var committed := Combat.commit(state, preview)
		_check(committed.units.orik.statuses.get(STATUS_ID) == expected and state == before, "preview/commit counter mismatch or source mutation")
	_status.reapply = Status.Reapply.REFRESH
	var resistant := _state()
	resistant.units.orik.statusResistances[STATUS_ID] = 2
	var preview := Combat.preview(resistant, ACTION_ID, "orik")
	_check(preview.get("setStatuses", {}).get("orik", {}).get(STATUS_ID) == 1, "default duration did not respect resistance")
	resistant.units.orik.statusResistances[STATUS_ID] = 3
	preview = Combat.preview(resistant, ACTION_ID, "orik")
	_check(not preview.get("setStatuses", {}).get("orik", {}).has(STATUS_ID), "full resistance did not block status")
	var own := _state()
	preview = Combat.preview(own, ACTION_ID, "mira")
	var committed := Combat.commit(own, preview)
	_check(committed.units.mira.statuses.get(STATUS_ID) == 2, "own action-end counter timing changed")
	for turn in 2:
		for id in committed.units: committed.units[id].nextAt = 1000.0
		committed.units.mira.nextAt = 0.0
		committed = Combat.commit(committed, Combat.preview(committed, "defend", "mira"))
	_check(not committed.units.mira.statuses.has(STATUS_ID), "author status did not expire naturally")

func _strike_state() -> Dictionary:
	var state := _state()
	state.units.mira.zone = 0
	state.units.wisp.zone = 1
	if "strike" not in state.units.mira.actions: state.units.mira.actions.append("strike")
	for seed in range(1, 200):
		state.rngSeed = seed
		var preview := Combat.preview(state, "strike", "wisp")
		if preview.get("hit", false) and not preview.get("critical", true): return state
	_check(false, "could not prepare a deterministic noncritical hit")
	return state

func _test_damage_rules() -> void:
	var state := _strike_state()
	var baseline := Combat.preview(state, "strike", "wisp")
	var base_damage := int(baseline.get("damage", {}).get("wisp", 0))
	_check(base_damage > 0, "baseline attack did not damage fixture enemy")
	_status.power_bonus = 5
	state.units.mira.statuses[STATUS_ID] = 2
	var preview := Combat.preview(state, "strike", "wisp")
	_check(int(preview.get("damage", {}).get("wisp", 0)) > base_damage, "power modifier did not affect real attack")
	_status.power_bonus = 0
	_status.outgoing_damage_percent = 200
	preview = Combat.preview(state, "strike", "wisp")
	_check(int(preview.get("damage", {}).get("wisp", 0)) == base_damage * 2, "outgoing modifier did not affect real attack")
	_status.outgoing_damage_percent = 100
	state.units.mira.statuses = {}
	state.units.wisp.statuses[STATUS_ID] = 2
	_status.incoming_damage_percent = 50
	_status.remove_on_damage = true
	preview = Combat.preview(state, "strike", "wisp")
	var damage := int(preview.get("damage", {}).get("wisp", 0))
	_check(damage == ceili(float(base_damage) * 0.5), "incoming damage modifier failed")
	var committed := Combat.commit(state, preview)
	_check(committed.units.wisp.hp == state.units.wisp.hp - damage and not committed.units.wisp.statuses.has(STATUS_ID), "damage/removal commit did not match preview")
	_status.incoming_damage_percent = 0
	preview = Combat.preview(state, "strike", "wisp")
	committed = Combat.commit(state, preview)
	_check(committed.units.wisp.hp == state.units.wisp.hp and committed.units.wisp.statuses.has(STATUS_ID), "zero damage incorrectly removed status")
	_status.incoming_damage_percent = 100
	_status.remove_on_damage = false

func _test_order_and_stale() -> void:
	var action := Catalog.Actions.resource(ACTION_ID)
	var apply := Catalog.Effects.resource(APPLY_ID)
	var remove := Catalog.Effects.resource(REMOVE_ID)
	var state := _state()
	state.units.orik.statuses[STATUS_ID] = 5
	action.effect_steps = [apply, remove]
	var preview := Combat.preview(state, ACTION_ID, "orik")
	_check(not Combat.commit(state, preview).units.orik.statuses.has(STATUS_ID), "apply -> remove ignored authored order")
	action.effect_steps = [remove, apply]
	preview = Combat.preview(state, ACTION_ID, "orik")
	_check(Combat.commit(state, preview).units.orik.statuses.get(STATUS_ID) == 3, "remove -> apply ignored authored order")
	_status.power_bonus = 1
	_check(Combat.commit(state, preview) == state, "changed status rules did not invalidate old preview")
	_status.default_duration = 0
	_check(not _status.validation_errors().is_empty() and not apply.validation_errors().is_empty(), "invalid status was accepted by dependent effect")
	_check(not bool(Combat.preview(state, ACTION_ID, "orik").get("ok", true)), "invalid active rule entered runtime preview")
	_status.default_duration = 3
	_status.power_bonus = 0
	action.effect_steps = [apply]

func _test_ui() -> void:
	var workspace := Workspace.new()
	workspace.configure(null, _undo)
	root.add_child(workspace)
	workspace.open_resource("systems", "systems_library")
	var hub := workspace.get("_game_systems_workspace") as Control
	hub.call("select_module", "effect", APPLY_ID)
	hub.call("begin_edit")
	var form := hub.get("_draft_editor") as Control
	var operation := form.find_child("DraftField_operation", true, false) as OptionButton
	var picker := form.find_child("DraftField_status_id", true, false) as OptionButton
	_check(picker != null and str(picker.get_item_metadata(picker.selected)) == STATUS_ID, "effect did not use named catalog picker")
	for op in Effect.OPERATION_IDS.size():
		operation.select(op)
		operation.item_selected.emit(op)
		var visible_fields: Array = DraftEditor.EFFECT_FIELDS[Effect.OPERATION_IDS[op]]
		for key in ["status_id", "status_duration", "remove_status_ids", "force", "elevation_delta", "spread_radius", "restore_hp_amount", "move_max_height_delta"]:
			_check((form.find_child("DraftField_" + key, true, false) as Control).visible == (key in visible_fields), "wrong operation fields: " + Effect.OPERATION_IDS[op] + " " + key)
		_check(hub.get("_session").draft.status_id == STATUS_ID, "operation switch lost hidden status reference")
	operation.select(Effect.Operation.REMOVE_STATUS)
	operation.item_selected.emit(Effect.Operation.REMOVE_STATUS)
	var box := form.find_child("DraftField_remove_status_ids", true, false) as VBoxContainer
	var toggle := box.find_child("DraftStatusChoice_wet", true, false) as CheckBox
	toggle.button_pressed = true
	_check("wet" in hub.get("_session").draft.remove_status_ids, "status checklist did not update stored IDs")
	form.call("_undo_draft")
	_check("wet" not in hub.get("_session").draft.remove_status_ids, "status checklist Undo failed")
	hub.call("discard_changes")
	hub.call("select_module", "status", STATUS_ID)
	hub.call("begin_edit")
	form = hub.get("_draft_editor") as Control
	_check((form.find_child("DraftField_max_duration", true, false) as Control).visible, "extend policy did not show duration cap")
	var reapply := form.find_child("DraftField_reapply", true, false) as OptionButton
	reapply.select(Status.Reapply.REFRESH)
	reapply.item_selected.emit(Status.Reapply.REFRESH)
	_check(not (form.find_child("DraftField_max_duration", true, false) as Control).visible, "refresh showed irrelevant accumulation cap")
	var summary := form.find_child("DraftRulesSummary", true, false) as Label
	_check("Обновить" in summary.text, "rule explanation did not update with form")
	workspace.free()
	await process_frame

func _check(condition: bool, error: String) -> void:
	if not condition: _errors.append(error)
