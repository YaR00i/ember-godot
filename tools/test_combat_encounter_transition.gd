extends SceneTree
## Scene lifecycle gate: exploration -> authored encounter -> exploration ->
## outcome action. No outgoing Node/UI reference is allowed to survive.

const SOURCE_SCENE := "res://scenes/agent_sandbox.tscn"
const ENCOUNTER_ID := "colored_crossing_demo"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: Array[String] = []
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if progress == null:
		printerr("FAIL encounter transition: progress autoload missing")
		quit(1)
		return
	progress.persistence_enabled = false
	progress.restore_enabled = false
	progress.reset_new_game()
	var persistent_mira: Dictionary = progress.party.get("mira", {})
	persistent_mira["hp"] = 11
	persistent_mira["mp"] = 13
	progress.party["mira"] = persistent_mira
	progress.inventory["herb"] = 2
	EmberCombatTransition.clear_for_test()
	if change_scene_to_file(SOURCE_SCENE) != OK:
		errors.append("could not open exploration fixture")
	else:
		await scene_changed
		await process_frame
		var before_coins := int(progress.inventory.get("coin", 0))
		var before_herbs := int(progress.inventory.get("herb", 0))
		var before_tea := int(progress.inventory.get("qingxin_tea", 0))
		var error := EmberCombatTransition.change_scene(self, ENCOUNTER_ID, progress)
		if error != OK:
			errors.append("encounter transition rejected a valid authored battle")
		else:
			await scene_changed
			await process_frame
			var hud := current_scene.find_child("CombatHUD", true, false)
			var state: Dictionary = hud.call("state_snapshot") if hud != null else {}
			if str(state.get("encounterId", "")) != ENCOUNTER_ID:
				errors.append("Combat Lab did not consume the pending encounter")
			var battle_mira: Dictionary = (state.get("units", {}) as Dictionary).get("mira", {})
			if int(battle_mira.get("hp", -1)) != 11 or int(battle_mira.get("mp", -1)) != 13:
				errors.append("Combat Lab did not receive the persistent party snapshot")
			if (
				int((state.get("inventory", {}) as Dictionary).get("herb", 0)) != 2
				or (state.get("itemDefinitions", {}) as Dictionary).get("herb", {}).is_empty()
			):
				errors.append("Combat Lab did not receive the shared inventory snapshot")
			var radial := current_scene.find_child("CombatRadialMenu", true, false) as Control
			if radial == null or not radial.visible or radial.get_child_count() < 7:
				errors.append("authored battle did not expose radial movement/actions around the active hero (visible=%s, children=%d)" % [
					str(radial != null and radial.visible), radial.get_child_count() if radial != null else -1,
				])
			var victory_state := state.duplicate(true)
			var units := victory_state.get("units", {}) as Dictionary
			for raw_id in units:
				var unit := units[raw_id] as Dictionary
				if str(unit.get("team", "")) == "enemy":
					unit["hp"] = 0
				elif str(raw_id) == "mira":
					unit["hp"] = 4
					unit["mp"] = 5
				elif str(raw_id) == "orik":
					unit["hp"] = 0
				units[raw_id] = unit
			victory_state["units"] = units
			var spent_inventory := (victory_state.get("inventory", {}) as Dictionary).duplicate(true)
			spent_inventory["herb"] = 1
			victory_state["inventory"] = spent_inventory
			var expected_report := EmberCombatResult.build(
				EmberEncounterCatalog.definition(ENCOUNTER_ID), victory_state, "victory"
			)
			var expected_mira := _xp_row(expected_report.get("xpRows", []), "mira")
			hud.set("_state", victory_state)
			hud.call("_refresh")
			await process_frame
			var result_overlay := current_scene.find_child("CombatResultOverlay", true, false) as Control
			var continue_button := current_scene.find_child("CombatResultContinue", true, false) as Button
			if result_overlay == null or not result_overlay.visible or continue_button == null or not continue_button.visible:
				errors.append("victory did not open a centered Continue result window")
			var result_body := current_scene.find_child("CombatResultPanel", true, false) as Control
			var result_text := _label_texts(result_body) if result_body != null else ""
			if result_body == null or "Монета ×" not in result_text or "Чай цинсинь ×1" not in result_text:
				errors.append("victory result did not preview fixed reward and enemy loot")
			if "+35 XP каждому герою" not in result_text or "Повышение уровня" not in result_text:
				errors.append("victory result did not explain equal XP and level-ups")
			if continue_button == null:
				errors.append("victory could not return to exploration")
			else:
				# A repeated UI signal must not start two transitions or apply rewards twice.
				continue_button.pressed.emit()
				continue_button.pressed.emit()
				await scene_changed
				await process_frame
				await process_frame
				if EmberCombatTransition.finish(self, "victory", progress) != ERR_ALREADY_IN_USE:
					errors.append("result transaction accepted a second victory application")
				var returned_mira := progress.party_member_view("mira")
				if (
					int(returned_mira.get("hp", -1)) != int(expected_mira.get("hpAfter", -2))
					or int(returned_mira.get("mp", -1)) != int(expected_mira.get("mpAfter", -2))
				):
					errors.append("battle result did not return progressed HP/MP exactly once")
				for hero_id in EmberPartyState.HERO_IDS:
					var returned_member := progress.party_member_view(hero_id)
					if int(returned_member.get("level", 0)) != 2 or int(returned_member.get("xp", -1)) != 5:
						errors.append("victory XP was not applied exactly once to %s" % hero_id)
				if int(progress.party_member_view("orik").get("hp", -1)) != 1:
					errors.append("fallen Orik did not return from victory at 1 HP")
				if current_scene.scene_file_path != SOURCE_SCENE:
					errors.append("battle returned to the wrong scene")
				if not bool(progress.flags.get("colored_crossing_won", false)):
					errors.append("victory result flag was not applied")
				if int(progress.flags.get("combat_victories", 0)) != 1:
					errors.append("victory counter was not applied exactly once")
				if int(progress.flags.get("combat_encounter_colored_crossing_demo_victories", 0)) != 1:
					errors.append("encounter-specific quest counter was not applied")
				if int(progress.flags.get("combat_defeated_total", 0)) != 3:
					errors.append("defeated-enemy counter lost the encounter result")
				if int(progress.flags.get("combat_defeated_tag_swamp", 0)) != 3:
					errors.append("enemy tag counter lost defeated swamp units")
				var expected_loot := _reward_totals(expected_report.get("lootRewards", []))
				var ui := current_scene.find_child("InteractionUI", true, false)
				if ui == null or str((ui.call("view_state") as Dictionary).get("mode", "")) != "reward":
					errors.append("returned world did not present the outcome action")
				else:
					for _index in 10:
						var ui_state := ui.call("view_state") as Dictionary
						if not bool(ui_state.get("scriptActive", false)):
							break
						ui.call("advance")
						await process_frame
				if int(progress.inventory.get("coin", 0)) != before_coins + 5 + int(expected_loot.get("coin", 0)):
					errors.append("victory queue did not grant fixed coins and rolled coins once")
				if int(progress.inventory.get("herb", 0)) != before_herbs - 1 + int(expected_loot.get("herb", 0)):
					errors.append("battle consumption and victory herb loot were not applied exactly once")
				if int(progress.inventory.get("qingxin_tea", 0)) != before_tea + int(expected_loot.get("qingxin_tea", 0)):
					errors.append("victory queue did not grant elite loot once")
	EmberCombatTransition.clear_for_test()
	if not errors.is_empty():
		printerr("FAIL encounter transition")
		for message in errors:
			printerr(" - ", message)
		quit(1)
		return
	print("PASS encounter transition")
	print("  radial battle HUD -> victory modal -> Continue returns to exploration")
	print("  party XP/level-up, fallen-at-1 rule and spent inventory return once")
	print("  repeated Continue cannot apply progression or grant rewards twice")
	quit(0)


func _label_texts(root_node: Node) -> String:
	var result: Array[String] = []
	for child in root_node.find_children("*", "Label", true, false):
		result.append((child as Label).text)
	return "\n".join(result)


func _reward_totals(rewards: Array) -> Dictionary:
	var result := {}
	for raw_reward in rewards:
		var reward: Dictionary = raw_reward
		var item_id := str(reward.get("itemId", ""))
		result[item_id] = int(result.get(item_id, 0)) + int(reward.get("count", 0))
	return result


func _xp_row(rows: Array, hero_id: String) -> Dictionary:
	for raw_row in rows:
		var row: Dictionary = raw_row
		if str(row.get("heroId", "")) == hero_id:
			return row
	return {}
