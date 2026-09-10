class_name EmberPartyState
extends RefCounted
## Pure persistent-party normalization and battle projection. EmberExploreState
## remains the only mutable/persistent owner; combat receives deep copies only.

const UnitCatalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")

const LEADER_ID := "protagonist"
const HERO_IDS: Array[String] = [LEADER_ID, "mira", "orik", "sena"]
const DEFAULT_BATTLE_STRATEGY: Array[String] = ["mira", "orik", "sena", LEADER_ID]
const MAX_LEVEL := 99

static var _unit_cache_ready := false
static var _units_by_id: Dictionary = {}


static func valid_active_hero_ids(raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY or raw.is_empty() or raw.size() > HERO_IDS.size():
		return false
	var seen: Array[String] = []
	for value in raw:
		if typeof(value) != TYPE_STRING or value not in HERO_IDS or value in seen:
			return false
		seen.append(value)
	return true


static func normalize_active_hero_ids(raw: Variant) -> Array[String]:
	# Missing/corrupt saves recover the complete legacy roster, never a partial
	# guessed story state. Runtime setters validate before calling this helper.
	var result: Array[String] = []
	result.assign(raw if valid_active_hero_ids(raw) else HERO_IDS)
	return result


static func active_strategy(raw: Variant, active_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for hero_id in normalize_battle_strategy(raw):
		if hero_id in active_ids:
			result.append(hero_id)
	return result


static func merge_active_strategy(raw: Variant, active_order: Array[String]) -> Array[String]:
	var result := normalize_battle_strategy(raw)
	var index := 0
	for slot in result.size():
		if result[slot] in active_order:
			result[slot] = active_order[index]
			index += 1
	return result


static func normalize_battle_strategy(raw: Variant) -> Array[String]:
	## A strategy stores party order only. Battlefield Resources remain the sole
	## spatial owner and map this order onto their first authored party cells.
	var source: Array = raw if typeof(raw) == TYPE_ARRAY else []
	var result: Array[String] = []
	for raw_id in source:
		var hero_id := str(raw_id).strip_edges()
		if hero_id not in HERO_IDS or hero_id in result:
			return DEFAULT_BATTLE_STRATEGY.duplicate()
		result.append(hero_id)
	return result if result.size() == HERO_IDS.size() else DEFAULT_BATTLE_STRATEGY.duplicate()


static func new_game(items: Dictionary = {}) -> Dictionary:
	var result := {}
	for hero_id in HERO_IDS:
		var member := _default_member(hero_id)
		var derived := derived_stats(hero_id, member, items)
		member["hp"] = int(derived.get("maxHp", 1))
		member["mp"] = int(derived.get("maxMp", 0))
		result[hero_id] = member
	return result


static func normalize(raw: Variant, items: Dictionary = {}) -> Dictionary:
	var source: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var result := {}
	var returned_items: Array[String] = []
	for hero_id in HERO_IDS:
		var fallback := _default_member(hero_id)
		var raw_member: Variant = source.get(hero_id, {})
		var member: Dictionary = raw_member if typeof(raw_member) == TYPE_DICTIONARY else {}
		var normalized := {
			"level": maxi(1, int(member.get("level", fallback.get("level", 1)))),
			"xp": maxi(0, int(member.get("xp", fallback.get("xp", 0)))),
			"hp": int(member.get("hp", fallback.get("hp", 1))),
			"mp": int(member.get("mp", fallback.get("mp", 0))),
			"equipment": EmberEquipment.empty(),
		}
		var equipment_result := _normalize_equipment(member.get("equipment", {}), hero_id, items)
		normalized["equipment"] = equipment_result.get("equipment", EmberEquipment.empty())
		returned_items.append_array(equipment_result.get("returnedItems", []))
		var derived := derived_stats(hero_id, normalized, items)
		normalized["hp"] = clampi(int(normalized["hp"]), 0, int(derived.get("maxHp", 1)))
		normalized["mp"] = clampi(int(normalized["mp"]), 0, int(derived.get("maxMp", 0)))
		result[hero_id] = normalized
	return {"party": result, "returnedItems": returned_items}


static func serialize(raw: Variant, items: Dictionary = {}) -> Dictionary:
	var normalized: Dictionary = normalize(raw, items).get("party", {})
	var result := {}
	for hero_id in HERO_IDS:
		var member: Dictionary = normalized.get(hero_id, {})
		result[hero_id] = {
			"level": int(member.get("level", 1)),
			"xp": int(member.get("xp", 0)),
			"hp": int(member.get("hp", 0)),
			"mp": int(member.get("mp", 0)),
			"equipment": EmberEquipment.normalize(member.get("equipment", {})),
		}
	return result


static func member_view(raw: Variant, hero_id: String, items: Dictionary = {}) -> Dictionary:
	if hero_id not in HERO_IDS:
		return {}
	var normalized: Dictionary = normalize(raw, items).get("party", {})
	return _member_view_from_normalized(normalized, hero_id, items)


static func unit_definition(hero_id: String) -> Dictionary:
	var unit := _unit_resource(hero_id)
	return unit.to_definition() if unit != null else {}


static func _member_view_from_normalized(
	normalized: Dictionary,
	hero_id: String,
	items: Dictionary,
) -> Dictionary:
	var member: Dictionary = normalized.get(hero_id, {})
	var result := member.duplicate(true)
	var unit := _unit_resource(hero_id)
	result["heroId"] = hero_id
	result["nameRu"] = unit.display_name if unit != null else hero_id
	result.merge(derived_stats(hero_id, member, items), true)
	return result


static func views(raw: Variant, items: Dictionary = {}, hero_ids: Array[String] = HERO_IDS) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var normalized: Dictionary = normalize(raw, items).get("party", {})
	for hero_id in hero_ids:
		result.append(_member_view_from_normalized(normalized, hero_id, items))
	return result


static func derived_stats(hero_id: String, member: Dictionary, items: Dictionary = {}) -> Dictionary:
	var unit := _unit_resource(hero_id)
	var level := maxi(1, int(member.get("level", 1)))
	var equipment := EmberEquipment.normalize(member.get("equipment", {}))
	var combat_stats := EmberEquipment.combat_stats(equipment, items)
	var base_hp := unit.max_hp if unit != null else 1
	var base_mp := unit.max_mp if unit != null else 0
	var max_hp := base_hp + (level - 1) * 2 + _equipment_bonus(equipment, items, "hpBonus")
	var max_mp := base_mp + (level - 1) + _equipment_bonus(equipment, items, "mpBonus")
	var level_steps := level - 1
	var base_strength := unit.strength if unit != null else 1
	var base_magic := unit.magic if unit != null else 1
	var base_defense := unit.defense if unit != null else 0
	var base_resistance := unit.resistance if unit != null else 0
	var base_speed := unit.speed if unit != null else 1
	var base_accuracy := unit.accuracy if unit != null else 80
	var base_luck := unit.luck if unit != null else 0
	var strength_value := base_strength + floori(float(level_steps) * 0.75) + int(combat_stats.get("atk", EmberEquipment.UNARMED_ATK))
	var magic_value := base_magic + floori(float(level_steps) * 0.75)
	var defense_value := base_defense + floori(float(level_steps) * 0.6) + int(combat_stats.get("def", EmberEquipment.UNARMED_DEF))
	var resistance_value := base_resistance + floori(float(level_steps) * 0.6)
	var speed_value := base_speed + floori(float(level_steps) / 4.0)
	var accuracy_value := base_accuracy + floori(float(level_steps) / 2.0)
	var luck_value := base_luck + floori(float(level_steps) / 3.0)
	return {
		"maxHp": maxi(1, max_hp),
		"maxMp": maxi(0, max_mp),
		"atk": int(combat_stats.get("atk", EmberEquipment.UNARMED_ATK)),
		"str": strength_value,
		"mag": magic_value,
		"def": defense_value,
		"res": resistance_value,
		"speed": speed_value,
		"acc": accuracy_value,
		"luck": luck_value,
		"eva": maxi(0, floori(float(speed_value) * 0.5 + float(luck_value) * 0.25)),
		"crit": clampi(5 + floori(float(luck_value) * 0.5), 0, 35),
		"resistances": unit.to_definition().get("resistances", {}).duplicate(true) if unit != null else {},
		"arenaAtk": int(combat_stats.get("arenaAtk", EmberEquipment.UNARMED_ATK)),
	}


static func battle_snapshot(raw: Variant, items: Dictionary = {}) -> Dictionary:
	return serialize(raw, items).duplicate(true)


static func apply_to_combat_state(
	combat_state: Dictionary,
	party_snapshot: Dictionary,
	items: Dictionary = {},
) -> Dictionary:
	var result := combat_state.duplicate(true)
	if party_snapshot.is_empty():
		return result
	var party_data: Dictionary = normalize(party_snapshot, items).get("party", {})
	var units: Dictionary = result.get("units", {})
	for hero_id in HERO_IDS:
		if not units.has(hero_id):
			continue
		var member: Dictionary = party_data.get(hero_id, {})
		var derived := derived_stats(hero_id, member, items)
		var unit: Dictionary = units[hero_id]
		unit["level"] = int(member.get("level", 1))
		unit["xp"] = int(member.get("xp", 0))
		unit["hp"] = int(member.get("hp", derived.get("maxHp", 1)))
		unit["maxHp"] = int(derived.get("maxHp", 1))
		unit["mp"] = int(member.get("mp", derived.get("maxMp", 0)))
		unit["maxMp"] = int(derived.get("maxMp", 0))
		unit["equipment"] = EmberEquipment.normalize(member.get("equipment", {}))
		unit["atk"] = int(derived.get("atk", EmberEquipment.UNARMED_ATK))
		for stat_key in ["str", "mag", "def", "res", "speed", "acc", "luck", "eva", "crit"]:
			unit[stat_key] = int(derived.get(stat_key, unit.get(stat_key, 0)))
		unit["resistances"] = (derived.get("resistances", {}) as Dictionary).duplicate(true)
		unit["arenaAtk"] = int(derived.get("arenaAtk", EmberEquipment.UNARMED_ATK))
		units[hero_id] = unit
	result["units"] = units
	return result


static func apply_combat_result(
	raw_party: Variant,
	combat_state: Dictionary,
	items: Dictionary = {},
	xp_reward: int = 0,
	victory: bool = false,
) -> Dictionary:
	var result: Dictionary = normalize(raw_party, items).get("party", {})
	var units: Dictionary = combat_state.get("units", {})
	var fallen_heroes := {}
	for hero_id in HERO_IDS:
		if not units.has(hero_id):
			continue
		var unit: Dictionary = units[hero_id]
		var member: Dictionary = result.get(hero_id, {})
		var derived := derived_stats(hero_id, member, items)
		var returned_hp := clampi(int(unit.get("hp", member.get("hp", 0))), 0, int(derived.get("maxHp", 1)))
		member["hp"] = returned_hp
		member["mp"] = clampi(int(unit.get("mp", member.get("mp", 0))), 0, int(derived.get("maxMp", 0)))
		result[hero_id] = member
		fallen_heroes[hero_id] = returned_hp <= 0
	if xp_reward > 0:
		result = (grant_equal_xp(result, xp_reward, items, combat_hero_ids(combat_state)).get("party", {}) as Dictionary)
	if victory:
		for hero_id in HERO_IDS:
			if not bool(fallen_heroes.get(hero_id, false)):
				continue
			var member: Dictionary = result.get(hero_id, {})
			member["hp"] = 1
			result[hero_id] = member
	return result


static func xp_to_next(level: int) -> int:
	var clean_level := clampi(level, 1, MAX_LEVEL)
	if clean_level >= MAX_LEVEL:
		return 0
	# Reversible vertical-slice curve: the first level arrives during the first
	# authored encounter, while later thresholds grow without changing save v2.
	return 30 + (clean_level - 1) * 15


static func grant_equal_xp(
	raw_party: Variant,
	xp_gain: int,
	items: Dictionary = {},
	hero_ids: Array[String] = HERO_IDS,
) -> Dictionary:
	var party_data: Dictionary = normalize(raw_party, items).get("party", {})
	var clean_gain := maxi(0, xp_gain)
	var rows: Array[Dictionary] = []
	for hero_id in hero_ids:
		var member: Dictionary = party_data.get(hero_id, {})
		var level_before := clampi(int(member.get("level", 1)), 1, MAX_LEVEL)
		var xp_before := maxi(0, int(member.get("xp", 0)))
		var hp_before := int(member.get("hp", 0))
		var mp_before := int(member.get("mp", 0))
		var derived_before := derived_stats(hero_id, member, items)
		var level_after := level_before
		var xp_after := xp_before + clean_gain
		while level_after < MAX_LEVEL:
			var threshold := xp_to_next(level_after)
			if threshold <= 0 or xp_after < threshold:
				break
			xp_after -= threshold
			level_after += 1
		if level_after >= MAX_LEVEL:
			xp_after = 0
		member["level"] = level_after
		member["xp"] = xp_after
		var derived_after := derived_stats(hero_id, member, items)
		var hp_growth := int(derived_after.get("maxHp", 1)) - int(derived_before.get("maxHp", 1))
		var mp_growth := int(derived_after.get("maxMp", 0)) - int(derived_before.get("maxMp", 0))
		# A level-up preserves the previous deficit. Zero HP stays zero here so the
		# victory rule can return a fallen hero at exactly 1 HP afterwards.
		member["hp"] = (
			0 if hp_before <= 0
			else clampi(hp_before + hp_growth, 1, int(derived_after.get("maxHp", 1)))
		)
		member["mp"] = clampi(mp_before + mp_growth, 0, int(derived_after.get("maxMp", 0)))
		party_data[hero_id] = member
		var stat_growth := {}
		for stat_key in ["maxHp", "maxMp", "str", "mag", "def", "res", "speed", "acc", "luck"]:
			var delta := int(derived_after.get(stat_key, 0)) - int(derived_before.get(stat_key, 0))
			if delta != 0:
				stat_growth[stat_key] = delta
		var unit := _unit_resource(hero_id)
		rows.append({
			"heroId": hero_id,
			"nameRu": unit.display_name if unit != null else hero_id,
			"xpGained": clean_gain,
			"levelBefore": level_before,
			"levelAfter": level_after,
			"xpBefore": xp_before,
			"xpAfter": xp_after,
			"xpToNext": xp_to_next(level_after),
			"hpBefore": hp_before,
			"hpAfter": int(member.get("hp", 0)),
			"mpBefore": mp_before,
			"mpAfter": int(member.get("mp", 0)),
			"statGrowth": stat_growth,
		})
	return {"party": party_data, "rows": rows, "xpGained": clean_gain}


static func combat_progression_preview(
	combat_state: Dictionary,
	xp_gain: int,
	victory: bool,
	items: Dictionary = {},
) -> Dictionary:
	var units: Dictionary = combat_state.get("units", {})
	var party_data := {}
	var fallen_heroes := {}
	for hero_id in HERO_IDS:
		var unit: Dictionary = units.get(hero_id, {})
		if unit.is_empty():
			continue
		party_data[hero_id] = {
			"level": int(unit.get("level", 1)),
			"xp": int(unit.get("xp", 0)),
			"hp": int(unit.get("hp", 0)),
			"mp": int(unit.get("mp", 0)),
			"equipment": EmberEquipment.normalize(unit.get("equipment", {})),
		}
		fallen_heroes[hero_id] = int(unit.get("hp", 0)) <= 0
	var progression := grant_equal_xp(party_data, xp_gain, items, combat_hero_ids(combat_state))
	# A preview describes participants only; normalization must not invent rows
	# or members for heroes who stayed outside this battle.
	for hero_id in HERO_IDS:
		if not party_data.has(hero_id):
			(progression["party"] as Dictionary).erase(hero_id)
	if victory:
		var progressed_party: Dictionary = progression.get("party", {})
		var rows: Array = progression.get("rows", [])
		for hero_id in HERO_IDS:
			if not bool(fallen_heroes.get(hero_id, false)):
				continue
			var member: Dictionary = progressed_party.get(hero_id, {})
			member["hp"] = 1
			progressed_party[hero_id] = member
			for index in rows.size():
				var row: Dictionary = rows[index]
				if str(row.get("heroId", "")) == hero_id:
					row["hpAfter"] = 1
					rows[index] = row
		progression["party"] = progressed_party
		progression["rows"] = rows
	return progression


static func combat_hero_ids(combat_state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var units: Dictionary = combat_state.get("units", {})
	for hero_id in HERO_IDS:
		if units.has(hero_id) and str((units[hero_id] as Dictionary).get("team", "")) == "hero":
			result.append(hero_id)
	return result


static func equipment_allowed(item: Dictionary, hero_id: String) -> bool:
	var raw_allowed: Variant = item.get("allowedHeroIds", [])
	if raw_allowed is PackedStringArray:
		return raw_allowed.is_empty() or hero_id in raw_allowed
	if typeof(raw_allowed) != TYPE_ARRAY or (raw_allowed as Array).is_empty():
		return true
	return hero_id in raw_allowed


static func _default_member(hero_id: String) -> Dictionary:
	var unit := _unit_resource(hero_id)
	return {
		"level": 1,
		"xp": 0,
		"hp": unit.max_hp if unit != null else 1,
		"mp": unit.max_mp if unit != null else 0,
		"equipment": EmberEquipment.empty(),
	}


static func _unit_resource(hero_id: String) -> EmberCombatUnitResource:
	if not _unit_cache_ready:
		# The general editor catalog intentionally performs fresh discovery. Party
		# runtime has four fixed IDs, so retain that single discovery snapshot for
		# this process instead of re-reading every combat Resource for each HP label.
		for unit in UnitCatalog.resources():
			_units_by_id[unit.unit_id] = unit
		_unit_cache_ready = true
	return _units_by_id.get(hero_id) as EmberCombatUnitResource


static func _normalize_equipment(raw: Variant, hero_id: String, items: Dictionary) -> Dictionary:
	var equipment := EmberEquipment.normalize(raw)
	var result := EmberEquipment.empty()
	var returned_items: Array[String] = []
	for slot in EmberEquipment.SLOTS:
		var value: Variant = equipment.get(slot, null)
		if value == null or str(value).strip_edges().is_empty():
			continue
		var item_id := str(value).strip_edges()
		var item: Dictionary = items.get(item_id, {})
		if item.is_empty() or EmberEquipment.slot_for_item(item) != slot or not equipment_allowed(item, hero_id):
			returned_items.append(item_id)
			continue
		result[slot] = item_id
	return {"equipment": result, "returnedItems": returned_items}


static func _equipment_bonus(equipment: Dictionary, items: Dictionary, key: String) -> int:
	var result := 0
	for slot in EmberEquipment.SLOTS:
		var value: Variant = equipment.get(slot, null)
		if value != null:
			result += int((items.get(str(value), {}) as Dictionary).get(key, 0))
	return result
