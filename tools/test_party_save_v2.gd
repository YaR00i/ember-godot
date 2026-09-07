extends SceneTree
## Stage 2 gate: fixed four-person party, save v2 slots/autosave, one-time v1
## migration and copy-in/copy-out combat ownership.

const ENCOUNTER := preload("res://content/combat/encounters/colored_crossing_demo.tres")
const EmberPartyState := preload("res://scripts/ember_party_state.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: Array[String] = []
	var nonce := "%d-%d" % [Time.get_ticks_usec(), randi()]
	var root_path := "user://ember-tests/party-save-v2-%s" % nonce
	var state := EmberExploreState.new()
	state.storage_root = root_path.path_join("v2")
	state.legacy_storage_root = root_path.path_join("v1")
	state.reset_new_game()

	var party_view := state.party_view()
	if party_view.size() != 4:
		errors.append("new game did not create exactly four persistent heroes")
	for hero_id in EmberPartyState.HERO_IDS:
		var member := state.party_member_view(hero_id)
		if member.is_empty() or (member.get("equipment", {}) as Dictionary).size() != 5:
			errors.append("%s did not receive level/HP/MP and five equipment slots" % hero_id)

	state.grant_item("funeral_polearm", 1, false)
	var equipped := state.equip_item_for_member("mira", "funeral_polearm")
	if not bool(equipped.get("ok", false)) or state.party_member_view("mira").get("equipment", {}).get("weapon") != "funeral_polearm":
		errors.append("equipment did not attach to the selected permanent hero")
	var mira: Dictionary = state.party.get("mira", {})
	mira["level"] = 3
	mira["xp"] = 47
	mira["hp"] = 7
	mira["mp"] = 9
	state.party["mira"] = mira
	state.playtime_seconds = 3723.0
	for slot in EmberExploreState.MANUAL_SLOT_COUNT:
		if not state.save_slot(slot):
			errors.append("manual slot %d could not be written" % (slot + 1))
	if not state.save_autosave():
		errors.append("autosave could not be written")

	var raw: Variant = EmberPack.parse_json_file(state.save_path(1))
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("save v2 payload could not be reopened")
	else:
		var payload: Dictionary = raw
		if int(payload.get("version", -1)) != 2 or str(payload.get("saveKind", "")) != "manual":
			errors.append("manual file lost save v2 identity")
		if payload.has("hp") or payload.has("maxHp") or payload.has("equipment"):
			errors.append("save v2 duplicated leader/derived state at the top level")
		var saved_party: Dictionary = payload.get("party", {})
		if saved_party.size() != 4:
			errors.append("save v2 did not serialize all four heroes")
		for hero_id in EmberPartyState.HERO_IDS:
			var saved_member: Dictionary = saved_party.get(hero_id, {})
			if saved_member.has("maxHp") or saved_member.has("maxMp") or saved_member.has("atk"):
				errors.append("%s serialized a derived stat" % hero_id)

	var metadata := state.all_slot_metadata()
	var manual: Array = metadata.get("manual", [])
	if manual.size() != 3 or not manual.all(func(meta: Dictionary) -> bool: return bool(meta.get("exists", false))):
		errors.append("menu metadata does not expose three manual slots")
	if not bool((metadata.get("autosave", {}) as Dictionary).get("exists", false)):
		errors.append("menu metadata does not expose the separate autosave")

	var loaded := EmberExploreState.new()
	loaded.storage_root = state.storage_root
	loaded.legacy_storage_root = state.legacy_storage_root
	if not loaded.load_slot(1):
		errors.append("manual save v2 did not reopen")
	else:
		var loaded_mira := loaded.party_member_view("mira")
		if (
			int(loaded_mira.get("level", 0)) != 3
			or int(loaded_mira.get("xp", 0)) != 47
			or int(loaded_mira.get("hp", 0)) != 7
			or int(loaded_mira.get("mp", 0)) != 9
			or (loaded_mira.get("equipment", {}) as Dictionary).get("weapon") != "funeral_polearm"
		):
			errors.append("hero level/XP/HP/MP/equipment changed after reopen")

	_test_v1_migration(root_path, errors)
	_test_combat_copy(loaded, errors)
	_test_progression_save(loaded, errors)
	_test_save_deletion(state, errors)
	state.free()
	loaded.free()
	if not errors.is_empty():
		printerr("FAIL party/save v2")
		for message in errors:
			printerr(" - ", message)
		quit(1)
		return
	print("PASS party/save v2")
	print("  four fixed heroes keep level/XP/HP/MP and five equipment slots")
	print("  three manual slots + separate autosave expose lightweight metadata")
	print("  v1 migrates once with an exact backup and returns invalid gear to the bag")
	print("  battle uses copies and returns party HP/MP plus shared inventory through one owner")
	print("  post-battle XP/levels and fallen-at-1 state survive save/reopen in v2")
	print("  deleting a slot archives its exact bytes before removing it")
	quit(0)


func _test_v1_migration(root_path: String, errors: Array[String]) -> void:
	var state := EmberExploreState.new()
	state.storage_root = root_path.path_join("migration-v2")
	state.legacy_storage_root = root_path.path_join("migration-v1")
	var legacy_path := state.legacy_save_path(0)
	var absolute_dir := ProjectSettings.globalize_path(legacy_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var legacy := {
		"version": 1,
		"packId": "ember_p1",
		"slot": 0,
		"savedAtMs": 1234,
		"mapId": "agent_sandbox",
		"tile": {"tx": 2, "ty": 3},
		"x": 40.0,
		"y": 56.0,
		"elev": 8.0,
		"inventory": {"coin": 20},
		"equipment": {"weapon": "herb", "body": "mourning_mail"},
		"openedChests": ["agent_sandbox:test"],
		"shopStock": {},
		"flags": {"legacy_flag": true},
		"hp": 50.0,
		"maxHp": 100.0,
	}
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	if file == null:
		errors.append("v1 migration fixture could not be written")
		return
	file.store_string(JSON.stringify(legacy, "  "))
	file.close()
	if not state.load_slot(0):
		errors.append("valid v1 save was not migrated")
		return
	if not FileAccess.file_exists(state.migration_backup_path(0)):
		errors.append("v1 migration did not create an exact backup")
	var leader := state.party_member_view("protagonist")
	if int(leader.get("hp", -1)) != 10:
		errors.append("v1 leader HP ratio was not preserved in the new stat scale")
	if (leader.get("equipment", {}) as Dictionary).get("body") != "mourning_mail":
		errors.append("compatible v1 equipment was not assigned to the protagonist")
	if int(state.inventory.get("herb", 0)) != 1:
		errors.append("incompatible v1 equipment was not returned to the shared bag")
	var backup_text := FileAccess.get_file_as_string(state.migration_backup_path(0))
	if backup_text != FileAccess.get_file_as_string(legacy_path):
		errors.append("v1 backup is not byte-for-byte identical to the source")
	legacy["hp"] = 0.0
	file = FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy, "  "))
	file.close()
	var reopened := EmberExploreState.new()
	reopened.storage_root = state.storage_root
	reopened.legacy_storage_root = state.legacy_storage_root
	if not reopened.load_slot(0) or int(reopened.party_member_view("protagonist").get("hp", -1)) != 10:
		errors.append("existing save v2 was migrated from v1 more than once")
	var deleted := state.delete_slot(0)
	if not bool(deleted.get("ok", false)):
		errors.append("migrated slot could not be deleted")
	elif FileAccess.file_exists(state.save_path(0)) or FileAccess.file_exists(state.legacy_save_path(0)):
		errors.append("deleting a migrated slot left a loadable v2/v1 source")
	elif not FileAccess.file_exists(state.migration_backup_path(0)):
		errors.append("deleting a migrated slot removed its protected migration backup")
	elif bool(state.slot_metadata(0).get("exists", false)):
		errors.append("deleted migrated slot still appears in menu metadata")
	state.free()
	reopened.free()


func _test_combat_copy(state: EmberExploreState, errors: Array[String]) -> void:
	var snapshot := state.combat_party_snapshot()
	var battle := ENCOUNTER.initial_state(snapshot)
	state.inventory["herb"] = 2
	battle["inventory"] = state.combat_inventory_snapshot()
	var battle_mira: Dictionary = (battle.get("units", {}) as Dictionary).get("mira", {})
	var persistent_view := state.party_member_view("mira")
	if int(battle_mira.get("hp", -1)) != 7 or int(battle_mira.get("mp", -1)) != 9:
		errors.append("battle did not receive current persistent HP/MP")
	if (
		int(battle_mira.get("str", -1)) != int(persistent_view.get("str", -2))
		or int(battle_mira.get("def", -1)) != int(persistent_view.get("def", -2))
		or int(battle_mira.get("acc", -1)) != int(persistent_view.get("acc", -2))
	):
		errors.append("battle did not recompute the party's production stats")
	var live_mira: Dictionary = state.party.get("mira", {})
	live_mira["hp"] = 1
	state.party["mira"] = live_mira
	if int(((battle.get("units", {}) as Dictionary).get("mira", {}) as Dictionary).get("hp", -1)) != 7:
		errors.append("battle snapshot shares mutable party data with exploration")
	var battle_inventory := (battle.get("inventory", {}) as Dictionary).duplicate(true)
	battle_inventory["herb"] = 1
	battle["inventory"] = battle_inventory
	if int(state.inventory.get("herb", 0)) != 2:
		errors.append("battle inventory snapshot aliases the persistent shared bag")
	battle_mira["hp"] = 3
	battle_mira["mp"] = 4
	var units: Dictionary = battle.get("units", {})
	units["mira"] = battle_mira
	battle["units"] = units
	state.apply_combat_result(battle, false)
	var returned := state.party_member_view("mira")
	if int(returned.get("hp", -1)) != 3 or int(returned.get("mp", -1)) != 4:
		errors.append("battle HP/MP did not return to the persistent party")
	if int(state.inventory.get("herb", 0)) != 1:
		errors.append("battle inventory remainder did not return through the persistent owner")
	if not state.save_slot(1):
		errors.append("post-combat shared inventory could not be saved")
	else:
		var reopened := EmberExploreState.new()
		reopened.storage_root = state.storage_root
		reopened.legacy_storage_root = state.legacy_storage_root
		if not reopened.load_slot(1) or int(reopened.inventory.get("herb", 0)) != 1:
			errors.append("post-combat shared inventory changed after save/reopen")
		reopened.free()
	battle_mira["hp"] = 0
	if int(state.party_member_view("mira").get("hp", -1)) != 3:
		errors.append("returned battle state still aliases the persistent party")


func _test_progression_save(state: EmberExploreState, errors: Array[String]) -> void:
	var items := EmberInteractionContent.item_definitions()
	var battle := ENCOUNTER.initial_state(state.combat_party_snapshot())
	var units: Dictionary = battle.get("units", {})
	var orik: Dictionary = units.get("orik", {})
	orik["hp"] = 0
	units["orik"] = orik
	battle["units"] = units
	state.apply_combat_result(battle, false, ENCOUNTER.victory_xp, true)
	var expected := EmberPartyState.serialize(state.party, items)
	if int(state.party_member_view("orik").get("hp", -1)) != 1:
		errors.append("victory did not preserve the fallen-at-1 state before saving")
	if not state.save_slot(1):
		errors.append("progressed party could not be saved")
		return
	var reopened := EmberExploreState.new()
	reopened.storage_root = state.storage_root
	reopened.legacy_storage_root = state.legacy_storage_root
	if not reopened.load_slot(1):
		errors.append("progressed party save could not be reopened")
	elif EmberPartyState.serialize(reopened.party, items) != expected:
		errors.append("XP/levels/HP/MP changed after progression save/reopen")
	reopened.free()


func _test_save_deletion(state: EmberExploreState, errors: Array[String]) -> void:
	var manual_path := state.save_path(2)
	var manual_text := FileAccess.get_file_as_string(manual_path)
	var manual_result := state.delete_slot(2)
	var manual_archives: Array = manual_result.get("archivedPaths", [])
	if not bool(manual_result.get("ok", false)) or int(manual_result.get("deleted", 0)) != 1:
		errors.append("manual slot delete did not report the exact removed source")
	elif FileAccess.file_exists(manual_path) or bool(state.slot_metadata(2).get("exists", false)):
		errors.append("deleted manual slot remains loadable")
	elif manual_archives.size() != 1 or FileAccess.get_file_as_string(str(manual_archives[0])) != manual_text:
		errors.append("manual slot recovery archive is not byte-for-byte identical")
	var auto_path := state.autosave_path()
	var auto_result := state.delete_autosave()
	if not bool(auto_result.get("ok", false)) or FileAccess.file_exists(auto_path):
		errors.append("autosave delete did not remove the active autosave")
