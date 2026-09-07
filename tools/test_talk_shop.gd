extends SceneTree
## Wave 4 talk/shop smoke over the real agent_sandbox content and scene nodes.

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
	_test_content_contract(errors)
	await _test_live_controller(errors)
	if not errors.is_empty():
		printerr("FAIL talk/shop")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS talk/shop")
	print("  guard dialogue: 3 authored lines")
	print("  branch dialogue: 2 authored choices")
	print("  shop intro -> village_kiosk: canonical catalog listings")
	print("  open overlay blocks movement and closes cleanly")
	return 0


func _test_content_contract(errors: Array[String]) -> void:
	var script_ref := EmberInteractionContent.resolve_script_ref("sandbox_notice")
	if str(script_ref.get("kind", "")) != "script":
		errors.append("scripts/ no longer wins resolve order over scenes/")
	var notice := EmberInteractionContent.dialogue_for_id("sandbox_notice")
	if str(notice.get("id", "")) != "sandbox_notice_talk":
		errors.append("action-list talk did not resolve its existing dialogueId")

	var guard := EmberInteractionContent.dialogue_for_id("sandbox_guard_talk")
	var session := EmberDialogueSession.new()
	if not session.start(guard):
		errors.append("sandbox_guard_talk could not start")
		return
	var expected := [
		"Эй. Это учебный двор, не деревня.",
		"Хочешь ветку — поговори с тем, кто у табличек.",
		"И не ломай сундук дважды. Он один.",
	]
	for text in expected:
		if session.current_text() != text:
			errors.append("guard dialogue order/content diverged")
			break
		session.advance()
	if not session.is_finished():
		errors.append("guard dialogue did not reach end")

	var branch := EmberInteractionContent.dialogue_for_id("sandbox_branch")
	if not session.start(branch) or session.current_kind() != "choice":
		errors.append("sandbox_branch did not start on its choice")
	else:
		var labels := session.choice_labels()
		if labels != ["Агент. Проверяю цепочки.", "Просто смотрю двор."]:
			errors.append("sandbox_branch choice labels diverged")
		session.choose(1)
		if session.current_text() != "Ладно. Таблички справа — доступен, активен, сдан.":
			errors.append("sandbox_branch second route diverged")

	var shop := EmberInteractionContent.shop_view("village_kiosk")
	var listings: Array = shop.get("listings", [])
	if str(shop.get("nameRu", "")) != "Киоск деревни" or listings.size() < 4:
		errors.append("village_kiosk catalog did not load its baseline listings")
	elif str(listings[0].get("nameRu", "")) != "Чай цинсинь":
		errors.append("shop listing did not join the existing item catalog")
	elif int(listings[3].get("buyPrice", -1)) != 12 or int(listings[3].get("stock", -1)) != 2:
		errors.append("shop prices/stock diverged from catalog.json")

	var vn := EmberInteractionContent.dialogue_for_id("hu_tao_clear_demo")
	if not session.start(vn) or session.current_kind() != "splash":
		errors.append("VN fixture did not start on its canonical splash")
	else:
		var splash_visual := session.current_visual_state()
		if str(splash_visual.get("artId", "")).is_empty():
			errors.append("runtime VN projection lost splash artId")
		session.advance()
		var dialogue_visual := session.current_visual_state()
		var actors: Array = dialogue_visual.get("actors", [])
		if str(dialogue_visual.get("portraitSide", "")) != "right":
			errors.append("runtime VN projection lost portraitSide")
		if str(dialogue_visual.get("bgArtId", "")).is_empty() or actors.is_empty():
			errors.append("runtime VN projection lost background or staged actors")
		elif not bool((actors[0] as Dictionary).get("lockY", false)):
			errors.append("runtime VN projection flattened advanced actor fields")
		session.advance()
		var choice_visual := session.current_visual_state()
		var choice_actors: Array = choice_visual.get("actors", [])
		if choice_actors.is_empty() or not is_equal_approx(float((choice_actors[0] as Dictionary).get("scale", 0.0)), 1.0):
			errors.append("runtime VN choice did not inherit the incoming stage cast")
	var fallback_scene := {
		"id": "visual_fallback",
		"nameRu": "Visual fallback",
		"defaultBgArtId": "default_bg",
		"startStepId": "line",
		"steps": [
			{"id": "line", "type": "dialogue", "textRu": "Line", "next": "end"},
			{"id": "end", "type": "end"},
		],
	}
	session.start(fallback_scene)
	if str(session.current_visual_state().get("bgArtId", "")) != "default_bg":
		errors.append("runtime VN projection did not apply scene defaultBgArtId")


func _test_live_controller(errors: Array[String]) -> void:
	if change_scene_to_file(SANDBOX_SCENE) != OK:
		errors.append("could not start agent_sandbox runtime scene")
		return
	await process_frame
	await process_frame
	var sandbox := current_scene
	var ui := sandbox.get_node_or_null("CanvasLayer/InteractionUI") as EmberInteractionUi
	var player := sandbox.get_node_or_null("Player") as EmberPlayer
	var talk := sandbox.get_node_or_null("Map/Props/sbx_talk_npc/Interact") as EmberInteract
	var branch := sandbox.get_node_or_null("Map/Props/sbx_branch_npc/Interact") as EmberInteract
	var kiosk := sandbox.get_node_or_null("Map/Props/sbx_shop_kiosk/Interact") as EmberInteract
	if ui == null or player == null or talk == null or branch == null or kiosk == null:
		errors.append("agent_sandbox lost Player/UI/talk/branch/shop wiring")
		return
	if player.interaction_ui != ui:
		errors.append("player did not receive the single interaction UI owner")
	var economy := EmberExploreState.new()
	economy.persistence_enabled = false
	economy.reset_new_game()
	ui.economy_state = economy
	if not ui.activate(talk).is_empty():
		errors.append("live guard talk failed to open")
	elif not ui.blocks_movement():
		errors.append("open dialogue did not block movement")
	elif str(ui.view_state().get("body", "")) != "Эй. Это учебный двор, не деревня.":
		errors.append("live dialogue overlay did not show authored first line")
	ui.advance()
	ui.advance()
	ui.advance()
	if ui.is_open():
		errors.append("live guard talk did not close at end")

	ui.activate(branch)
	if not str(ui.view_state().get("choices", "")).contains("2. Просто смотрю двор."):
		errors.append("live choice overlay did not expose both options")
	ui.choose(1)
	if not str(ui.view_state().get("body", "")).begins_with("Ладно."):
		errors.append("live choice selection did not enter second branch")
	ui.advance()
	if ui.is_open():
		errors.append("live branch dialogue did not close")

	if not ui.activate(kiosk).is_empty():
		errors.append("live shop intro failed to open")
	elif str(ui.view_state().get("mode", "")) != "dialogue":
		errors.append("shop skipped its authored shop_intro scene")
	ui.advance()
	var shop_view := ui.view_state()
	if str(shop_view.get("mode", "")) != "shop" or str(shop_view.get("shopId", "")) != "village_kiosk":
		errors.append("shop intro did not continue into its shopId")
	if not str(shop_view.get("body", "")).contains("Погребальная трава"):
		errors.append("live shop did not render names from items/catalog.json")
	ui.advance()
	if int(economy.inventory.get("coin", -1)) != 14 or int(economy.inventory.get("qingxin_tea", 0)) != 1:
		errors.append("F in shop did not buy selected catalog item")
	if not str(ui.view_state().get("feedback", "")).begins_with("Куплено"):
		errors.append("shop did not show successful transaction feedback")
	ui.close()
	if ui.is_open() or ui.blocks_movement():
		errors.append("shop did not close/release movement")
	ui.economy_state = null
	economy.free()
