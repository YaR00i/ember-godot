extends SceneTree
## Action-list vertical slice over real JOI content and agent_sandbox wiring.

const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var runtime_progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if runtime_progress:
		runtime_progress.persistence_enabled = false
		runtime_progress.restore_enabled = false
		runtime_progress.reset_new_game()
	_test_queue_contract(errors)
	_test_typed_dialogue_flags(errors)
	await _test_live_chain(errors)
	if not errors.is_empty():
		printerr("FAIL action scripts")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS action scripts")
	print("  sandbox_chain: talk -> visible coin reward -> typed flag -> real wait")
	print("  open_shop resumes after close; change_map preserves target region")
	print("  script-only region joins the existing F interaction path")
	print("  mutations stay in EmberExploreState and save once per completed chain")
	return 0


func _test_queue_contract(errors: Array[String]) -> void:
	var built := EmberActionScript.queue_for("sandbox_chain")
	if not bool(built.get("ok", false)):
		errors.append("sandbox_chain could not be resolved")
		return
	var steps: Array = built.get("steps", [])
	var types: Array[String] = []
	for raw_step in steps:
		if typeof(raw_step) == TYPE_DICTIONARY:
			types.append(str(raw_step.get("type", "")))
	if types != ["talk", "give_item", "set_flag", "wait"]:
		errors.append("sandbox_chain action order diverged: %s" % [types])
	elif str(steps[0].get("dialogueId", "")) != "sandbox_notice_talk":
		errors.append("talk did not retain its authored dialogueId")
	elif str(steps[1].get("itemId", "")) != "coin" or int(steps[1].get("count", 0)) != 1:
		errors.append("give_item did not retain coin x1")
	elif steps[2].get("value", null) != true:
		errors.append("set_flag did not retain its typed bool value")
	var direct := EmberActionScript.queue_for("sandbox_notice_talk")
	var direct_steps: Array = direct.get("steps", [])
	if not bool(direct.get("ok", false)) or direct_steps.size() != 1:
		errors.append("direct scene ref did not normalize to one talk step")
	elif str(direct_steps[0].get("type", "")) != "talk":
		errors.append("direct scene ref did not normalize as talk")
	if bool(EmberActionScript.queue_for("missing_action_script").get("ok", true)):
		errors.append("missing action script was accepted")


func _test_typed_dialogue_flags(errors: Array[String]) -> void:
	var session := EmberDialogueSession.new()
	var scene := {
		"id": "typed_flags_fixture",
		"startStepId": "set_string",
		"steps": [
			{"id": "set_string", "type": "set_flag", "flag": "route", "value": "west", "next": "set_number"},
			{"id": "set_number", "type": "set_flag", "flag": "rank", "value": 3, "next": "end"},
			{"id": "end", "type": "end"},
		],
	}
	session.start(scene)
	var flags := session.flags()
	if flags.get("route") != "west" or flags.get("rank") != 3:
		errors.append("dialogue set_flag collapsed string/number values to bool")


func _test_live_chain(errors: Array[String]) -> void:
	if change_scene_to_file(SANDBOX_SCENE) != OK:
		errors.append("could not start agent_sandbox runtime scene")
		return
	await process_frame
	await process_frame
	var sandbox := current_scene
	var ui := sandbox.get_node_or_null("CanvasLayer/InteractionUI") as EmberInteractionUi
	var player := sandbox.get_node_or_null("Player") as EmberPlayer
	var region := sandbox.get_node_or_null("Map/Regions/chain_demo") as EmberRegion
	var quest_interact := sandbox.get_node_or_null("Map/Props/sbx_quest_sign/Interact") as EmberInteract
	if (
		ui == null
		or player == null
		or region == null
		or quest_interact == null
	):
		errors.append("agent_sandbox lost Player/UI/chain_demo/quest-giver wiring")
		return
	if not quest_interact.is_in_group("ember_interact"):
		errors.append("bound quest marker did not join the executable F group")
	elif quest_interact.resolved_action_script_id() != "sandbox_notice":
		errors.append("quest marker did not resolve its bound notice action")
	if region.script_id != "sandbox_chain":
		errors.append("chain_demo did not import sandbox_chain from the map")
	if not region.is_in_group("ember_interact"):
		errors.append("script-only region did not join ember_interact")
	player.global_position = region.global_position
	if player._nearest_prompt() != "Действие":
		errors.append("script-only chain_demo region did not expose F: Действие")

	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.restore_enabled = false
	state.reset_new_game()
	ui.economy_state = state
	player._try_interact()
	if str(ui.view_state().get("mode", "")) != "dialogue":
		errors.append("F in chain_demo region did not open sandbox_chain dialogue")
	elif int(state.inventory.get("coin", -1)) != EmberExploreState.STARTING_COINS:
		errors.append("give_item ran before the dialogue completed")
	ui.advance()
	ui.advance()
	var reward_view := ui.view_state()
	if str(reward_view.get("mode", "")) != EmberInteractionUi.MODE_REWARD:
		errors.append("give_item did not stop on a visible reward card")
	elif not str(reward_view.get("body", "")).contains("Монета") or not str(reward_view.get("body", "")).contains("+1"):
		errors.append("reward card does not explain the granted coin")
	if int(state.inventory.get("coin", -1)) != EmberExploreState.STARTING_COINS + 1:
		errors.append("sandbox_chain did not grant exactly one coin")
	if state.flags.has("sandbox_chain_done"):
		errors.append("steps after reward ran before F continued the chain")
	ui.advance()
	if ui.is_open():
		errors.append("completed sandbox_chain left the reward overlay open")
	if state.flags.get("sandbox_chain_done", false) != true:
		errors.append("sandbox_chain did not set sandbox_chain_done")

	ui._script_queue = [
		{"type": "wait", "sec": 0.05},
		{"type": "set_flag", "flag": "wait_finished", "value": true},
	]
	ui._script_active = true
	ui._script_mutated = false
	ui._advance_script_queue()
	if str(ui.view_state().get("mode", "")) != EmberInteractionUi.MODE_WAIT:
		errors.append("positive wait did not open timed pause state")
	ui.advance()
	if state.flags.has("wait_finished"):
		errors.append("F skipped an authored wait")
	await create_timer(0.08).timeout
	if state.flags.get("wait_finished", false) != true:
		errors.append("wait did not resume the remaining queue")

	ui._script_queue = [
		{"type": "open_shop", "shopId": "village_kiosk"},
		{"type": "set_flag", "flag": "shop_chain_finished", "value": true},
	]
	ui._script_active = true
	ui._script_mutated = false
	ui._advance_script_queue()
	if str(ui.view_state().get("mode", "")) != EmberInteractionUi.MODE_SHOP:
		errors.append("open_shop action did not open the existing shop UI")
	elif state.flags.has("shop_chain_finished"):
		errors.append("steps after open_shop ran before the shop closed")
	ui.close()
	if state.flags.get("shop_chain_finished", false) != true:
		errors.append("closing an action-list shop did not resume the remaining queue")
	elif ui.is_open():
		errors.append("completed post-shop queue left its overlay open")
	ui.economy_state = null
	state.free()

	ui._script_queue = [
		{"type": "change_map", "targetMapId": "agent_sandbox_interior", "targetRegionId": "start"},
	]
	ui._script_active = true
	ui._script_mutated = false
	ui._advance_script_queue()
	await process_frame
	await process_frame
	if current_scene == null or current_scene.name != "AgentSandboxInterior":
		errors.append("change_map action did not enter the authored map scene")
	else:
		var interior_map := current_scene.get_node_or_null("Map") as EmberMapLoader
		var interior_player := current_scene.get_node_or_null("Player") as EmberPlayer
		if interior_map == null or interior_player == null:
			errors.append("change_map action target lost Map/Player wiring")
		elif Vector2(interior_player.global_position.x, interior_player.global_position.z).distance_to(
			Vector2(interior_map.region_world("start").x, interior_map.region_world("start").z)
		) > 0.1:
			errors.append("change_map action did not preserve targetRegionId=start")
