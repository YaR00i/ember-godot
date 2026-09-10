class_name EmberCombatPrototype
extends RefCounted
## Pure D1 combat laboratory model.
## This is deliberately not a production battle/save/content owner. The lab UI,
## preview and commit all call the same resolver so the tested rules cannot drift.

const Terrain = preload("res://scripts/prototypes/ember_combat_terrain.gd")
const UnitCatalog = preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const ActionCatalog = preload("res://scripts/prototypes/ember_combat_action_catalog.gd")
const AiProfileCatalog = preload("res://scripts/prototypes/ember_combat_ai_profile_catalog.gd")
const StatusRules = preload("res://scripts/prototypes/ember_combat_status_rules.gd")
const DamageRules = preload("res://scripts/prototypes/ember_combat_damage_rules.gd")
const EffectRules = preload("res://scripts/prototypes/ember_combat_effect_rules.gd")
const StateSchema = preload("res://scripts/prototypes/ember_combat_state_schema.gd")
const INVALID_CELL := Vector2i(-999999, -999999)
const ITEM_COMMAND_PREFIX := "item:"
const HELD_THROW_COMMAND := "__held_throw"
const HELD_LOWER_COMMAND := "__held_lower"
const HELD_GUARD_COMMAND := "__held_guard"

const ZONES := [
	{
		"id": "hero_rear", "name": "Тыл героев",
		"subtitle": "без правила", "tags": [],
		"color": Color("31435f"),
	},
	{
		"id": "wet_lowland", "name": "Мокрая низина",
		"subtitle": "Wet проводит молнию", "tags": ["wet"],
		"color": Color("245b73"),
	},
	{
		"id": "stone_crossing", "name": "Каменный мост",
		"subtitle": "узкая позиция", "tags": [],
		"color": Color("5a5268"),
	},
	{
		"id": "enemy_rear", "name": "Тыл врагов",
		"subtitle": "без правила", "tags": [],
		"color": Color("65404c"),
	},
]


static func initial_state(rng_seed: int = 1) -> Dictionary:
	var units := UnitCatalog.definitions()
	return {
		"encounterId": "e1_wet_conductor",
		"turn": 1,
		"rngSeed": rng_seed,
		"units": units,
		"holds": {},
		"zones": ZONES.duplicate(true),
		"log": ["E1 · Мокрый проводник: подготовьте Wet и используйте реакцию."],
	}


static func action_definition(action_id: String) -> Dictionary:
	return ActionCatalog.definition(action_id)


static func command_definition(state: Dictionary, command_id: String) -> Dictionary:
	if command_id in [HELD_THROW_COMMAND, HELD_LOWER_COMMAND, HELD_GUARD_COMMAND]:
		var carrier_id := current_unit_id(state)
		if held_target_id(state, carrier_id).is_empty():
			return {}
		var definitions := {
			HELD_THROW_COMMAND: {
				"id": HELD_THROW_COMMAND, "name": "Бросить", "element": "physical",
				"target": "cell", "effect": "held_throw", "mpCost": 0,
				"delay": 100, "range": _held_throw_range(state, carrier_id),
				"power": int(_held_lift_action(state, carrier_id).get("power", 0)),
				"hint": "Бросить удерживаемую цель на выбранную клетку.",
			},
			HELD_LOWER_COMMAND: {
				"id": HELD_LOWER_COMMAND, "name": "Опустить", "element": "support",
				"target": "self", "effect": "held_lower", "power": 0, "mpCost": 0,
				"delay": 100, "range": 0,
				"hint": "Поставить удерживаемую цель на ближайшую допустимую клетку.",
			},
			HELD_GUARD_COMMAND: {
				"id": HELD_GUARD_COMMAND, "name": "Удерживать и защищаться",
				"element": "support", "target": "self", "effect": "held_guard",
				"power": 0, "mpCost": 0, "delay": 100, "range": 0,
				"hint": "Сохранить удержание и завершить ход в Защите.",
			},
		}
		return (definitions[command_id] as Dictionary).duplicate(true)
	if not is_item_command(command_id):
		return action_definition(command_id)
	var item_id := item_id_from_command(command_id)
	var item := combat_item_definition(state, item_id)
	if item.is_empty():
		return {}
	var effects: Array[String] = []
	if int(item.get("hpRestore", 0)) > 0:
		effects.append("HP +%d" % int(item.get("hpRestore", 0)))
	if int(item.get("mpRestore", 0)) > 0:
		effects.append("MP +%d" % int(item.get("mpRestore", 0)))
	if int(item.get("reviveHp", 0)) > 0:
		effects.append("воскрешение с %d HP" % int(item.get("reviveHp", 0)))
	return {
		"id": command_id,
		"itemId": item_id,
		"name": str(item.get("nameRu", item.get("name", item_id))),
		"element": "support",
		"target": "ally",
		"effect": "item_use",
		"power": 0,
		"mpCost": 0,
		"delay": maxi(1, int(item.get("combatDelay", 100))),
		"range": maxi(0, int(item.get("combatRange", 1))),
		"hint": ", ".join(effects),
		"requirements": (
			"Только павший союзник; предмет расходуется и завершает действие."
			if int(item.get("reviveHp", 0)) > 0
			else "Живой союзник с неполными HP или MP; предмет расходуется и завершает действие."
		),
		"menuGroup": "item",
		"menuGroupLabel": "Предмет",
		"uiColor": Color("79d8a3"),
		"iconId": str(item.get("iconId", "")),
		"hpRestore": int(item.get("hpRestore", 0)),
		"mpRestore": int(item.get("mpRestore", 0)),
		"reviveHp": int(item.get("reviveHp", 0)),
	}


static func is_item_command(command_id: String) -> bool:
	return command_id.begins_with(ITEM_COMMAND_PREFIX) and not item_id_from_command(command_id).is_empty()


static func item_id_from_command(command_id: String) -> String:
	return command_id.trim_prefix(ITEM_COMMAND_PREFIX).strip_edges()


static func combat_item_definition(state: Dictionary, item_id: String) -> Dictionary:
	var item := ((state.get("itemDefinitions", {}) as Dictionary).get(item_id, {}) as Dictionary)
	if (
		item.is_empty()
		or str(item.get("useIn", "explore")) not in ["arena", "both"]
		or str(item.get("kind", "")) != "consumable"
		or (
			int(item.get("hpRestore", 0)) <= 0
			and int(item.get("mpRestore", 0)) <= 0
			and int(item.get("reviveHp", 0)) <= 0
		)
	):
		return {}
	return item.duplicate(true)


static func combat_item_ids(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var inventory: Dictionary = state.get("inventory", {})
	for raw_id in inventory:
		var item_id := str(raw_id)
		if int(inventory.get(raw_id, 0)) > 0 and not combat_item_definition(state, item_id).is_empty():
			result.append("%s%s" % [ITEM_COMMAND_PREFIX, item_id])
	result.sort_custom(func(a: String, b: String) -> bool:
		return str(command_definition(state, a).get("name", a)).naturalnocasecmp_to(
			str(command_definition(state, b).get("name", b))
		) < 0
	)
	return result


static func command_ids_for_current_actor(state: Dictionary, include_items := true) -> Array[String]:
	var actor_id := current_unit_id(state)
	if actor_id.is_empty():
		return []
	if not held_target_id(state, actor_id).is_empty():
		return [HELD_THROW_COMMAND, HELD_LOWER_COMMAND, HELD_GUARD_COMMAND]
	var result: Array[String] = []
	for raw_id in unit_definition(state, actor_id).get("actions", []):
		result.append(str(raw_id))
	if include_items and str(unit_definition(state, actor_id).get("team", "")) == "hero":
		result.append_array(combat_item_ids(state))
	return result


static func held_target_id(state: Dictionary, carrier_id: String) -> String:
	return str((state.get("holds", {}) as Dictionary).get(carrier_id, ""))


static func carrier_id_for(state: Dictionary, target_id: String) -> String:
	for raw_carrier_id in state.get("holds", {}):
		var carrier_id := str(raw_carrier_id)
		if held_target_id(state, carrier_id) == target_id:
			return carrier_id
	return ""


static func is_held(state: Dictionary, unit_id: String) -> bool:
	return not carrier_id_for(state, unit_id).is_empty()


static func with_inventory(
	state: Dictionary,
	inventory: Dictionary,
	item_definitions: Dictionary,
) -> Dictionary:
	var result := state.duplicate(true)
	var counts := {}
	var definitions := {}
	for raw_id in inventory:
		var item_id := str(raw_id).strip_edges()
		var count := maxi(0, int(inventory.get(raw_id, 0)))
		if item_id.is_empty() or count <= 0:
			continue
		counts[item_id] = count
		var item := (item_definitions.get(item_id, {}) as Dictionary)
		if not item.is_empty():
			definitions[item_id] = item.duplicate(true)
	result["inventory"] = counts
	result["itemDefinitions"] = definitions
	return result


static func _item_has_effect_for_target(action: Dictionary, target: Dictionary) -> bool:
	var hp := int(target.get("hp", 0))
	if int(action.get("reviveHp", 0)) > 0:
		return hp <= 0
	if hp <= 0:
		return false
	var missing_hp := hp < int(target.get("maxHp", hp))
	var mp := int(target.get("mp", 0))
	var missing_mp := mp < int(target.get("maxMp", mp))
	return (
		(int(action.get("hpRestore", 0)) > 0 and missing_hp)
		or (int(action.get("mpRestore", 0)) > 0 and missing_mp)
	)


static func action_ids() -> PackedStringArray:
	return ActionCatalog.ids()


static func unit_definition(state: Dictionary, unit_id: String) -> Dictionary:
	return ((state.get("units", {}) as Dictionary).get(unit_id, {}) as Dictionary).duplicate(true)


static func state_validation_errors(state: Dictionary) -> Array[String]:
	return StateSchema.validation_errors(state)


static func current_unit_id(state: Dictionary) -> String:
	var best_id := ""
	var best_at := INF
	for raw_id in state.get("units", {}):
		var unit_id := str(raw_id)
		var unit: Dictionary = (state.get("units", {}) as Dictionary).get(unit_id, {})
		if int(unit.get("hp", 0)) <= 0 or is_held(state, unit_id):
			continue
		var next_at := float(unit.get("nextAt", 0.0))
		if next_at < best_at or (is_equal_approx(next_at, best_at) and unit_id < best_id):
			best_at = next_at
			best_id = unit_id
	return best_id


static func timeline(state: Dictionary, count: int = 8, pending_action_id: String = "") -> Array[Dictionary]:
	var times := {}
	var speeds := {}
	var units: Dictionary = state.get("units", {})
	for raw_id in units:
		var unit_id := str(raw_id)
		var unit: Dictionary = units[unit_id]
		if int(unit.get("hp", 0)) <= 0 or is_held(state, unit_id):
			continue
		times[unit_id] = float(unit.get("nextAt", 0.0))
		speeds[unit_id] = maxi(1, int(unit.get("speed", 10)))
	var active_id := current_unit_id(state)
	if not pending_action_id.is_empty() and times.has(active_id):
		var pending := command_definition(state, pending_action_id)
		if (
			not pending.is_empty()
			and duo_partner_unavailable_reason(state, pending_action_id).is_empty()
		):
			times[active_id] = float(times[active_id]) + _delay_for(pending, int(speeds[active_id]))
			var partner_id := str(pending.get("partnerId", ""))
			if times.has(partner_id):
				times[partner_id] = float(times[partner_id]) + _delay_for(
					{"delay": int(pending.get("partnerDelay", 0))},
					int(speeds[partner_id]),
				)
	var result: Array[Dictionary] = []
	for _index in maxi(0, count):
		if times.is_empty():
			break
		var next_id := _earliest_id(times)
		result.append({"unitId": next_id, "at": float(times[next_id])})
		times[next_id] = float(times[next_id]) + _delay_for(
			{"delay": 100}, int(speeds[next_id])
		)
	return result


static func valid_target_ids(state: Dictionary, action_id: String) -> Array[String]:
	return _unit_target_ids(state, action_id, true)


static func eligible_target_ids(state: Dictionary, action_id: String) -> Array[String]:
	## Position-independent target eligibility for the grid approach planner.
	## Range and line of sight are intentionally deferred; ownership, resources,
	## team, life state and authored target conditions still apply.
	return _unit_target_ids(state, action_id, false)


static func _unit_target_ids(
	state: Dictionary,
	action_id: String,
	check_position: bool,
) -> Array[String]:
	var result: Array[String] = []
	var actor_id := current_unit_id(state)
	var actor := unit_definition(state, actor_id)
	var action := command_definition(state, action_id)
	var item_command := is_item_command(action_id)
	var synthetic_command := action_id in [HELD_LOWER_COMMAND, HELD_GUARD_COMMAND]
	if (
		actor.is_empty()
		or action.is_empty()
		or (not item_command and not synthetic_command and action_id not in actor.get("actions", []))
		or (item_command and str(actor.get("team", "")) != "hero")
		or (not held_target_id(state, actor_id).is_empty() and not synthetic_command)
	):
		return result
	if item_command:
		var item_id := item_id_from_command(action_id)
		if int((state.get("inventory", {}) as Dictionary).get(item_id, 0)) <= 0:
			return result
	if int(actor.get("mp", 0)) < int(action.get("mpCost", 0)):
		return result
	if not duo_partner_unavailable_reason(state, action_id).is_empty():
		return result
	var target_team := str(action.get("target", "enemy"))
	var effect_id := str(action.get("effect", "damage"))
	if target_team == "cell":
		return result
	if effect_id == "lift_throw" and not state.has("grid"):
		return result
	for raw_id in state.get("units", {}):
		var target_id := str(raw_id)
		var target := unit_definition(state, target_id)
		if is_held(state, target_id):
			continue
		var same_team := str(target.get("team", "")) == str(actor.get("team", ""))
		if item_command:
			if not same_team or not _item_has_effect_for_target(action, target):
				continue
		elif int(target.get("hp", 0)) <= 0:
			continue
		if target_team == "unit" and target_id == actor_id:
			continue
		if target_team == "self" and target_id != actor_id:
			continue
		if target_team == "enemy" and same_team:
			continue
		if target_team == "ally" and not same_team:
			continue
		if not _authored_effects_allow_unit_target(action, target):
			continue
		if (
			effect_id == "lift_throw"
			and int(target.get("weightClass", 1)) > int(action.get("maxLiftWeight", 0))
		):
			continue
		if state.has("grid") and check_position:
			var actor_cell: Vector2i = actor.get("cell", Vector2i.ZERO)
			var target_cell: Vector2i = target.get("cell", Vector2i.ZERO)
			var distance := Terrain.action_distance(state, actor_cell, target_cell)
			if distance > int(action.get("range", 1)):
				continue
			if target_team != "self" and not Terrain.has_line_of_sight(state, actor_cell, target_cell):
				continue
		if str(action.get("effect", "")) == "duo_pulse" and not _is_wet(state, target):
			continue
		if str(action.get("effect", "")) == "steam_breach" and not _is_frozen(state, target):
			continue
		result.append(target_id)
	return result


static func has_valid_target(state: Dictionary, action_id: String) -> bool:
	var action := command_definition(state, action_id)
	if str(action.get("target", "")) == "cell":
		return not valid_target_cells(state, action_id).is_empty()
	return not valid_target_ids(state, action_id).is_empty()


static func valid_target_cells(state: Dictionary, action_id: String) -> Array[Vector2i]:
	return _target_cells(state, action_id, true)


static func eligible_target_cells(state: Dictionary, action_id: String) -> Array[Vector2i]:
	return _target_cells(state, action_id, false)


static func _target_cells(state: Dictionary, action_id: String, check_position: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var actor_id := current_unit_id(state)
	var actor := unit_definition(state, actor_id)
	var action := command_definition(state, action_id)
	var synthetic_throw := action_id == HELD_THROW_COMMAND
	if (
		actor.is_empty()
		or action.is_empty()
		or str(action.get("target", "")) != "cell"
		or not state.has("grid")
		or (not synthetic_throw and action_id not in actor.get("actions", []))
		or (not held_target_id(state, actor_id).is_empty() and not synthetic_throw)
		or int(actor.get("mp", 0)) < int(action.get("mpCost", 0))
		or not duo_partner_unavailable_reason(state, action_id).is_empty()
	):
		return result
	var actor_cell: Vector2i = actor.get("cell", INVALID_CELL)
	var grid: Dictionary = state.get("grid", {})
	for y in int(grid.get("height", 0)):
		for x in int(grid.get("width", 0)):
			var cell := Vector2i(x, y)
			if synthetic_throw:
				if _release_cell_available(state, actor_id, cell) and (
					not check_position or Terrain.action_distance(state, actor_cell, cell) <= int(action.get("range", 0))
				):
					result.append(cell)
				continue
			if (
				(check_position and Terrain.action_distance(state, actor_cell, cell) > int(action.get("range", 0)))
				or (check_position and not Terrain.has_line_of_sight(state, actor_cell, cell))
				or not _effect_steps_apply_to_cell(state, action, cell)
			):
				continue
			result.append(cell)
	return result


static func duo_partner_unavailable_reason(state: Dictionary, action_id: String) -> String:
	var action := command_definition(state, action_id)
	var partner_id := str(action.get("partnerId", ""))
	if partner_id.is_empty():
		return ""
	var actor_id := current_unit_id(state)
	var actor := unit_definition(state, actor_id)
	var partner := unit_definition(state, partner_id)
	if partner.is_empty() or partner_id == actor_id or str(partner.get("team", "")) != str(actor.get("team", "")):
		return "Партнёр недоступен"
	if int(partner.get("hp", 0)) <= 0:
		return "%s выведен из боя" % str(partner.get("name", partner_id))
	var context := duo_partner_context(state, action_id)
	if not bool(context.get("hasGridDistance", false)):
		return "Для связки требуется клеточное поле"
	if not bool(context.get("inRange", false)):
		return "%s вне радиуса: %d/%d клеток" % [
			str(partner.get("name", partner_id)),
			int(context.get("distance", -1)),
			int(context.get("range", 0)),
		]
	var partner_cost := int(action.get("partnerMpCost", 0))
	if int(partner.get("mp", 0)) < partner_cost:
		return "%s: нужно %d MP" % [str(partner.get("name", partner_id)), partner_cost]
	return ""


static func duo_partner_context(state: Dictionary, action_id: String) -> Dictionary:
	var action := command_definition(state, action_id)
	var partner_id := str(action.get("partnerId", ""))
	if partner_id.is_empty():
		return {}
	var actor_id := current_unit_id(state)
	var actor := unit_definition(state, actor_id)
	var partner := unit_definition(state, partner_id)
	var radius := maxi(0, int(action.get("partnerRange", 0)))
	var result := {
		"actionId": action_id,
		"actorId": actor_id,
		"partnerId": partner_id,
		"partnerName": str(partner.get("name", partner_id)),
		"range": radius,
		"distance": -1,
		"hasGridDistance": false,
		"inRange": false,
	}
	if (
		state.has("grid")
		and actor.has("cell")
		and partner.has("cell")
		and radius > 0
	):
		var distance := Terrain.action_distance(
			state,
			actor.get("cell", Vector2i.ZERO),
			partner.get("cell", Vector2i.ZERO),
		)
		result["distance"] = distance
		result["hasGridDistance"] = true
		result["inRange"] = distance <= radius
	return result


static func valid_secondary_cells(
	state: Dictionary,
	action_id: String,
	target_id: String,
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var action := command_definition(state, action_id)
	if (
		str(action.get("effect", "")) != "lift_throw"
		or target_id not in valid_target_ids(state, action_id)
	):
		return result
	var target := unit_definition(state, target_id)
	if not target.has("cell"):
		return result
	var grid: Dictionary = state.get("grid", {})
	for y in int(grid.get("height", 0)):
		for x in int(grid.get("width", 0)):
			var cell := Vector2i(x, y)
			if _secondary_cell_available(state, action, target, cell):
				result.append(cell)
	return result


static func preview(
	state: Dictionary,
	action_id: String,
	target_id: String,
	secondary_cell: Vector2i = INVALID_CELL,
	target_cell: Vector2i = INVALID_CELL,
	lift_choice: String = "throw",
) -> Dictionary:
	var state_error := StateSchema.first_error(state)
	if not state_error.is_empty():
		return _invalid_preview(state_error)
	var actor_id := current_unit_id(state)
	var actor := unit_definition(state, actor_id)
	var action := command_definition(state, action_id)
	var cell_target := str(action.get("target", "")) == "cell"
	var resolved_target_id := target_id
	if cell_target and target_cell in valid_target_cells(state, action_id):
		resolved_target_id = _grid_occupant(state, target_cell)
	var target := unit_definition(state, resolved_target_id)
	if actor.is_empty() or action.is_empty() or (not cell_target and target.is_empty()):
		return _invalid_preview("Не выбраны действие или цель.")
	var synthetic_command := action_id in [HELD_THROW_COMMAND, HELD_LOWER_COMMAND, HELD_GUARD_COMMAND]
	if (
		(
			not is_item_command(action_id)
			and not synthetic_command
			and action_id not in actor.get("actions", [])
		)
		or (not held_target_id(state, actor_id).is_empty() and not synthetic_command)
		or (
			cell_target
			and target_cell not in valid_target_cells(state, action_id)
		)
		or (
			not cell_target
			and target_id not in valid_target_ids(state, action_id)
		)
	):
		return _invalid_preview("Эта цель недоступна для выбранного действия.")
	var effect_id := str(action.get("effect", "damage"))
	if (
		effect_id == "lift_throw"
		and lift_choice not in ["hold", "lower"]
		and not _secondary_cell_available(state, action, target, secondary_cell)
	):
		return _invalid_preview("Выберите допустимую клетку приземления.")
	var partner_id := str(action.get("partnerId", ""))
	var partner := unit_definition(state, partner_id)
	var partner_mp_cost := int(action.get("partnerMpCost", 0))
	var partner_context := duo_partner_context(state, action_id)
	var result := {
		"ok": true,
		"stateTurn": int(state.get("turn", 1)),
		"stateHash": hash(state),
		"actorId": actor_id,
		"actionId": action_id,
		"targetId": resolved_target_id,
		"targetCell": target_cell,
		"mpCost": int(action.get("mpCost", 0)),
		"mpBefore": int(actor.get("mp", 0)),
		"mpAfter": maxi(0, int(actor.get("mp", 0)) - int(action.get("mpCost", 0))),
		"partnerId": partner_id,
		"partnerRange": int(partner_context.get("range", 0)),
		"partnerDistance": int(partner_context.get("distance", -1)),
		"partnerMpCost": partner_mp_cost,
		"partnerMpBefore": int(partner.get("mp", 0)) if not partner.is_empty() else 0,
		"partnerMpAfter": maxi(0, int(partner.get("mp", 0)) - partner_mp_cost) if not partner.is_empty() else 0,
		"partnerDelay": int(action.get("partnerDelay", 0)),
		"damage": {},
		"fixedDamage": {},
		"setStatuses": {},
		"removeStatuses": {},
		"moves": {},
		"cellChanges": {},
		"restoreHp": {},
		"restoreMp": {},
		"inventoryCost": {},
		"reaction": "",
		"notes": [],
		"secondaryCell": secondary_cell,
	}
	if not partner.is_empty():
		(result["notes"] as Array).append(
			"%s участвует в технике и задерживается в очереди." % str(partner.get("name", partner_id))
		)
	var hostile := not target.is_empty() and str(actor.get("team", "")) != str(target.get("team", ""))
	result["hostile"] = hostile
	result["hitChance"] = 100
	result["hitRoll"] = 0
	result["hit"] = true
	result["critChance"] = 0
	result["critRoll"] = 0
	result["critical"] = false
	if hostile:
		var hit_chance := _hit_chance(actor, target, action)
		var hit_roll := _locked_roll(state, actor, action, target, secondary_cell, "hit")
		var critical_chance := _critical_chance(actor, action)
		var critical_roll := _locked_roll(state, actor, action, target, secondary_cell, "crit")
		result["hitChance"] = hit_chance
		result["hitRoll"] = hit_roll
		result["hit"] = hit_roll <= hit_chance
		result["critChance"] = critical_chance
		result["critRoll"] = critical_roll
		result["critical"] = bool(result["hit"]) and critical_chance > 0 and critical_roll <= critical_chance
		if not bool(result["hit"]):
			(result["notes"] as Array).append("Атака не попадает; MP и ход всё равно расходуются.")
			result["summary"] = describe_preview(state, result)
			return result
	var power := maxi(0, int(action.get("power", 0)))
	var element_id := str(action.get("element", ""))
	if power > 0 and _has_status(actor, "overheated"):
		power += 2
		(result["notes"] as Array).append("Накал усиливает силу приёма на +2.")
	var field_bonus := _field_power_bonus(state, actor, element_id)
	if field_bonus > 0:
		power += field_bonus
		(result["notes"] as Array).append("Жар-фокус усиливает огонь на +%d." % field_bonus)
	if power > 0 and effect_id != "lift_throw" and not resolved_target_id.is_empty():
		_set_damage(result, resolved_target_id, power)
	match effect_id:
		"item_use":
			var item_id := item_id_from_command(action_id)
			result["inventoryCost"] = {"itemId": item_id, "count": 1}
			var hp_restore := int(action.get("hpRestore", 0))
			var mp_restore := int(action.get("mpRestore", 0))
			var revive_hp := int(action.get("reviveHp", 0))
			if int(target.get("hp", 0)) <= 0 and revive_hp > 0:
				(result["restoreHp"] as Dictionary)[target_id] = mini(
					int(target.get("maxHp", 1)), revive_hp
				)
				result["reaction"] = "Возвращение в бой"
			else:
				if hp_restore > 0:
					(result["restoreHp"] as Dictionary)[target_id] = mini(
						int(target.get("maxHp", 1)), int(target.get("hp", 0)) + hp_restore
					)
				if mp_restore > 0:
					(result["restoreMp"] as Dictionary)[target_id] = mini(
						int(target.get("maxMp", 0)), int(target.get("mp", 0)) + mp_restore
					)
		"douse":
			if _has_status(target, "burning"):
				_remove_status(result, target_id, "burning")
				result["reaction"] = "Тушение"
			_set_hostile_status(result, target, "wet", 2)
			if state.has("grid") and target.has("cell"):
				_set_cell_tags(
					state, result, target.get("cell", Vector2i.ZERO), ["wet"], ["frozen"]
				)
				(result["notes"] as Array).append(
					"Клетка %s становится Wet." % _cell_label(target.get("cell", Vector2i.ZERO))
				)
		"chill":
			if _is_wet(state, target):
				_set_hostile_status(result, target, "frozen", 1)
				_remove_status(result, target_id, "wet")
				_set_damage(result, target_id, power + 1)
				result["reaction"] = "Заморозка"
				if state.has("grid") and target.has("cell") and _grid_cell_has_tag(
					state, target.get("cell", Vector2i.ZERO), "wet"
				):
					_change_linked_surface(
						state, result, target.get("cell", Vector2i.ZERO), ["frozen"], ["wet"]
					)
					(result["notes"] as Array).append(
						"Связанные мокрые панели замерзают."
					)
		"spark":
			if _is_wet(state, target):
				result["reaction"] = "Проводящая цепь"
				for raw_id in state.get("units", {}):
					var chained_id := str(raw_id)
					var chained := unit_definition(state, chained_id)
					if (
						chained_id == target_id
						or int(chained.get("hp", 0)) <= 0
						or str(chained.get("team", "")) == str(actor.get("team", ""))
						or not _shares_conduction_area(state, target, chained)
						or not _is_wet(state, chained)
					):
						continue
					_set_damage(result, chained_id, maxi(1, power - 1))
				(result["notes"] as Array).append("Цепь проходит по мокрой области.")
		"kindle":
			var frozen_field := (
				state.has("grid")
				and target.has("cell")
				and _grid_cell_has_tag(state, target.get("cell", Vector2i.ZERO), "frozen")
			)
			if _has_status(target, "frozen"):
				_remove_status(result, target_id, "frozen")
				_set_damage(result, target_id, power + 2)
				result["reaction"] = "Паровой импульс"
				_set_push(state, result, actor, target, int(action.get("force", 0)))
			elif frozen_field:
				result["reaction"] = "Оттепель"
			elif _is_wet(state, target):
				_remove_status(result, target_id, "wet")
				_set_damage(result, target_id, maxi(1, power - 2))
				result["reaction"] = "Испарение"
			else:
				_set_hostile_status(result, target, "burning", 2)
			if frozen_field:
				_change_linked_surface(
					state, result, target.get("cell", Vector2i.ZERO), ["wet"], ["frozen"]
				)
				(result["notes"] as Array).append(
					"Нагрев возвращает связанным панелям Wet."
				)
		"gust":
			_set_push(state, result, actor, target, int(action.get("force", 0)))
		"guard":
			_set_status(result, target_id, "guard", 1)
		"defend":
			_set_status(result, target_id, "guard", 2 if target_id == actor_id else 1)
			result["reaction"] = "Оборона"
			(result["notes"] as Array).append("Ход завершается без атаки.")
		"held_guard":
			_set_status(result, actor_id, "guard", 2)
			result["reaction"] = "Удержание и оборона"
			(result["notes"] as Array).append("Цель остаётся поднятой; носитель защищается.")
		"held_lower":
			var lower_cell := _nearest_release_cell(state, actor_id)
			if lower_cell == INVALID_CELL:
				return _invalid_preview("Нет допустимой клетки, чтобы опустить цель.")
			result["releaseHold"] = {"carrierId": actor_id, "targetId": held_target_id(state, actor_id)}
			(result["moves"] as Dictionary)[held_target_id(state, actor_id)] = lower_cell
			result["reaction"] = "Цель опущена"
			(result["notes"] as Array).append("Освобождение: %s." % _cell_label(lower_cell))
		"held_throw":
			var held_id := held_target_id(state, actor_id)
			var held_target := unit_definition(state, held_id)
			result["releaseHold"] = {"carrierId": actor_id, "targetId": held_id}
			(result["moves"] as Dictionary)[held_id] = target_cell
			result["throwPath"] = [actor.get("cell", INVALID_CELL), target_cell]
			result["reaction"] = "Бросок удерживаемой цели"
			if str(actor.get("team", "")) != str(held_target.get("team", "")) and power > 0:
				_add_damage(result, held_id, power)
			var held_origin: Vector2i = actor.get("cell", INVALID_CELL)
			var held_fall := Terrain.fall_damage(state, held_origin, target_cell)
			if held_fall > 0:
				_add_fixed_damage(result, held_id, held_fall)
				result["fallDamage"] = held_fall
		"duo_pulse":
			result["reaction"] = "Грозовая связка"
			for raw_id in state.get("units", {}):
				var chained_id := str(raw_id)
				var chained := unit_definition(state, chained_id)
				if (
					chained_id == target_id
					or int(chained.get("hp", 0)) <= 0
					or str(chained.get("team", "")) == str(actor.get("team", ""))
					or not _shares_conduction_area(state, target, chained)
					or not _is_wet(state, chained)
				):
					continue
				_set_damage(result, chained_id, maxi(1, power - 2))
			(result["notes"] as Array).append("Связка проходит по мокрым врагам одной цепи.")
		"steam_breach":
			result["reaction"] = "Паровой пробой"
			_add_damage(result, target_id, 3)
			_remove_status(result, target_id, "frozen")
			_set_push(state, result, actor, target, int(action.get("force", 0)))
			if state.has("grid") and target.has("cell") and _grid_cell_has_tag(
				state, target.get("cell", Vector2i.ZERO), "frozen"
			):
				_change_linked_surface(
					state, result, target.get("cell", Vector2i.ZERO), ["wet"], ["frozen"]
				)
				(result["notes"] as Array).append("Пар возвращает связанным панелям Wet.")
		"lift_throw":
			var target_origin: Vector2i = target.get("cell", INVALID_CELL)
			if lift_choice == "lower":
				(result["moves"] as Dictionary)[target_id] = target_origin
				result["reaction"] = "Цель опущена"
			elif lift_choice == "hold":
				_set_status(result, actor_id, "guard", 2)
				result["setHold"] = {"carrierId": actor_id, "targetId": target_id}
				result["reaction"] = "Цель оставлена поднятой"
				(result["notes"] as Array).append("Цель больше не занимает исходную клетку.")
			else:
				var moves: Dictionary = result.get("moves", {})
				moves[target_id] = secondary_cell
				result["moves"] = moves
				result["throwPath"] = [target_origin, secondary_cell]
				result["reaction"] = "Подъём и бросок"
				if str(actor.get("team", "")) != str(target.get("team", "")) and power > 0:
					_add_damage(result, target_id, power)
				var fall := Terrain.fall_damage(state, target_origin, secondary_cell)
				if fall > 0:
					_add_fixed_damage(result, target_id, fall)
					result["fallDamage"] = int(result.get("fallDamage", 0)) + fall
					(result["notes"] as Array).append(
						"Падение с h%d на h%d наносит %d HP." % [
							Terrain.elevation(state, target_origin),
							Terrain.elevation(state, secondary_cell),
							fall,
						]
					)
				(result["notes"] as Array).append(
					"Приземление: %s." % _cell_label(secondary_cell)
				)
	_apply_authored_effects(state, result, actor, target, action, target_cell)
	if action_id not in [HELD_THROW_COMMAND, HELD_LOWER_COMMAND]:
		_strip_held_effects(state, result)
	_finalize_action_damage(state, result, actor, action)
	_apply_guard_preview(state, result)
	result["summary"] = describe_preview(state, result)
	return result


static func commit(state: Dictionary, resolved: Dictionary) -> Dictionary:
	if not StateSchema.first_error(state).is_empty():
		return state.duplicate(true)
	if not StateSchema.first_result_error(resolved).is_empty():
		return state.duplicate(true)
	if not bool(resolved.get("ok", false)):
		return state.duplicate(true)
	if resolved.has("stateTurn") and int(resolved.get("stateTurn", -1)) != int(state.get("turn", 1)):
		return state.duplicate(true)
	if resolved.has("stateHash") and int(resolved.get("stateHash", 0)) != hash(state):
		return state.duplicate(true)
	var partner_id := str(resolved.get("partnerId", ""))
	if not partner_id.is_empty():
		var partner_before := unit_definition(state, partner_id)
		var action_before := command_definition(state, str(resolved.get("actionId", "")))
		if (
			partner_before.is_empty()
			or int(partner_before.get("hp", 0)) <= 0
			or str(action_before.get("partnerId", "")) != partner_id
			or int(partner_before.get("mp", 0)) < int(resolved.get("partnerMpCost", 0))
			or not duo_partner_unavailable_reason(
				state, str(resolved.get("actionId", ""))
			).is_empty()
		):
			return state.duplicate(true)
	var inventory_cost := resolved.get("inventoryCost", {}) as Dictionary
	if not inventory_cost.is_empty():
		var cost_item_id := str(inventory_cost.get("itemId", ""))
		var cost_count := maxi(1, int(inventory_cost.get("count", 1)))
		if int((state.get("inventory", {}) as Dictionary).get(cost_item_id, 0)) < cost_count:
			return state.duplicate(true)
	var result := state.duplicate(true)
	var units: Dictionary = result.get("units", {})
	for raw_id in resolved.get("damage", {}):
		var unit_id := str(raw_id)
		if not units.has(unit_id):
			continue
		var unit: Dictionary = units[unit_id]
		unit["hp"] = maxi(0, int(unit.get("hp", 0)) - int((resolved.get("damage", {}) as Dictionary)[unit_id]))
		units[unit_id] = unit
	for raw_id in resolved.get("removeStatuses", {}):
		var unit_id := str(raw_id)
		if not units.has(unit_id):
			continue
		var unit: Dictionary = units[unit_id]
		var statuses: Dictionary = unit.get("statuses", {}).duplicate(true)
		for raw_status in (resolved.get("removeStatuses", {}) as Dictionary)[unit_id]:
			statuses.erase(str(raw_status))
		unit["statuses"] = statuses
		units[unit_id] = unit
	for raw_id in resolved.get("setStatuses", {}):
		var unit_id := str(raw_id)
		if not units.has(unit_id):
			continue
		var unit: Dictionary = units[unit_id]
		var statuses: Dictionary = unit.get("statuses", {}).duplicate(true)
		for raw_status in (resolved.get("setStatuses", {}) as Dictionary)[unit_id]:
			statuses[str(raw_status)] = int(((resolved.get("setStatuses", {}) as Dictionary)[unit_id] as Dictionary)[raw_status])
		unit["statuses"] = statuses
		units[unit_id] = unit
	for raw_id in resolved.get("restoreHp", {}):
		var unit_id := str(raw_id)
		if units.has(unit_id):
			var unit: Dictionary = units[unit_id]
			unit["hp"] = clampi(
				int((resolved.get("restoreHp", {}) as Dictionary)[raw_id]),
				0,
				int(unit.get("maxHp", 1)),
			)
			units[unit_id] = unit
	for raw_id in resolved.get("restoreMp", {}):
		var unit_id := str(raw_id)
		if units.has(unit_id):
			var unit: Dictionary = units[unit_id]
			unit["mp"] = clampi(
				int((resolved.get("restoreMp", {}) as Dictionary)[raw_id]),
				0,
				int(unit.get("maxMp", 0)),
			)
			units[unit_id] = unit
	for raw_id in resolved.get("moves", {}):
		var unit_id := str(raw_id)
		if units.has(unit_id):
			var unit: Dictionary = units[unit_id]
			var destination: Variant = (resolved.get("moves", {}) as Dictionary)[unit_id]
			if destination is Vector2i:
				unit["cell"] = destination
			else:
				unit["zone"] = int(destination)
			units[unit_id] = unit
	var holds := (result.get("holds", {}) as Dictionary).duplicate(true)
	var released_target_id := ""
	var set_hold := resolved.get("setHold", {}) as Dictionary
	if not set_hold.is_empty():
		var carrier_id := str(set_hold.get("carrierId", ""))
		var held_id := str(set_hold.get("targetId", ""))
		if units.has(carrier_id) and units.has(held_id):
			holds[carrier_id] = held_id
			var held_unit: Dictionary = units[held_id]
			held_unit.erase("cell")
			units[held_id] = held_unit
	var release_hold := resolved.get("releaseHold", {}) as Dictionary
	if not release_hold.is_empty():
		released_target_id = str(release_hold.get("targetId", ""))
		holds.erase(str(release_hold.get("carrierId", "")))
	result = Terrain.apply_cell_changes(result, resolved.get("cellChanges", {}))
	if not inventory_cost.is_empty():
		var inventory := (result.get("inventory", {}) as Dictionary).duplicate(true)
		var cost_item_id := str(inventory_cost.get("itemId", ""))
		var next_count := int(inventory.get(cost_item_id, 0)) - maxi(
			1, int(inventory_cost.get("count", 1))
		)
		if next_count > 0:
			inventory[cost_item_id] = next_count
		else:
			inventory.erase(cost_item_id)
		result["inventory"] = inventory
	var actor_id := str(resolved.get("actorId", ""))
	if units.has(actor_id):
		var actor: Dictionary = units[actor_id]
		var action := command_definition(state, str(resolved.get("actionId", "")))
		actor["mp"] = maxi(0, int(actor.get("mp", 0)) - int(resolved.get("mpCost", 0)))
		actor["nextAt"] = float(actor.get("nextAt", 0.0)) + _delay_for(
			action, maxi(1, int(actor.get("speed", 10)))
		)
		actor["statuses"] = _decay_statuses(actor.get("statuses", {}))
		units[actor_id] = actor
	if not partner_id.is_empty() and units.has(partner_id):
		var partner: Dictionary = units[partner_id]
		partner["mp"] = maxi(
			0, int(partner.get("mp", 0)) - int(resolved.get("partnerMpCost", 0))
		)
		partner["nextAt"] = float(partner.get("nextAt", 0.0)) + _delay_for(
			{"delay": int(resolved.get("partnerDelay", 0))},
			maxi(1, int(partner.get("speed", 10))),
		)
		units[partner_id] = partner
	_normalize_held_timeline(units, holds)
	if not released_target_id.is_empty():
		var still_held_ids: Array[String] = []
		for raw_held_id in holds.values():
			still_held_ids.append(str(raw_held_id))
		_advance_unit_past_current(units, released_target_id, still_held_ids)
	for raw_carrier_id in holds.keys():
		var carrier_id := str(raw_carrier_id)
		if not units.has(carrier_id) or int((units[carrier_id] as Dictionary).get("hp", 0)) > 0:
			continue
		var held_id := str(holds.get(carrier_id, ""))
		var release_cell := _nearest_release_cell_for_units(result, units, carrier_id, held_id)
		if units.has(held_id) and release_cell != INVALID_CELL:
			var held_unit: Dictionary = units[held_id]
			held_unit["cell"] = release_cell
			units[held_id] = held_unit
		holds.erase(carrier_id)
	result["holds"] = holds
	result["units"] = units
	result["turn"] = int(result.get("turn", 1)) + 1
	var log: Array = result.get("log", []).duplicate()
	log.append(str(resolved.get("summary", "Действие выполнено.")))
	result["log"] = log
	return result


static func enemy_command(
	state: Dictionary,
	position_options: Array[Dictionary] = [],
) -> Dictionary:
	var actor_id := current_unit_id(state)
	var actor := unit_definition(state, actor_id)
	if str(actor.get("team", "")) != "enemy":
		return _invalid_preview("Сейчас ход не врага.")
	var profile_id := str(actor.get("aiProfileId", "")).strip_edges()
	var profile := AiProfileCatalog.definition(profile_id)
	if profile.is_empty():
		profile = {
			"id": "fallback", "targetPriority": "lowest_hp",
			"actionPriority": "unit_order", "preferReactions": false,
			"lowHpThresholdPercent": 0, "lowHpBehavior": "keep_fighting",
			"positioningBehavior": "move_to_action",
		}
	var low_hp_command := (
		{}
		if not held_target_id(state, actor_id).is_empty()
		else _ai_low_hp_command(state, actor, profile)
	)
	if bool(low_hp_command.get("ok", false)):
		low_hp_command["aiProfileId"] = profile_id
		return low_hp_command
	var positions: Array[Dictionary] = [{
		"state": state,
		"destination": actor.get("cell", Vector2i.ZERO),
		"movementCost": 0,
	}]
	if (
		str(profile.get("positioningBehavior", "move_to_action")) == "move_to_action"
		and not position_options.is_empty()
	):
		positions = position_options
	var candidates: Array[Dictionary] = []
	var actions: Array[String] = command_ids_for_current_actor(state, false)
	var origin: Vector2i = actor.get("cell", Vector2i.ZERO)
	for option in positions:
		var positioned_state: Dictionary = option.get("state", state)
		var positioned_actor := unit_definition(positioned_state, actor_id)
		var destination: Vector2i = option.get("destination", origin)
		var movement_cost := maxi(0, int(option.get("movementCost", 0)))
		for action_index in actions.size():
			var action_id := str(actions[action_index])
			var action := command_definition(positioned_state, action_id)
			if action.is_empty():
				continue
			if str(action.get("target", "")) == "cell":
				for target_cell in valid_target_cells(positioned_state, action_id):
					var resolved := preview(
						positioned_state, action_id, "", INVALID_CELL, target_cell
					)
					if not bool(resolved.get("ok", false)):
						continue
					if destination != origin:
						var path: Array[Vector2i] = []
						for raw_cell in option.get("movementPath", [origin, destination]):
							if raw_cell is Vector2i:
								path.append(raw_cell)
						_compose_movement_preview(
							resolved, actor_id, path, int(option.get("fallDamage", 0))
						)
						resolved["summary"] = "Перемещение: %s → %s\n%s" % [
							_cell_label(origin), _cell_label(destination),
							describe_preview(positioned_state, resolved),
						]
					var score := _ai_action_score(action, action_index, actions.size(), profile)
					var occupant := unit_definition(
						positioned_state, _grid_occupant(positioned_state, target_cell)
					)
					if not occupant.is_empty():
						score += _ai_target_score(
							positioned_state, positioned_actor, occupant, profile
						)
					score -= movement_cost * 10
					score -= int(option.get("fallDamage", 0)) * 1000
					candidates.append({
						"score": score,
						"key": "%04d|%s|cell:%d:%d|%d:%d" % [
							movement_cost, action_id, target_cell.x, target_cell.y,
							destination.x, destination.y,
						],
						"resolved": resolved,
					})
				continue
			for target_id in valid_target_ids(positioned_state, action_id):
				var target := unit_definition(positioned_state, target_id)
				if (
					str(action.get("effect", "")) == "lift_throw"
					and str(target.get("team", "")) == str(positioned_actor.get("team", ""))
				):
					continue
				var secondary_cells: Array[Vector2i] = [INVALID_CELL]
				if str(action.get("effect", "")) == "lift_throw":
					secondary_cells = valid_secondary_cells(positioned_state, action_id, target_id)
				for secondary_cell in secondary_cells:
					var resolved := preview(positioned_state, action_id, target_id, secondary_cell)
					if not bool(resolved.get("ok", false)):
						continue
					if destination != origin:
						var path: Array[Vector2i] = []
						for raw_cell in option.get("movementPath", [origin, destination]):
							if raw_cell is Vector2i:
								path.append(raw_cell)
						_compose_movement_preview(
							resolved, actor_id, path, int(option.get("fallDamage", 0))
						)
						resolved["summary"] = "Перемещение: %s → %s\n%s" % [
							_cell_label(origin), _cell_label(destination),
							describe_preview(positioned_state, resolved),
						]
					var score := _ai_action_score(action, action_index, actions.size(), profile)
					score += _ai_target_score(
						positioned_state, positioned_actor, target, profile,
					)
					score -= movement_cost * 10
					score -= int(option.get("fallDamage", 0)) * 1000
					if bool(profile.get("preferReactions", false)) and _has_reaction_setup(
						positioned_state, target, action
					):
						score += 1000000
					candidates.append({
						"score": score,
						"key": "%04d|%s|%s|%d:%d|%d:%d" % [
							movement_cost, action_id, target_id, destination.x, destination.y,
							secondary_cell.x, secondary_cell.y,
						],
						"resolved": resolved,
					})
	if candidates.is_empty():
		var pursuit := _ai_pursuit_preview(state, actor, profile, positions)
		if bool(pursuit.get("ok", false)):
			pursuit["aiProfileId"] = profile_id
			return pursuit
		return _invalid_preview("У врага нет доступного действия или клетки сближения.")
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.get("score", 0)) != int(right.get("score", 0)):
			return int(left.get("score", 0)) > int(right.get("score", 0))
		return str(left.get("key", "")) < str(right.get("key", ""))
	)
	var selected := (candidates[0].get("resolved", {}) as Dictionary).duplicate(true)
	selected["aiProfileId"] = profile_id
	return selected


static func _ai_pursuit_preview(
	state: Dictionary,
	actor: Dictionary,
	profile: Dictionary,
	positions: Array[Dictionary],
) -> Dictionary:
	if str(profile.get("positioningBehavior", "move_to_action")) != "move_to_action":
		return {}
	var actor_id := str(actor.get("id", ""))
	var origin: Vector2i = actor.get("cell", Vector2i.ZERO)
	var targets: Array[Dictionary] = []
	for raw_id in state.get("units", {}):
		var target_id := str(raw_id)
		var target := unit_definition(state, target_id)
		if (
			int(target.get("hp", 0)) <= 0
			or str(target.get("team", "")) == str(actor.get("team", ""))
			or not target.has("cell")
		):
			continue
		targets.append({
			"id": target_id,
			"score": _ai_target_score(state, actor, target, profile),
		})
	if targets.is_empty():
		return {}
	targets.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.get("score", 0)) != int(right.get("score", 0)):
			return int(left.get("score", 0)) > int(right.get("score", 0))
		return str(left.get("id", "")) < str(right.get("id", ""))
	)
	var target_id := str(targets[0].get("id", ""))
	var best_destination := origin
	var best_distance := _ai_distance(state, actor, unit_definition(state, target_id))
	var best_cost := 0
	var best_path: Array[Vector2i] = []
	var best_fall := 0
	var best_state := state
	for option in positions:
		var positioned_state: Dictionary = option.get("state", state)
		var destination: Vector2i = option.get("destination", origin)
		var movement_cost := maxi(0, int(option.get("movementCost", 0)))
		var distance := _ai_distance(
			positioned_state,
			unit_definition(positioned_state, actor_id),
			unit_definition(positioned_state, target_id),
		)
		if (
			distance < best_distance
			or (
				distance == best_distance
				and destination != origin
				and (best_destination == origin or movement_cost < best_cost)
			)
		):
			best_destination = destination
			best_distance = distance
			best_cost = movement_cost
			best_state = positioned_state
			best_path.clear()
			for raw_cell in option.get("movementPath", [origin, destination]):
				if raw_cell is Vector2i:
					best_path.append(raw_cell)
			best_fall = int(option.get("fallDamage", 0))
	if best_destination == origin:
		return {}
	var actor_name := str(actor.get("name", actor_id))
	var target_name := str(unit_definition(state, target_id).get("name", target_id))
	for raw_action_id in actor.get("actions", []):
		var defend_id := str(raw_action_id)
		if str(command_definition(best_state, defend_id).get("effect", "")) != "defend":
			continue
		if actor_id not in valid_target_ids(best_state, defend_id):
			continue
		var defended := preview(best_state, defend_id, actor_id)
		if not bool(defended.get("ok", false)):
			continue
		_compose_movement_preview(defended, actor_id, best_path, best_fall)
		defended["approachTargetId"] = target_id
		defended["approachDestination"] = best_destination
		defended["approachPath"] = best_path.duplicate()
		defended["approachWillExecute"] = false
		defended["approachFallbackDefend"] = true
		defended["summary"] = "%s приближается к %s: %s → %s. Затем применяет Защиту." % [
			actor_name, target_name, _cell_label(origin), _cell_label(best_destination),
		]
		if best_fall > 0:
			defended["summary"] += "\nПадение по пути наносит %d HP." % best_fall
		return defended
	var result := {
		"ok": true,
		"stateTurn": int(state.get("turn", 1)),
		"stateHash": hash(state),
		"actorId": actor_id,
		"actionId": "",
		"targetId": target_id,
		"mpCost": 0,
		"mpBefore": int(actor.get("mp", 0)),
		"mpAfter": int(actor.get("mp", 0)),
		"damage": {},
		"fixedDamage": {},
		"setStatuses": {},
		"removeStatuses": {},
		"moves": {},
		"movementPath": best_path,
		"cellChanges": {},
		"restoreHp": {},
		"restoreMp": {},
		"inventoryCost": {},
		"reaction": "Сближение",
		"notes": ["Ход завершается без атаки."],
		"movementOnly": true,
		"summary": "%s приближается к %s: %s → %s.\nХод завершается без атаки." % [
			actor_name, target_name, _cell_label(origin), _cell_label(best_destination),
		],
	}
	_compose_movement_preview(result, actor_id, best_path, best_fall)
	if best_fall > 0:
		result["summary"] += "\nПадение по пути наносит %d HP." % best_fall
	return result


static func _ai_low_hp_command(
	state: Dictionary,
	actor: Dictionary,
	profile: Dictionary,
) -> Dictionary:
	if str(profile.get("lowHpBehavior", "")) != "defend_if_available":
		return {}
	var max_hp := maxi(1, int(actor.get("maxHp", 1)))
	var hp_percent := int(round(100.0 * float(actor.get("hp", 0)) / float(max_hp)))
	if hp_percent > int(profile.get("lowHpThresholdPercent", 0)):
		return {}
	for raw_action_id in actor.get("actions", []):
		var action_id := str(raw_action_id)
		if str(action_definition(action_id).get("effect", "")) != "defend":
			continue
		var targets := valid_target_ids(state, action_id)
		if not targets.is_empty():
			return preview(state, action_id, targets[0])
	return {}


static func _ai_action_score(
	action: Dictionary,
	action_index: int,
	action_count: int,
	profile: Dictionary,
) -> int:
	match str(profile.get("actionPriority", "unit_order")):
		"highest_power":
			return int(action.get("power", 0)) * 10000 - int(action.get("delay", 100))
		"fastest":
			return (1000 - int(action.get("delay", 100))) * 100 + int(action.get("power", 0))
		_:
			return maxi(0, action_count - action_index) * 10000


static func _ai_target_score(
	state: Dictionary,
	actor: Dictionary,
	target: Dictionary,
	profile: Dictionary,
) -> int:
	var current_hp := int(target.get("hp", 0))
	var distance := _ai_distance(state, actor, target)
	match str(profile.get("targetPriority", "lowest_hp")):
		"highest_hp":
			return current_hp
		"nearest":
			return 1000 - distance
		"farthest":
			return distance
		_:
			return 10000 - current_hp


static func _ai_distance(state: Dictionary, actor: Dictionary, target: Dictionary) -> int:
	if state.has("grid") and actor.has("cell") and target.has("cell"):
		var actor_cell: Vector2i = actor.get("cell", Vector2i.ZERO)
		var target_cell: Vector2i = target.get("cell", Vector2i.ZERO)
		return absi(actor_cell.x - target_cell.x) + absi(actor_cell.y - target_cell.y)
	return absi(int(actor.get("zone", 0)) - int(target.get("zone", 0)))


static func outcome(state: Dictionary) -> String:
	var heroes_alive := false
	var enemies_alive := false
	for raw_id in state.get("units", {}):
		var unit := unit_definition(state, str(raw_id))
		if int(unit.get("hp", 0)) <= 0:
			continue
		if str(unit.get("team", "")) == "hero":
			heroes_alive = true
		else:
			enemies_alive = true
	if not enemies_alive:
		return "victory"
	if not heroes_alive:
		return "defeat"
	return "active"


static func describe_intent(
	state: Dictionary,
	action_id: String,
	target_id: String = "",
	destination: Vector2i = INVALID_CELL,
	pair_context_state: Dictionary = {},
	target_cell: Vector2i = INVALID_CELL,
) -> String:
	## Player-facing information before commit. The resolver still locks the full
	## result internally, but this copy deliberately never reveals hit/crit rolls
	## or damage. Learning the enemy remains part of the battle.
	var action := command_definition(state, action_id)
	if action.is_empty():
		return "Выберите действие."
	var actor := unit_definition(state, current_unit_id(state))
	var target := unit_definition(state, target_id)
	var parts: Array[String] = [str(action.get("name", action_id))]
	parts.append("%s · %s · цель: %s · дальность: %d" % [
		str(action.get("menuGroupLabel", "Действие")),
		_element_label(str(action.get("element", "physical"))),
		_target_label(str(action.get("target", "enemy"))),
		int(action.get("range", 0)),
	])
	var mp_cost := int(action.get("mpCost", 0))
	if mp_cost > 0:
		parts.append("MP: %d · доступно: %d" % [mp_cost, int(actor.get("mp", 0))])
	var partner_id := str(action.get("partnerId", ""))
	if not partner_id.is_empty():
		var pair_state := state if pair_context_state.is_empty() else pair_context_state
		var partner := unit_definition(pair_state, partner_id)
		var partner_context := duo_partner_context(pair_state, action_id)
		var distance_copy := (
			"%d/%d · В РАДИУСЕ" % [
				int(partner_context.get("distance", -1)),
				int(partner_context.get("range", 0)),
			]
			if bool(partner_context.get("inRange", false))
			else "%d/%d · ВНЕ РАДИУСА" % [
				int(partner_context.get("distance", -1)),
				int(partner_context.get("range", 0)),
			]
		)
		parts.append("Партнёр: %s · дистанция %s · MP: %d · доступно: %d" % [
			str(partner.get("name", partner_id)),
			distance_copy,
			int(action.get("partnerMpCost", 0)),
			int(partner.get("mp", 0)),
		])
	parts.append("Эффект: %s" % str(action.get("hint", "—")))
	parts.append("Условия: %s" % str(action.get("requirements", "—")))
	if not target.is_empty():
		parts.append("Выбранная цель: %s" % str(target.get("name", target_id)))
	elif target_cell != INVALID_CELL:
		parts.append("Выбранная клетка: %s" % _cell_label(target_cell))
	if destination != INVALID_CELL and actor.has("cell") and destination != actor.get("cell"):
		parts.append("Перемещение перед действием: %s" % _cell_label(destination))
	return "\n".join(parts)


static func describe_preview(state: Dictionary, resolved: Dictionary) -> String:
	if not bool(resolved.get("ok", false)):
		return str(resolved.get("error", "Недоступное действие."))
	var actor := unit_definition(state, str(resolved.get("actorId", "")))
	var target := unit_definition(state, str(resolved.get("targetId", "")))
	var action := command_definition(state, str(resolved.get("actionId", "")))
	var target_cell: Vector2i = resolved.get("targetCell", INVALID_CELL)
	var heading := (
		"%s → %s: %s" % [
			str(actor.get("name", "?")), _cell_label(target_cell), str(action.get("name", "?")),
		]
		if target.is_empty() and target_cell != INVALID_CELL
		else (
			"%s: %s" % [str(actor.get("name", "?")), str(action.get("name", "?"))]
			if str(resolved.get("actorId", "")) == str(resolved.get("targetId", ""))
			else "%s → %s: %s" % [
				str(actor.get("name", "?")),
				str(target.get("name", "?")),
				str(action.get("name", "?")),
			]
		)
	)
	var parts: Array[String] = [heading]
	if bool(resolved.get("hostile", false)):
		var hit_copy := "Попадание %d%% · бросок %d → %s" % [
			int(resolved.get("hitChance", 100)),
			int(resolved.get("hitRoll", 0)),
			"ПОПАДАНИЕ" if bool(resolved.get("hit", true)) else "ПРОМАХ",
		]
		if bool(resolved.get("critical", false)):
			hit_copy += " · КРИТ"
		elif int(resolved.get("critChance", 0)) > 0 and bool(resolved.get("hit", true)):
			hit_copy += " · крит %d%% (бросок %d)" % [
				int(resolved.get("critChance", 0)), int(resolved.get("critRoll", 0)),
			]
		parts.append(hit_copy)
	var mp_cost := int(resolved.get("mpCost", 0))
	if mp_cost > 0:
		parts.append("MP: %d → %d (−%d)" % [
			int(resolved.get("mpBefore", 0)), int(resolved.get("mpAfter", 0)), mp_cost,
		])
	var partner_id := str(resolved.get("partnerId", ""))
	if not partner_id.is_empty():
		parts.append("%s: MP %d → %d (−%d)" % [
			str(unit_definition(state, partner_id).get("name", partner_id)),
			int(resolved.get("partnerMpBefore", 0)),
			int(resolved.get("partnerMpAfter", 0)),
			int(resolved.get("partnerMpCost", 0)),
		])
	for raw_id in resolved.get("restoreHp", {}):
		var unit_id := str(raw_id)
		var before_hp := int(unit_definition(state, unit_id).get("hp", 0))
		var after_hp := int((resolved.get("restoreHp", {}) as Dictionary)[raw_id])
		parts.append("%s: HP %d → %d" % [
			str(unit_definition(state, unit_id).get("name", unit_id)), before_hp, after_hp,
		])
	for raw_id in resolved.get("restoreMp", {}):
		var unit_id := str(raw_id)
		var before_mp := int(unit_definition(state, unit_id).get("mp", 0))
		var after_mp := int((resolved.get("restoreMp", {}) as Dictionary)[raw_id])
		parts.append("%s: MP %d → %d" % [
			str(unit_definition(state, unit_id).get("name", unit_id)), before_mp, after_mp,
		])
	var reaction := str(resolved.get("reaction", ""))
	if not reaction.is_empty():
		parts.append("Реакция: %s" % reaction)
	var damage_parts: Array[String] = []
	for raw_id in resolved.get("damage", {}):
		var unit_id := str(raw_id)
		damage_parts.append("%s −%d HP" % [
			str(unit_definition(state, unit_id).get("name", unit_id)),
			int((resolved.get("damage", {}) as Dictionary)[unit_id]),
		])
	if not damage_parts.is_empty():
		parts.append(", ".join(damage_parts))
	for raw_id in resolved.get("setStatuses", {}):
		var unit_id := str(raw_id)
		var names: Array[String] = []
		for raw_status in (resolved.get("setStatuses", {}) as Dictionary)[unit_id]:
			names.append(status_name(str(raw_status)))
		parts.append("%s получает %s" % [
			str(unit_definition(state, unit_id).get("name", unit_id)),
			", ".join(names),
		])
	for raw_id in resolved.get("moves", {}):
		var unit_id := str(raw_id)
		var destination: Variant = (resolved.get("moves", {}) as Dictionary)[unit_id]
		var destination_name := (
			_cell_label(destination as Vector2i)
			if destination is Vector2i
			else zone_name(state, int(destination))
		)
		parts.append("%s перемещается: %s" % [
			str(unit_definition(state, unit_id).get("name", unit_id)),
			destination_name,
		])
	var changed_cells: Array[String] = []
	for raw_key in resolved.get("cellChanges", {}):
		var patch: Dictionary = (resolved.get("cellChanges", {}) as Dictionary).get(raw_key, {})
		var cell: Vector2i = patch.get("cell", Vector2i(-1, -1))
		if cell.x < 0:
			continue
		var changes: Array[String] = []
		var tags: Array = patch.get("tags", [])
		if "activated" in tags:
			changes.append("узел активирован")
		elif "frozen" in tags:
			changes.append("Frozen")
		elif "wet" in tags:
			changes.append("Wet")
		if patch.has("elevation"):
			changes.append("высота h%d" % int(patch.get("elevation", 0)))
		if patch.has("blocked"):
			changes.append("преграда" if bool(patch.get("blocked", false)) else "проход открыт")
		changed_cells.append("%s → %s" % [
			_cell_label(cell), ", ".join(changes) if not changes.is_empty() else "изменено",
		])
	if not changed_cells.is_empty():
		parts.append("Поле: %s" % "; ".join(changed_cells))
	for note in resolved.get("notes", []):
		parts.append(str(note))
	return "\n".join(parts)


static func status_name(status_id: String) -> String:
	return StatusRules.display_name(status_id)


static func status_definition(status_id: String) -> Dictionary:
	return StatusRules.definition(status_id)


static func _element_label(element_id: String) -> String:
	return str({
		"physical": "Физический",
		"water": "Вода",
		"cold": "Холод",
		"lightning": "Молния",
		"fire": "Огонь",
		"air": "Воздух",
		"support": "Поддержка",
		"duo": "Парное",
		"earth": "Земля",
	}.get(element_id, element_id))


static func _target_label(target_id: String) -> String:
	return str({
		"enemy": "враг",
		"ally": "союзник",
		"self": "на себя",
		"unit": "любой боец",
		"cell": "клетка",
	}.get(target_id, target_id))


static func zone_name(state: Dictionary, zone_index: int) -> String:
	var zones: Array = state.get("zones", [])
	if zone_index < 0 or zone_index >= zones.size():
		return "?"
	return str((zones[zone_index] as Dictionary).get("name", "?"))


static func _delay_for(action: Dictionary, speed: int) -> float:
	return float(action.get("delay", 100)) * 10.0 / float(maxi(1, speed))


static func _earliest_id(times: Dictionary) -> String:
	var best_id := ""
	var best_at := INF
	for raw_id in times:
		var unit_id := str(raw_id)
		var at := float(times[raw_id])
		if at < best_at or (is_equal_approx(at, best_at) and unit_id < best_id):
			best_id = unit_id
			best_at = at
	return best_id


static func _has_status(unit: Dictionary, status_id: String) -> bool:
	return StatusRules.has(unit, status_id)


static func _zone_has_tag(state: Dictionary, zone_index: int, tag: String) -> bool:
	var zones: Array = state.get("zones", [])
	if zone_index < 0 or zone_index >= zones.size():
		return false
	return tag in (zones[zone_index] as Dictionary).get("tags", [])


static func _is_wet(state: Dictionary, unit: Dictionary) -> bool:
	if _has_status(unit, "wet"):
		return true
	if state.has("grid") and unit.has("cell"):
		return "wet" in _grid_cell_definition(state, unit.get("cell", Vector2i(-1, -1))).get("tags", [])
	return _zone_has_tag(state, int(unit.get("zone", -1)), "wet")


static func _is_frozen(state: Dictionary, unit: Dictionary) -> bool:
	if _has_status(unit, "frozen"):
		return true
	if state.has("grid") and unit.has("cell"):
		return "frozen" in _grid_cell_definition(state, unit.get("cell", Vector2i(-1, -1))).get("tags", [])
	return false


static func _has_elemental_setup(state: Dictionary, unit: Dictionary) -> bool:
	return (
		_is_wet(state, unit)
		or _has_status(unit, "frozen")
		or _has_status(unit, "burning")
	)


static func _has_reaction_setup(
	state: Dictionary,
	target: Dictionary,
	action: Dictionary,
) -> bool:
	match str(action.get("effect", "")):
		"douse":
			return _has_status(target, "burning")
		"chill", "spark":
			return _is_wet(state, target)
		"kindle":
			return _is_wet(state, target) or _has_status(target, "frozen")
		"duo_pulse":
			return _is_wet(state, target)
		"steam_breach":
			return _is_frozen(state, target)
	return false


static func _hit_chance(actor: Dictionary, target: Dictionary, action: Dictionary) -> int:
	return DamageRules.hit_chance(actor, target, action)


static func _critical_chance(actor: Dictionary, action: Dictionary) -> int:
	return DamageRules.critical_chance(actor, action)


static func _locked_roll(
	state: Dictionary,
	actor: Dictionary,
	action: Dictionary,
	target: Dictionary,
	secondary_cell: Vector2i,
	channel: String,
) -> int:
	return DamageRules.locked_roll(state, actor, action, target, secondary_cell, channel)


static func _finalize_action_damage(
	state: Dictionary,
	resolved: Dictionary,
	actor: Dictionary,
	action: Dictionary,
) -> void:
	var damage: Dictionary = resolved.get("damage", {})
	var fixed_damage: Dictionary = resolved.get("fixedDamage", {})
	for raw_id in damage.keys():
		var unit_id := str(raw_id)
		var fixed_amount := maxi(0, int(fixed_damage.get(unit_id, 0)))
		var action_power := maxi(0, int(damage.get(unit_id, 0)) - fixed_amount)
		var scaled := 0
		if action_power > 0:
			scaled = _scaled_action_damage(
				actor,
				unit_definition(state, unit_id),
				action,
				action_power,
				bool(resolved.get("critical", false)),
			)
		damage[unit_id] = scaled + fixed_amount
	resolved["damage"] = damage


static func _scaled_action_damage(
	actor: Dictionary,
	target: Dictionary,
	action: Dictionary,
	raw_power: int,
	critical: bool,
) -> int:
	return DamageRules.scaled_action_damage(actor, target, action, raw_power, critical)


static func _set_damage(resolved: Dictionary, unit_id: String, amount: int) -> void:
	DamageRules.set_damage(resolved, unit_id, amount)


static func _add_damage(resolved: Dictionary, unit_id: String, amount: int) -> void:
	DamageRules.add_damage(resolved, unit_id, amount)


static func _add_fixed_damage(resolved: Dictionary, unit_id: String, amount: int) -> void:
	DamageRules.add_fixed_damage(resolved, unit_id, amount)


static func _set_status(resolved: Dictionary, unit_id: String, status_id: String, duration: int) -> void:
	StatusRules.set_status(resolved, unit_id, status_id, duration)


static func _set_hostile_status(
	resolved: Dictionary,
	target: Dictionary,
	status_id: String,
	duration: int,
) -> bool:
	return StatusRules.set_hostile_status(resolved, target, status_id, duration)


static func _remove_status(resolved: Dictionary, unit_id: String, status_id: String) -> void:
	StatusRules.remove_status(resolved, unit_id, status_id)


static func _set_push(
	state: Dictionary,
	resolved: Dictionary,
	actor: Dictionary,
	target: Dictionary,
	force: int,
) -> void:
	EffectRules.set_push(state, resolved, actor, target, force)


static func _shares_conduction_area(
	state: Dictionary,
	first: Dictionary,
	second: Dictionary,
) -> bool:
	return EffectRules.shares_conduction_area(state, first, second)


static func _field_power_bonus(state: Dictionary, actor: Dictionary, element: String) -> int:
	return EffectRules.field_power_bonus(state, actor, element)


static func _grid_cell_definition(state: Dictionary, cell: Vector2i) -> Dictionary:
	return Terrain.cell_definition(state, cell)


static func _grid_cell_has_tag(state: Dictionary, cell: Vector2i, tag: String) -> bool:
	return tag in _grid_cell_definition(state, cell).get("tags", [])


static func _change_linked_surface(
	state: Dictionary,
	resolved: Dictionary,
	origin: Vector2i,
	add_tags: Array[String],
	remove_tags: Array[String],
) -> void:
	EffectRules.change_linked_surface(state, resolved, origin, add_tags, remove_tags)


static func linked_surface_cells(state: Dictionary, origin: Vector2i) -> Array[Vector2i]:
	return EffectRules.linked_surface_cells(state, origin)


static func _set_cell_tags(
	state: Dictionary,
	resolved: Dictionary,
	cell: Vector2i,
	add_tags: Array[String],
	remove_tags: Array[String],
) -> void:
	EffectRules.set_cell_tags(state, resolved, cell, add_tags, remove_tags)


static func _effect_steps_apply_to_cell(
	state: Dictionary,
	action: Dictionary,
	cell: Vector2i,
) -> bool:
	return EffectRules.effect_steps_apply_to_cell(state, action, cell)


static func _apply_authored_effects(
	state: Dictionary,
	resolved: Dictionary,
	actor: Dictionary,
	target: Dictionary,
	action: Dictionary,
	target_cell: Vector2i,
) -> void:
	EffectRules.apply_authored_effects(state, resolved, actor, target, action, target_cell)


static func _authored_effects_allow_unit_target(action: Dictionary, target: Dictionary) -> bool:
	return EffectRules.authored_effects_allow_unit_target(action, target)


static func _is_grid_focus_cell(state: Dictionary, cell: Vector2i) -> bool:
	return ((state.get("grid", {}) as Dictionary).get("focus", {}) as Dictionary).get(
		"cell", INVALID_CELL
	) == cell


static func _grid_inside(state: Dictionary, cell: Vector2i) -> bool:
	var grid: Dictionary = state.get("grid", {})
	return (
		cell.x >= 0 and cell.y >= 0
		and cell.x < int(grid.get("width", 0))
		and cell.y < int(grid.get("height", 0))
	)


static func _grid_occupant(state: Dictionary, cell: Vector2i) -> String:
	for raw_id in state.get("units", {}):
		var unit := unit_definition(state, str(raw_id))
		if int(unit.get("hp", 0)) > 0 and unit.get("cell", Vector2i(-1, -1)) == cell:
			return str(raw_id)
	return ""


static func _secondary_cell_available(
	state: Dictionary,
	action: Dictionary,
	target: Dictionary,
	cell: Vector2i,
) -> bool:
	if not _grid_inside(state, cell) or not target.has("cell"):
		return false
	var origin: Vector2i = target.get("cell", INVALID_CELL)
	if (
		cell == origin
		or Terrain.action_distance(state, origin, cell) > maxi(0, int(action.get("throwRange", 0)))
		or bool(_grid_cell_definition(state, cell).get("blocked", true))
		or not _grid_occupant(state, cell).is_empty()
	):
		return false
	var focus: Dictionary = (state.get("grid", {}) as Dictionary).get("focus", {})
	return focus.get("cell", INVALID_CELL) != cell


static func _cell_label(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), cell.y + 1]


static func _compose_movement_preview(
	resolved: Dictionary,
	actor_id: String,
	path: Array[Vector2i],
	fall_damage: int,
) -> void:
	if path.is_empty():
		return
	var moves: Dictionary = resolved.get("moves", {})
	moves[actor_id] = path[-1]
	resolved["moves"] = moves
	resolved["movementPath"] = path.duplicate()
	if fall_damage > 0:
		_add_fixed_damage(resolved, actor_id, fall_damage)
		resolved["fallDamage"] = int(resolved.get("fallDamage", 0)) + fall_damage
		(resolved.get("notes", []) as Array).append(
			"Падение по пути наносит %d HP." % fall_damage
		)


static func _apply_guard_preview(state: Dictionary, resolved: Dictionary) -> void:
	var damage: Dictionary = resolved.get("damage", {})
	for raw_id in damage.keys():
		var unit_id := str(raw_id)
		var unit := unit_definition(state, unit_id)
		if not _has_status(unit, "guard"):
			continue
		damage[unit_id] = ceili(float(damage[unit_id]) * 0.5)
		_remove_status(resolved, unit_id, "guard")
		(resolved.get("notes", []) as Array).append("Защита уменьшает входящий урон.")
	resolved["damage"] = damage


static func _decay_statuses(raw: Variant) -> Dictionary:
	return StatusRules.decay(raw)


## Geometric intent only: never read resolved damage, hit, crit or cell deltas.
static func target_unavailable_reason(state: Dictionary, action_id: String, cell: Vector2i, target_id: String) -> String:
	var actor_id := current_unit_id(state)
	var actor := unit_definition(state, actor_id)
	var action := command_definition(state, action_id)
	if int(actor.get("mp", 0)) < int(action.get("mpCost", 0)):
		return "Недостаточно MP."
	if not held_target_id(state, actor_id).is_empty():
		return "Носитель может только бросить, опустить или удерживать и защищаться."
	var partner_reason := duo_partner_unavailable_reason(state, action_id)
	if not partner_reason.is_empty():
		return partner_reason
	if str(action.get("target", "")) == "cell":
		return "Содержимое, препятствие или теги клетки не подходят этому действию."
	if target_id.is_empty():
		return "На клетке нет подходящего бойца."
	var target := unit_definition(state, target_id)
	if is_held(state, target_id):
		return "Поднятую цель нельзя выбирать."
	if str(action.get("effect", "")) == "lift_throw" and int(target.get("weightClass", 1)) > int(action.get("maxLiftWeight", 0)):
		return "Цель слишком тяжёлая для подъёма."
	if str(action.get("target", "")) == "enemy" and str(actor.get("team", "")) == str(target.get("team", "")):
		return "Действие применяется к врагу."
	if str(action.get("target", "")) == "ally" and str(actor.get("team", "")) != str(target.get("team", "")):
		return "Действие применяется к союзнику."
	return "Состояние цели или условия действия не позволяют применить его."


static func action_footprint(state: Dictionary, action_id: String, center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _grid_inside(state, center):
		return result
	result.append(center)
	var action := command_definition(state, action_id)
	var preset := str(action.get("effect", ""))
	var tags: Array = _grid_cell_definition(state, center).get("tags", [])
	if (preset == "chill" and "wet" in tags) or (preset in ["kindle", "steam_breach"] and "frozen" in tags):
		result = linked_surface_cells(state, center)
	if preset in ["spark", "duo_pulse"]:
		var target := unit_definition(state, _grid_occupant(state, center))
		var actor := unit_definition(state, current_unit_id(state))
		if not target.is_empty() and _is_wet(state, target):
			for raw_id in state.get("units", {}):
				var unit := unit_definition(state, str(raw_id))
				if is_held(state, str(raw_id)) or int(unit.get("hp", 0)) <= 0 or str(unit.get("team", "")) == str(actor.get("team", "")):
					continue
				if _shares_conduction_area(state, target, unit) and _is_wet(state, unit) and unit.has("cell") and unit["cell"] not in result:
					result.append(unit["cell"])
	for raw_effect in action.get("effects", []):
		var effect := raw_effect as Dictionary
		if str(effect.get("operation", "")) != "spread":
			continue
		var grid: Dictionary = state.get("grid", {})
		for y in int(grid.get("height", 0)):
			for x in int(grid.get("width", 0)):
				var cell := Vector2i(x, y)
				if cell not in result and Terrain.action_distance(state, center, cell) <= maxi(1, int(effect.get("spreadRadius", 1))):
					result.append(cell)
	return result


static func action_moves_actor(action: Dictionary) -> bool:
	for raw_effect in action.get("effects", []):
		if str((raw_effect as Dictionary).get("operation", "")) == "move_actor":
			return true
	return false


static func _held_throw_range(state: Dictionary, carrier_id: String) -> int:
	return maxi(1, int(_held_lift_action(state, carrier_id).get("throwRange", 1)))


static func _held_lift_action(state: Dictionary, carrier_id: String) -> Dictionary:
	var carrier := unit_definition(state, carrier_id)
	for raw_action_id in carrier.get("actions", []):
		var action := action_definition(str(raw_action_id))
		if str(action.get("effect", "")) == "lift_throw":
			return action
	return {}


static func _release_cell_available(state: Dictionary, carrier_id: String, cell: Vector2i) -> bool:
	if (
		not _grid_inside(state, cell)
		or bool(_grid_cell_definition(state, cell).get("blocked", true))
		or _is_grid_focus_cell(state, cell)
	):
		return false
	var held_id := held_target_id(state, carrier_id)
	for raw_id in state.get("units", {}):
		var unit_id := str(raw_id)
		if unit_id == held_id:
			continue
		var unit := unit_definition(state, unit_id)
		if int(unit.get("hp", 0)) > 0 and unit.get("cell", INVALID_CELL) == cell:
			return false
	return true


static func _nearest_release_cell(state: Dictionary, carrier_id: String) -> Vector2i:
	return _nearest_release_cell_for_units(
		state, state.get("units", {}) as Dictionary, carrier_id, held_target_id(state, carrier_id)
	)


static func _nearest_release_cell_for_units(
	state: Dictionary,
	units: Dictionary,
	carrier_id: String,
	held_id: String,
) -> Vector2i:
	if not units.has(carrier_id):
		return INVALID_CELL
	var origin: Vector2i = (units[carrier_id] as Dictionary).get("cell", INVALID_CELL)
	if origin == INVALID_CELL:
		return INVALID_CELL
	var grid := state.get("grid", {}) as Dictionary
	var candidates: Array[Vector2i] = []
	for y in int(grid.get("height", 0)):
		for x in int(grid.get("width", 0)):
			var cell := Vector2i(x, y)
			if bool(_grid_cell_definition(state, cell).get("blocked", true)) or _is_grid_focus_cell(state, cell):
				continue
			var occupied := false
			for raw_id in units:
				var unit_id := str(raw_id)
				if unit_id in [carrier_id, held_id]:
					continue
				var unit := units[unit_id] as Dictionary
				if int(unit.get("hp", 0)) > 0 and unit.get("cell", INVALID_CELL) == cell:
					occupied = true
					break
			var carrier_dead := int((units[carrier_id] as Dictionary).get("hp", 0)) <= 0
			if not occupied and (cell != origin or carrier_dead):
				candidates.append(cell)
	candidates.sort_custom(func(left: Vector2i, right: Vector2i) -> bool:
		var left_distance := absi(left.x - origin.x) + absi(left.y - origin.y)
		var right_distance := absi(right.x - origin.x) + absi(right.y - origin.y)
		return left_distance < right_distance or (
			left_distance == right_distance and _cell_label(left) < _cell_label(right)
		)
	)
	return candidates[0] if not candidates.is_empty() else INVALID_CELL


static func _strip_held_effects(state: Dictionary, resolved: Dictionary) -> void:
	for key in ["damage", "fixedDamage", "setStatuses", "removeStatuses", "restoreHp", "restoreMp", "moves"]:
		var values := resolved.get(key, {}) as Dictionary
		for raw_id in values.keys():
			if is_held(state, str(raw_id)):
				values.erase(raw_id)
		resolved[key] = values


static func _normalize_held_timeline(units: Dictionary, holds: Dictionary) -> void:
	var held_ids: Array[String] = []
	for raw_held_id in holds.values():
		held_ids.append(str(raw_held_id))
	for raw_carrier_id in holds:
		_advance_unit_past_current(units, str(holds[raw_carrier_id]), held_ids)


static func _advance_unit_past_current(
	units: Dictionary,
	unit_id: String,
	ignored_ids: Array[String] = [],
) -> void:
	if not units.has(unit_id):
		return
	var current_at := INF
	for raw_id in units:
		var other_id := str(raw_id)
		if other_id == unit_id or other_id in ignored_ids:
			continue
		var other := units[other_id] as Dictionary
		if int(other.get("hp", 0)) > 0:
			current_at = minf(current_at, float(other.get("nextAt", 0.0)))
	if is_inf(current_at):
		return
	var unit := units[unit_id] as Dictionary
	var delay := _delay_for({"delay": 100}, maxi(1, int(unit.get("speed", 10))))
	while float(unit.get("nextAt", 0.0)) <= current_at:
		unit["nextAt"] = float(unit.get("nextAt", 0.0)) + delay
	units[unit_id] = unit


static func _invalid_preview(message: String) -> Dictionary:
	return {"ok": false, "error": message, "summary": message}
