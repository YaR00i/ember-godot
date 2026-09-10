extends SceneTree
## Stage 3 progression gate: one equal XP grant, deterministic level-ups and
## preservation of combat damage through the existing persistent party owner.

const ENCOUNTER := preload("res://content/combat/encounters/colored_crossing_demo.tres")
const PartyState := preload("res://scripts/ember_party_state.gd")


func _init() -> void:
	var errors: Array[String] = []
	var items := EmberInteractionContent.item_definitions()
	var party := PartyState.new_game(items)
	for count in range(1, 5):
		var active: Array[String] = []
		active.assign(["mira", "orik", "sena", "protagonist"].slice(0, count))
		var partial := ENCOUNTER.initial_state(party, 73, active)
		partial["units"]["mira"]["hp"] = 0
		partial["units"]["mira"]["mp"] = 1
		var projected := PartyState.combat_progression_preview(partial, 35, true, items)
		var committed := PartyState.apply_combat_result(party, partial, items, 35, true)
		if projected["rows"].size() != count or projected["party"].size() != count:
			errors.append("active %d preview invented absent heroes" % count)
		for hero_id in PartyState.HERO_IDS:
			if hero_id in active:
				if committed[hero_id] != projected["party"].get(hero_id):
					errors.append("active %d preview/commit disagree for %s" % [count, hero_id])
			elif committed[hero_id] != party[hero_id]:
				errors.append("inactive %s received HP/MP/XP/equipment changes" % hero_id)
	var mira: Dictionary = party.get("mira", {})
	var mira_before := PartyState.derived_stats("mira", mira, items)
	mira["hp"] = int(mira_before.get("maxHp", 1)) - 5
	mira["mp"] = int(mira_before.get("maxMp", 0)) - 3
	party["mira"] = mira
	var orik: Dictionary = party.get("orik", {})
	orik["hp"] = 0
	party["orik"] = orik

	var battle := ENCOUNTER.initial_state(PartyState.battle_snapshot(party, items))
	var preview := PartyState.combat_progression_preview(battle, 35, true, items)
	var result := PartyState.apply_combat_result(party, battle, items, 35, true)
	var rows: Array = preview.get("rows", [])
	if rows.size() != PartyState.HERO_IDS.size():
		errors.append("progression preview did not include the full fixed party")
	for hero_id in PartyState.HERO_IDS:
		var member: Dictionary = result.get(hero_id, {})
		if int(member.get("level", 0)) != 2 or int(member.get("xp", -1)) != 5:
			errors.append("%s did not receive the same 35 XP and level-up" % hero_id)
		var row := _row_for(rows, hero_id)
		if row.is_empty() or int(row.get("levelAfter", 0)) != 2 or int(row.get("xpAfter", -1)) != 5:
			errors.append("%s result preview disagrees with committed progression" % hero_id)
		elif int(row.get("hpAfter", -1)) != int(member.get("hp", -2)):
			errors.append("%s preview and commit disagree about post-battle HP" % hero_id)

	var progressed_mira: Dictionary = result.get("mira", {})
	var mira_after := PartyState.derived_stats("mira", progressed_mira, items)
	if int(progressed_mira.get("hp", -1)) != int(mira_after.get("maxHp", 1)) - 5:
		errors.append("living hero was fully healed instead of preserving the HP deficit")
	if int(progressed_mira.get("mp", -1)) != int(mira_after.get("maxMp", 0)) - 3:
		errors.append("level-up did not preserve the persistent MP deficit")
	if int((result.get("orik", {}) as Dictionary).get("hp", -1)) != 1:
		errors.append("fallen hero did not return from victory at exactly 1 HP")

	var boundary_party := PartyState.new_game(items)
	for hero_id in PartyState.HERO_IDS:
		var member: Dictionary = boundary_party.get(hero_id, {})
		member["xp"] = 29
		boundary_party[hero_id] = member
	var boundary := PartyState.grant_equal_xp(boundary_party, 1, items)
	for hero_id in PartyState.HERO_IDS:
		var member: Dictionary = (boundary.get("party", {}) as Dictionary).get(hero_id, {})
		if int(member.get("level", 0)) != 2 or int(member.get("xp", -1)) != 0:
			errors.append("XP threshold is not deterministic for %s" % hero_id)

	var no_reward := PartyState.apply_combat_result(party, battle, items, 0, false)
	if int((no_reward.get("orik", {}) as Dictionary).get("hp", -1)) != 0:
		errors.append("defeat path revived a fallen hero")
	for hero_id in PartyState.HERO_IDS:
		var member: Dictionary = no_reward.get(hero_id, {})
		if int(member.get("level", 0)) != 1 or int(member.get("xp", -1)) != 0:
			errors.append("no-reward result changed progression for %s" % hero_id)

	if not errors.is_empty():
		printerr("FAIL party progression")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS party progression")
	print("  all four heroes receive equal XP, including fallen heroes")
	print("  level-up preserves HP/MP deficits; victory revives fallen heroes at 1 HP")
	print("  preview and commit share one deterministic progression rule")
	quit(0)


func _row_for(rows: Array, hero_id: String) -> Dictionary:
	for raw_row in rows:
		var row: Dictionary = raw_row
		if str(row.get("heroId", "")) == hero_id:
			return row
	return {}
