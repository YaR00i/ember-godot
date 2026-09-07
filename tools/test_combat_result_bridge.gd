extends SceneTree
## Pure result/reward/event proof for the authored colored-crossing encounter.

const Catalog := preload("res://scripts/prototypes/ember_encounter_catalog.gd")
const Result := preload("res://scripts/prototypes/ember_combat_result.gd")


func _init() -> void:
	var errors: Array[String] = []
	var encounter := Catalog.definition("colored_crossing_demo")
	var state := encounter.initial_state() if encounter != null else {}
	for raw_id in state.get("units", {}):
		var unit: Dictionary = (state.get("units", {}) as Dictionary)[raw_id]
		if str(unit.get("team", "")) == "enemy":
			unit["hp"] = 0
		elif str(raw_id) == "orik":
			unit["hp"] = 0
		(state.get("units", {}) as Dictionary)[raw_id] = unit
	var report := Result.build(encounter, state, "victory")
	if (report.get("defeatedEnemyIds", []) as Array).size() != 3:
		errors.append("result did not count defeated encounter enemies")
	if int((report.get("defeatedTags", {}) as Dictionary).get("swamp", 0)) != 3:
		errors.append("result did not aggregate stable enemy tags")
	var rewards: Array = report.get("rewards", [])
	var reward_totals := _reward_totals(rewards)
	if int(reward_totals.get("coin", 0)) < 7:
		errors.append("result preview lost fixed coins or enemy coin loot")
	if int(reward_totals.get("herb", 0)) < 1 or int(reward_totals.get("qingxin_tea", 0)) != 1:
		errors.append("result preview did not aggregate enemy loot tables")
	var first_loot: Array = report.get("lootRewards", [])
	var repeated_report := Result.build(encounter, state, "victory")
	var repeated_loot: Array = repeated_report.get("lootRewards", [])
	if first_loot != repeated_loot or (report.get("lootSteps", []) as Array).is_empty():
		errors.append("loot preview is not deterministic or did not become reward steps")
	if int(report.get("xpReward", 0)) != 35:
		errors.append("victory result lost the encounter XP reward")
	var xp_rows: Array = report.get("xpRows", [])
	if xp_rows.size() != 4 or xp_rows != repeated_report.get("xpRows", []):
		errors.append("equal-party XP preview is missing or not deterministic")
	for raw_row in xp_rows:
		var row: Dictionary = raw_row
		if int(row.get("levelAfter", 0)) != 2 or int(row.get("xpAfter", -1)) != 5:
			errors.append("victory preview did not apply 35 XP to %s" % row.get("heroId", "?"))
		if str(row.get("heroId", "")) == "orik" and int(row.get("hpAfter", -1)) != 1:
			errors.append("victory preview did not return fallen Orik at 1 HP")
	var defeat_report := Result.build(encounter, state, "defeat")
	if int(defeat_report.get("xpReward", -1)) != 0:
		errors.append("defeat result granted XP")
	if not errors.is_empty():
		printerr("FAIL combat result bridge")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat result bridge")
	print("  enemy/tag/count, loot and equal-party XP share authored encounter data")
	quit(0)


func _reward_totals(rewards: Array) -> Dictionary:
	var result := {}
	for raw_reward in rewards:
		var reward: Dictionary = raw_reward
		var item_id := str(reward.get("itemId", ""))
		result[item_id] = int(result.get(item_id, 0)) + int(reward.get("count", 0))
	return result
