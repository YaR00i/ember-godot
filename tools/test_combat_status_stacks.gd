extends SceneTree
## Independent periodic doses through canonical Resources, the resolver and native HUD.
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Rules = preload("res://scripts/prototypes/ember_combat_status_rules.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Schema = preload("res://scripts/prototypes/ember_combat_state_schema.gd")
const Action = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const Effect = preload("res://scripts/prototypes/ember_combat_effect_resource.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const POISON := "periodic_fixture_poison"
const REGEN := "stacks_fixture_regen"
const APPLY := "stacks_fixture_apply"
const CLEANSE := "stacks_fixture_cleanse"
var _errors: Array[String] = []
var _paths: Array[String] = []
var _history := UndoRedo.new()

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL stack gate refused non-disposable project")
		quit.call_deferred(2)
		return
	Maps.prepare(self, "user://stacks-%d" % OS.get_process_id())
	root.size = Vector2i(1600, 900)
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: _errors.append(message)

func _publish(module: String, resource: Resource) -> void:
	var path := Store.path_for(module, Store.id_for(module, resource))
	_paths.append(path)
	_check(Store.write(module, resource, path) == OK, "fixture publication failed: " + path)

func _run() -> void:
	if "--stacks-play" in OS.get_cmdline_user_args():
		await _native()
	else:
		_authoring()
		_setup()
		_lifecycle()
		_combat()
	_history.clear_history(false)
	_history.free()
	_paths.reverse()
	for path in _paths: Store.restore({"path": path, "exists": false})
	if _errors.is_empty(): print("PASS game systems independent doses: authoring/validation/Undo/Redo/Discard/Save/reopen/UID, cap earliest replacement, timers/decay/cleanse/heal-first/death, shared preview/commit/AI/conditions/schema and native HUD")
	else: printerr("FAIL independent doses: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _authoring() -> void:
	var session := Session.new()
	session.configure(_history)
	_check(session.create("status", POISON, "Яд дозами", Store.Catalog.Statuses.resource("poison")), "dose draft failed")
	_paths.append(session.path)
	var form := Form.new()
	root.add_child(form)
	form.setup(session)
	(form.find_child("DraftField_turn_end_hp_change", true, false) as SpinBox).value = -6
	(form.find_child("DraftField_max_stacks", true, false) as SpinBox).value = 3
	form.call("_undo_draft")
	_check(session.draft.max_stacks == 1, "dose limit Undo failed")
	form.call("_redo_draft")
	_check(session.draft.max_stacks == 3, "dose limit Redo failed")
	_check(not (form.find_child("DraftField_reapply", true, false) as Control).visible and session.save(), "dose mode did not hide single reapply / Save failed")
	var sha := Store.signature(session.path)
	var uid := ResourceLoader.get_resource_uid(session.path)
	_check(session.open("status", {"path": session.path, "resource": null}) and session.draft.max_stacks == 3 and session.draft.turn_end_hp_change == -6, "dose Save/reopen failed")
	for cap in [0, 13]:
		session.set_value("max_stacks", cap)
		_check(not session.save(), "invalid cap published")
	session.set_value("max_stacks", 3)
	session.set_value("turn_end_hp_change", 0)
	_check(not session.save(), "nonperiodic doses accepted")
	session.discard()
	_check(Store.signature(Store.path_for("status", POISON)) == sha and ResourceLoader.get_resource_uid(Store.path_for("status", POISON)) == uid, "Discard changed dose file/UID")
	_history.undo()
	_check(not FileAccess.file_exists(Store.path_for("status", POISON)), "publication Undo failed")
	_history.redo()
	_check(Store.signature(Store.path_for("status", POISON)) == sha, "publication Redo lost exact bytes")
	form.free()

func _setup() -> void:
	var regen := Store.clone(Store.Catalog.Statuses.resource("regeneration"))
	regen.status_id = REGEN
	regen.max_stacks = 3
	regen.turn_end_hp_change = 4
	_publish("status", regen)
	for remove in [false, true]:
		var effect := Effect.new()
		effect.effect_id = CLEANSE if remove else APPLY
		effect.display_name = "Снять все дозы" if remove else "Добавить дозу"
		effect.description = "Проверка независимых доз."
		if remove:
			effect.operation = Effect.Operation.REMOVE_STATUS
			effect.remove_status_ids = PackedStringArray([POISON])
		else:
			effect.status_id = POISON
		_publish("effect", effect)
		var action := Action.new()
		action.action_id = effect.effect_id
		action.display_name = effect.display_name
		action.hint = effect.description
		action.requirements_text = "Выберите бойца."
		action.target = Action.Target.ALLY if remove else Action.Target.ENEMY
		action.effect = Action.Effect.EFFECT_CHAIN
		action.element = Action.Element.SUPPORT
		action.scaling = Action.Scaling.NONE
		action.range_cells = 99
		action.effect_steps.append(Store.Catalog.Effects.resource(effect.effect_id))
		_publish("action", action)

func _state() -> Dictionary:
	var state := Combat.initial_state(17)
	for id in state.units:
		state.units[id].nextAt = 0.0 if id == "mira" else 1000.0
		state.units[id].statuses = {}
	state.units.mira.maxHp = 100
	state.units.mira.hp = 100
	state.units.mira.actions = [APPLY, CLEANSE, "defend"]
	return state

func _lifecycle() -> void:
	var resolved := {"ok": true}
	var existing := {POISON: [4, 2, 3]}
	Rules.set_status(resolved, "mira", POISON, 5, existing)
	_check(resolved.setStatuses.mira[POISON] == [4, 5, 3] and existing[POISON] == [4, 2, 3], "cap did not replace earliest / mutated source")
	resolved = {"ok": true}
	Rules.set_status(resolved, "mira", POISON, 3, {})
	Rules.set_status(resolved, "mira", POISON, 2, {})
	_check(resolved.setStatuses.mira[POISON] == [3, 2], "two applications in one effect chain lost a dose")
	Rules.set_status(resolved, "mira", POISON, 4, {POISON: 1})
	_check(resolved.setStatuses.mira[POISON] == [3, 2, 4], "pending doses read old source again")
	var unit: Dictionary = _state().units.mira
	unit.statuses = {POISON: [1, 3], REGEN: [2, 1]}
	unit.maxHp = 10
	unit.hp = 3
	var before := unit.duplicate(true)
	var ending := Rules.turn_end(unit)
	_check(ending.healedHp == 10 and ending.hp == 0 and ending.healing == 7 and ending.damage == 10 and unit == before, "doses did not clamp healing before lethal poison / mutated preview")
	_check(ending.statuses[POISON] == [2] and ending.statuses[REGEN] == [1], "independent last tick/expiry failed")
	unit.statuses = {REGEN: [1, 2]}
	unit.hp = 0
	_check(Rules.turn_end(unit).hp == 0, "stacked regeneration resurrected dead unit")
	unit.hp = 50
	unit.maxHp = 100
	unit.statuses = {POISON: [1, 3]}
	var poison := Store.Catalog.Statuses.resource(POISON)
	poison.power_bonus = 2
	poison.outgoing_damage_percent = 150
	_check(Rules.power_bonus(unit) == 2 and Rules.damage_amount(unit, 10, true) == 15, "doses multiplied nonperiodic properties")
	poison.power_bonus = 0
	poison.outgoing_damage_percent = 100
	poison.remove_on_damage = true
	_check(not Rules.turn_end(unit).statuses.has(POISON), "damage cleanup retained doses")
	poison.remove_on_damage = false
	# Legacy integer counters still mean a single dose after enabling accumulation.
	_check(Rules.decay({POISON: 3, "wet": 2}) == {POISON: 2, "wet": 1}, "legacy integer counters changed")
	for bad in [[], [0], [-1], [1.5], ["2"], [1, 2, 3, 4]]:
		var state := _state()
		state.units.mira.statuses[POISON] = bad
		_check(not Schema.first_error(state).is_empty(), "malformed dose snapshot accepted: " + str(bad))

func _combat() -> void:
	var state := _state()
	state.units.wisp.statuses = {POISON: [1, 3]}
	var before := state.duplicate(true)
	var preview := Combat.preview(state, APPLY, "wisp")
	var after := Combat.commit(state, preview)
	_check(preview.get("ok", false) and state == before and after.units.wisp.statuses[POISON] == [1, 3, 3], "real apply/preview/commit lost independent target dose")
	_check(Combat.commit(after, preview) == after, "dose command committed twice")
	state.units.mira.hp = 30
	state.units.mira.statuses = {POISON: [1, 3], REGEN: [2, 3]}
	preview = Combat.preview(state, "defend", "mira")
	var ending := Combat.turn_end_preview(state, preview)
	after = Combat.commit(state, preview)
	_check(ending.hp == 26 and after.units.mira.hp == 26 and after.units.mira.statuses[POISON] == [2] and after.units.mira.statuses[REGEN] == [1, 2], "shared turn-end preview/commit diverged")
	var changed := state.duplicate(true)
	changed.units.mira.statuses[POISON] = [2]
	_check(Combat.commit(changed, preview) == changed, "changed doses bypassed state guard")
	var poison := Store.Catalog.Statuses.resource(POISON)
	poison.max_stacks = 2
	_check(Combat.commit(state, preview) == state, "changed cap bypassed status-content guard")
	poison.max_stacks = 3
	preview = Combat.preview(state, CLEANSE, "mira")
	after = Combat.commit(state, preview)
	_check(preview.get("ok", false) and not after.units.mira.statuses.has(POISON) and after.units.mira.hp == 38, "cleanse failed to remove every dose before end of turn")
	var conditional := Store.Catalog.Actions.resource(APPLY)
	conditional.actor_required_status_ids = PackedStringArray([POISON])
	_check(Combat.preview(state, APPLY, "wisp").get("ok", false), "status conditions rejected active array dose")
	conditional.actor_required_status_ids = PackedStringArray()
	var self_state := _state()
	self_state.units.mira.statuses = {POISON: [2]}
	conditional.target = Action.Target.SELF
	var self_preview := Combat.preview(self_state, APPLY, "mira")
	var self_after := Combat.commit(self_state, self_preview)
	_check(self_preview.get("ok", false) and self_after.units.mira.hp == 88 and self_after.units.mira.statuses[POISON] == [1, 2], "self-applied new dose did not tick exactly once with existing dose")
	conditional.target = Action.Target.ENEMY
	state.units.mira.statuses.clear()
	state.units.wisp.actions = [APPLY, "defend"]
	state.units.wisp.nextAt = 0.0
	state.units.mira.nextAt = 1000.0
	var ai := Combat.enemy_command(state)
	_check(ai.get("ok", false) and ai.get("actionId") == APPLY, "actual AI did not use dose action")
	after = Combat.commit(state, ai)
	_check(after.units[ai.targetId].statuses[POISON].size() == 1, "AI commit did not apply dose")

func _native() -> void:
	var poison := Store.Catalog.Statuses.resource(POISON)
	_check(poison != null and poison.max_stacks == 3 and poison.turn_end_hp_change == -6, "fresh process lost native authored dose settings")
	_check(change_scene_to_file("res://scenes/combat_lab.tscn") == OK, "native battle scene failed")
	await scene_changed
	for frame in 15: await process_frame
	var hud := current_scene.find_child("CombatHUD", true, false)
	_check(hud != null, "native HUD missing")
	if hud == null: return
	hud.set("_library_test", true)
	hud.set("_deployment_active", false)
	var state: Dictionary = hud.call("state_snapshot")
	for id in state.units:
		state.units[id].nextAt = 1000.0
		state.units[id].statuses = {}
	state.units.mira.nextAt = 0.0
	state.units.orik.nextAt = 1.0
	state.units.mira.hp = 25
	state.units.mira.maxHp = 30
	state.units.mira.statuses = {POISON: [1, 3], "regeneration": 2}
	hud.set("_state", state)
	hud.call("_clear_selected_action_state")
	hud.call("_refresh")
	_check("×2" in str(hud.call("_status_text", state.units.mira)) and "1/3" in str(hud.call("_status_icon_text", state.units.mira)), "native dose count/timers missing")
	var badge := current_scene.find_child("CombatStatus_mira_" + POISON, true, false) as Label3D
	_check(badge != null and "×2" in badge.text, "3D status badge lost dose count")
	await _capture("before")
	hud.call("_select_action", "defend")
	for frame in 15: await process_frame
	var after: Dictionary = hud.call("state_snapshot")
	_check(after.units.mira.hp == 18 and after.units.mira.statuses[POISON] == [2], "native defend did not heal then tick both doses/expire one")
	_check("×2" in str(after.log.back()) and "−12 HP" in str(after.log.back()), "native log lost multiplied dose damage")
	await _capture("after")
	_check(not root.get_node("EmberExploreProgress").persistence_enabled, "native dose test enabled user saves")

func _capture(label: String) -> void:
	for frame in 6: await process_frame
	RenderingServer.force_draw(false)
	var path := "user://stacks-%s-%d.png" % [label, OS.get_process_id()]
	_check(root.get_texture().get_image().save_png(path) == OK, "native capture failed")
	print("STACKS_CAPTURE ", ProjectSettings.globalize_path(path))
