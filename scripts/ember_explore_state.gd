class_name EmberExploreState
extends Node
## Single process-wide owner of exploration progress and persistent party save v2.
## `hp/max_hp/equipment` are a temporary compatibility projection of protagonist;
## they are never serialized beside the canonical `party` payload.

const QuestCatalog = preload("res://scripts/ember_quest_catalog.gd")
const EmberPartyState = preload("res://scripts/ember_party_state.gd")

signal economy_changed
signal progress_changed
signal saved(path: String)
signal party_follow_mode_changed(mode: String)
signal exploration_leader_changed(hero_id: String)

const SAVE_VERSION := 2
const LEGACY_SAVE_VERSION := 1
const PACK_ID := "ember_p1"
const DEFAULT_SLOT := 0
const MANUAL_SLOT_COUNT := 3
const STARTING_COINS := 20
const DEFAULT_MAX_HP := 100.0
const DEFAULT_STORAGE_ROOT := "user://ember-save-v2"
const DEFAULT_LEGACY_STORAGE_ROOT := "user://ember-save-v1"

var active_slot := DEFAULT_SLOT
var storage_root := DEFAULT_STORAGE_ROOT
var legacy_storage_root := DEFAULT_LEGACY_STORAGE_ROOT
var persistence_enabled := true
var restore_enabled := true
var inventory: Dictionary = {}
var shop_stock: Dictionary = {}
var party: Dictionary = {}
var active_hero_ids: Array[String] = EmberPartyState.HERO_IDS.duplicate()
# Process-local transaction guard, owned/cleared by CombatTransition.
var combat_party_locked := false
var battle_strategy: Array[String] = []
var equipment: Dictionary = {}
var opened_chests: Array = []
var flags: Dictionary = {}
var hp := DEFAULT_MAX_HP
var max_hp := DEFAULT_MAX_HP
var playtime_seconds := 0.0
# Session preference, intentionally excluded from gameplay save v2.
var party_follow_mode := "formation"
var exploration_leader_id := EmberPartyState.LEADER_ID

var _map_id := "fan_town"
var _player: Node3D
var _tile_size := 16.0
var _restore_pending := false
var _saved_map_id := ""
var _saved_x: Variant = null
var _saved_y: Variant = null
var _saved_elev: Variant = null
var _saved_tile := {"tx": 0, "ty": 0}
var _item_definitions_cache: Dictionary = {}
var _item_definitions_cache_ready := false


func _ready() -> void:
	active_slot = _manual_slot(ProjectSettings.get_setting("ember/save_slot", DEFAULT_SLOT))
	if not load_latest_available():
		reset_new_game()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and delta > 0.0 and is_finite(delta):
		playtime_seconds += delta


func reset_new_game() -> void:
	inventory = {EmberEconomy.WALLET_ITEM_ID: STARTING_COINS}
	shop_stock = {}
	party = EmberPartyState.new_game(_items())
	active_hero_ids = EmberPartyState.HERO_IDS.duplicate()
	battle_strategy = EmberPartyState.normalize_battle_strategy([])
	_sync_compatibility_from_party()
	opened_chests = []
	flags = {}
	playtime_seconds = 0.0
	_restore_pending = false
	_saved_map_id = ""
	_saved_x = null
	_saved_y = null
	_saved_elev = null
	_saved_tile = {"tx": 0, "ty": 0}
	exploration_leader_id = EmberPartyState.LEADER_ID
	economy_changed.emit()
	progress_changed.emit()
	exploration_leader_changed.emit(exploration_leader_id)


func set_party_follow_mode(value: String) -> void:
	var normalized := "train" if value == "train" else "formation"
	if party_follow_mode == normalized:
		return
	party_follow_mode = normalized
	party_follow_mode_changed.emit(party_follow_mode)


func set_exploration_leader(hero_id: String) -> bool:
	var clean_id := hero_id.strip_edges()
	if clean_id not in active_hero_ids:
		return false
	if exploration_leader_id == clean_id:
		return true
	exploration_leader_id = clean_id
	exploration_leader_changed.emit(exploration_leader_id)
	return true


func next_exploration_leader() -> String:
	var index := active_hero_ids.find(exploration_leader_id)
	if index < 0:
		index = 0
	set_exploration_leader(active_hero_ids[(index + 1) % active_hero_ids.size()])
	return exploration_leader_id


func set_active_hero_ids(raw: Variant, autosave := true) -> bool:
	if combat_party_locked or not EmberPartyState.valid_active_hero_ids(raw):
		return false
	active_hero_ids = EmberPartyState.normalize_active_hero_ids(raw)
	_ensure_active_leader()
	progress_changed.emit()
	if autosave:
		save_autosave()
	return true


func _ensure_active_leader() -> void:
	if exploration_leader_id not in active_hero_ids:
		set_exploration_leader(active_hero_ids[0])


func set_world_context(map_id: String, player: Node3D, tile_size: float) -> void:
	_map_id = map_id.strip_edges()
	_player = player
	_tile_size = maxf(1.0, tile_size)


func start_scene_path_for(current_scene_path: String) -> String:
	if not restore_enabled or not _restore_pending or _saved_map_id.is_empty():
		return ""
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if current_scene_path != main_scene:
		return ""
	var target := EmberMapTransition.scene_path(_saved_map_id)
	if target == current_scene_path or not ResourceLoader.exists(target):
		return ""
	return target


func consume_saved_spawn(map_id: String, tile_size: float) -> Variant:
	if not restore_enabled or not _restore_pending or map_id != _saved_map_id:
		return null
	var ts := maxf(1.0, tile_size)
	var x := (
		float(_saved_x)
		if _is_number(_saved_x)
		else float(_saved_tile.get("tx", 0)) * ts + ts * 0.5
	)
	var y := (
		float(_saved_y)
		if _is_number(_saved_y)
		else float(_saved_tile.get("ty", 0)) * ts + ts * 0.5
	)
	var elev := float(_saved_elev) if _is_number(_saved_elev) else 0.0
	_restore_pending = false
	return Vector3(x, elev, y)


func arm_saved_spawn_restore() -> void:
	## Battle return reloads the authored map scene. Reuse the same saved-position
	## contract as startup restore so the player returns beside the source object.
	_restore_pending = not _saved_map_id.is_empty()


func chest_is_opened(map_id: String, region_id: String) -> bool:
	return _chest_key(map_id, region_id) in opened_chests


func open_chest(
	map_id: String,
	region_id: String,
	loot_ids: Array,
	repeatable: bool,
) -> Dictionary:
	var key := _chest_key(map_id, region_id)
	var already_open := key in opened_chests
	if not already_open:
		opened_chests.append(key)
	if already_open and not repeatable:
		return {
			"ok": false,
			"reason": "already_open",
			"loot": [],
			"names": [],
		}
	var unique_loot: Array = []
	for raw_id in loot_ids:
		var item_id := str(raw_id).strip_edges()
		if not item_id.is_empty() and item_id not in unique_loot:
			unique_loot.append(item_id)
	var items := _items()
	inventory = EmberEconomy.grant_items(inventory, unique_loot, items)
	var names: Array[String] = []
	for item_id in unique_loot:
		var item: Dictionary = items.get(item_id, {})
		names.append(str(item.get("nameRu", item.get("name", item_id))))
	economy_changed.emit()
	progress_changed.emit()
	save_autosave()
	return {
		"ok": true,
		"reason": "",
		"loot": unique_loot,
		"names": names,
		"alreadyOpen": already_open,
		"repeatable": repeatable,
	}


func set_flag(flag_id: String, value: Variant, autosave := true) -> bool:
	var clean_id := flag_id.strip_edges()
	if clean_id.is_empty() or not _is_flag_value(value):
		return false
	flags[clean_id] = value
	progress_changed.emit()
	if autosave:
		save_autosave()
	return true


func increment_flag(flag_id: String, amount: int, autosave := true) -> bool:
	## Numeric world/quest progress uses the same typed flag owner and save file.
	## A non-numeric value is rejected instead of being silently overwritten.
	var clean_id := flag_id.strip_edges()
	if clean_id.is_empty() or amount == 0:
		return false
	var current: Variant = flags.get(clean_id, 0)
	if typeof(current) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return set_flag(clean_id, int(current) + amount, autosave)


func apply_combat_counters(counter_deltas: Dictionary, autosave := true) -> int:
	## Keep global statistics and route each fact into available quest objectives.
	## Objective flags are distinct, so sequential quests cannot complete early.
	var changed := 0
	for raw_event in counter_deltas:
		var event_id := str(raw_event).strip_edges()
		var amount := int(counter_deltas[raw_event])
		if event_id.is_empty() or amount <= 0:
			continue
		if increment_flag(event_id, amount, false):
			changed += 1
		for update in QuestCatalog.counter_objective_updates(event_id, amount, flags):
			if increment_flag(str(update.get("flagId", "")), int(update.get("amount", 0)), false):
				changed += 1
	if autosave and changed > 0:
		save_autosave()
	return changed


func apply_authored_flag(flag_id: String, value: Variant, autosave := true) -> Dictionary:
	## Action/dialogue authoring enters through this gate. Debug restore and
	## explicit state repair may still use set_flag directly.
	var transition := QuestCatalog.authored_flag_transition(flag_id, value, flags)
	if not bool(transition.get("allowed", false)):
		transition["changed"] = false
		return transition
	transition["changed"] = set_flag(flag_id, value, autosave)
	return transition


func clear_flags(flag_ids: Array[String], autosave := true) -> int:
	var removed := 0
	for raw_id in flag_ids:
		var flag_id := str(raw_id).strip_edges()
		if not flag_id.is_empty() and flags.erase(flag_id):
			removed += 1
	if removed > 0:
		progress_changed.emit()
		if autosave:
			save_autosave()
	return removed


func grant_item(item_id: String, count := 1, autosave := true) -> Dictionary:
	var clean_id := item_id.strip_edges()
	if clean_id.is_empty():
		return {"ok": false, "reason": "missing_item", "count": 0}
	var items := _items()
	if not items.has(clean_id):
		return {"ok": false, "reason": "missing_item", "count": 0}
	var repeats := maxi(1, int(count))
	var grants: Array = []
	grants.resize(repeats)
	grants.fill(clean_id)
	inventory = EmberEconomy.grant_items(inventory, grants, items)
	economy_changed.emit()
	progress_changed.emit()
	if autosave:
		save_autosave()
	return {
		"ok": true,
		"reason": "",
		"count": repeats,
		"itemId": clean_id,
		"nameRu": str((items[clean_id] as Dictionary).get("nameRu", clean_id)),
	}


func inventory_view() -> Dictionary:
	return inventory_view_for_member(EmberPartyState.LEADER_ID)


func inventory_view_for_member(hero_id: String) -> Dictionary:
	if hero_id not in active_hero_ids:
		return {}
	_sync_party_from_compatibility()
	var items := _items()
	var member := EmberPartyState.member_view(party, hero_id, items)
	if member.is_empty():
		return {}
	member["items"] = EmberEquipment.inventory_views(inventory, items)
	return member


func party_view() -> Array[Dictionary]:
	_sync_party_from_compatibility()
	return EmberPartyState.views(party, _items(), active_hero_ids)


func party_member_view(hero_id: String) -> Dictionary:
	_sync_party_from_compatibility()
	return EmberPartyState.member_view(party, hero_id, _items())


func equip_item(item_id: String) -> Dictionary:
	return equip_item_for_member(EmberPartyState.LEADER_ID, item_id)


func equip_item_for_member(hero_id: String, item_id: String) -> Dictionary:
	if hero_id not in active_hero_ids:
		return {"ok": false, "reason": "missing_hero", "inventory": inventory.duplicate(true)}
	_sync_party_from_compatibility()
	if hero_id not in EmberPartyState.HERO_IDS:
		return {"ok": false, "reason": "missing_hero", "inventory": inventory.duplicate(true)}
	var items := _items()
	var item: Dictionary = items.get(item_id.strip_edges(), {})
	if not item.is_empty() and not EmberPartyState.equipment_allowed(item, hero_id):
		return {"ok": false, "reason": "wrong_hero", "inventory": inventory.duplicate(true)}
	var member: Dictionary = party.get(hero_id, {})
	var result := EmberEquipment.equip(
		inventory,
		member.get("equipment", {}),
		item_id.strip_edges(),
		items,
	)
	_apply_equipment_result(hero_id, result)
	return result


func unequip_slot(slot: String) -> Dictionary:
	return unequip_slot_for_member(EmberPartyState.LEADER_ID, slot)


func unequip_slot_for_member(hero_id: String, slot: String) -> Dictionary:
	if hero_id not in active_hero_ids:
		return {"ok": false, "reason": "missing_hero", "inventory": inventory.duplicate(true)}
	_sync_party_from_compatibility()
	if hero_id not in EmberPartyState.HERO_IDS:
		return {"ok": false, "reason": "missing_hero", "inventory": inventory.duplicate(true)}
	var member: Dictionary = party.get(hero_id, {})
	var result := EmberEquipment.unequip(
		inventory,
		member.get("equipment", {}),
		slot.strip_edges(),
		_items(),
	)
	_apply_equipment_result(hero_id, result)
	return result


func use_item(item_id: String, autosave := true) -> Dictionary:
	return use_item_on_member(EmberPartyState.LEADER_ID, item_id, autosave)


func use_item_on_member(hero_id: String, item_id: String, autosave := true) -> Dictionary:
	if hero_id not in active_hero_ids:
		return {"ok": false, "reason": "missing_hero", "inventory": inventory.duplicate(true)}
	_sync_party_from_compatibility()
	if hero_id not in EmberPartyState.HERO_IDS:
		return {"ok": false, "reason": "missing_hero", "inventory": inventory.duplicate(true)}
	var member: Dictionary = party.get(hero_id, {})
	var item := (_items().get(item_id.strip_edges(), {}) as Dictionary)
	if int(item.get("reviveHp", 0)) > 0 and int(member.get("hp", 0)) > 0:
		return {"ok": false, "reason": "target_alive", "inventory": inventory.duplicate(true)}
	var result := EmberEquipment.use_item(
		inventory,
		member.get("equipment", {}),
		item_id.strip_edges(),
		_items(),
	)
	if not bool(result.get("ok", false)):
		return result
	inventory = result.get("inventory", {}).duplicate(true)
	member["equipment"] = EmberEquipment.normalize(result.get("equipment", {}))
	var derived := EmberPartyState.derived_stats(hero_id, member, _items())
	var before := int(member.get("hp", 0))
	var before_mp := int(member.get("mp", 0))
	if before <= 0 and int(result.get("reviveHp", 0)) > 0:
		member["hp"] = clampi(int(result.get("reviveHp", 0)), 1, int(derived.get("maxHp", 1)))
	else:
		member["hp"] = clampi(before + int(result.get("heal", 0)), 0, int(derived.get("maxHp", 1)))
	member["mp"] = clampi(before_mp + int(result.get("mana", 0)), 0, int(derived.get("maxMp", 0)))
	party[hero_id] = member
	_sync_compatibility_from_party()
	result["gained"] = maxi(0, int(member["hp"]) - before)
	result["gainedMp"] = maxi(0, int(member["mp"]) - before_mp)
	result["hp"] = int(member["hp"])
	result["maxHp"] = int(derived.get("maxHp", 1))
	result["mp"] = int(member["mp"])
	result["maxMp"] = int(derived.get("maxMp", 0))
	economy_changed.emit()
	progress_changed.emit()
	if autosave:
		save_autosave()
	return result


func apply_damage(raw_damage: float, autosave := true) -> Dictionary:
	return apply_damage_to_member(EmberPartyState.LEADER_ID, raw_damage, autosave)


func apply_damage_to_member(hero_id: String, raw_damage: float, autosave := true) -> Dictionary:
	if hero_id not in EmberPartyState.HERO_IDS:
		return {"ok": false, "reason": "missing_hero"}
	if hero_id == EmberPartyState.LEADER_ID:
		_sync_party_from_compatibility()
	var member: Dictionary = party.get(hero_id, {})
	var derived := EmberPartyState.derived_stats(hero_id, member, _items())
	var member_hp := float(member.get("hp", 0.0))
	var member_max_hp := float(derived.get("maxHp", 1.0))
	var raw := raw_damage if is_finite(raw_damage) else 0.0
	if raw <= 0.0:
		return {
			"ok": false,
			"reason": "no_damage",
			"raw": raw,
			"damage": 0.0,
			"hp": member_hp,
			"maxHp": member_max_hp,
			"dead": member_hp <= 0.0,
		}
	var stats := EmberEquipment.combat_stats(
		EmberEquipment.normalize(member.get("equipment", {})),
		_items(),
	)
	var damage := maxf(1.0, raw - maxf(0.0, float(stats.get("def", 0))))
	member_hp = clampf(member_hp - damage, 0.0, member_max_hp)
	member["hp"] = roundi(member_hp)
	party[hero_id] = member
	_sync_compatibility_from_party()
	progress_changed.emit()
	if autosave:
		save_autosave()
	return {
		"ok": true,
		"reason": "",
		"raw": raw,
		"damage": damage,
		"hp": member_hp,
		"maxHp": member_max_hp,
		"dead": member_hp <= 0.0,
	}


func respawn(autosave := true) -> Dictionary:
	return respawn_member(EmberPartyState.LEADER_ID, autosave)


func respawn_member(hero_id: String, autosave := true) -> Dictionary:
	if hero_id not in EmberPartyState.HERO_IDS:
		return {"ok": false, "reason": "missing_hero"}
	if hero_id == EmberPartyState.LEADER_ID:
		_sync_party_from_compatibility()
	var member: Dictionary = party.get(hero_id, {})
	var derived := EmberPartyState.derived_stats(hero_id, member, _items())
	var member_hp := float(member.get("hp", 0.0))
	var member_max_hp := float(derived.get("maxHp", 1.0))
	if member_hp > 0.0:
		return {
			"ok": false,
			"reason": "not_defeated",
			"hp": member_hp,
			"maxHp": member_max_hp,
		}
	member["hp"] = roundi(member_max_hp)
	party[hero_id] = member
	_sync_compatibility_from_party()
	progress_changed.emit()
	if autosave:
		save_autosave()
	return {
		"ok": true,
		"reason": "",
		"hp": member_max_hp,
		"maxHp": member_max_hp,
	}


func shop_view(shop_id: String) -> Dictionary:
	var shop := EmberInteractionContent.shop_definition(shop_id)
	if shop.is_empty():
		return {}
	var remaining := _remaining_for_shop(shop)
	return {
		"id": str(shop.get("id", shop_id)),
		"nameRu": str(shop.get("nameRu", shop_id)),
		"wallet": EmberEconomy.wallet_count(inventory),
		"listings": EmberEconomy.listing_views(
			shop,
			remaining,
			_items(),
		),
		"sellable": EmberEconomy.sellable_views(
			shop,
			inventory,
			_items(),
		),
	}


func buy(shop_id: String, item_id: String) -> Dictionary:
	var shop := EmberInteractionContent.shop_definition(shop_id)
	var result := EmberEconomy.buy(
		shop,
		item_id,
		inventory,
		_remaining_for_shop(shop),
		_items(),
	)
	_apply_economy_result(shop_id, result)
	return result


func sell(shop_id: String, item_id: String) -> Dictionary:
	var shop := EmberInteractionContent.shop_definition(shop_id)
	var result := EmberEconomy.sell(
		shop,
		item_id,
		inventory,
		_remaining_for_shop(shop),
		_items(),
	)
	_apply_economy_result(shop_id, result)
	return result


func combat_party_snapshot() -> Dictionary:
	_sync_party_from_compatibility()
	return EmberPartyState.battle_snapshot(party, _items())


func combat_inventory_snapshot() -> Dictionary:
	return EmberEconomy.compact_counts(inventory)


func combat_strategy_snapshot() -> Array[String]:
	return EmberPartyState.normalize_battle_strategy(battle_strategy).duplicate()


func set_battle_strategy(raw: Variant) -> Array[String]:
	battle_strategy = EmberPartyState.normalize_battle_strategy(raw)
	progress_changed.emit()
	return battle_strategy.duplicate()


func apply_combat_result(
	combat_state: Dictionary,
	autosave := true,
	xp_reward := 0,
	victory := false,
) -> void:
	_sync_party_from_compatibility()
	party = EmberPartyState.apply_combat_result(
		party,
		combat_state,
		_items(),
		maxi(0, int(xp_reward)),
		victory,
	)
	if combat_state.has("inventory"):
		inventory = EmberEconomy.compact_counts(combat_state.get("inventory", {}))
		economy_changed.emit()
	_sync_compatibility_from_party()
	progress_changed.emit()
	if autosave:
		save_autosave()


func save_slot(slot := active_slot) -> bool:
	if not persistence_enabled:
		return true
	active_slot = _manual_slot(slot)
	var path := save_path(active_slot)
	var payload := capture_save("manual", active_slot)
	if not _write_payload(path, payload):
		return false
	_remember_saved_payload(payload, false)
	saved.emit(path)
	return true


func save_autosave() -> bool:
	if not persistence_enabled:
		return true
	var path := autosave_path()
	var payload := capture_save("autosave", active_slot)
	if not _write_payload(path, payload):
		return false
	_remember_saved_payload(payload, false)
	saved.emit(path)
	return true


func delete_slot(slot := active_slot) -> Dictionary:
	var clean_slot := _manual_slot(slot)
	return _archive_and_remove_saves(
		[save_path(clean_slot), legacy_save_path(clean_slot)],
		"manual_%d" % clean_slot,
	)


func delete_autosave() -> Dictionary:
	return _archive_and_remove_saves([autosave_path()], "autosave")


func load_slot(slot := active_slot) -> bool:
	active_slot = _manual_slot(slot)
	var path := save_path(active_slot)
	if not FileAccess.file_exists(path):
		return _migrate_legacy_slot(active_slot)
	return _load_v2_path(path, "manual", active_slot)


func load_autosave() -> bool:
	return _load_v2_path(autosave_path(), "autosave", -1)


func adopt_loaded_save(source: EmberExploreState) -> void:
	## Commit a save that was already parsed and normalized by another instance of
	## this owner. Combat transitions use this as the second phase of loading so a
	## corrupt save or rejected scene change cannot partially mutate live progress.
	if source == null:
		return
	active_slot = source.active_slot
	inventory = source.inventory.duplicate(true)
	shop_stock = source.shop_stock.duplicate(true)
	party = source.party.duplicate(true)
	active_hero_ids = source.active_hero_ids.duplicate()
	battle_strategy = source.battle_strategy.duplicate()
	equipment = source.equipment.duplicate(true)
	opened_chests = source.opened_chests.duplicate(true)
	flags = source.flags.duplicate(true)
	hp = source.hp
	max_hp = source.max_hp
	playtime_seconds = source.playtime_seconds
	_map_id = source._map_id
	_restore_pending = source._restore_pending
	_saved_map_id = source._saved_map_id
	_saved_x = source._saved_x
	_saved_y = source._saved_y
	_saved_elev = source._saved_elev
	_saved_tile = source._saved_tile.duplicate(true)
	_ensure_active_leader()
	economy_changed.emit()
	progress_changed.emit()


func load_latest_available() -> bool:
	var newest := {"savedAtMs": -1, "kind": "", "slot": active_slot}
	var auto_meta := autosave_metadata()
	if bool(auto_meta.get("exists", false)) and int(auto_meta.get("version", -1)) == SAVE_VERSION:
		newest = {
			"savedAtMs": int(auto_meta.get("savedAtMs", 0)),
			"kind": "autosave",
			"slot": int(auto_meta.get("activeManualSlot", active_slot)),
		}
	for slot in MANUAL_SLOT_COUNT:
		var meta := slot_metadata(slot)
		if (
			bool(meta.get("exists", false))
			and int(meta.get("version", -1)) == SAVE_VERSION
			and int(meta.get("savedAtMs", 0)) > int(newest.get("savedAtMs", -1))
		):
			newest = {"savedAtMs": int(meta.get("savedAtMs", 0)), "kind": "manual", "slot": slot}
	if str(newest.get("kind", "")) == "autosave":
		active_slot = _manual_slot(newest.get("slot", active_slot))
		return load_autosave()
	if str(newest.get("kind", "")) == "manual":
		return load_slot(int(newest.get("slot", active_slot)))
	return load_slot(active_slot)


func _load_v2_path(path: String, expected_kind: String, expected_slot: int) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var raw: Variant = EmberPack.parse_json_file(path)
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = raw
	if int(data.get("version", -1)) != SAVE_VERSION:
		return false
	if str(data.get("packId", "")) != PACK_ID or str(data.get("saveKind", "")) != expected_kind:
		return false
	if expected_kind == "manual" and int(data.get("slot", -1)) != expected_slot:
		return false
	if expected_kind == "autosave":
		active_slot = _manual_slot(data.get("activeManualSlot", active_slot))
	else:
		active_slot = _manual_slot(expected_slot)
	_apply_v2_payload(data, true)
	return true


func _apply_v2_payload(data: Dictionary, pending_restore: bool) -> void:
	var items := _items()
	inventory = EmberEconomy.compact_counts(data.get("inventory", {}))
	shop_stock = _parse_shop_stock(data.get("shopStock", {}))
	opened_chests = _parse_string_array(data.get("openedChests", []))
	flags = _parse_flags(data.get("flags", {}))
	var normalized := EmberPartyState.normalize(data.get("party", {}), items)
	party = normalized.get("party", {}).duplicate(true)
	battle_strategy = EmberPartyState.normalize_battle_strategy(data.get("battleStrategy", []))
	active_hero_ids = EmberPartyState.normalize_active_hero_ids(data.get("activeHeroIds", null))
	for item_id in normalized.get("returnedItems", []):
		inventory = EmberEconomy.grant_items(inventory, [str(item_id)], items)
	playtime_seconds = maxf(0.0, float(data.get("playtimeSeconds", 0.0)))
	_sync_compatibility_from_party()
	_remember_saved_payload(data, pending_restore)
	_ensure_active_leader()
	economy_changed.emit()
	progress_changed.emit()


func capture_save(save_kind := "manual", slot := active_slot) -> Dictionary:
	_sync_party_from_compatibility()
	var pos := _current_save_position()
	var tx := floori(pos.x / _tile_size)
	var ty := floori(pos.z / _tile_size)
	var kind := "autosave" if save_kind == "autosave" else "manual"
	var payload := {
		"version": SAVE_VERSION,
		"packId": PACK_ID,
		"saveKind": kind,
		"savedAtMs": int(Time.get_unix_time_from_system() * 1000.0),
		"timeZoneBiasMinutes": int(Time.get_time_zone_from_system().get("bias", 0)),
		"playtimeSeconds": maxf(0.0, playtime_seconds),
		"mapId": _map_id if not _map_id.is_empty() else "fan_town",
		"tile": {"tx": tx, "ty": ty},
		"x": pos.x,
		"y": pos.z,
		"elev": pos.y,
		"inventory": EmberEconomy.compact_counts(inventory),
		"party": EmberPartyState.serialize(party, _items()),
		"activeHeroIds": active_hero_ids.duplicate(),
		"battleStrategy": EmberPartyState.normalize_battle_strategy(battle_strategy),
		"openedChests": _parse_string_array(opened_chests),
		"shopStock": _parse_shop_stock(shop_stock),
		"flags": _parse_flags(flags),
	}
	if kind == "manual":
		payload["slot"] = _manual_slot(slot)
	else:
		payload["activeManualSlot"] = active_slot
	return payload


func save_path(slot := active_slot) -> String:
	return storage_root.path_join(PACK_ID).path_join("manual_%d.json" % _manual_slot(slot))


func autosave_path() -> String:
	return storage_root.path_join(PACK_ID).path_join("autosave.json")


func legacy_save_path(slot := active_slot) -> String:
	return legacy_storage_root.path_join(PACK_ID).path_join("%d.json" % _manual_slot(slot))


func migration_backup_path(slot := active_slot) -> String:
	return storage_root.path_join(PACK_ID).path_join("migration_backups").path_join(
		"manual_%d_v1.json" % _manual_slot(slot)
	)


func slot_metadata(slot: int) -> Dictionary:
	var clean_slot := _manual_slot(slot)
	var result := _metadata_for_path(save_path(clean_slot), "manual", clean_slot)
	if not bool(result.get("exists", false)) and FileAccess.file_exists(legacy_save_path(clean_slot)):
		var legacy: Variant = EmberPack.parse_json_file(legacy_save_path(clean_slot))
		if typeof(legacy) == TYPE_DICTIONARY and int(legacy.get("version", -1)) == LEGACY_SAVE_VERSION:
			result = _metadata_from_payload(legacy, "manual", clean_slot)
			result["migrationPending"] = true
	return result


func autosave_metadata() -> Dictionary:
	return _metadata_for_path(autosave_path(), "autosave", -1)


func all_slot_metadata() -> Dictionary:
	var manual: Array[Dictionary] = []
	for slot in MANUAL_SLOT_COUNT:
		manual.append(slot_metadata(slot))
	return {"manual": manual, "autosave": autosave_metadata()}


func resume_scene_path() -> String:
	if _saved_map_id.is_empty():
		return ""
	return EmberMapTransition.scene_path(_saved_map_id)


func _remaining_for_shop(shop: Dictionary) -> Dictionary:
	var shop_id := str(shop.get("id", ""))
	if shop_id.is_empty():
		return {}
	if not shop_stock.has(shop_id):
		shop_stock[shop_id] = EmberEconomy.seed_shop_remaining(shop)
	return shop_stock[shop_id]


func _apply_economy_result(shop_id: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	inventory = result.get("inventory", {}).duplicate(true)
	shop_stock[shop_id] = result.get("remaining", {}).duplicate(true)
	economy_changed.emit()
	progress_changed.emit()
	save_autosave()


func _apply_equipment_result(hero_id: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	inventory = result.get("inventory", {}).duplicate(true)
	var member: Dictionary = party.get(hero_id, {})
	member["equipment"] = EmberEquipment.normalize(result.get("equipment", {}))
	party[hero_id] = member
	_sync_compatibility_from_party()
	economy_changed.emit()
	progress_changed.emit()
	save_autosave()


func _write_payload(path: String, payload: Dictionary) -> bool:
	if not _ensure_parent_directory(path):
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ember save: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	return true


func _archive_and_remove_saves(paths: Array[String], archive_stem: String) -> Dictionary:
	if not persistence_enabled:
		return {"ok": true, "deleted": 0, "archivedPaths": []}
	var existing: Array[String] = []
	for path in paths:
		if FileAccess.file_exists(path):
			existing.append(path)
	if existing.is_empty():
		return {"ok": false, "deleted": 0, "archivedPaths": [], "reason": "missing"}
	var archive_dir := storage_root.path_join(PACK_ID).path_join("deleted_saves")
	if not _ensure_parent_directory(archive_dir.path_join("placeholder")):
		return {"ok": false, "deleted": 0, "archivedPaths": [], "reason": "archive_directory"}
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	var archived: Array[String] = []
	for index in existing.size():
		var source := existing[index]
		var suffix := "" if index == 0 else "_legacy"
		var archive_path := archive_dir.path_join("%s%s_%d.json" % [archive_stem, suffix, stamp])
		while FileAccess.file_exists(archive_path):
			stamp += 1
			archive_path = archive_dir.path_join("%s%s_%d.json" % [archive_stem, suffix, stamp])
		var source_file := FileAccess.open(source, FileAccess.READ)
		if source_file == null:
			return {"ok": false, "deleted": 0, "archivedPaths": archived, "reason": "read"}
		var bytes := source_file.get_buffer(source_file.get_length())
		source_file.close()
		var archive_file := FileAccess.open(archive_path, FileAccess.WRITE)
		if archive_file == null:
			return {"ok": false, "deleted": 0, "archivedPaths": archived, "reason": "archive_write"}
		archive_file.store_buffer(bytes)
		archive_file.close()
		archived.append(archive_path)
	for source in existing:
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(source))
		if remove_error != OK:
			return {
				"ok": false,
				"deleted": 0,
				"archivedPaths": archived,
				"reason": "remove",
			}
	return {"ok": true, "deleted": existing.size(), "archivedPaths": archived, "reason": ""}


func _ensure_parent_directory(path: String) -> bool:
	var absolute_dir := ProjectSettings.globalize_path(path.get_base_dir())
	var dir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		push_error("ember save: cannot create %s" % absolute_dir)
		return false
	return true


func _migrate_legacy_slot(slot: int) -> bool:
	var clean_slot := _manual_slot(slot)
	var legacy_path := legacy_save_path(clean_slot)
	if not FileAccess.file_exists(legacy_path):
		return false
	var raw: Variant = EmberPack.parse_json_file(legacy_path)
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var legacy: Dictionary = raw
	if (
		int(legacy.get("version", -1)) != LEGACY_SAVE_VERSION
		or str(legacy.get("packId", "")) != PACK_ID
		or int(legacy.get("slot", -1)) != clean_slot
	):
		return false
	var backup_path := migration_backup_path(clean_slot)
	if not FileAccess.file_exists(backup_path):
		if not _ensure_parent_directory(backup_path):
			return false
		var backup := FileAccess.open(backup_path, FileAccess.WRITE)
		if backup == null:
			return false
		backup.store_string(FileAccess.get_file_as_string(legacy_path))
		backup.close()

	var items := _items()
	inventory = EmberEconomy.compact_counts(legacy.get("inventory", {}))
	shop_stock = _parse_shop_stock(legacy.get("shopStock", {}))
	opened_chests = _parse_string_array(legacy.get("openedChests", []))
	flags = _parse_flags(legacy.get("flags", {}))
	party = EmberPartyState.new_game(items)
	battle_strategy = EmberPartyState.normalize_battle_strategy([])
	active_hero_ids = EmberPartyState.HERO_IDS.duplicate()
	var leader: Dictionary = party.get(EmberPartyState.LEADER_ID, {})
	leader["equipment"] = _parse_equipment(legacy.get("equipment", {}))
	party[EmberPartyState.LEADER_ID] = leader
	var normalized := EmberPartyState.normalize(party, items)
	party = normalized.get("party", {}).duplicate(true)
	for item_id in normalized.get("returnedItems", []):
		inventory = EmberEconomy.grant_items(inventory, [str(item_id)], items)
	leader = party.get(EmberPartyState.LEADER_ID, {})
	var old_max := _stage_player_hp(str(legacy.get("mapId", _map_id)))
	if _is_finite_number(legacy.get("maxHp", null)) and float(legacy.get("maxHp", 0.0)) > 0.0:
		old_max = float(legacy.get("maxHp", old_max))
	var old_hp := old_max
	if _is_finite_number(legacy.get("hp", null)):
		old_hp = clampf(float(legacy.get("hp", old_max)), 0.0, old_max)
	var leader_max := int(EmberPartyState.derived_stats(EmberPartyState.LEADER_ID, leader, items).get("maxHp", 1))
	leader["hp"] = clampi(roundi(float(leader_max) * old_hp / maxf(1.0, old_max)), 0, leader_max)
	party[EmberPartyState.LEADER_ID] = leader
	playtime_seconds = maxf(0.0, float(legacy.get("playtimeSeconds", 0.0)))
	_remember_saved_payload(legacy, true)
	_sync_compatibility_from_party()
	var payload := capture_save("manual", clean_slot)
	payload["migratedFromVersion"] = LEGACY_SAVE_VERSION
	payload["migrationBackup"] = backup_path
	var target_path := save_path(clean_slot)
	if not _write_payload(target_path, payload):
		return false
	active_slot = clean_slot
	_apply_v2_payload(payload, true)
	saved.emit(target_path)
	return true


func _metadata_for_path(path: String, kind: String, slot: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _empty_metadata(kind, slot)
	var raw: Variant = EmberPack.parse_json_file(path)
	if typeof(raw) != TYPE_DICTIONARY:
		return _empty_metadata(kind, slot)
	var data: Dictionary = raw
	if str(data.get("packId", "")) != PACK_ID:
		return _empty_metadata(kind, slot)
	return _metadata_from_payload(data, kind, slot)


func _metadata_from_payload(data: Dictionary, kind: String, slot: int) -> Dictionary:
	var saved_at_ms := maxi(0, int(data.get("savedAtMs", 0)))
	var display_unix := floori(float(saved_at_ms) / 1000.0) + int(data.get("timeZoneBiasMinutes", 0)) * 60
	var party_raw: Variant = data.get("party", {})
	var party_count := 1 if int(data.get("version", -1)) == LEGACY_SAVE_VERSION else 0
	var alive_count := 1 if float(data.get("hp", 0.0)) > 0.0 else 0
	var leader_hp := int(data.get("hp", 0))
	if typeof(party_raw) == TYPE_DICTIONARY:
		party_count = 0
		alive_count = 0
		var saved_active := EmberPartyState.normalize_active_hero_ids(data.get("activeHeroIds", null))
		for hero_id in saved_active:
			var raw_member: Variant = party_raw.get(hero_id, {})
			if typeof(raw_member) != TYPE_DICTIONARY:
				continue
			party_count += 1
			var member_hp := int(raw_member.get("hp", 0))
			if member_hp > 0:
				alive_count += 1
			if hero_id == saved_active[0]:
				leader_hp = member_hp
	return {
		"exists": true,
		"kind": kind,
		"slot": slot,
		"version": int(data.get("version", -1)),
		"savedAtMs": saved_at_ms,
		"savedAtText": Time.get_datetime_string_from_unix_time(display_unix, true) if saved_at_ms > 0 else "",
		"playtimeSeconds": maxf(0.0, float(data.get("playtimeSeconds", 0.0))),
		"mapId": str(data.get("mapId", "fan_town")),
		"partyCount": party_count,
		"aliveCount": alive_count,
		"leaderHp": leader_hp,
		"activeManualSlot": _manual_slot(data.get("activeManualSlot", active_slot)),
		"migrationPending": false,
	}


func _empty_metadata(kind: String, slot: int) -> Dictionary:
	return {
		"exists": false,
		"kind": kind,
		"slot": slot,
		"version": -1,
		"savedAtMs": 0,
		"savedAtText": "",
		"playtimeSeconds": 0.0,
		"mapId": "",
		"partyCount": 0,
		"aliveCount": 0,
		"leaderHp": 0,
		"migrationPending": false,
	}


func _sync_party_from_compatibility() -> void:
	var items := _items()
	if party.is_empty():
		party = EmberPartyState.new_game(items)
	var leader: Dictionary = party.get(EmberPartyState.LEADER_ID, {})
	leader["equipment"] = EmberEquipment.normalize(equipment)
	var derived := EmberPartyState.derived_stats(EmberPartyState.LEADER_ID, leader, items)
	leader["hp"] = clampi(roundi(hp), 0, int(derived.get("maxHp", 1)))
	party[EmberPartyState.LEADER_ID] = leader
	var normalized := EmberPartyState.normalize(party, items)
	party = normalized.get("party", {}).duplicate(true)
	for item_id in normalized.get("returnedItems", []):
		inventory = EmberEconomy.grant_items(inventory, [str(item_id)], items)
	_sync_compatibility_from_party()


func _sync_compatibility_from_party() -> void:
	if party.is_empty():
		return
	var view := EmberPartyState.member_view(
		party,
		EmberPartyState.LEADER_ID,
		_items(),
	)
	if view.is_empty():
		return
	equipment = EmberEquipment.normalize(view.get("equipment", {}))
	hp = float(view.get("hp", 0))
	max_hp = float(view.get("maxHp", 1))


func _items() -> Dictionary:
	if not _item_definitions_cache_ready:
		# Item definitions are read-only during a play session. Keeping one snapshot
		# avoids reparsing the legacy catalog and reloading every native item for a
		# label, Tab switch or follower refresh.
		_item_definitions_cache = EmberInteractionContent.item_definitions()
		_item_definitions_cache_ready = true
	return _item_definitions_cache


func _manual_slot(value: Variant) -> int:
	return clampi(int(value), 0, MANUAL_SLOT_COUNT - 1)


func _current_save_position() -> Vector3:
	if is_instance_valid(_player):
		return _player.global_position if _player.is_inside_tree() else _player.position
	if _saved_map_id == _map_id:
		var x := float(_saved_x) if _is_number(_saved_x) else 0.0
		var y := float(_saved_y) if _is_number(_saved_y) else 0.0
		var elev := float(_saved_elev) if _is_number(_saved_elev) else 0.0
		return Vector3(x, elev, y)
	return Vector3.ZERO


func _remember_saved_payload(data: Dictionary, pending: bool) -> void:
	_saved_map_id = str(data.get("mapId", _map_id)).strip_edges()
	_map_id = _saved_map_id if not _saved_map_id.is_empty() else _map_id
	_saved_x = data.get("x", null)
	_saved_y = data.get("y", null)
	_saved_elev = data.get("elev", null)
	var raw_tile: Variant = data.get("tile", {})
	_saved_tile = raw_tile.duplicate(true) if typeof(raw_tile) == TYPE_DICTIONARY else {"tx": 0, "ty": 0}
	_restore_pending = pending


func _parse_shop_stock(raw: Variant) -> Dictionary:
	var result := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	for raw_shop_id in raw:
		var shop_id := str(raw_shop_id).strip_edges()
		if not shop_id.is_empty():
			result[shop_id] = EmberEconomy.normalize_stock_counts(raw[raw_shop_id])
	return result


func _parse_string_array(raw: Variant) -> Array:
	var result: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return result
	for value in raw:
		var text := str(value).strip_edges()
		if not text.is_empty() and text not in result:
			result.append(text)
	return result


func _parse_equipment(raw: Variant) -> Dictionary:
	return EmberEquipment.normalize(raw)


func _parse_flags(raw: Variant) -> Dictionary:
	var result := {}
	if typeof(raw) != TYPE_DICTIONARY:
		return result
	for raw_id in raw:
		var flag_id := str(raw_id).strip_edges()
		var value: Variant = raw[raw_id]
		if not flag_id.is_empty() and _is_flag_value(value):
			result[flag_id] = _normalize_flag_value(value)
	return result


func _chest_key(map_id: String, region_id: String) -> String:
	return "%s:%s" % [map_id.strip_edges(), region_id.strip_edges()]


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_finite_number(value: Variant) -> bool:
	return _is_number(value) and is_finite(float(value))


func _is_flag_value(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_BOOL
		or typeof(value) == TYPE_STRING
		or _is_number(value)
	)


func _normalize_flag_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)):
		var rounded := roundi(float(value))
		if is_equal_approx(float(value), float(rounded)):
			return rounded
	return value


func _empty_equipment() -> Dictionary:
	return EmberEquipment.empty()


func _stage_player_hp(map_id: String) -> float:
	var raw: Variant = EmberPack.parse_json_file(EmberPack.stage_path(map_id.strip_edges()))
	if typeof(raw) != TYPE_DICTIONARY:
		return DEFAULT_MAX_HP
	var value: Variant = raw.get("playerHp", DEFAULT_MAX_HP)
	if not _is_finite_number(value) or float(value) <= 0.0:
		return DEFAULT_MAX_HP
	return float(value)
