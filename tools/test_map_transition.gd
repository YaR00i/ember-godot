extends SceneTree
## Real exploration/door/trigger/spawn handoff on saved native test maps.
## No historical city, author scene or JOI map is part of this mechanics gate.

const Transition = preload("res://scripts/ember_map_transition.gd")
const Fixture = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")

var _fixtures: Array[PackedScene] = []
var _routes: Array[Dictionary] = []
var _source_id := ""
var _directory := ""
var _errors: Array[String] = []
var _setup: Dictionary = {}
var _scene_hashes: Dictionary = {}


func _init() -> void:
	_directory = "user://ember-tests/map-transition-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_setup = Fixture.prepare(self, _directory)
	_run.call_deferred()


func _check(value: bool, message: String) -> bool:
	if not value: _errors.append(message)
	return value


func _run() -> void:
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if not _check(progress != null, "progress autoload missing"):
		quit(1)
		return
	progress.persistence_enabled = false
	progress.restore_enabled = false
	_check(_setup.error == OK, "could not prepare native fixture")
	_check(_setup.progress_isolated, "progress was not isolated before autoload readiness")
	progress.reset_new_game()
	Transition.clear_for_test()
	_test_handoff()
	if _make_fixtures():
		_test_saved_scenes()
		Transition.clear_for_test()
		await _test_live_routes()
	Transition.clear_for_test()
	for path in _scene_hashes:
		_check(FileAccess.get_sha256(path) == _scene_hashes[path], "runtime changed the saved fixture scene")
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
		await process_frame
	if not _errors.is_empty():
		printerr("FAIL map transition: ", "; ".join(_errors))
		quit(1)
		return
	print("PASS map transition")
	print("  six saved/reopened native fixtures in user://; no historical maps/models or JOI")
	print("  native item catalog needs no item JSON; other JOI domains remain separate")
	print("  five real door -> nested entry -> exit -> matching return routes")
	print("  real exploration/player/HUD/water-contact owners, no runtime substitutes")
	print("  one-shot destination, wrong-map handoff, missing scene cleanup and 1200 ms arrival guard")
	quit(0)


func _test_handoff() -> void:
	Transition.prepare("fixture_room", "entry")
	_check(Transition.consume_spawn_region("other_map", 999).is_empty(), "wrong map consumed a destination")
	_check(Transition.consume_spawn_region("fixture_room", 1000) == "entry", "target region was not handed to the room")
	_check(Transition.consume_spawn_region("fixture_room", 1001).is_empty(), "spawn destination consumed twice")
	Transition.prepare("fixture_home", "return_point")
	_check(Transition.consume_spawn_region("fixture_home", 2000) == "return_point", "return destination lost")
	_check(not Transition.trigger_allowed("return_point", 2500), "arrival trigger guard did not block its region")
	_check(Transition.trigger_allowed("different_region", 2500), "arrival guard blocked an unrelated region")
	_check(Transition.trigger_allowed("return_point", 3300), "arrival guard did not expire")
	Transition.prepare("stale_map", "stale_region")
	_check(Transition.change_scene(self, "__missing_transition_scene__", "missing") == ERR_FILE_NOT_FOUND, "missing scene error lost")
	_check(Transition.consume_spawn_region("stale_map", 3400).is_empty(), "failed transition left stale pending state")


func _make_fixtures() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	_source_id = "transition_fixture_home_%d" % OS.get_process_id()
	var doors: Array[Dictionary] = []
	var returns: Array[Dictionary] = []
	for index in 5:
		var room_id := "transition_fixture_room_%d_%d" % [index, OS.get_process_id()]
		var return_id := "return_%d" % index
		_routes.append({"door": "door_%d" % index, "map": room_id, "return": return_id})
		doors.append({"id": "door_%d" % index, "map": room_id, "region": "entry"})
		returns.append({"id": return_id, "position": Vector3(10 + index * 10, 4, 44), "map": room_id, "region": "entry"})
		var exits: Array[Dictionary] = [{"id": "exit", "position": Vector3(44, 4, 40), "map": _source_id, "region": return_id}]
		var room := Fixture.save_map(room_id, _directory, [], exits)
		if not _check(room != null, "could not save/reopen native room fixture"): return false
		_fixtures.append(room)
		var room_path := _directory.path_join(room_id + ".tscn")
		_scene_hashes[room_path] = FileAccess.get_sha256(room_path)
	var source := Fixture.save_map(_source_id, _directory, doors, returns)
	if not _check(source != null, "could not save/reopen native source fixture"): return false
	_fixtures.append(source)
	var source_path := _directory.path_join(_source_id + ".tscn")
	_scene_hashes[source_path] = FileAccess.get_sha256(source_path)
	return true


func _test_saved_scenes() -> void:
	for packed in _fixtures:
		_check(ResourceLoader.exists(packed.resource_path), "logical fixture destination is unavailable")
		var scene := packed.instantiate()
		var map := scene.get_node("Map") as EmberMapLoader
		_check(map != null and map.has_authored_content(), "saved native ground missing; legacy import would run")
		_check(not map.hydrate_legacy_regions, "fixture retained legacy region hydration")
		_check(map.compact_terrain.validation_errors().is_empty(), "fixture terrain failed validation")
		_check(map.find_region("entry") != null, "saved nested player_start missing")
		_check(map.region_world("entry").is_equal_approx(Vector3(32, 4, 16)), "saved nested transforms were lost")
		_check(map.spawn_world().is_equal_approx(map.region_world("entry")), "default/explicit saved entry disagree")
		_check(scene.get_node_or_null("CanvasLayer/Gate") != null, "shared exploration HUD missing")
		scene.free()


func _test_live_routes() -> void:
	if not _check(change_scene_to_file(Transition.scene_path(_source_id)) == OK, "could not start native source scene"): return
	if not await _wait_scene(_source_id): return
	for route in _routes:
		var door := current_scene.get_node_or_null("Map/Props/%s/Interact" % route.door) as EmberInteract
		if not _check(door != null, "saved door missing: " + route.door): return
		if not _check(door.activate().begins_with("enter"), "real door did not transition: " + route.door): return
		if not await _wait_scene(route.map): return
		var map := current_scene.get_node_or_null("Map") as EmberMapLoader
		var player := current_scene.get_node_or_null("Player") as EmberPlayer
		if not _check(map != null and player != null, "room did not create real Map + Player"): return
		_check(player.find_child("WaterContact", false, false) != null, "real player's water contact missing")
		_check(_same_xz(player.global_position, map.region_world("entry")), "player did not use the selected nested entry")
		var exit := map.find_region("exit")
		if not _check(exit != null, "saved exit trigger missing"): return
		exit._on_body_entered(player)
		if not await _wait_scene(_source_id): return
		var returned_map := current_scene.get_node("Map") as EmberMapLoader
		var returned_player := current_scene.get_node("Player") as EmberPlayer
		_check(_same_xz(returned_player.global_position, returned_map.region_world(route.return)), "return region lost for " + route.map)
		_check(not Transition.trigger_allowed(route.return), "arrival region not protected: " + route.return)
		var return_trigger := returned_map.find_region(route.return)
		return_trigger._on_body_entered(returned_player)
		_check(not return_trigger._transitioning and current_scene.name == _source_id, "arrival trigger caused an immediate scene bounce")


func _same_xz(a: Vector3, b: Vector3) -> bool:
	return Vector2(a.x, a.z).is_equal_approx(Vector2(b.x, b.z))


func _wait_scene(expected: String) -> bool:
	for frame in 12:
		await process_frame
		if current_scene != null and str(current_scene.name) == expected:
			await process_frame
			return true
	return _check(false, "scene transition did not reach " + expected)
