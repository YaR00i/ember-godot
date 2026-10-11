extends SceneTree
const Fixture = preload("res://tools/fixtures/ember_map_startup_test_fixture.gd")
var _state: Dictionary

class EmptyMap extends EmberMapLoader:
	var reimports := 0
	func load_map(_id: String) -> Dictionary:
		reimports += 1
		return {}

func _init() -> void:
	_state = Fixture.prepare(self)
	if _state.refused:
		quit.call_deferred(2)
		return
	_run.call_deferred()

func _run() -> void:
	var errors: Array[String] = []
	var saved := Fixture.saved_scene(_state)
	if saved.is_empty():
		printerr("FAIL native startup fixture")
		quit(1)
		return
	var scene := (saved.scene as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var map := scene.get_node("Map") as EmberMapLoader
	var entry := map.find_region("entry")
	var chest := map.find_region("chest")
	if entry.kind != "player_start" or not entry.target_map_id.is_empty() or chest.kind != "chest" or chest.loot_ids != ["herb"] or chest.opened:
		errors.append("startup overwrote native region properties from JSON")
	var expected_position := Vector3(32, 4, 16)
	if not map.region_world("entry").is_equal_approx(expected_position): errors.append("startup changed nested native entry")
	map.authored_size_blocks = Vector2i.ZERO
	if map._expected_world_surface_blocks() != Vector2i.ZERO: errors.append("unknown native footprint fell back to JSON")
	map.authored_size_blocks = Vector2i(4, 4)
	if map._expected_world_surface_blocks() != Vector2i(4, 4): errors.append("saved native footprint lost")
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	var before := int(progress.inventory.get("herb", 0))
	chest.activate()
	map.refresh_region_runtime()
	chest.activate()
	if int(progress.inventory.get("herb", 0)) != before + 1 or not progress.chest_is_opened(Fixture.MAP, "chest"):
		errors.append("runtime chest refresh lost one-time native reward")
	scene.free()
	ProjectSettings.set_setting("ember/pack_path", ProjectSettings.globalize_path(str(_state.directory).path_join("absent-pack")))
	scene = (saved.scene as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	map = scene.get_node("Map") as EmberMapLoader
	if map.find_region("entry").kind != "player_start" or map.find_region("chest").prompt() != "Сундук уже открыт": errors.append("native reopen without JOI lost region/progress")
	scene.free()
	await _check_empty_scene(errors)
	Fixture.verify(_state, saved, errors)
	if not _state.progress_isolated: errors.append("autoload was not isolated before ready")
	if not errors.is_empty():
		printerr("FAIL native map startup: ", "; ".join(errors))
		quit(1)
		return
	print("PASS native map startup; poison/absent JSON, nested regions, footprint, chest progress, empty scene without reimport")
	quit(0)

func _check_empty_scene(errors: Array[String]) -> void:
	ProjectSettings.set_setting("ember/pack_path", _state.pack)
	var scene := Node3D.new()
	scene.set_script(Fixture.Maps.ExploreScene)
	scene.set("map_id", "empty_startup_fixture")
	var map := EmptyMap.new()
	map.name = "Map"
	map.map_id = "empty_startup_fixture"
	scene.add_child(map)
	var layer := CanvasLayer.new()
	layer.name = "CanvasLayer"
	scene.add_child(layer)
	var label := Label.new()
	label.name = "Gate"
	layer.add_child(label)
	root.add_child(scene)
	await process_frame
	if map.reimports != 0 or map.has_authored_content(): errors.append("empty native scene attempted automatic legacy reimport")
	scene.free()
