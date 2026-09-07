extends SceneTree
## Shared-bag combat item contract: deterministic target/effect, full action,
## one inventory decrement and stale-preview protection in the existing resolver.

const Combat := preload("res://scripts/prototypes/ember_combat_prototype.gd")


func _init() -> void:
	var errors: Array[String] = []
	_test_restore_item(errors)
	_test_revive_item(errors)
	if not errors.is_empty():
		printerr("FAIL combat items")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS combat items")
	print("  shared HP/MP item is deterministic, consumes one stack and a full action")
	print("  revive targets only fallen allies; stale commit cannot consume twice")
	quit(0)


func _test_restore_item(errors: Array[String]) -> void:
	var state := Combat.initial_state(17)
	var actor_id := Combat.current_unit_id(state)
	var units := state.get("units", {}) as Dictionary
	var actor := units.get(actor_id, {}) as Dictionary
	actor["hp"] = maxi(1, int(actor.get("maxHp", 1)) - 5)
	actor["mp"] = maxi(0, int(actor.get("maxMp", 0)) - 6)
	units[actor_id] = actor
	state["units"] = units
	state = Combat.with_inventory(
		state,
		{"tea": 1, "explore_only": 4},
		{
			"tea": {
				"id": "tea", "nameRu": "Тестовый чай", "kind": "consumable",
				"useIn": "both", "hpRestore": 12, "mpRestore": 8, "combatRange": 2,
			},
			"explore_only": {
				"id": "explore_only", "nameRu": "Вне боя", "kind": "consumable",
				"useIn": "explore", "hpRestore": 99,
			},
		},
	)
	if Combat.combat_item_ids(state) != ["item:tea"]:
		errors.append("combat bag did not filter counts and explore-only items")
	if actor_id not in Combat.valid_target_ids(state, "item:tea"):
		errors.append("injured active ally is not a valid restorative item target")
	var before_next := float(Combat.unit_definition(state, actor_id).get("nextAt", 0.0))
	var preview := Combat.preview(state, "item:tea", actor_id)
	if (
		not bool(preview.get("ok", false))
		or bool(preview.get("hostile", true))
		or (preview.get("inventoryCost", {}) as Dictionary).get("itemId", "") != "tea"
	):
		errors.append("restorative item preview is not a deterministic shared-bag command")
		return
	var committed := Combat.commit(state, preview)
	var restored := Combat.unit_definition(committed, actor_id)
	if (
		int(restored.get("hp", 0)) != int(restored.get("maxHp", 1))
		or int(restored.get("mp", 0)) != int(restored.get("maxMp", 0))
	):
		errors.append("combat item did not clamp HP/MP restoration to the target maxima")
	if (committed.get("inventory", {}) as Dictionary).has("tea"):
		errors.append("combat item did not consume exactly one final stack")
	if (
		int(committed.get("turn", 0)) != int(state.get("turn", 0)) + 1
		or float(restored.get("nextAt", 0.0)) <= before_next
	):
		errors.append("combat item did not consume the actor's full action")
	var repeated := Combat.commit(committed, preview)
	if repeated != committed:
		errors.append("stale item preview changed state or consumed inventory twice")
	if int(Combat.unit_definition(state, actor_id).get("hp", 0)) == int(restored.get("hp", 0)):
		errors.append("item preview/commit mutated the source snapshot")


func _test_revive_item(errors: Array[String]) -> void:
	var state := Combat.initial_state(29)
	var units := state.get("units", {}) as Dictionary
	var fallen := units.get("orik", {}) as Dictionary
	fallen["hp"] = 0
	units["orik"] = fallen
	state["units"] = units
	state = Combat.with_inventory(
		state,
		{"spark": 1},
		{
			"spark": {
				"id": "spark", "nameRu": "Искра", "kind": "consumable",
				"useIn": "arena", "reviveHp": 1, "combatRange": 1,
			},
		},
	)
	var targets := Combat.valid_target_ids(state, "item:spark")
	if targets != ["orik"]:
		errors.append("revive item did not select only the fallen ally: %s" % [targets])
		return
	var preview := Combat.preview(state, "item:spark", "orik")
	var committed := Combat.commit(state, preview)
	if int(Combat.unit_definition(committed, "orik").get("hp", 0)) != 1:
		errors.append("revive item did not return the fallen ally with authored HP")
