extends SceneTree
## Inventory/equipment vertical slice: pure mutations, one UI owner and live
## agent_sandbox wiring over the existing EmberExploreState.

const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"
const VISUAL_ARG := "--visual"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var runtime_progress := get_root().get_node_or_null("EmberExploreProgress") as EmberExploreState
	if runtime_progress:
		runtime_progress.persistence_enabled = false
		runtime_progress.restore_enabled = false
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	state.inventory = {
		"coin": 20,
		"herb": 1,
		"funeral_polearm": 1,
		"spirit_bolt": 1,
	}
	_test_state_contract(state, errors)
	_test_save_round_trip(state, errors)
	await _test_ui_contract(state, errors)
	await _test_live_wiring(errors)
	state.free()
	if not errors.is_empty():
		printerr("FAIL inventory/equipment")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS inventory/equipment")
	print("  bag view joins the real item catalog")
	print("  JRPG/arena slots move items both ways and update stats")
	print("  one overlay blocks movement and coexists with talk/shop")
	return 0


func _test_state_contract(state: EmberExploreState, errors: Array[String]) -> void:
	var initial := state.inventory_view()
	if int(initial.get("atk", -1)) != 4:
		errors.append("unarmed explore attack diverged from the established value 4")
	if int(initial.get("arenaAtk", -1)) != 4:
		errors.append("unarmed arena atk diverged from JOI 4")
	var rows: Array = initial.get("items", [])
	if not _has_named_row(rows, "funeral_polearm", "Пика похоронного бюро"):
		errors.append("bag did not join inventory ids to items/catalog.json")
	var polearm := state.equip_item("funeral_polearm")
	if not bool(polearm.get("ok", false)):
		errors.append("JRPG weapon could not be equipped")
	elif state.equipment.get("weapon") != "funeral_polearm":
		errors.append("weapon_jrpg did not resolve to weapon slot")
	elif state.inventory.has("funeral_polearm"):
		errors.append("equipped polearm remained in the bag")
	elif int(state.inventory_view().get("atk", -1)) != 18:
		errors.append("equipped polearm did not add atk 14 to baseline 4")
	var arena := state.equip_item("spirit_bolt")
	if not bool(arena.get("ok", false)) or state.equipment.get("arena_weapon") != "spirit_bolt":
		errors.append("weapon_arena did not resolve to arena_weapon slot")
	elif int(state.inventory_view().get("arenaAtk", -1)) != 14:
		errors.append("arena weapon did not update arena atk")
	var returned := state.unequip_slot("weapon")
	if not bool(returned.get("ok", false)) or int(state.inventory.get("funeral_polearm", 0)) != 1:
		errors.append("unequip did not return the item to the bag")
	if bool(state.equip_item("herb").get("ok", false)):
		errors.append("non-equipment item was equipped")


func _test_save_round_trip(state: EmberExploreState, errors: Array[String]) -> void:
	var nonce := "%s_%s" % [Time.get_unix_time_from_system(), randi()]
	state.storage_root = "user://ember-tests/inventory-equipment-%s" % nonce
	state.persistence_enabled = true
	if not state.save_slot(0):
		errors.append("equipment save v2 fixture could not be written")
		return
	var loaded := EmberExploreState.new()
	loaded.storage_root = state.storage_root
	if not loaded.load_slot(0):
		errors.append("equipment save v2 fixture could not be loaded")
	elif loaded.equipment.get("arena_weapon") != "spirit_bolt":
		errors.append("arena equipment did not survive save v2 restart")
	elif int(loaded.inventory.get("funeral_polearm", 0)) != 1:
		errors.append("bag counts changed during equipment save round-trip")
	var file_path := state.save_path(0)
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	loaded.free()
	state.persistence_enabled = false


func _test_ui_contract(state: EmberExploreState, errors: Array[String]) -> void:
	var ui := EmberInventoryUi.new()
	ui.progress_state = state
	get_root().add_child(ui)
	await process_frame
	ui.open()
	if not ui.is_open() or not ui.blocks_movement():
		errors.append("open inventory overlay did not block movement")
	var strategy_section := ui.find_child("InventoryStrategySection", true, false)
	var strategy_save := ui.find_child("InventoryStrategySave", true, false) as Button
	var original_strategy := state.combat_strategy_snapshot()
	ui.call("_select_strategy_row", 1)
	if not ui.move_strategy_hero(-1):
		errors.append("inventory Strategy could not reorder the selected hero")
	elif state.combat_strategy_snapshot() != original_strategy:
		errors.append("inventory Strategy mutated the preset before explicit save")
	elif strategy_section == null or strategy_save == null or strategy_save.disabled:
		errors.append("inventory does not expose a functional Strategy save section")
	elif not ui.save_strategy() or state.combat_strategy_snapshot()[0] != original_strategy[1]:
		errors.append("explicit Strategy save did not commit through EmberExploreState")
	if not ui.select_item("funeral_polearm"):
		errors.append("inventory UI could not select the returned polearm")
	else:
		ui.confirm()
		if state.equipment.get("weapon") != "funeral_polearm":
			errors.append("F/confirm did not route equip through EmberExploreState")
	ui._set_mode(EmberInventoryUi.MODE_EQUIPMENT)
	ui.confirm()
	if state.equipment.get("weapon") != null or int(state.inventory.get("funeral_polearm", 0)) != 1:
		errors.append("equipment mode confirm did not unequip the selected slot")
	ui.call("_select_hero", 1)
	if not ui.select_item("funeral_polearm"):
		errors.append("party member switch lost the shared bag")
	else:
		ui.confirm()
		if (
			str(ui.view_state().get("heroId", "")) != "mira"
			or (state.party_member_view("mira").get("equipment", {}) as Dictionary).get("weapon") != "funeral_polearm"
		):
			errors.append("inventory hero tabs did not equip the selected party member")
	ui.close()
	if ui.is_open() or ui.blocks_movement():
		errors.append("inventory overlay did not release movement on close")
	ui.queue_free()
	await process_frame


func _test_live_wiring(errors: Array[String]) -> void:
	if change_scene_to_file(SANDBOX_SCENE) != OK:
		errors.append("could not start agent_sandbox runtime scene")
		return
	await process_frame
	await process_frame
	var sandbox := current_scene
	var player := sandbox.get_node_or_null("Player") as EmberPlayer
	var inventory_ui := sandbox.get_node_or_null("CanvasLayer/InventoryUI") as EmberInventoryUi
	var interaction_ui := sandbox.get_node_or_null("CanvasLayer/InteractionUI") as EmberInteractionUi
	if player == null or inventory_ui == null or interaction_ui == null:
		errors.append("agent_sandbox lost Player/InventoryUI/InteractionUI wiring")
		return
	if player.inventory_ui != inventory_ui or player.interaction_ui != interaction_ui:
		errors.append("player does not reference the two exclusive overlay owners")
	inventory_ui.open()
	if not player._ui_blocks_movement():
		errors.append("live player movement is not blocked by inventory")
	if VISUAL_ARG in OS.get_cmdline_user_args():
		await process_frame
		await process_frame
		var capture_path := "user://inventory_strategy.png"
		var capture_error := root.get_texture().get_image().save_png(capture_path)
		print("CAPTURE inventory strategy: ", ProjectSettings.globalize_path(capture_path), " error=", capture_error)
	var inventory_switch_started := Time.get_ticks_usec()
	for probe in 40:
		inventory_ui.select_next_hero()
	var inventory_switch_micros := Time.get_ticks_usec() - inventory_switch_started
	if inventory_switch_micros > 300000:
		errors.append("40 live inventory hero switches took %d us" % inventory_switch_micros)
	var before_hero := str(inventory_ui.view_state().get("heroId", ""))
	var next_event := InputEventKey.new()
	next_event.physical_keycode = KEY_E
	next_event.pressed = true
	Input.parse_input_event(next_event)
	await process_frame
	if str(inventory_ui.view_state().get("heroId", "")) == before_hero:
		errors.append("E did not reach the next inventory hero while UI had focus")
	var selected_button := sandbox.find_child("InventoryHero_mira", true, false) as Button
	if selected_button == null or not selected_button.text.begins_with("▶"):
		errors.append("selected inventory hero is not visibly marked")
	if player.controlled_hero_id != "mira":
		errors.append("inventory hero selection did not update the live exploration model")
	var previous_event := InputEventKey.new()
	previous_event.physical_keycode = KEY_Q
	previous_event.pressed = true
	Input.parse_input_event(previous_event)
	await process_frame
	if str(inventory_ui.view_state().get("heroId", "")) != "protagonist":
		errors.append("Q did not select the previous inventory hero")
	if player.quest_journal_ui.is_open():
		errors.append("inventory Q leaked through and opened the quest journal")
	inventory_ui.close()
	if player._ui_blocks_movement():
		errors.append("live player remained blocked after inventory close")
	print("  40 live inventory hero switches: %d us" % inventory_switch_micros)


func _has_named_row(rows: Array, item_id: String, name_ru: String) -> bool:
	for raw in rows:
		if typeof(raw) == TYPE_DICTIONARY and str(raw.get("itemId", "")) == item_id:
			return str(raw.get("nameRu", "")) == name_ru
	return false
