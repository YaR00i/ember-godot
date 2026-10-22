extends SceneTree
## Normal game lifecycle; author data arrives only from the preceding editor process.
const Fixture = preload("res://tools/fixtures/ember_game_systems_cycle_fixture.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Catalog = preload("res://addons/ember_import/ember_game_systems_catalog.gd")
var _errors: Array[String] = []
var _isolation := {}
var _progress: EmberExploreState
var _loading := false
var _map_hash := ""
var _save_hash := ""
var _source: PackedScene
const SEMANTIC_KEYS := ["party", "inventory", "flags", "activeHeroIds", "battleStrategy", "openedChests", "shopStock", "mapId"]

func _init() -> void:
	if not Fixture.guarded():
		printerr("FAIL cycle runtime refused non-disposable project")
		quit.call_deferred(2)
		return
	_loading = "--cycle-load" in OS.get_cmdline_user_args()
	root.size = Vector2i(1600, 900)
	_isolation = Maps.prepare(self, Fixture.DIRECTORY)
	if _loading:
		# Register the saved native fixture before autoload validates its destination.
		_source = ResourceLoader.load(_map_file(), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if _source != null: _source.take_over_path(EmberMapTransition.scene_path(Fixture.MAP))
	_run.call_deferred()

func _frames(count: int) -> void:
	for index in count: await process_frame

func _map_file() -> String:
	return Fixture.DIRECTORY.path_join(Fixture.MAP + ".tscn")

func _freeze_player() -> void:
	var player := current_scene.get_node("Player")
	player.set_physics_process(false)

func _capture(label: String) -> void:
	await _frames(6)
	RenderingServer.force_draw(false)
	var path := Fixture.DIRECTORY.path_join(label + ".png")
	_check(root.get_texture().get_image().save_png(path) == OK, "capture failed: " + label)
	print("CYCLE_CAPTURE ", ProjectSettings.globalize_path(path))

func _run() -> void:
	_progress = root.get_node("EmberExploreProgress") as EmberExploreState
	_progress.set_process(false)
	_check(_isolation.error == OK and _isolation.progress_isolated, "save isolation did not precede autoload readiness")
	_check(not EmberCombatTransition.isolated_editor_process_requested(), "full cycle accidentally entered reward-disabled library test mode")
	_errors.append_array(Fixture.file_errors())
	if _loading:
		_check(_progress.flags.get("cycle_won", false) and _progress.party.mira.level == 2 and _progress.inventory.get(Fixture.POTION) == 8, "cold autoload did not read private saved progress")
	if not _errors.is_empty():
		_finish()
		return
	var scene: PackedScene
	if _loading:
		scene = _source
	else:
		_source = Maps.save_map(Fixture.MAP, Fixture.DIRECTORY)
		scene = _source
	_check(scene != null, "saved native fixture map missing")
	if scene == null:
		_finish()
		return
	_map_hash = FileAccess.get_sha256(_map_file())
	_progress.persistence_enabled = true
	_progress.restore_enabled = true
	_check(change_scene_to_file(EmberMapTransition.scene_path(Fixture.MAP)) == OK, "initial native map failed")
	if not _errors.is_empty():
		_finish()
		return
	await scene_changed
	await _frames(2)
	_freeze_player()
	if _loading: await _fresh_load()
	else: await _play()
	_errors.append_array(Fixture.file_errors())
	_check(FileAccess.get_sha256(_map_file()) == _map_hash, "gameplay changed saved fixture map")
	_finish()

func _play() -> void:
	_check(_progress.set_active_hero_ids(["mira"], false), "native active party setup failed")
	_check(_progress.party.mira.equipment.weapon == Fixture.WEAPON and _progress.party.mira.level == 1 and _progress.party.mira.xp == 0, "fresh new game lost authored worn starter weapon")
	_check(_progress.inventory.get(Fixture.POTION) == 3 and _progress.inventory.get("coin") == 27 and not _progress.inventory.has(Fixture.WEAPON), "fresh new game lost authored bag or duplicated worn weapon")
	_check(_progress.party.mira.equipment.shoes == Fixture.SHOES, "fresh game lost starter shoes")
	var inventory := current_scene.find_child("InventoryUI", true, false) as EmberInventoryUi
	_check(inventory != null, "normal inventory missing for footwear")
	if inventory == null: return
	inventory.open()
	inventory.set("_mode", EmberInventoryUi.MODE_EQUIPMENT)
	inventory.set("_slot_index", EmberEquipment.SLOTS.find("shoes"))
	inventory.call("_refresh")
	inventory.confirm()
	_check(_progress.party.mira.equipment.shoes == null and _progress.party_member_view("mira").moveRange == Catalog.Units.resource("mira").move_range, "native unequip did not restore base MOVE")
	_check(inventory.select_item(Fixture.SHOES), "normal inventory could not select authored shoes")
	inventory.confirm()
	_check(_progress.party.mira.equipment.shoes == Fixture.SHOES and "MOVE" in str(inventory.view_state().equipment), "native equip did not apply/display shoe stats")
	await _capture("footwear-inventory")
	inventory.close()
	var member: Dictionary = _progress.party.mira
	var derived := EmberPartyState.derived_stats("mira", member, EmberItemCatalog.definitions())
	member.hp = int(derived.maxHp) - 6
	_progress.party.mira = member
	var player := current_scene.get_node("Player") as EmberPlayer
	player.global_position = Vector3(43.25, 5.0, 27.5)
	_check(_progress.save_autosave(), "prebattle autosave failed")
	var persistent_party := _progress.party.duplicate(true)
	var persistent_inventory := _progress.inventory.duplicate(true)
	var encounter := EmberEncounterCatalog.definition(Fixture.ENCOUNTER)
	_check(encounter != null and encounter.battlefield.field_id == Fixture.FIELD and encounter.victory_xp == 35, "fresh process lost authored encounter/field")
	_check(Fixture.ACTION in Catalog.Units.resource("mira").action_ids and Catalog.Actions.resource(Fixture.ACTION).mp_cost == 2, "fresh process lost assignment or read discarded draft")
	_check(Catalog.Actions.resource(Fixture.ACTION).actor_forbidden_status_ids == PackedStringArray(["frozen"]), "fresh process lost saved status predicate")
	_check(Catalog.Actions.resource(Fixture.ACTION).value_conditions == [{"subject": "actor", "stat": "hp", "comparison": "gte", "unit": "percent", "value": 1}], "fresh process lost saved numeric predicate")
	_check(Catalog.Actions.resource(Fixture.ACTION).equipment_conditions == [{"subject": "actor", "slot": "", "mode": "item", "item_id": Fixture.WEAPON}], "fresh process lost saved gear predicate")
	if not _errors.is_empty(): return
	_check(_start_from_map(), "normal encounter transition failed")
	if not _errors.is_empty(): return
	await scene_changed
	# Normal Lab requests fullscreen; keep this automated GPU gate in one window.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(10)
	var hud := current_scene.find_child("CombatHUD", true, false)
	if hud == null:
		_check(false, "native battle HUD missing")
		return
	_assert_arena(hud)
	await _capture("deployment")
	hud.call("_confirm_deployment")
	var initial: Dictionary = hud.call("state_snapshot")
	_check(not hud.get("_library_test") and initial.encounterId == Fixture.ENCOUNTER and initial.units.size() == 4, "normal battle did not consume new saved content")
	_check(initial.units.mira.equipment.weapon == Fixture.WEAPON and initial.units.mira.maxHp == derived.maxHp and int(initial.units.mira.str) == int(derived.str), "authored equipment bonus failed battle projection")
	_check(initial.units.mira.moveRange == derived.moveRange and initial.units.mira.jumpHeight == derived.jumpHeight and initial.units.mira.pushResistance == derived.pushResistance and initial.units.mira.statusResistances.wet == derived.statusResistances.wet, "authored footwear failed normal map-to-battle projection")
	_check(Fixture.ACTION in Combat.command_ids_for_current_actor(initial) and "item:" + Fixture.POTION in Combat.combat_item_ids(initial), "new action/consumable absent from battle menu")
	hud = await _defeat_paths(hud, initial)
	if hud == null or not _errors.is_empty(): return
	initial = hud.call("state_snapshot")
	var blocked := initial.duplicate(true)
	blocked.units.mira.statuses.frozen = 2
	_check(not Combat.preview(blocked, Fixture.ACTION, Fixture.ENEMY).get("ok", true), "saved predicate not enforced in fresh runtime")
	blocked = initial.duplicate(true)
	blocked.units.mira.maxHp = 1000 * int(blocked.units.mira.hp)
	_check("HP" in Combat.action_condition_reason(blocked, Fixture.ACTION, Fixture.ENEMY) and not Combat.preview(blocked, Fixture.ACTION, Fixture.ENEMY).get("ok", true), "saved numeric predicate not enforced in fresh runtime")
	blocked = initial.duplicate(true)
	blocked.units.mira.equipment.weapon = null
	blocked.inventory[Fixture.WEAPON] = 1
	_check(not Combat.action_condition_reason(blocked, Fixture.ACTION, Fixture.ENEMY).is_empty() and not Combat.preview(blocked, Fixture.ACTION, Fixture.ENEMY).get("ok", true), "saved gear predicate accepted bag-only weapon in fresh runtime")
	blocked = initial.duplicate(true)
	blocked.units[Fixture.ENEMY].statuses = {"burning": 2}
	var skipped := Combat.preview(blocked, Fixture.ACTION, Fixture.ENEMY)
	_check(skipped.get("ok", false) and skipped.damage.has(Fixture.ENEMY) and not skipped.get("setStatuses", {}).get(Fixture.ENEMY, {}).has(Fixture.STATUS), "saved effect predicate did not skip only bonus step")
	blocked = initial.duplicate(true)
	blocked.units[Fixture.ENEMY].statuses = {"frozen": 2}
	_check(not Combat.preview(blocked, Fixture.ACTION, Fixture.ENEMY).get("ok", true) and "ИЛИ" in Combat.action_condition_reason(blocked, Fixture.ACTION, Fixture.ENEMY), "saved OR did not block both failed alternatives")
	blocked.units[Fixture.ENEMY].statuses.wet = 2
	_check(Combat.preview(blocked, Fixture.ACTION, Fixture.ENEMY).get("ok", false), "saved OR did not accept Wet alternative in fresh runtime")
	await _capture("battle")
	# These are the same selection handlers used by the native action buttons.
	hud.call("_select_action", "item:" + Fixture.POTION)
	hud.call("_select_target", "mira")
	await _frames(10)
	var consumed: Dictionary = hud.call("state_snapshot")
	_check(consumed.inventory.get(Fixture.POTION) == 2 and int(consumed.units.mira.hp) == int(initial.units.mira.hp) + 4, "authored consumable failed native selection/commit")
	_check(_progress.party == persistent_party and _progress.inventory == persistent_inventory, "battle input mutated progress before Continue")
	var marked := false
	var stacked := false
	for attempt in 24:
		var before: Dictionary = hud.call("state_snapshot")
		if Combat.outcome(before) != "active": break
		_check(Combat.current_unit_id(before) == "mira", "enemy AI did not return control to hero")
		var target_id := ""
		for enemy in encounter.enemy_instances():
			if int(before.units[enemy.id].hp) > 0:
				target_id = enemy.id
				break
		_check(not target_id.is_empty(), "living enemy instance missing before victory")
		hud.call("_select_action", Fixture.ACTION)
		hud.call("_select_target", target_id)
		await _frames(10)
		var after: Dictionary = hud.call("state_snapshot")
		var doses: Variant = after.units[target_id].statuses.get(Fixture.STATUS, 0)
		if Combat.StatusRules.remaining(doses) > 0: marked = true
		if doses is Array and doses.size() == 2: stacked = true
		_check(after.turn > before.turn and int(after.units.mira.mp) == int(before.units.mira.mp) - 2, "authored action failed commit/cost")
	var final: Dictionary = hud.call("state_snapshot")
	_check(marked and stacked and Combat.outcome(final) == "victory", "saved action/effect/independent doses failed actual victory")
	var report := EmberCombatResult.build(encounter, final, "victory")
	_check(report.xpReward == 35 and report.lootRewards.size() == 1 and report.lootRewards[0].itemId == Fixture.POTION and int(report.lootRewards[0].count) == 6 and report.defeatedEnemyIds.size() == 3 and report.counterDeltas.combat_defeated_total == 3, "authored result lost XP or guaranteed enemy loot")
	var result := current_scene.find_child("CombatResultOverlay", true, false) as Control
	_check(result != null and result.visible and "Настой проверки" in str(hud.get("_result_body").text), "native result did not show authored loot")
	_check(_progress.party == persistent_party and _progress.inventory == persistent_inventory, "result preview applied rewards prematurely")
	await _capture("result")
	if not _errors.is_empty(): return
	var continued := current_scene.find_child("CombatResultContinue", true, false) as Button
	continued.pressed.emit()
	continued.pressed.emit()
	await scene_changed
	await _frames(3)
	_freeze_player()
	var ui := current_scene.find_child("InteractionUI", true, false)
	if ui != null:
		for index in 12:
			if not bool(ui.call("view_state").get("scriptActive", false)): break
			ui.call("advance")
			await process_frame
	_check(current_scene.scene_file_path == EmberMapTransition.scene_path(Fixture.MAP), "result returned to wrong native map")
	var returned_player := current_scene.get_node("Player") as EmberPlayer
	_check(is_equal_approx(returned_player.global_position.x, 43.25) and is_equal_approx(returned_player.global_position.z, 27.5), "victory lost departure position")
	_check(not _progress.combat_party_locked, "victory kept the active party locked")
	_check(_progress.party.mira.level == 2 and _progress.party.mira.xp == 5 and _progress.party.mira.equipment.weapon == Fixture.WEAPON, "XP/level/equipment did not return once")
	_check(_progress.inventory.get(Fixture.POTION) == 8 and _progress.flags.get("cycle_won", false) and _progress.flags.get("combat_victories") == 1, "loot/consumption/result flag/counter did not apply once")
	_check(EmberCombatTransition.finish(self, "victory", _progress, final) == ERR_ALREADY_IN_USE, "duplicate victory applied twice")
	var pause := current_scene.get_node_or_null("CanvasLayer/ExplorePauseUI") as EmberExplorePauseMenu
	if pause == null:
		_check(false, "native Save menu missing")
		return
	pause.call("open_menu")
	_check(pause.is_open(), "normal save menu did not open after rewards")
	(current_scene.find_child("ExploreSaveSlot1", true, false) as Button).pressed.emit()
	var path := _progress.save_path(0)
	_check(FileAccess.file_exists(path), "native save button did not publish manual slot")
	_save_hash = FileAccess.get_sha256(path)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(int(saved.version) == 2 and int(saved.slot) == 0 and saved.saveKind == "manual", "manual save publication envelope invalid")
	await _capture("save")
	var expected := {"payload": saved, "saveHash": _save_hash, "mapHash": _map_hash, "playPid": OS.get_process_id()}
	_check(Fixture.write_json(Fixture.EVIDENCE, expected) == OK, "cross-process save evidence missing")
	# Alter live state before the menu Load: the native reader must restore the file.
	_progress.inventory[Fixture.POTION] = 0
	_progress.party.mira.xp = 0
	_progress.flags["cycle_won"] = false
	(current_scene.find_child("ExploreLoadSlot1", true, false) as Button).pressed.emit()
	await scene_changed
	await _frames(3)
	_freeze_player()
	_assert_loaded(saved)
	_check(FileAccess.get_sha256(path) == _save_hash, "menu Load overwrote manual save")
	await _capture("menu-loaded")
	print("CYCLE_RESULT_EVIDENCE ", ProjectSettings.globalize_path(Fixture.EVIDENCE))

func _start_from_map() -> bool:
	var interaction := current_scene.find_child("InteractionUI", true, false)
	return interaction != null and str(interaction.call("_start_battle_from_script", Fixture.ENCOUNTER)).is_empty()

func _assert_arena(hud: Node) -> void:
	var arena := current_scene.get_node_or_null("Arena") as EmberCombatGrid3DWorld
	_check(arena != null and hud.get("_external_3d_world") == arena, "selected arena did not own normal battle projection")
	if arena == null: return
	_check(arena.scene_file_path == Fixture.ARENA and arena.get_meta("cycle_arena", false) and arena.get_node_or_null("AuthoredArenaMarker") is MeshInstance3D, "normal battle kept default arena or lost decoration")
	_check(arena.battlefield.field_id == Fixture.FIELD and arena.battlefield.resource_path != "res://content/combat/battlefields/thaw_keeper.tres", "arena preview field superseded encounter field")
	var camera := arena.get_node("CameraRig/CombatCamera3D") as Camera3D
	_check(root.get_camera_3d() == camera and is_equal_approx(camera.fov, 44.0) and is_equal_approx(float(arena.get_node("CameraRig").get("pitch_degrees")), 35.0), "authored camera lost or decor camera hijacked rendering")
	_check((arena.get_node("CombatKeyLight") as DirectionalLight3D).light_color == Color(0.9, 0.8, 1, 1), "authored lighting lost")
	_check(arena.pick_cell_at(arena.screen_position_for_cell(Vector2i(1, 1))) == Vector2i(1, 1), "normal selected arena cannot pick encounter grid")
	_check(current_scene.get_child_count() == 2 and current_scene.find_children("CombatHUD", "", true, false).size() == 1, "arena replacement duplicated HUD/root children")
	hud.set("_field_view_mode", "2d")
	hud.call("_refresh")
	_check(not arena.visible, "2D view left selected arena decor visible")
	hud.set("_field_view_mode", "3d")
	hud.call("_refresh")
	_check(arena.visible, "3D view failed to restore selected arena")

func _spend_and_defeat(hud: Node) -> void:
	hud.call("_select_action", "item:" + Fixture.POTION)
	hud.call("_select_target", "mira")
	await _frames(10)
	var spent: Dictionary = hud.call("state_snapshot")
	_check(spent.inventory.get(Fixture.POTION) == 2, "defeat attempt did not spend actual consumable")
	# Force only the terminal HP condition; exercise the real modal and recovery.
	spent.units.mira.hp = 0
	hud.set("_state", spent)
	hud.call("_refresh")
	_check(Combat.outcome(spent) == "defeat" and (current_scene.find_child("CombatResultLoad", true, false) as Button).visible, "normal defeat did not offer gameplay Load")

func _defeat_paths(hud: Node, initial: Dictionary) -> Node:
	var arena_id := current_scene.get_node("Arena").get_instance_id()
	var hud_id := hud.get_instance_id()
	var progress_before := _semantic(_progress.capture_save())
	var autosave_path := _progress.autosave_path()
	var autosave_hash := FileAccess.get_sha256(autosave_path)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(autosave_path))
	await _spend_and_defeat(hud)
	await _capture("defeat")
	(current_scene.find_child("CombatResultRetry", true, false) as Button).pressed.emit()
	await _frames(10)
	var retried: Dictionary = hud.call("state_snapshot")
	_check(retried.units == initial.units and retried.inventory == initial.inventory and retried.turn == initial.turn and retried.rngSeed != initial.rngSeed, "defeat Retry lost prebattle units/bag/deployment or reused seed")
	_check(current_scene.get_node("Arena").get_instance_id() == arena_id and hud.get_instance_id() == hud_id, "Retry replaced selected arena/HUD")
	_assert_arena(hud)
	_check(_semantic(_progress.capture_save()) == progress_before and FileAccess.get_sha256(autosave_path) == autosave_hash, "defeat/Retry changed persistent progress/save")
	await _spend_and_defeat(hud)
	(current_scene.find_child("CombatResultLoad", true, false) as Button).pressed.emit()
	await process_frame
	var autosave_button := current_scene.find_child("CombatDefeatLoadAutosave", true, false) as Button
	if autosave_button == null or autosave_button.disabled:
		_check(false, "defeat autosave choice unavailable")
		return null
	autosave_button.pressed.emit()
	await scene_changed
	await _frames(3)
	_freeze_player()
	_assert_loaded(saved)
	_check(not _progress.combat_party_locked and FileAccess.get_sha256(autosave_path) == autosave_hash, "defeat Load kept lock or wrote save")
	await _capture("defeat-loaded")
	if not _start_from_map():
		_check(false, "could not re-enter selected arena after defeat Load")
		return null
	await scene_changed
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await _frames(10)
	var reopened := current_scene.find_child("CombatHUD", true, false)
	if reopened == null:
		_check(false, "HUD missing after re-entry")
		return null
	_assert_arena(reopened)
	reopened.call("_confirm_deployment")
	var fresh: Dictionary = reopened.call("state_snapshot")
	_check(fresh.units == initial.units and fresh.inventory == initial.inventory, "re-entry lost restored prebattle state")
	return reopened

func _fresh_load() -> void:
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Fixture.EVIDENCE))
	_check(not evidence.is_empty() and int(evidence.playPid) != OS.get_process_id(), "fresh Load reused previous process state")
	_check(FileAccess.get_sha256(_map_file()) == evidence.mapHash, "fresh Load fixture map changed")
	_save_hash = str(evidence.saveHash)
	_check(FileAccess.get_sha256(_progress.save_path(0)) == _save_hash, "manual save changed between processes")
	# The fresh autoload reads disk; bind_scene restores the saved native position.
	_check(_semantic(_progress.capture_save()) == _semantic(evidence.payload), "cold scene startup did not restore saved disk progress")
	_progress.inventory[Fixture.POTION] = 0
	_progress.party.mira.xp = 0
	_progress.flags["cycle_won"] = false
	var pause := current_scene.get_node_or_null("CanvasLayer/ExplorePauseUI") as EmberExplorePauseMenu
	pause.call("open_menu")
	_check(pause.is_open(), "fresh Load menu did not open")
	(current_scene.find_child("ExploreLoadSlot1", true, false) as Button).pressed.emit()
	await scene_changed
	await _frames(3)
	_freeze_player()
	_assert_loaded(evidence.payload)
	_check(FileAccess.get_sha256(_progress.save_path(0)) == _save_hash, "fresh Load overwrote manual save")
	_check(Fixture.ACTION in Catalog.Units.resource("mira").action_ids and Catalog.Actions.resource(Fixture.ACTION).effect_steps[0].effect_id == Fixture.EFFECT, "fresh Load lost authored assignment/shared refs")
	_check(Catalog.Actions.resource(Fixture.ACTION).actor_forbidden_status_ids == PackedStringArray(["frozen"]), "fresh Load lost saved status predicate")
	_check(Catalog.Actions.resource(Fixture.ACTION).value_conditions.size() == 1 and Catalog.Actions.resource(Fixture.ACTION).value_conditions[0].value == 1, "fresh Load lost saved numeric predicate")
	_check(Catalog.Actions.resource(Fixture.ACTION).equipment_conditions.size() == 1 and Catalog.Actions.resource(Fixture.ACTION).equipment_conditions[0].item_id == Fixture.WEAPON, "fresh Load lost saved gear predicate")
	var before := _progress.capture_save()
	_check(EmberCombatTransition.change_scene(self, Fixture.ENCOUNTER, _progress) == ERR_ALREADY_EXISTS, "loaded completion flag allowed duplicate rewards")
	_check(_semantic(_progress.capture_save()) == _semantic(before), "refused repeat changed loaded progress")
	await _capture("fresh-loaded")

func _semantic(payload: Dictionary) -> Dictionary:
	var result := {}
	var normalized: Dictionary = JSON.parse_string(JSON.stringify(payload))
	for key in SEMANTIC_KEYS: result[key] = normalized.get(key)
	return result

func _assert_loaded(expected: Dictionary) -> void:
	_check(_semantic(_progress.capture_save()) == _semantic(expected), "Load lost party/HP/MP/XP/slots/inventory/flags/active group/strategy/chests/shop state")
	var player := current_scene.get_node("Player") as EmberPlayer
	_check(is_equal_approx(player.global_position.x, float(expected.x)) and is_equal_approx(player.global_position.z, float(expected.y)), "Load lost saved position")
	_check(current_scene.scene_file_path == EmberMapTransition.scene_path(Fixture.MAP), "Load opened wrong native scene")

func _finish() -> void:
	if _errors.is_empty(): print("PASS game systems cycle ", "load" if _loading else "play", ": selected normal arena/decor/camera/field, defeat Retry/autosave Load/re-entry, native equipment/consumable/action/status/AI/result, rewards once, manual menu Save/Load and preserved author files")
	else: printerr("FAIL cycle runtime: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)
