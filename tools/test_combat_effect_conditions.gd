extends SceneTree
## Saved shared effects and the same original-target predicates in player/AI paths.
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Session = preload("res://addons/ember_import/ember_game_systems_session.gd")
const Form = preload("res://addons/ember_import/ember_game_systems_draft_editor.gd")
const Effect = preload("res://scripts/prototypes/ember_combat_effect_resource.gd")
const Action = preload("res://scripts/prototypes/ember_combat_action_resource.gd")
const Rules = preload("res://scripts/prototypes/ember_combat_effect_rules.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const ID := "effect_conditions_fixture"
var _errors: Array[String] = []
var _history := UndoRedo.new()
var _session
var _form: Control
var _effect: Resource
var _action: Resource

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL effect conditions refused non-disposable project")
		quit.call_deferred(2)
		return
	Maps.prepare(self, "user://effect-conditions-%d" % OS.get_process_id())
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok: _errors.append(message)

func _run() -> void:
	_session = Session.new()
	_session.configure(_history)
	_authoring()
	if _effect != null and _action != null:
		_intent()
		if "--effect-intent-play" in OS.get_cmdline_user_args():
			await _native_intent()
		else:
			_runtime()
			_cells_and_ai()
	if _form != null: _form.free()
	_session.discard()
	_history.clear_history(false)
	_history.free()
	for module in ["action", "effect"]: Store.restore({"path": Store.path_for(module, ID), "exists": false})
	if _errors.is_empty(): print("PASS game systems effect conditions: conditional intent/reasons/hidden outcomes, original target snapshot, all/none/status doses, skipped step/base damage, SELF/CELL, player/AI/Grid/footprint/stale guards, validation/links/form/Undo/Redo/Discard/Save/reopen/UID and legacy defaults")
	else: printerr("FAIL effect conditions: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _steps(values: Array) -> Array[Resource]:
	var result: Array[Resource] = []
	result.assign(values)
	return result

func _mount() -> void:
	if _form != null: _form.free()
	_form = Form.new()
	root.add_child(_form)
	_form.setup(_session)

func _toggle(key: String, id: String, value: bool) -> void:
	var field := _form.find_child("DraftField_" + key, true, false)
	var toggle := field.find_child("DraftStatusChoice_" + id, true, false) as CheckBox
	_check(toggle != null, "missing named status checkbox")
	if toggle != null: toggle.button_pressed = value

func _authoring() -> void:
	_check(_session.create("effect", ID, "Заморозить мокрого", Store.Catalog.Effects.resource("apply_frozen")), "create failed")
	_mount()
	var baseline: String = _session.draft.content_signature()
	_toggle("target_required_status_ids", "wet", true)
	_toggle("target_forbidden_status_ids", "burning", true)
	var changed: String = _session.draft.content_signature()
	_check(changed != baseline and Store.validation("effect", _session.draft).is_empty(), "signature/valid predicates failed")
	_form.call("_undo_draft")
	_check(_session.draft.target_forbidden_status_ids.is_empty(), "Undo failed")
	_form.call("_redo_draft")
	_check(_session.draft.content_signature() == changed, "Redo failed")
	for ids in [["wet", "wet"], ["not_in_library"], ["bad id"], [" wet "]]:
		_session.set_value("target_required_status_ids", PackedStringArray(ids))
		_check(not _session.save(), "invalid list published: " + str(ids))
	_session.set_value("target_required_status_ids", PackedStringArray(["missing_saved_status"]))
	_mount()
	_toggle("target_required_status_ids", "missing_saved_status", false)
	_check(_session.draft.target_required_status_ids.is_empty(), "saved missing predicate not correctable")
	_session.set_value("target_required_status_ids", PackedStringArray(["burning"]))
	_check(not _session.save(), "contradiction published")
	_session.set_value("target_required_status_ids", PackedStringArray(["wet"]))
	_session.set_value("operation", Effect.Operation.MOVE_ACTOR)
	_session.set_value("move_max_height_delta", 2)
	_check(not _session.save(), "unreachable empty-destination status predicate published")
	_session.set_value("operation", Effect.Operation.APPLY_STATUS)
	_session.set_value("move_max_height_delta", 0)
	_check(_session.save(), "valid effect Save failed: " + _session.last_error)
	var path := Store.path_for("effect", ID)
	var sha := Store.signature(path)
	var uid := ResourceLoader.get_resource_uid(path)
	_check(_session.open("effect", {"path": path, "resource": null}), "reopen failed")
	_check(_session.draft.content_signature() == changed, "saved predicates changed")
	var links: Array = Store.Catalog.relations("effect", {"resource": _session.draft})
	for id in ["wet", "burning"]:
		_check(links.any(func(link: Dictionary) -> bool: return str(link.get("id", "")) == id), "outgoing condition link absent: " + id)
	var usage: Array = Store.Catalog.incoming_links("status", Store.Catalog.saved_record("status", Store.Catalog.Statuses.resource("wet").resource_path, Store.SPECS), Store.SPECS)
	_check(usage.any(func(row: Dictionary) -> bool: return row.get("confirmed", false) and str(row.get("path", "")) == path), "incoming condition use absent")
	_session.set_value("target_required_status_ids", PackedStringArray())
	_session.discard()
	_check(Store.signature(path) == sha, "Discard wrote file")
	_history.undo()
	_check(not FileAccess.file_exists(path), "publication Undo failed")
	_history.redo()
	_check(Store.signature(path) == sha and ResourceLoader.get_resource_uid(path) == uid, "publication Redo lost bytes/UID")
	_effect = Store.Catalog.Effects.resource(ID)
	_check(_session.create("action", ID, "Условная заморозка", Store.Catalog.Actions.resource("strike")), "create action failed")
	_session.set_value("effect_steps", _steps([_effect]))
	_session.set_value("range_cells", 6)
	_session.set_value("accuracy_modifier", 50)
	_check(_session.save(), "action Save failed: " + _session.last_error)
	_action = Store.Catalog.Actions.resource(ID)
	_effect = _action.effect_steps[0]
	_check(_action != null and _action.effect_steps[0].target_required_status_ids == PackedStringArray(["wet"]), "shared effect reference lost")
	var copied := Store.clone(_effect)
	copied.target_required_status_ids.append("guard")
	var definition: Dictionary = _effect.to_definition()
	definition.targetRequiredStatusIds.append("guard")
	_check(_effect.target_required_status_ids == PackedStringArray(["wet"]), "copy/projection aliases source predicates")

func _state(actor := "mira") -> Dictionary:
	var state := Grid.initial_state(null, 17)
	for id in state.units:
		state.units[id].nextAt = 1000.0
		state.units[id].statuses = {}
		state.units[id].statusResistances = {}
		if id not in ["mira", "orik", "wisp"]: state.units[id].hp = 0
	state.units[actor].nextAt = 0.0
	state.units[actor].actions = [ID, "defend"]
	state.units[actor].mp = 20
	state.units.mira.cell = Vector2i(0, 2)
	state.units.orik.cell = Vector2i(2, 3)
	state.units.wisp.cell = Vector2i(1, 2)
	return state

func _runtime() -> void:
	var state := _state()
	var before := state.duplicate(true)
	var dry := Combat.preview(state, ID, "wisp")
	_check(dry.get("ok", false) and not dry.setStatuses.has("wisp") and dry.damage.has("wisp"), "failed condition blocked damage/did not skip")
	_check("эффект пропущен" in str(dry.notes), "skipped effect unexplained")
	_check(state == before and Combat.commit(state, dry).turn == state.turn + 1, "preview mutated input/commit failed")
	_check(Rules.target_conditions_met(_effect.to_definition(), {"statuses": {"wet": [1, 3]}}), "status doses not recognized")
	state.units.wisp.statuses = {"wet": 2}
	var wet := Combat.preview(state, ID, "wisp")
	_check(wet.get("setStatuses", {}).get("wisp", {}).has("frozen"), "required status/doses not recognized")
	var malformed := wet.duplicate(true)
	malformed.effectConditionsHash = "invalid"
	_check(Combat.commit(state, malformed) == state, "malformed effect hash consumed turn")
	var after := Combat.commit(state, wet)
	_check(after.units.wisp.statuses.has("frozen") and state.units.wisp.statuses == {"wet": 2}, "preview/commit diverged or input mutated")
	_check(Combat.commit(after, wet) == after, "stale command reapplied")
	_check(Grid.action_plan(state, ID, state.units.wisp.cell).ok, "approach rejected conditional action")
	_effect.target_forbidden_status_ids.append("wet")
	_check(Combat.commit(state, wet) == state, "changed effect predicates bypassed stale guard")
	_effect.target_forbidden_status_ids = PackedStringArray(["burning"])
	state.units.wisp.statuses.burning = 2
	_check(not Combat.preview(state, ID, "wisp").get("setStatuses", {}).has("wisp"), "forbidden status ignored")
	state.units.wisp.statuses.erase("burning")
	_effect.target_required_status_ids = PackedStringArray(["wet", "guard"])
	_check(not Combat.preview(state, ID, "wisp").get("setStatuses", {}).has("wisp"), "required list not ALL")
	state.units.wisp.statuses.guard = 2
	_check(Combat.preview(state, ID, "wisp").get("setStatuses", {}).get("wisp", {}).has("frozen"), "ALL rejected both required statuses")
	_effect.target_forbidden_status_ids = PackedStringArray(["burning", "guard"])
	_check(not Combat.preview(state, ID, "wisp").get("setStatuses", {}).has("wisp"), "forbidden list required every forbidden status")
	_effect.target_forbidden_status_ids = PackedStringArray(["burning"])
	_effect.target_required_status_ids = PackedStringArray(["wet"])
	# The base preset and earlier steps may add/remove Wet, but predicates read the input.
	state.units.wisp.statuses.clear()
	_action.effect = Action.Effect.DOUSE
	_check(not Combat.preview(state, ID, "wisp").get("setStatuses", {}).get("wisp", {}).has("frozen"), "base preset satisfied condition retroactively")
	_action.effect = Action.Effect.DAMAGE
	var apply_wet: Resource = Store.Catalog.Effects.resource("apply_wet")
	_action.effect_steps = _steps([apply_wet, _effect])
	_check(not Combat.preview(state, ID, "wisp").get("setStatuses", {}).get("wisp", {}).has("frozen"), "earlier step satisfied condition retroactively")
	var cleanse := Effect.new()
	cleanse.operation = Effect.Operation.REMOVE_STATUS
	cleanse.remove_status_ids = PackedStringArray(["wet"])
	state.units.wisp.statuses = {"wet": 2}
	_action.effect_steps = _steps([cleanse, _effect])
	_check(Combat.preview(state, ID, "wisp").get("setStatuses", {}).get("wisp", {}).has("frozen"), "earlier removal changed condition")
	_action.effect_steps = _steps([_effect, cleanse])
	_check(Combat.preview(state, ID, "wisp").get("setStatuses", {}).get("wisp", {}).has("frozen"), "reordered predicates changed result")
	_action.effect_steps = _steps([_effect])
	_action.target = Action.Target.SELF
	state.units.mira.statuses = {"wet": 2}
	_check(Combat.preview(state, ID, "mira").get("setStatuses", {}).get("mira", {}).has("frozen"), "SELF condition did not use actor")
	_action.target = Action.Target.ENEMY

func _cells_and_ai() -> void:
	_action.effect = Action.Effect.EFFECT_CHAIN
	_action.power = 0
	var state := _state("wisp")
	_check("mira" not in Combat.eligible_target_ids(state, ID) and Combat.enemy_command(state).get("actionId", "") != ID, "player/AI accepted all-skipped chain")
	state.units.mira.statuses = {"wet": 2}
	var ai := Combat.enemy_command(state)
	_check(ai.get("ok", false) and ai.get("actionId", "") == ID and ai.get("targetId", "") == "mira", "AI ignored active conditional step")
	_check(ai.get("setStatuses", {}).get("mira", {}).has("frozen"), "AI result did not use conditional step")
	# A field focus remains a real source of base damage even for authored power 0.
	state.units.mira.statuses.clear()
	_action.element = Action.Element.FIRE
	state.grid.focus = {"effect": "fire_power", "bonus": 3, "cell": state.units.wisp.cell}
	state.grid.cells["1:2"].group = "conditional_focus"
	_check("mira" in Combat.eligible_target_ids(state, ID) and Combat.preview(state, ID, "mira").get("damage", {}).has("mira"), "all-skipped filtering hid base field damage")
	_action.element = Action.Element.PHYSICAL
	_action.target = Action.Target.CELL
	state = _state()
	var cell: Vector2i = state.units.wisp.cell
	state.units.wisp.statuses = {"wet": 2}
	_check(cell in Combat.valid_target_cells(state, ID), "CELL occupant rejected")
	_check(Combat.preview(state, ID, "", Combat.INVALID_CELL, cell).get("setStatuses", {}).get("wisp", {}).has("frozen"), "CELL occupant projection failed")
	_effect.target_required_status_ids = PackedStringArray()
	_effect.target_forbidden_status_ids = PackedStringArray(["burning"])
	_check(not Rules.target_conditions_met(_effect.to_definition(), {}), "empty CELL satisfied absence condition")
	_check(Vector2i(1, 1) not in Combat.valid_target_cells(state, ID), "all-skipped empty cell exposed as a target")
	# Inactive healing cannot block the independent base attack against a full-HP target.
	_effect.operation = Effect.Operation.RESTORE_HP
	_effect.restore_hp_amount = 5
	_effect.target_required_status_ids = PackedStringArray(["guard"])
	_action.target = Action.Target.ENEMY
	_action.effect = Action.Effect.DAMAGE
	_action.power = 4
	_check("wisp" in Combat.valid_target_ids(state, ID), "inactive healing blocked base attack")
	_action.target = Action.Target.CELL
	_action.effect = Action.Effect.EFFECT_CHAIN
	_action.power = 0
	_effect.operation = Effect.Operation.SPREAD
	_effect.spread_status_ids = PackedStringArray(["wet"])
	_effect.spread_radius = 2
	_effect.target_required_status_ids = PackedStringArray(["guard"])
	_check(Combat.action_footprint(state, ID, cell) == [cell], "skipped spread still advertised radius")
	state.units.wisp.statuses.guard = 2
	_check(Combat.action_footprint(state, ID, cell).size() > 1, "active spread footprint missing")
	# Empty predicates preserve unconditional operation, including empty-cell effects.
	_effect.target_required_status_ids = PackedStringArray()
	_effect.target_forbidden_status_ids = PackedStringArray()
	_check(Rules.target_conditions_met(_effect.to_definition(), {}) and Rules.target_conditions_met({}, {}), "legacy defaults changed")


func _intent() -> void:
	var state := _state()
	var initial := state.duplicate(true)
	var dry := Combat.describe_intent(state, ID, "wisp")
	_check("Заморозить мокрого: пропустится — нет статуса «Мокрый»" in dry, "missing required status not explained with authored name")
	_check("выберите цель" in Combat.describe_intent(state, ID), "unselected target presented as failed condition")
	state.units.wisp.statuses = {"wet": 2}
	var wet := Combat.describe_intent(state, ID, "wisp")
	_check("Заморозить мокрого: условия выполнены" in wet and "зависят от попадания" in wet, "satisfied condition promised guaranteed hit or lacked explanation")
	_check(wet.find("Заморозить мокрого:") < wet.find("дальность:"), "conditional text hidden below general details")
	state.units.wisp.statuses.burning = 2
	_check("есть запрещённый статус «Горение»" in Combat.describe_intent(state, ID, "wisp"), "forbidden status not explained")
	_check(Rules.target_condition_reason(_effect.to_definition(), {"statuses": {"wet": [1, 3]}}).is_empty(), "intent rejected active independent doses")
	state = initial.duplicate(true)
	state.grid.cells["1:2"].tags = ["wet"]
	_check("нет статуса «Мокрый»" in Combat.describe_intent(state, ID, "wisp"), "surface wetness satisfied status explanation")
	_action.effect = Action.Effect.DOUSE
	_check("нет статуса «Мокрый»" in Combat.describe_intent(state, ID, "wisp"), "intent used status from base preset")
	_action.effect = Action.Effect.DAMAGE
	_action.target = Action.Target.SELF
	state.units.mira.statuses = {"wet": 2}
	_check("условия выполнены" in Combat.describe_intent(state, ID) and "нет статуса «Мокрый»" not in Combat.describe_intent(state, ID, "wisp"), "SELF intent did not use original actor")
	_action.target = Action.Target.CELL
	_check("на клетке нет бойца" in Combat.describe_intent(state, ID, "", Combat.INVALID_CELL, {}, Vector2i(1, 1)), "empty cell not distinguished from unchosen target")
	state.units.wisp.statuses.wet = 2
	_check("условия выполнены" in Combat.describe_intent(state, ID, "", Combat.INVALID_CELL, {}, state.units.wisp.cell), "CELL intent did not resolve occupant")
	var staged := state.duplicate(true)
	staged.units.wisp.cell = Vector2i(2, 2)
	_check("на клетке нет бойца" in Combat.describe_intent(state, ID, "wisp", Combat.INVALID_CELL, staged, state.units.wisp.cell), "CELL intent ignored staged occupancy")
	_action.target = Action.Target.ENEMY
	state = initial.duplicate(true)
	state.units.wisp.statuses = {"wet": 2}
	var accuracy: int = _action.accuracy_modifier
	_action.accuracy_modifier = -30
	var copy := Combat.describe_intent(state, ID, "wisp")
	var hits := {}
	for seed_value in range(1, 65):
		state.rngSeed = seed_value
		var before := state.duplicate(true)
		var resolved := Combat.preview(state, ID, "wisp")
		hits[resolved.get("hit", false)] = true
		_check(Combat.describe_intent(state, ID, "wisp") == copy and state == before, "intent disclosed RNG/outcome or mutated snapshot")
	for secret in ["hitRoll", "critRoll", "Попадание ", "бросок ", "КРИТ", "ПРОМАХ", " HP", "−", "%"]:
		_check(secret not in copy, "conditional intent leaked outcome: " + secret)
	_check(hits.has(true) and hits.has(false), "privacy fixture did not cover both hits and misses")
	_action.accuracy_modifier = accuracy
	_check(Rules.conditional_intent(Store.Catalog.Actions.resource("strike").to_definition(), {}, false).is_empty(), "legacy action gained empty conditional block")


func _native_intent() -> void:
	if _form != null:
		_form.free()
		_form = null
	var heat := Store.clone(Store.Catalog.Effects.resource("apply_burning"))
	heat.effect_id = "intent_heat_fixture"
	heat.display_name = "Тепловой отклик"
	heat.target_required_status_ids = PackedStringArray(["frozen"])
	_action.effect_steps.assign([_effect, heat])
	if OS.get_environment("EMBER_UI_LAYOUT") == "1":
		for index in 4:
			var extra := Store.clone(_effect)
			extra.effect_id = "layout_step_%d" % index
			extra.display_name = "Дополнительный условный эффект с длинным названием №%d" % (index + 1)
			_action.effect_steps.append(extra)
	_check(ResourceSaver.save(_action, Store.path_for("action", ID)) == OK, "native intent fixture save failed")
	_check(change_scene_to_file("res://scenes/combat_lab.tscn") == OK, "native scene load failed")
	await scene_changed
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	if OS.get_environment("EMBER_UI_LAYOUT") == "1":
		DisplayServer.window_set_size(Vector2i(1280, 800))
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_factor = 1.25
	for frame in 15: await process_frame
	var hud := current_scene.find_child("CombatHUD", true, false)
	_check(hud != null, "native intent HUD missing")
	if hud == null: return
	hud.set("_library_test", true)
	hud.set("_deployment_active", false)
	hud.set("_encounter_mode", "grid")
	var state := _state()
	state.units.wisp.statuses = {"wet": 2}
	state.units.warden.hp = state.units.warden.maxHp
	state.units.warden.cell = Vector2i(2, 2)
	state.units.warden.statuses = {"frozen": 2}
	hud.set("_state", state)
	hud.call("_clear_selected_action_state")
	hud.set("_pending_actor_id", "")
	hud.set("_pending_cell", Combat.INVALID_CELL)
	hud.call("_refresh")
	var original: Dictionary = hud.call("state_snapshot")
	hud.call("_select_action", ID)
	var info := hud.get("_ability_info_label") as RichTextLabel
	_check("выберите цель" in info.text, "native unchosen target omitted prompt")
	hud.call("_on_grid_cell_hovered", state.units.wisp.cell)
	_check("Заморозить мокрого: условия выполнены" in info.text and "Тепловой отклик: пропустится" in info.text, "native wet hover info stale/wrong")
	var preview_label := hud.get("_preview_label") as RichTextLabel
	_check("Заморозить мокрого: условия выполнены" in preview_label.text, "legacy intent panel disagrees")
	await _capture_intent("wet")
	if OS.get_environment("EMBER_UI_LAYOUT") == "1":
		var bounds: Rect2 = hud.get_viewport_rect()
		print("LAYOUT_BATTLE ", bounds, " scale ", root.content_scale_factor)
		for control in [hud.get("_ability_info_panel"), hud.get("_console_panel"), hud.get("_console_input"), hud.get("_footer"), hud.get("_timeline_panel"), hud.get("_reset_button"), hud.find_child("CombatPauseButton", true, false)]:
			if not bounds.grow(2).encloses(control.get_global_rect()) or control.size.x < 32 or control.size.y < 24:
				_check(false, "battle control outside 125 percent viewport: " + str(control.name) + " " + str(control.get_global_rect()))
		_check(info.size.x >= 300.0, "conditional explanation too narrow to read")
		var bar := info.get_v_scroll_bar()
		bar.value = bar.max_value
		for frame in 3: await process_frame
		_check(bar.value > 0.0, "conditional card cannot scroll to the remaining explanation")
		await _capture_intent("scrolled")
		bar.value = 0.0
	hud.call("_on_grid_cell_hovered", state.units.warden.cell)
	_check("Заморозить мокрого: пропустится" in info.text and "Тепловой отклик: условия выполнены" in info.text, "native frozen hover info stale/wrong")
	await _capture_intent("frozen")
	hud.call("_on_grid_cell_hovered", Vector2i(1, 1))
	_check("пропустится" in info.text and "на клетке нет бойца" in info.text, "native empty hover lost reason")
	await _capture_intent("empty")
	_check(hud.call("state_snapshot") == original, "hover consumed MP/turn/status or changed battle")
	hud.call("_cancel_radial_targeting")
	_check(hud.call("state_snapshot") == original, "cancel after conditional hover changed battle")
	_check(not root.get_node("EmberExploreProgress").persistence_enabled, "native intent enabled real saves")


func _capture_intent(label: String) -> void:
	for frame in 6: await process_frame
	RenderingServer.force_draw(false)
	var path := "user://effect-intent-%s-%d.png" % [label, OS.get_process_id()]
	if not OS.get_environment("EMBER_UI_EVIDENCE").is_empty(): path = OS.get_environment("EMBER_UI_EVIDENCE").path_join("battle-" + label + ".png")
	_check(root.get_texture().get_image().save_png(path) == OK, "native intent capture failed")
	print("EFFECT_INTENT_CAPTURE ", ProjectSettings.globalize_path(path))
