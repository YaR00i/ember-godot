extends SceneTree
## Guarded authoring -> exact preview/commit and actual native HUD turn end.
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Rules = preload("res://scripts/prototypes/ember_combat_status_rules.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Status = preload("res://scripts/prototypes/ember_combat_status_resource.gd")
const Effect = preload("res://scripts/prototypes/ember_combat_effect_resource.gd")
const Action = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const POISON := "periodic_fixture_poison"
const REGEN := "periodic_fixture_regen"
const APPLY := "periodic_fixture_apply"
const CLEANSE := "periodic_fixture_cleanse"
var _errors: Array[String] = []
var _paths: Array[String] = []
var _history := UndoRedo.new()

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL periodic gate refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1600, 900)
	Maps.prepare(self, "user://ember-tests/periodic-%d" % OS.get_process_id())
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: _errors.append(message)

func _publish(module: String, resource: Resource) -> void:
	var path := Store.path_for(module, Store.id_for(module, resource))
	_paths.append(path)
	_check(Store.write(module, resource, path) == OK, "publication failed " + path + ": " + str(Store.validation(module, resource)))

func _run() -> void:
	if "--periodic-play" in OS.get_cmdline_user_args():
		await _native()
	else:
		_authoring()
		_timing()
		_lifecycle()
		_enemy_and_outcome()
		_history.clear_history(false)
		_paths.reverse()
		for path in _paths: Store.restore({"path": path, "exists": false})
	_history.free()
	if _errors.is_empty(): print("PASS game systems periodic statuses: saved signed HP rules/forms/Undo/Redo/Discard/UID, healing before damage/clamp/no resurrection/final tick/cleanse/self/ally/AI/outcome/held release, pure exact preview and stale once-only commit")
	else: printerr("FAIL periodic statuses: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _authoring() -> void:
	_check(Store.Catalog.Statuses.resource("poison").turn_end_hp_change == -5 and Store.Catalog.Statuses.resource("regeneration").turn_end_hp_change == 5, "canonical authorable templates missing")
	var session := Session.new()
	session.configure(_history)
	_check(session.create("status", POISON, "Проверочный яд", Store.Catalog.Statuses.resource("poison")), "new periodic status failed")
	_paths.append(session.path)
	var form := Form.new()
	root.add_child(form)
	form.setup(session)
	var input := form.find_child("DraftField_turn_end_hp_change", true, false) as SpinBox
	_check(input != null, "named periodic HP control missing")
	if input != null: input.value = -6
	form.call("_undo_draft")
	_check(session.draft.turn_end_hp_change == -5, "periodic Undo failed")
	form.call("_redo_draft")
	_check(session.draft.turn_end_hp_change == -6, "periodic Redo failed")
	_check(not FileAccess.file_exists(session.path) and session.save(), "periodic draft wrote early / Save failed")
	var uid := ResourceLoader.get_resource_uid(session.path)
	_check(session.open("status", {"path": session.path, "resource": null}) and session.draft.turn_end_hp_change == -6, "saved signed HP value lost at reopen")
	session.set_value("turn_end_hp_change", 1000)
	_check(not Store.validation("status", session.draft).is_empty() and not session.save(), "out-of-range tick saved")
	session.discard()
	_check(Store.Catalog.Statuses.resource(POISON).turn_end_hp_change == -6 and ResourceLoader.get_resource_uid(Store.path_for("status", POISON)) == uid, "Discard changed saved tick/UID")
	form.free()
	var regen := Store.clone(Store.Catalog.Statuses.resource("regeneration"))
	regen.status_id = REGEN
	regen.turn_end_hp_change = 4
	_publish("status", regen)
	for remove in [false, true]:
		var effect := Effect.new()
		effect.effect_id = CLEANSE if remove else APPLY
		effect.display_name = "Снять яд" if remove else "Наложить яд"
		effect.description = "Проверка периодического статуса."
		if remove:
			effect.operation = Effect.Operation.REMOVE_STATUS
			effect.remove_status_ids = PackedStringArray([POISON])
		else:
			effect.status_id = POISON
			effect.status_duration = 0
		_publish("effect", effect)
		var action := Action.new()
		action.action_id = effect.effect_id
		action.display_name = effect.display_name
		action.hint = effect.description
		action.requirements_text = "Союзник в дальности приёма."
		action.target = Action.Target.ALLY
		action.element = Action.Element.SUPPORT
		action.effect = Action.Effect.EFFECT_CHAIN
		action.scaling = Action.Scaling.NONE
		action.range_cells = 99
		action.effect_steps = [Store.Catalog.Effects.resource(effect.effect_id)]
		_publish("action", action)

func _state(actor := "mira", hp := 10) -> Dictionary:
	var state := Combat.initial_state(17)
	for id in state.units:
		state.units[id].nextAt = 1000.0
		state.units[id].statuses = {}
	state.units[actor].nextAt = 0.0
	state.units[actor].hp = hp
	state.units[actor].maxHp = 10
	for action in ["defend", APPLY, CLEANSE]:
		if action not in state.units[actor].actions: state.units[actor].actions.append(action)
	return state

func _step(state: Dictionary, expected: int, action := "defend", target := "") -> Dictionary:
	var actor := Combat.current_unit_id(state)
	var before := state.duplicate(true)
	var preview := Combat.preview(state, action, actor if target.is_empty() else target)
	_check(preview.get("ok", false), "periodic action failed: " + str(preview.get("error")))
	var ending := Combat.turn_end_preview(state, preview)
	var after := Combat.commit(state, preview)
	_check(state == before, "preview/commit mutated input")
	_check(after.units[actor].hp == expected, "wrong end HP: %s != %s" % [after.units[actor].hp, expected])
	if not ending.is_empty(): _check(ending.hp == after.units[actor].hp and ending.statuses == after.units[actor].statuses, "turn-end projection differs from commit")
	_check(Combat.commit(after, preview) == after, "stale command repeated a tick")
	return after

func _timing() -> void:
	var state := _state()
	state.units.mira.statuses = {POISON: 1, REGEN: 1}
	var after := _step(state, 4) # Full HP: healing is wasted BEFORE poison, not netted.
	_check(not after.units.mira.statuses.has(POISON) and not after.units.mira.statuses.has(REGEN), "last tick/expiry order wrong")
	_check("+0 HP" in str(after.log.back()) and "−6 HP" in str(after.log.back()), "log hid capped healing or periodic damage")
	state = _state("mira", 3)
	state.units.mira.statuses = {REGEN: 2, POISON: 2}
	after = _step(state, 1) # Healing first saves the actor from an early poison death.
	_check(after.units.mira.statuses[POISON] == 1 and after.units.mira.statuses[REGEN] == 1, "counter changed more than once")
	var reversed := state.duplicate(true)
	reversed.units.mira.statuses = {POISON: 2, REGEN: 2}
	_check(_step(reversed, 1).units.mira == after.units.mira, "status dictionary order changed health")
	state = _state("mira", 2)
	state.units.mira.statuses = {REGEN: 1}
	_step(state, 6)
	var dead: Dictionary = state.units.mira.duplicate(true)
	dead.hp = 0
	_check(Rules.turn_end(dead).hp == 0, "regeneration resurrected a fallen unit")
	var poison := Store.Catalog.Statuses.resource(POISON)
	poison.incoming_damage_percent = 0
	state = _state()
	state.units.mira.statuses = {POISON: 2, "guard": 2}
	_step(state, 4) # Fixed HP loss bypasses guard and authored damage modifiers.
	poison.incoming_damage_percent = 100
	var regen := Store.Catalog.Statuses.resource(REGEN)
	regen.remove_on_damage = true
	state = _state()
	state.units.mira.statuses = {REGEN: 2, POISON: 2}
	_check(not _step(state, 4).units.mira.statuses.has(REGEN), "periodic damage did not remove remove-on-damage status")
	regen.remove_on_damage = false

func _lifecycle() -> void:
	var own := _state()
	var after := _step(own, 4, APPLY)
	_check(after.units.mira.statuses.get(POISON) == 2, "self application did not tick before counter decay")
	var ally := _state()
	var ally_hp := int(ally.units.orik.hp)
	after = _step(ally, 10, APPLY, "orik")
	_check(after.units.orik.hp == ally_hp and after.units.orik.statuses.get(POISON) == 3, "ally ticked on someone else's turn")
	var cleansed := _state()
	cleansed.units.mira.statuses = {POISON: 1}
	_step(cleansed, 10, CLEANSE)
	var stale := _state()
	stale.units.mira.statuses = {POISON: 2}
	var preview := Combat.preview(stale, "defend", "mira")
	var poison := Store.Catalog.Statuses.resource(POISON)
	poison.turn_end_hp_change = -7
	_check(Combat.commit(stale, preview) == stale, "changed tick rules accepted stale preview")
	poison.turn_end_hp_change = -6
	var intent := Combat.describe_intent(stale, "defend", "mira")
	_check("сначала лечение, затем урон" in intent and "HP 10 →" not in intent and "бросок" not in intent, "public intent omitted order / leaked exact rolled outcome")

func _enemy_and_outcome() -> void:
	var state := _state("wisp", 2)
	state.units.wisp.statuses = {POISON: 1}
	for id in state.units:
		if state.units[id].team == "enemy" and id != "wisp": state.units[id].hp = 0
	var command := Combat.enemy_command(state)
	var after := Combat.commit(state, command)
	_check(command.get("ok", false) and after.units.wisp.hp == 0 and Combat.outcome(after) == "victory", "AI poison death did not finish the battle")
	state = _state("mira", 2)
	state.units.mira.statuses = {POISON: 1}
	for id in state.units:
		if state.units[id].team == "hero" and id != "mira": state.units[id].hp = 0
	_check(Combat.outcome(_step(state, 0)) == "defeat", "last hero poison death did not defeat party")
	# Movement-only AI fallback still ends its own turn and must tick once.
	state = _state("wisp", 8)
	state.units.wisp.statuses = {POISON: 2}
	command = Combat.preview(state, "defend", "wisp")
	command.actionId = ""
	command.erase("actionConditionsHash")
	_check(Combat.commit(state, command).units.wisp.hp == 2, "movement-only completion skipped periodic HP")
	state = _state("mira", 2)
	state.units.mira.statuses = {POISON: 1}
	state.holds = {"mira": "wisp"}
	command = Combat.preview(state, Combat.HELD_GUARD_COMMAND, "mira")
	after = Combat.commit(state, command)
	_check(command.get("ok", false) and after.units.mira.hp == 0 and after.holds.is_empty() and after.units.wisp.hp > 0, "poison carrier death orphaned held target")

func _native() -> void:
	_check(Store.Catalog.Statuses.resource(POISON) != null and Store.Catalog.Statuses.resource(POISON).turn_end_hp_change == -6, "fresh runtime lost editor-authored periodic rule")
	_check(change_scene_to_file("res://scenes/combat_lab.tscn") == OK, "native battle scene failed")
	await scene_changed
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	for frame in 12: await process_frame
	var hud := current_scene.find_child("CombatHUD", true, false)
	_check(hud != null, "native battle HUD missing")
	if hud == null: return
	hud.set("_library_test", true)
	hud.set("_deployment_active", false)
	var state: Dictionary = hud.call("state_snapshot")
	for id in state.units:
		state.units[id].nextAt = 1000.0
		state.units[id].statuses = {}
	state.units.mira.nextAt = 0.0
	state.units.orik.nextAt = 1.0 # Hand control to another hero after this action.
	state.units.mira.hp = 3
	state.units.mira.maxHp = 10
	state.units.mira.statuses = {POISON: 2, "regeneration": 2}
	hud.set("_state", state)
	hud.call("_clear_selected_action_state")
	hud.call("_refresh")
	await _capture("before")
	hud.call("_select_action", "defend")
	for frame in 15: await process_frame
	var after: Dictionary = hud.call("state_snapshot")
	_check(after.units.mira.hp == 2 and after.units.mira.statuses.get(POISON) == 1 and after.units.mira.statuses.get("regeneration") == 1, "native action did not heal first, then poison once")
	_check("Регенерация: +5 HP" in str(after.log.back()) and "−6 HP" in str(after.log.back()), "native log lost actual tick amounts")
	var journal := hud.get("_log_label") as RichTextLabel
	_check("Конец хода" in journal.get_parsed_text(), "native journal did not show turn-end explanation")
	for frame in 6: await process_frame
	var bar := journal.get_v_scroll_bar()
	_check(bar.value + bar.page >= bar.max_value - 1, "native journal did not follow the final periodic line")
	await _capture("after")
	# The existing owner keeps accumulated HP; combat status counters stay battle-local.
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	_check(not progress.persistence_enabled, "native gate enabled persistent user saves")

func _capture(label: String) -> void:
	for frame in 6: await process_frame
	RenderingServer.force_draw(false)
	var path := "user://periodic-%s-%d.png" % [label, OS.get_process_id()]
	_check(root.get_texture().get_image().save_png(path) == OK, "periodic capture failed")
	print("PERIODIC_CAPTURE ", ProjectSettings.globalize_path(path))
