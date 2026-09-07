class_name EmberCombatResult
extends RefCounted
## Pure projection of an authored encounter outcome. It previews the existing
## outcome action and emits numeric progress deltas; it never grants rewards.

const ActionScript := preload("res://scripts/ember_action_script.gd")
const EncounterCatalog := preload("res://scripts/prototypes/ember_encounter_catalog.gd")
const UnitCatalog := preload("res://scripts/prototypes/ember_combat_unit_catalog.gd")
const PartyState := preload("res://scripts/ember_party_state.gd")


static func build(
	encounter: EmberEncounterResource,
	state: Dictionary,
	outcome: String,
) -> Dictionary:
	if encounter == null or outcome not in ["victory", "defeat"]:
		return {}
	var defeated_ids: Array[String] = []
	var defeated_tags := {}
	if outcome == "victory":
		var units: Dictionary = state.get("units", {})
		for raw_id in encounter.enemy_unit_ids:
			var unit_id := str(raw_id)
			var unit: Dictionary = units.get(unit_id, {})
			if unit.is_empty() or int(unit.get("hp", 0)) > 0:
				continue
			defeated_ids.append(unit_id)
			for raw_tag in unit.get("combatTags", []):
				var tag := str(raw_tag).strip_edges().to_lower()
				if not tag.is_empty():
					defeated_tags[tag] = int(defeated_tags.get(tag, 0)) + 1
	var counters := {}
	if outcome == "victory":
		counters["combat_victories"] = 1
		counters[encounter_victory_counter(encounter.encounter_id)] = 1
		counters["combat_defeated_total"] = defeated_ids.size()
		for tag in defeated_tags:
			counters[tag_counter(str(tag))] = int(defeated_tags[tag])
	var fixed_rewards := reward_preview(encounter.action_for_outcome(outcome))
	var loot_rewards: Array[Dictionary] = []
	if outcome == "victory":
		loot_rewards = loot_preview(encounter, state, defeated_ids)
	var xp_reward := encounter.victory_xp if outcome == "victory" else 0
	var progression := PartyState.combat_progression_preview(
		state,
		xp_reward,
		outcome == "victory",
		EmberInteractionContent.item_definitions(),
	)
	return {
		"encounterId": encounter.encounter_id,
		"outcome": outcome,
		"defeatedEnemyIds": defeated_ids,
		"defeatedTags": defeated_tags,
		"counterDeltas": counters,
		"fixedRewards": fixed_rewards,
		"lootRewards": loot_rewards,
		"lootSteps": reward_steps(loot_rewards),
		"rewards": merge_rewards(fixed_rewards, loot_rewards),
		"xpReward": xp_reward,
		"xpRows": progression.get("rows", []),
	}


static func reward_preview(action_id: String) -> Array[Dictionary]:
	var rewards: Array[Dictionary] = []
	if action_id.strip_edges().is_empty():
		return rewards
	var queue := ActionScript.queue_for(action_id)
	if not bool(queue.get("ok", false)):
		return rewards
	var totals := {}
	for raw_step in queue.get("steps", []):
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		if str(step.get("type", "")) != "give_item":
			continue
		var item_id := str(step.get("itemId", "")).strip_edges()
		if not item_id.is_empty():
			totals[item_id] = int(totals.get(item_id, 0)) + maxi(1, int(step.get("count", 1)))
	var items := EmberInteractionContent.item_definitions()
	for raw_id in totals:
		var item_id := str(raw_id)
		var item: Dictionary = items.get(item_id, {})
		rewards.append({
			"itemId": item_id,
			"nameRu": str(item.get("nameRu", item.get("name", item_id))),
			"count": int(totals[item_id]),
		})
	return rewards


static func loot_preview(
	encounter: EmberEncounterResource,
	state: Dictionary,
	defeated_ids: Array[String],
) -> Array[Dictionary]:
	var rolled: Array[Dictionary] = []
	for index in defeated_ids.size():
		var unit_id := defeated_ids[index]
		var unit := UnitCatalog.resource(unit_id)
		if unit == null or unit.loot_table == null:
			continue
		var context_key := "%s|turn:%d|enemy:%s|slot:%d" % [
			encounter.encounter_id,
			int(state.get("turn", 0)),
			unit_id,
			index,
		]
		rolled.append_array(unit.loot_table.roll(context_key))
	return merge_rewards([], rolled)


static func merge_rewards(left: Array, right: Array) -> Array[Dictionary]:
	var totals := {}
	var names := {}
	var order: Array[String] = []
	for source in [left, right]:
		for raw_reward in source:
			if typeof(raw_reward) != TYPE_DICTIONARY:
				continue
			var reward: Dictionary = raw_reward
			var item_id := str(reward.get("itemId", "")).strip_edges()
			if item_id.is_empty():
				continue
			if not totals.has(item_id):
				order.append(item_id)
			totals[item_id] = int(totals.get(item_id, 0)) + maxi(1, int(reward.get("count", 1)))
			names[item_id] = str(reward.get("nameRu", item_id))
	var result: Array[Dictionary] = []
	for item_id in order:
		result.append({"itemId": item_id, "nameRu": names[item_id], "count": totals[item_id]})
	return result


static func reward_steps(rewards: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_reward in rewards:
		if typeof(raw_reward) != TYPE_DICTIONARY:
			continue
		var reward: Dictionary = raw_reward
		var item_id := str(reward.get("itemId", "")).strip_edges()
		if not item_id.is_empty():
			result.append({
				"type": "give_item",
				"itemId": item_id,
				"count": maxi(1, int(reward.get("count", 1))),
			})
	return result


static func encounter_victory_counter(encounter_id: String) -> String:
	return "combat_encounter_%s_victories" % encounter_id.strip_edges().to_lower()


static func tag_counter(tag: String) -> String:
	return "combat_defeated_tag_%s" % tag.strip_edges().to_lower()


static func counter_options() -> Array[Dictionary]:
	## One signed library for Inspector/Graph authoring. Tags will move to the
	## actor catalog with the roster; today the prototype roster owns them.
	var result: Array[Dictionary] = [
		{"id": "combat_victories", "label": "Победы в любых боях"},
		{"id": "combat_defeated_total", "label": "Побеждённые враги · любые"},
	]
	for encounter_id in EncounterCatalog.ids():
		var encounter := EncounterCatalog.definition(encounter_id)
		result.append({
			"id": encounter_victory_counter(encounter_id),
			"label": "Победы · %s" % (encounter.display_name if encounter != null else encounter_id),
		})
	var known_tags := {}
	for raw_unit in EmberCombatPrototype.initial_state().get("units", {}).values():
		if typeof(raw_unit) != TYPE_DICTIONARY:
			continue
		for raw_tag in (raw_unit as Dictionary).get("combatTags", []):
			known_tags[str(raw_tag)] = true
	var tags: Array = known_tags.keys()
	tags.sort()
	for raw_tag in tags:
		var tag := str(raw_tag)
		result.append({"id": tag_counter(tag), "label": "Побеждённые · тег %s" % tag})
	return result
