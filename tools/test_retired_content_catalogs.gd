extends SceneTree
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
var _directory := ""

func _init() -> void:
	_directory = "user://ember-tests/retired-content-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	Maps.prepare(self, _directory)
	_run.call_deferred()

func _run() -> void:
	var errors: Array[String] = []
	if EmberActionCatalog.ids() != ["colored_crossing_start", "colored_crossing_victory"]: errors.append("active action catalog contains archived city chains")
	if not EmberShopCatalog.ids().is_empty() or not EmberQuestCatalog.ids().is_empty(): errors.append("archived shop/quest still appears in catalog")
	var intro := EmberDialogueCatalog.document("colored_crossing_intro")
	if intro.is_empty() or EmberDialogueCatalog.document("hu_tao_clear_demo").is_empty(): errors.append("retirement deleted preserved dialogue")
	if not EmberDialogueCatalog.document("sandbox_notice_talk").is_empty(): errors.append("retired sandbox dialogue still resolves")
	var queue := EmberActionScript.queue_for("colored_crossing_start")
	var steps: Array = queue.get("steps", [])
	if not queue.get("ok", false) or steps.size() != 2 or steps[0] != {"type": "talk", "dialogueId": "colored_crossing_intro"} or steps[1] != {"type": "start_battle", "encounterId": "colored_crossing_demo"}: errors.append("current battle start lost its dialogue/encounter order")
	var session := EmberDialogueSession.new()
	if not session.start(intro): errors.append("current battle introduction cannot start")
	for index in range(2):
		if session.is_finished() or session.current_kind() != "dialogue" or session.current_text().is_empty(): errors.append("battle introduction lost one of its two lines")
		if not session.flags().is_empty(): errors.append("introduction writes progress before both lines are read")
		if "Песочница" in session.current_text() or "Сундук" in session.current_text(): errors.append("battle introduction still contains retired map directions")
		session.advance()
	if not session.is_finished() or session.flags() != {"new_flag": true}: errors.append("battle introduction changed existing completion flag/end")
	for id in ["vox_fan_barrel", "vox_fan_crate_stack"]:
		if EmberVoxelCatalog.native_resource(id) == null: errors.append("shared Pier model missing " + id)
	for id in ["fan_town", "agent_sandbox"]:
		if ResourceLoader.exists(EmberVoxelModelResource.world_surface_path(id)): errors.append("retired city Surface survived")
	var map_source := Maps.save_map(EmberMapTransition.DEFAULT_MAP_ID, _directory)
	if map_source == null:
		printerr("FAIL retired content native fixture")
		quit(1)
		return
	var state := EmberExploreState.new()
	state.storage_root = _directory.path_join("save")
	state.persistence_enabled = true
	state.restore_enabled = true
	state.reset_new_game()
	state.flags = {"sandbox_notice_status": "done", "sandbox_notice_read": true, "sandbox_notice_quest_objective_2": true}
	var ui := EmberInteractionUi.new()
	ui.economy_state = state
	ui._dialogue = session
	if not ui._apply_dialogue_flags().is_empty() or not state.flags.get("new_flag", false): errors.append("completed introduction did not publish its flag through the existing UI owner")
	ui.free()
	state.shop_stock = {"village_kiosk": {"herb": 4, "retired_item": 2}}
	state.inventory = {"coin": 77, "retired_item": 250}
	if not state.save_slot(0): errors.append("retired progress fixture save failed")
	var source_hash := FileAccess.get_sha256(state.save_path(0))
	var loaded := EmberExploreState.new()
	loaded.storage_root = state.storage_root
	loaded.restore_enabled = true
	if not loaded.load_slot(0) or loaded.flags != state.flags or loaded.shop_stock != state.shop_stock or loaded.inventory != state.inventory: errors.append("catalog retirement changed saved flags/stock/inventory")
	if not EmberQuestCatalog.visible_projections(loaded.flags).is_empty(): errors.append("retired quest still appears in journal")
	if not loaded.shop_view("village_kiosk").is_empty(): errors.append("retired shop still opens")
	if FileAccess.get_sha256(state.save_path(0)) != source_hash: errors.append("loading rewrote saved progress")
	loaded.free()
	state.free()
	if not errors.is_empty():
		printerr("FAIL retired content catalogs: ", "; ".join(errors))
		quit(1)
		return
	print("PASS actual native catalogs; archived city data absent, current battle/shared models preserved, old flags/stock/items round-trip unchanged")
	quit(0)
