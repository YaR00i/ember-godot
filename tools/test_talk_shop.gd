extends SceneTree

const Content = preload("res://tools/fixtures/ember_interaction_test_fixture.gd")
var _setup: Dictionary = {}
var _source: PackedScene
var _scene_path := ""
## Talk/shop mechanics over synthetic native content and real exploration nodes.



func _init() -> void:
	_setup = Content.prepare(self)
	if _setup.refused:
		quit.call_deferred(2)
		return
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	if _setup.error != OK or not _setup.progress_isolated:
		printerr("FAIL interaction fixture/progress setup")
		return 1
	var runtime_progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if runtime_progress:
		runtime_progress.persistence_enabled = false
		runtime_progress.restore_enabled = false
	_prepare_map()
	_test_content_contract(errors)
	await _test_live_controller(errors)
	Content.verify_sources(_setup, errors)
	if not errors.is_empty():
		printerr("FAIL talk/shop")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS talk/shop")
	print("  guard dialogue: 3 authored lines")
	print("  branch dialogue: 2 authored choices")
	print("  shop intro -> interaction_shop: canonical catalog listings")
	print("  open overlay blocks movement and closes cleanly")
	return 0


func _test_content_contract(errors: Array[String]) -> void:
	var script_ref := EmberInteractionContent.resolve_script_ref("interaction_notice")
	if str(script_ref.get("kind", "")) != "script":
		errors.append("scripts/ no longer wins resolve order over scenes/")
	var notice := EmberInteractionContent.dialogue_for_id("interaction_notice")
	if str(notice.get("id", "")) != "interaction_notice_talk":
		errors.append("action-list talk did not resolve its existing dialogueId")

	var guard := EmberInteractionContent.dialogue_for_id("interaction_guard")
	var session := EmberDialogueSession.new()
	if not session.start(guard):
		errors.append("interaction_guard could not start")
		return
	var expected := [
		"Первая тестовая реплика.",
		"Вторая тестовая реплика.",
		"Третья тестовая реплика.",
	]
	for text in expected:
		if session.current_text() != text:
			errors.append("guard dialogue order/content diverged")
			break
		session.advance()
	if not session.is_finished():
		errors.append("guard dialogue did not reach end")

	var branch := EmberInteractionContent.dialogue_for_id("interaction_branch")
	if not session.start(branch) or session.current_kind() != "choice":
		errors.append("interaction_branch did not start on its choice")
	else:
		var labels := session.choice_labels()
		if labels != ["Первый вариант.", "Второй вариант."]:
			errors.append("interaction_branch choice labels diverged")
		session.choose(1)
		if session.current_text() != "Выбран второй вариант.":
			errors.append("interaction_branch second route diverged")

	var shop := EmberInteractionContent.shop_view("interaction_shop")
	var listings: Array = shop.get("listings", [])
	if str(shop.get("nameRu", "")) != "Тестовая лавка" or listings.size() < 4:
		errors.append("interaction_shop catalog did not load its baseline listings")
	elif str(listings[0].get("nameRu", "")) != "Чай цинсинь":
		errors.append("shop listing did not join the existing item catalog")
	elif int(listings[3].get("buyPrice", -1)) != 12 or int(listings[3].get("stock", -1)) != 2:
		errors.append("shop prices/stock diverged from native fixture")

	var vn := EmberInteractionContent.dialogue_for_id("interaction_visual_projection")
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
	if change_scene_to_file(_scene_path) != OK:
		errors.append("could not start fixture_map runtime scene")
		return
	await process_frame
	await process_frame
	var sandbox := current_scene
	var ui := sandbox.get_node_or_null("CanvasLayer/InteractionUI") as EmberInteractionUi
	var player := sandbox.get_node_or_null("Player") as EmberPlayer
	var talk := sandbox.get_node_or_null("Map/Props/talk_npc/Interact") as EmberInteract
	var branch := sandbox.get_node_or_null("Map/Props/branch_npc/Interact") as EmberInteract
	var kiosk := sandbox.get_node_or_null("Map/Props/shop/Interact") as EmberInteract
	if ui == null or player == null or talk == null or branch == null or kiosk == null:
		errors.append("fixture_map lost Player/UI/talk/branch/shop wiring")
		return
	if player.interaction_ui != ui:
		errors.append("player did not receive the single interaction UI owner")
	var economy := root.get_node("EmberExploreProgress") as EmberExploreState
	economy.persistence_enabled = true
	if ui.economy_state != economy:
		errors.append("interaction UI bypassed the real progress autoload")
	if not ui.activate(talk).is_empty():
		errors.append("live guard talk failed to open")
	elif not ui.blocks_movement():
		errors.append("open dialogue did not block movement")
	elif str(ui.view_state().get("body", "")) != "Первая тестовая реплика.":
		errors.append("live dialogue overlay did not show authored first line")
	ui.advance()
	ui.advance()
	ui.advance()
	if ui.is_open():
		errors.append("live guard talk did not close at end")

	ui.activate(branch)
	if not str(ui.view_state().get("choices", "")).contains("2. Второй вариант."):
		errors.append("live choice overlay did not expose both options")
	ui.choose(1)
	if not str(ui.view_state().get("body", "")).begins_with("Выбран второй"):
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
	if str(shop_view.get("mode", "")) != "shop" or str(shop_view.get("shopId", "")) != "interaction_shop":
		errors.append("shop intro did not continue into its shopId")
	if not str(shop_view.get("body", "")).contains(str(EmberItemCatalog.native_definition("herb").get("nameRu", ""))):
		errors.append("live shop did not render native item names")
	ui.advance()
	if int(economy.inventory.get("coin", -1)) != 14 or int(economy.inventory.get("qingxin_tea", 0)) != 1:
		errors.append("F in shop did not buy selected catalog item")
	if not str(ui.view_state().get("feedback", "")).begins_with("Куплено"):
		errors.append("shop did not show successful transaction feedback")
	ui.advance()
	if int(economy.inventory.get("coin", -1)) != 8 or int(economy.inventory.get("qingxin_tea", 0)) != 2:
		errors.append("shop did not apply the second native listing transaction")
	var after_stock := economy.inventory.duplicate(true)
	ui.advance()
	if economy.inventory != after_stock:
		errors.append("shop allowed buying an exhausted native listing")
	ui.close()
	if ui.is_open() or ui.blocks_movement():
		errors.append("shop did not close/release movement")
	var reopened := EmberExploreState.new()
	reopened.storage_root = economy.storage_root
	if not reopened.load_autosave() or reopened.inventory != economy.inventory or int(reopened.shop_stock.get("interaction_shop", {}).get("qingxin_tea", -1)) != 0:
		errors.append("shop wallet/inventory/remaining stock did not survive save reopen")
	reopened.free()
	economy.persistence_enabled = false


func _prepare_map() -> void:
	var id := "interaction_fixture_%d" % OS.get_process_id()
	_source = Content.save_map(id, _setup.directory)
	_scene_path = EmberMapTransition.scene_path(id)
