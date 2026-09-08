extends SceneTree
## Production defeat lifecycle gate: the failed attempt never crosses into the
## persistent owner, Retry restores pre-battle copies with a new seed, and the
## result modal can load an existing manual save or autosave.

const SOURCE_SCENE := "res://scenes/agent_sandbox.tscn"
const ENCOUNTER_ID := "colored_crossing_demo"
const VISUAL_ARG := "--visual"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: Array[String] = []
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if progress == null:
		printerr("FAIL combat defeat/retry: progress autoload missing")
		quit(1)
		return
	var nonce := "%d-%d" % [Time.get_ticks_usec(), randi()]
	var root_path := "user://ember-tests/combat-defeat-retry-%s" % nonce
	progress.storage_root = root_path.path_join("v2")
	progress.legacy_storage_root = root_path.path_join("v1")
	progress.persistence_enabled = true
	progress.restore_enabled = true
	progress.reset_new_game()
	var manual_bytes := PackedByteArray()
	var autosave_bytes := PackedByteArray()

	if change_scene_to_file(SOURCE_SCENE) != OK:
		errors.append("could not open exploration fixture")
	else:
		await scene_changed
		await process_frame
		_set_party_values(progress, 17, 12)
		progress.inventory["herb"] = 3
		progress.flags = {"loaded_marker": "manual"}
		if not progress.save_slot(0):
			errors.append("manual fixture save could not be written")
		_set_party_values(progress, 9, 6)
		progress.inventory["herb"] = 1
		progress.flags = {"loaded_marker": "autosave"}
		if not progress.save_autosave():
			errors.append("autosave fixture could not be written")
		manual_bytes = _file_bytes(progress.save_path(0))
		autosave_bytes = _file_bytes(progress.autosave_path())
		# The exploration fixture contains authored autosave regions. Disable writes
		# after creating the isolated fixtures so the gate measures Retry itself.
		progress.persistence_enabled = false
		_set_party_values(progress, 13, 7)
		progress.inventory["herb"] = 2
		progress.flags = {"attempt_marker": "prebattle"}
		var prebattle_party := progress.combat_party_snapshot()
		var prebattle_inventory := progress.combat_inventory_snapshot()
		EmberCombatTransition.clear_for_test()
		var enter_error := EmberCombatTransition.change_scene(self, ENCOUNTER_ID, progress)
		if enter_error != OK:
			errors.append("valid authored encounter rejected defeat/retry fixture")
		else:
			await scene_changed
			await process_frame
			var hud := current_scene.find_child("CombatHUD", true, false)
			if hud == null:
				errors.append("Combat Lab HUD missing")
			else:
				var first_state: Dictionary = hud.call("state_snapshot")
				var first_seed := int(first_state.get("rngSeed", 0))
				_force_spent_defeat(hud)
				await process_frame
				_assert_defeat_modal(hud, errors)
				var persistent_party := progress.party.duplicate(true)
				var persistent_inventory := progress.inventory.duplicate(true)
				var persistent_flags := progress.flags.duplicate(true)
				if EmberCombatTransition.finish(self, "defeat", progress, hud.call("state_snapshot")) != ERR_UNAVAILABLE:
					errors.append("defeat could still cross the persistent result commit point")
				var retry := current_scene.find_child("CombatResultRetry", true, false) as Button
				if retry == null:
					errors.append("defeat modal has no Retry button")
				else:
					retry.pressed.emit()
					await process_frame
					var retried: Dictionary = hud.call("state_snapshot")
					_assert_retry_state(
						retried, first_seed, prebattle_party, prebattle_inventory, errors
					)
					if progress.party != persistent_party or progress.inventory != persistent_inventory or progress.flags != persistent_flags:
						errors.append("Retry mutated persistent party, inventory or flags")
					if _file_bytes(progress.save_path(0)) != manual_bytes or _file_bytes(progress.autosave_path()) != autosave_bytes:
						errors.append("Retry wrote a manual save or autosave")

					_force_spent_defeat(hud)
					await process_frame
					var mismatched_payload := progress.capture_save("manual", 1)
					mismatched_payload["saveKind"] = "autosave"
					if not _write_json(progress.save_path(1), mismatched_payload):
						errors.append("mismatched save fixture could not be written")
					var progress_before_failed_load := _progress_snapshot(progress)
					var handoff_party_before_failed_load := EmberCombatTransition.active_party_snapshot()
					var handoff_inventory_before_failed_load := EmberCombatTransition.active_inventory_snapshot()
					if EmberCombatTransition.load_save(self, progress, "manual", 1) != ERR_FILE_CORRUPT:
						errors.append("mismatched save was not rejected as corrupt")
					if _progress_snapshot(progress) != progress_before_failed_load:
						errors.append("failed load partially mutated persistent progress")
					if (
						EmberCombatTransition.active_party_snapshot() != handoff_party_before_failed_load
						or EmberCombatTransition.active_inventory_snapshot() != handoff_inventory_before_failed_load
					):
						errors.append("failed load changed the active defeat handoff")
					DirAccess.remove_absolute(ProjectSettings.globalize_path(progress.save_path(1)))
					if EmberCombatTransition.load_save(self, progress, "manual", 2) != ERR_FILE_NOT_FOUND:
						errors.append("missing load slot did not fail without leaving combat")
					var load_button := current_scene.find_child("CombatResultLoad", true, false) as Button
					if load_button == null:
						errors.append("defeat modal has no load-save button")
					else:
						load_button.pressed.emit()
						await process_frame
						_assert_load_choices(errors)
						var state_before_blocked_retry: Dictionary = hud.call("state_snapshot")
						var retry_event := InputEventKey.new()
						retry_event.pressed = true
						retry_event.keycode = KEY_R
						hud.call("_unhandled_input", retry_event)
						await process_frame
						var load_panel_after_retry := current_scene.find_child("CombatDefeatLoadPanel", true, false) as Control
						var first_slot_after_retry := current_scene.find_child("CombatDefeatLoadSlot1", true, false) as Button
						if (
							hud.call("state_snapshot") != state_before_blocked_retry
							or not load_panel_after_retry.visible
							or root.gui_get_focus_owner() != first_slot_after_retry
						):
							errors.append("R bypassed the open defeat load panel")
						if VISUAL_ARG in OS.get_cmdline_user_args():
							await process_frame
							var capture_path := root_path.path_join("defeat-load.png")
							DirAccess.make_dir_recursive_absolute(
								ProjectSettings.globalize_path(capture_path.get_base_dir())
							)
							var capture_error := root.get_texture().get_image().save_png(capture_path)
							print(
								"READY combat defeat/load visual gate · capture=",
								ProjectSettings.globalize_path(capture_path),
								" · error=",
								capture_error,
							)
							return
						var back_button := current_scene.find_child("CombatDefeatLoadBack", true, false) as Button
						back_button.pressed.emit()
						await process_frame
						var load_panel := current_scene.find_child("CombatDefeatLoadPanel", true, false) as Control
						if load_panel.visible or root.gui_get_focus_owner() != retry:
							errors.append("Back did not return load-only choices to focused Retry")
						load_button.pressed.emit()
						await process_frame
						var manual_button := current_scene.find_child("CombatDefeatLoadSlot1", true, false) as Button
						manual_button.pressed.emit()
						await scene_changed
						await process_frame
						_assert_loaded_state(progress, "manual", 17, 12, 3, errors)
						_set_party_values(progress, 9, 6)
						progress.inventory["herb"] = 1
						progress.flags = {"loaded_marker": "autosave"}
						progress.persistence_enabled = true
						if not progress.save_autosave():
							errors.append("autosave fixture could not be refreshed")
						progress.persistence_enabled = false
						if not progress.load_slot(0):
							errors.append("manual fixture could not be restored before autosave test")

						var second_enter := EmberCombatTransition.change_scene(self, ENCOUNTER_ID, progress)
						if second_enter != OK:
							errors.append("could not re-enter encounter for autosave load")
						else:
							await scene_changed
							await process_frame
							var second_hud := current_scene.find_child("CombatHUD", true, false)
							_force_spent_defeat(second_hud)
							await process_frame
							(current_scene.find_child("CombatResultLoad", true, false) as Button).pressed.emit()
							await process_frame
							(current_scene.find_child("CombatDefeatLoadAutosave", true, false) as Button).pressed.emit()
							await scene_changed
							await process_frame
							_assert_loaded_state(progress, "autosave", 9, 6, 1, errors)

	EmberCombatTransition.clear_for_test()
	if not errors.is_empty():
		printerr("FAIL combat defeat/retry")
		for message in errors:
			printerr(" - ", message)
		quit(1)
		return
	print("PASS combat defeat/retry")
	print("  defeated attempts cannot commit HP/MP, inventory, flags or save writes")
	print("  Retry restores pre-battle party/inventory/deployment with a new RNG seed")
	print("  load-only result UI opens three manual slots plus autosave")
	print("  corrupt load failures preserve persistent progress and the active handoff")
	print("  R cannot bypass the load-only panel; Back keeps its focus contract")
	print("  manual save and autosave both clear combat handoff and restore their scene")
	quit(0)


func _set_party_values(progress: EmberExploreState, hp: int, mp: int) -> void:
	for hero_id in EmberPartyState.HERO_IDS:
		var member: Dictionary = progress.party.get(hero_id, {})
		member["hp"] = hp
		member["mp"] = mp
		progress.party[hero_id] = member


func _force_spent_defeat(hud: Node) -> void:
	var state: Dictionary = hud.call("state_snapshot")
	var units := state.get("units", {}) as Dictionary
	var moved_hero := false
	for raw_id in units:
		var unit := units[raw_id] as Dictionary
		if str(unit.get("team", "")) == "hero":
			unit["hp"] = 0
			unit["mp"] = 0
			if not moved_hero:
				unit["cell"] = Vector2i(0, 0)
				moved_hero = true
			units[raw_id] = unit
	state["units"] = units
	var inventory := (state.get("inventory", {}) as Dictionary).duplicate(true)
	inventory["herb"] = 0
	state["inventory"] = inventory
	hud.set("_state", state)
	hud.call("_refresh")


func _assert_defeat_modal(hud: Node, errors: Array[String]) -> void:
	var state: Dictionary = hud.call("state_snapshot")
	if EmberCombatPrototype.outcome(state) != "defeat":
		errors.append("fixture did not reach defeat")
	var overlay := current_scene.find_child("CombatResultOverlay", true, false) as Control
	var load := current_scene.find_child("CombatResultLoad", true, false) as Button
	var old_return := current_scene.find_child("CombatResultReturn", true, false)
	if overlay == null or not overlay.visible:
		errors.append("defeat did not open the result modal")
	if load == null or not load.visible or old_return != null:
		errors.append("defeat still exposes world return instead of load-save")


func _assert_retry_state(
	state: Dictionary,
	first_seed: int,
	prebattle_party: Dictionary,
	prebattle_inventory: Dictionary,
	errors: Array[String],
) -> void:
	if EmberCombatPrototype.outcome(state) != "active":
		errors.append("Retry did not rebuild an active encounter")
	if int(state.get("rngSeed", 0)) == first_seed:
		errors.append("Retry reused the previous encounter RNG seed")
	if (state.get("inventory", {}) as Dictionary) != prebattle_inventory:
		errors.append("Retry did not restore the exact pre-battle inventory")
	var units := state.get("units", {}) as Dictionary
	for hero_id in EmberPartyState.HERO_IDS:
		var unit := units.get(hero_id, {}) as Dictionary
		var member := prebattle_party.get(hero_id, {}) as Dictionary
		if int(unit.get("hp", -1)) != int(member.get("hp", -2)) or int(unit.get("mp", -1)) != int(member.get("mp", -2)):
			errors.append("Retry did not restore pre-battle HP/MP for %s" % hero_id)
	var encounter := EmberEncounterCatalog.definition(ENCOUNTER_ID)
	for index in encounter.party_unit_ids.size():
		var hero_id := str(encounter.party_unit_ids[index])
		if (units.get(hero_id, {}) as Dictionary).get("cell", Vector2i(-1, -1)) != encounter.battlefield.party_deployment_cells[index]:
			errors.append("Retry changed authored deployment for %s" % hero_id)


func _assert_load_choices(errors: Array[String]) -> void:
	var panel := current_scene.find_child("CombatDefeatLoadPanel", true, false) as Control
	var slot_1 := current_scene.find_child("CombatDefeatLoadSlot1", true, false) as Button
	var slot_2 := current_scene.find_child("CombatDefeatLoadSlot2", true, false) as Button
	var slot_3 := current_scene.find_child("CombatDefeatLoadSlot3", true, false) as Button
	var autosave := current_scene.find_child("CombatDefeatLoadAutosave", true, false) as Button
	if panel == null or not panel.visible:
		errors.append("load-only save choices did not open")
		return
	if slot_1 == null or slot_1.disabled or slot_2 == null or not slot_2.disabled or slot_3 == null or not slot_3.disabled:
		errors.append("manual load choices do not reflect slot metadata")
	if autosave == null or autosave.disabled:
		errors.append("autosave is missing from defeat load choices")
	if root.gui_get_focus_owner() != slot_1:
		errors.append("load-only choices did not focus the first available save")


func _assert_loaded_state(
	progress: EmberExploreState,
	marker: String,
	hp: int,
	mp: int,
	herbs: int,
	errors: Array[String],
) -> void:
	if current_scene == null or current_scene.scene_file_path != SOURCE_SCENE:
		errors.append("%s did not restore the saved exploration scene" % marker)
	if str(progress.flags.get("loaded_marker", "")) != marker:
		errors.append("%s did not restore its saved flags" % marker)
	var mira := progress.party_member_view("mira")
	if int(mira.get("hp", -1)) != hp or int(mira.get("mp", -1)) != mp:
		errors.append("%s did not restore saved party HP/MP" % marker)
	if int(progress.inventory.get("herb", -1)) != herbs:
		errors.append("%s did not restore saved inventory" % marker)
	if not EmberCombatTransition.active_party_snapshot().is_empty() or not EmberCombatTransition.active_inventory_snapshot().is_empty():
		errors.append("%s load left a stale active combat handoff" % marker)


func _file_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var result := file.get_buffer(file.get_length())
	file.close()
	return result


func _write_json(path: String, payload: Dictionary) -> bool:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	return true


func _progress_snapshot(progress: EmberExploreState) -> Dictionary:
	return {
		"activeSlot": progress.active_slot,
		"inventory": progress.inventory.duplicate(true),
		"shopStock": progress.shop_stock.duplicate(true),
		"party": progress.party.duplicate(true),
		"equipment": progress.equipment.duplicate(true),
		"openedChests": progress.opened_chests.duplicate(true),
		"flags": progress.flags.duplicate(true),
		"hp": progress.hp,
		"maxHp": progress.max_hp,
		"playtimeSeconds": progress.playtime_seconds,
		"mapId": progress.get("_map_id"),
		"restorePending": progress.get("_restore_pending"),
		"savedMapId": progress.get("_saved_map_id"),
		"savedX": progress.get("_saved_x"),
		"savedY": progress.get("_saved_y"),
		"savedElev": progress.get("_saved_elev"),
		"savedTile": (progress.get("_saved_tile") as Dictionary).duplicate(true),
	}
