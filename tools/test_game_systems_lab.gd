extends SceneTree
## Real runtime test flag: the existing Lab consumes saved native content privately.
const Scene = preload("res://scenes/combat_lab.tscn")
const Transition = preload("res://scripts/ember_combat_transition.gd")
const Launcher = preload("res://addons/ember_import/ember_game_systems_lab_launcher.gd")
var _errors: Array[String] = []

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL library Lab gate refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1600, 900)
	_run.call_deferred()

func _frames(count: int) -> void:
	for frame in count: await process_frame

func _capture(label: String) -> void:
	await _frames(6)
	if DisplayServer.get_name() == "headless": return
	RenderingServer.force_draw(false)
	var path := "user://library-lab-%s-%d.png" % [label, OS.get_process_id()]
	root.get_texture().get_image().save_png(path)
	print("LIBRARY_LAB_CAPTURE ", ProjectSettings.globalize_path(path))

func _run() -> void:
	_check(Transition.library_test_requested(), "runtime launch flag missing")
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	progress.set_process(false)
	_check(not progress.persistence_enabled and not progress.restore_enabled and progress.storage_root != EmberExploreState.DEFAULT_STORAGE_ROOT, "autoload loaded normal save mode")
	var default_file := EmberExploreState.DEFAULT_STORAGE_ROOT.path_join(EmberExploreState.PACK_ID).path_join("manual_0.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(default_file.get_base_dir()))
	var file := FileAccess.open(default_file, FileAccess.WRITE)
	file.store_string("library-lab-save-sentinel")
	file.close()
	var before_file := FileAccess.get_file_as_string(default_file)
	var snapshot := progress.capture_save()
	snapshot.erase("savedAtMs")
	var path := "res://content/combat/encounters/library_lab_fixture.tres"
	_check(Transition.library_test_content(path).get("ok", false), "saved fixture refused")
	_check(not Transition.library_test_content("res://scenes/../content/combat/encounters/library_lab_fixture.tres").get("ok", true), "unsafe path accepted")
	_check(not Transition.library_test_request(PackedStringArray()).get("ok", true), "missing request accepted")
	_check(not Transition.library_test_request(PackedStringArray([Transition.LIBRARY_TEST_PREFIX + path, Transition.LIBRARY_TEST_PREFIX + path])).get("ok", true), "ambiguous request accepted")
	_check(Launcher.arguments(path).has(Transition.LIBRARY_TEST_PREFIX + path), "launcher lost saved path")
	var lab := Scene.instantiate()
	root.add_child(lab)
	current_scene = lab
	await _frames(15)
	var controller := lab.find_child("CombatLab", true, false)
	if controller == null: controller = lab.find_child("CombatHUD", true, false)
	# The controller's node name is authored by the existing scene.
	if controller == null:
		for child in lab.get_children():
			if child.has_method("state_snapshot"): controller = child
	if controller == null:
		_check(false, "native Lab controller missing")
		lab.free()
		_finish()
		return
	var state: Dictionary = controller.state_snapshot()
	controller.call("_confirm_deployment")
	_check(controller.get("_library_test") and state.encounterId == "library_lab_fixture", "Lab did not consume selected encounter")
	_check(state.units.size() == 2 and state.units.has("mira") and state.units.has("wisp"), "saved roster ignored")
	_check(controller.get("_party_snapshot").is_empty() and controller.get("_inventory_snapshot").is_empty(), "gameplay party/inventory leaked into test")
	await _capture("battle")
	state.units.wisp.hp = 0
	controller.set("_state", state)
	controller.call("_refresh")
	_check((controller.find_child("CombatResultContinue", true, false) as Button).text == "Закрыть тест · Enter", "test result offered persistent Continue")
	_check((controller.find_child("CombatResultRetry", true, false) as Button).visible, "victory Retry missing")
	_check(not (controller.find_child("CombatResultLoad", true, false) as Button).visible, "test exposed gameplay save load")
	_check("не выдаются" in controller.get("_result_body").text and "+9 XP" in controller.get("_result_body").text, "reward calculation/isolation copy missing")
	await _capture("victory")
	controller.call("_retry_encounter")
	state = controller.state_snapshot()
	_check(state.units.wisp.hp > 0 and state.turn == 1, "Retry did not rebuild native initial state")
	state.units.mira.hp = 0
	controller.set("_state", state)
	controller.call("_refresh")
	controller.call("_open_defeat_load_choices")
	_check(not controller.get("_defeat_load_open") and not (controller.find_child("CombatResultLoad", true, false) as Button).visible, "defeat exposed saves")
	await _capture("defeat")
	_check(Transition.finish(self, "victory", progress, state) == ERR_UNAVAILABLE, "test result crossed gameplay transition")
	_check(Transition.change_scene(self, "colored_crossing_demo", progress) == ERR_UNAVAILABLE, "test started persistent transition")
	progress.save_slot(0)
	progress.save_autosave()
	_check(FileAccess.get_file_as_string(default_file) == before_file and not FileAccess.file_exists(progress.save_path(0)) and not FileAccess.file_exists(progress.autosave_path()), "test wrote progress saves")
	var after := progress.capture_save()
	after.erase("savedAtMs")
	_check(after == snapshot, "result/Retry mutated private progress")
	lab.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(default_file))
	_finish()

func _finish() -> void:
	if _errors.is_empty(): print("PASS game systems library Lab: real flag/autoload isolation, saved encounter/roster, same result XP/loot, victory/defeat/Retry, save/transition refusal and unchanged progress")
	else: printerr("FAIL library Lab: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)
