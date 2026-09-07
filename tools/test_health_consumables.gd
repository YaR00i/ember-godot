extends SceneTree
## Leader HP, armor mitigation, hpRestore consumption, save v2 and sandbox H probe.

const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"
const ExploreState = preload("res://scripts/ember_explore_state.gd")


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var runtime_progress := root.get_node_or_null("EmberExploreProgress") as ExploreState
	if runtime_progress:
		runtime_progress.persistence_enabled = false
		runtime_progress.restore_enabled = false
	var state := ExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	_test_health_contract(state, errors)
	_test_save_round_trip(state, errors)
	await _test_inventory_ui(state, errors)
	await _test_live_sandbox(errors)
	state.free()
	if not errors.is_empty():
		printerr("FAIL health/consumables")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS health/consumables")
	print("  persistent protagonist HP -> armor damage -> hpRestore clamp")
	print("  consumable decrements through EmberExploreState and save v2 stores current HP only")
	print("  agent_sandbox H probe applies authored debug damage without a second health owner")
	return 0


func _test_health_contract(state: ExploreState, errors: Array[String]) -> void:
	if state.hp != 20.0 or state.max_hp != 20.0:
		errors.append("new game did not project the protagonist's derived 20 HP")
	state.inventory = {"coin": 5, "herb": 2, "meat_bun": 1}
	state.equipment = EmberEquipment.normalize({"body": "mourning_mail"})
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
		errors.append("full-HP use diverged from JOI's HP already full result")
	elif state.inventory.has("herb"):
		errors.append("full-HP use did not decrement the stack like JOI")
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


func _test_live_sandbox(errors: Array[String]) -> void:
	if change_scene_to_file(SANDBOX_SCENE) != OK:
		errors.append("could not start agent_sandbox runtime scene")
		return
	await process_frame
	await process_frame
	# The scene still instantiates the real EmberPlayer. The smoke only needs its
	# public test hooks, so keep parsing independent from global class order.
	var player := current_scene.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		errors.append("agent_sandbox lost Player")
		return
	if float(player.get("debug_damage_amount")) != 30.0 or not InputMap.has_action("health_test"):
		errors.append("agent_sandbox did not expose its data-driven H damage probe")
	var state := ExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	player.set("progress_state", state)
	player.call("_apply_debug_damage")
	if state.hp != 0.0:
		errors.append("sandbox H probe did not apply 30 raw damage")
	if not str(player.call("_hud_text")).contains("HP 0/20"):
		errors.append("live explore HUD did not expose current/max HP")
	player.set("progress_state", null)
	state.free()
