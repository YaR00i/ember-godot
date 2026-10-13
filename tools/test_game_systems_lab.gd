extends SceneTree
## Real runtime test flag: the existing Lab consumes saved native content privately.
const Scene = preload("res://scenes/combat_lab.tscn")
const Transition = preload("res://scripts/ember_combat_transition.gd")
const Launcher = preload("res://addons/ember_import/ember_game_systems_lab_launcher.gd")
const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const GridWorld = preload("res://scripts/prototypes/ember_combat_grid_3d_world.gd")
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
	_arena_validation()
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
	var request := Transition.library_test_request(OS.get_cmdline_user_args())
	_check(request.get("ok", false), "runtime setup input refused")
	if not request.get("ok", false):
		_finish()
		return
	var configured: bool = not request.preparedSetup.setup.is_empty()
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
	var arena := controller.get("_external_3d_world") as EmberCombatGrid3DWorld
	_check(arena != null and arena == lab.get_node("Arena"), "selected arena did not own the HUD projection")
	if arena == null:
		lab.free()
		_finish()
		return
	_check(arena.scene_file_path == request.encounter.arena_scene.resource_path and arena.get_meta("library_arena_fixture", false), "Lab kept its fixed arena")
	_check(arena.get_node_or_null("AuthoredArenaMarker") is MeshInstance3D, "selected arena decoration missing")
	_check(arena.battlefield == request.encounter.battlefield and arena.battlefield.field_id == "colored_crossing", "arena preview field replaced encounter semantics")
	_check(arena.get_node("CombatGridMap").get_used_cells().size() == state.grid.width * state.grid.height, "selected arena projection disagrees with encounter grid")
	_check(root.get_camera_3d() == arena.get_node("CameraRig/CombatCamera3D"), "fixed arena left a second active camera")
	var picked := arena.pick_cell_at(arena.screen_position_for_cell(Vector2i(1, 1)))
	_check(picked == Vector2i(1, 1), "selected arena camera cannot pick semantic grid")
	var arena_instance_id := arena.get_instance_id()
	controller.set("_field_view_mode", "2d")
	controller.call("_refresh")
	_check(not arena.visible, "2D view left arena decoration visible")
	controller.set("_field_view_mode", "3d")
	controller.call("_refresh")
	_check(arena.visible, "3D view did not restore selected arena")
	await _capture("deployment")
	controller.call("_confirm_deployment")
	_check(controller.get("_library_test") and state.encounterId == "library_lab_fixture", "Lab did not consume selected encounter")
	_check(state.units.size() == 2 and state.units.has("mira") and state.units.has("wisp"), "saved roster ignored")
	_check(controller.get("_party_snapshot").is_empty() and controller.get("_inventory_snapshot") == request.preparedSetup.inventory, "gameplay party/inventory leaked into test")
	var initial := state.duplicate(true)
	if configured:
		var member: Dictionary = request.preparedSetup.setup.party.mira
		_check(state.units.mira.level == 9 and state.units.mira.equipment == member.equipment and state.units.mira.maxHp == request.preparedSetup.derived.mira.maxHp and state.inventory == {"herb": 3}, "runtime discarded configured level/equipment/bag")
		_check(Combat.current_unit_id(state) == "mira", "fixture starting actor changed")
		state.units.mira.hp -= 4
		var preview := Combat.preview(state, "item:herb", "mira")
		_check(preview.get("ok", false), "configured bag cannot use a native consumable")
		state = Combat.commit(state, preview)
		_check(state.inventory.get("herb") == 2 and state.units.mira.hp == initial.units.mira.maxHp, "native consumption changed setup or failed to heal")
		controller.set("_state", state)
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
	_check(arena.get_instance_id() == arena_instance_id and lab.get_child_count() == 2 and arena.get_node_or_null("AuthoredArenaMarker") != null, "Retry recreated/lost/duplicated arena or HUD")
	_check(state.units.wisp.hp > 0 and state.turn == 1, "Retry did not rebuild native initial state")
	_check(state.units.mira == initial.units.mira and state.inventory == initial.inventory, "Retry lost setup or kept consumed bag/damage")
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

func _arena_validation() -> void:
	for path in ["res://scenes/combat/arenas/colored_crossing.tscn", "res://scenes/combat/arenas/thaw_keeper.tscn"]:
		_check(EmberEncounterResource.arena_validation_errors(load(path)).is_empty(), "existing inherited arena rejected: " + path)
	var marker := "user://arena-validation-instantiated-%d" % OS.get_process_id()
	_check(not FileAccess.file_exists(marker), "validation fixture marker exists before test")
	var validation_only := load("res://scenes/combat/arenas/library_validation_only.tscn") as PackedScene
	_check(EmberEncounterResource.arena_validation_errors(validation_only).is_empty(), "derived projection script rejected")
	_check(not FileAccess.file_exists(marker), "read-only validation instantiated author script")
	_check(not Launcher.start("res://content/combat/encounters/library_lab_bad_arena.tres").get("ok", true), "launcher started incompatible saved arena")
	var node := Node3D.new()
	var invalid := PackedScene.new()
	invalid.pack(node)
	_check(not EmberEncounterResource.arena_validation_errors(invalid).is_empty(), "plain scene without projection accepted")
	node.set_script(GridWorld)
	invalid = PackedScene.new()
	invalid.pack(node)
	_check(not EmberEncounterResource.arena_validation_errors(invalid).is_empty(), "missing projection/camera nodes accepted")
	node.free()
	var empty := PackedScene.new()
	_check(not EmberEncounterResource.arena_validation_errors(empty).is_empty(), "empty arena accepted")

func _finish() -> void:
	if _errors.is_empty(): print("PASS game systems library Lab: selected inherited arena/decor/camera/picking, encounter field authority, 2D/3D/deployment/Retry, structure validation, real flag/autoload isolation, saved encounter/roster, same result XP/loot, victory/defeat, save/transition refusal and unchanged progress")
	else: printerr("FAIL library Lab: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)
