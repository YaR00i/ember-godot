extends SceneTree
## Leader HP, armor mitigation, hpRestore consumption, save v2 and native H probe.

const Fixture = preload("res://tools/fixtures/ember_party_test_fixture.gd")
var _setup: Dictionary
const ExploreState = preload("res://scripts/ember_explore_state.gd")


func _init() -> void:
	_setup = Fixture.prepare(self, 30.0)
	if _setup.refused:
		quit.call_deferred(2)
		return
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	if _setup.error != OK or not _setup.progress_isolated:
		printerr("FAIL native party fixture preparation")
		return 1
	var runtime_progress := root.get_node_or_null("EmberExploreProgress") as ExploreState
	if runtime_progress:
		runtime_progress.persistence_enabled = false
		runtime_progress.restore_enabled = false
	var state := ExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	state.set_world_context(_setup.map_id, null, 16.0)
	_test_health_contract(state, errors)
	_test_save_round_trip(state, errors)
	await _test_inventory_ui(state, errors)
	await _test_live_fixture(errors)
	state.free()
	Fixture.verify_sources(_setup, errors)
	if not errors.is_empty():
		printerr("FAIL health/consumables")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS health/consumables")
	print("  persistent protagonist HP -> armor damage -> hpRestore clamp")
	print("  consumable decrements through EmberExploreState and save v2 stores current HP only")
	print("  native fixture H probe applies authored debug damage without a second health owner")
	return 0


func _test_health_contract(state: ExploreState, errors: Array[String]) -> void:
	if state.hp != 20.0 or state.max_hp != 20.0:
		errors.append("new game did not project the protagonist's derived 20 HP")
	state.inventory = {"coin": 5, "herb": 2, "meat_bun": 1}
	state.equipment = EmberEquipment.normalize({"armor": Fixture.ARMOR})
	var hit := state.apply_damage(18.0, false)
	if float(hit.get("damage", -1.0)) != 10.0 or state.hp != 10.0:
		errors.append("incoming damage did not apply max(1, raw - def)")
	var herb := state.use_item("herb", false)
	if not bool(herb.get("ok", false)) or float(herb.get("gained", -1.0)) != 4.0:
		errors.append("herb did not restore authored hpRestore=4")
	elif state.hp != 14.0 or int(state.inventory.get("herb", 0)) != 1:
		errors.append("successful herb use did not mutate HP and stack together")
	var bun := state.use_item("meat_bun", false)
	if not bool(bun.get("ok", false)) or float(bun.get("gained", -1.0)) != 6.0:
		errors.append("healing did not clamp at maxHp")
	elif state.hp != state.max_hp or state.inventory.has("meat_bun"):
		errors.append("clamped heal did not consume exactly one bun")
	var full := state.use_item("herb", false)
	if not bool(full.get("ok", false)) or float(full.get("gained", -1.0)) != 0.0:
		errors.append("full-HP use diverged from the established HP already full result")
	elif state.inventory.has("herb"):
		errors.append("full-HP use did not decrement the stack at full HP")
	var before_coin := state.inventory.duplicate(true)
	var coin := state.use_item("coin", false)
	if bool(coin.get("ok", false)) or str(coin.get("reason", "")) != "cannot_use":
		errors.append("non-hpRestore item was accepted as consumable")
	elif state.inventory != before_coin:
		errors.append("failed item use mutated inventory")


func _test_save_round_trip(state: ExploreState, errors: Array[String]) -> void:
	var nonce := "%s_%s" % [Time.get_unix_time_from_system(), randi()]
	state.storage_root = "user://ember-tests/health-consumables-%s" % nonce
	state.persistence_enabled = true
	state.hp = 13.0
	if not state.save_slot(0):
		errors.append("health save v2 fixture could not be written")
		return
	var loaded := ExploreState.new()
	loaded.storage_root = state.storage_root
	if not loaded.load_slot(0):
		errors.append("health save v2 fixture could not be loaded")
	elif loaded.hp != 13.0 or loaded.max_hp != 20.0:
		errors.append("current HP did not survive save v2 while max HP was recomputed")
	var raw: Variant = EmberPack.parse_json_file(state.save_path(0))
	if typeof(raw) != TYPE_DICTIONARY or raw.has("maxHp"):
		errors.append("save v2 persisted a derived max HP")
	var file_path := state.save_path(0)
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	loaded.free()
	state.persistence_enabled = false


func _test_inventory_ui(state: ExploreState, errors: Array[String]) -> void:
	state.hp = 12.0
	state.inventory = {"herb": 1}
	state.equipment = EmberEquipment.empty()
	var ui := EmberInventoryUi.new()
	ui.progress_state = state
	root.add_child(ui)
	await process_frame
	ui.open()
	if not ui.select_item("herb"):
		errors.append("inventory UI could not select hpRestore item")
	else:
		ui.confirm()
		var view := ui.view_state()
		if state.hp != 16.0 or state.inventory.has("herb"):
			errors.append("F/use did not route through EmberExploreState")
		if not str(view.get("feedback", "")).contains("+4 HP"):
			errors.append("inventory UI did not report gained HP")
		if not str(view.get("detail", "")).contains("+4 HP"):
			errors.append("inventory detail did not retain heal feedback after row removal")
	ui.queue_free()
	await process_frame


func _test_live_fixture(errors: Array[String]) -> void:
	if change_scene_to_file(_setup.scene.resource_path) != OK:
		errors.append("could not start native fixture runtime scene")
		return
	await process_frame
	await process_frame
	var player := current_scene.get_node_or_null("Player") as EmberPlayer
	var state := root.get_node_or_null("EmberExploreProgress") as ExploreState
	if player == null:
		errors.append("native fixture lost Player")
		return
	if state == null or player.progress_state != state or player.inventory_ui.progress_state != state:
		errors.append("health/consumption UI does not use the real progress owner")
		return
	if float(player.get("debug_damage_amount")) != 30.0 or not InputMap.has_action("health_test"):
		errors.append("native fixture did not expose its data-driven H damage probe")
	Input.action_press("health_test")
	await physics_frame
	await process_frame
	Input.action_release("health_test")
	if state.hp != 0.0:
		errors.append("native H probe did not apply 30 raw damage")
	if not str(player.call("_hud_text")).contains("HP 0/20"):
		errors.append("live explore HUD did not expose current/max HP")
