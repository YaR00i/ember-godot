extends SceneTree

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const TerrainMath = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
const Generation = preload("res://addons/ember_import/ember_compact_terrain_generation.gd")
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Extension = preload("res://addons/ember_import/ember_compact_map_extension.gd")
const Editor = preload("res://addons/ember_import/ember_world_editor.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Preview = preload("res://addons/ember_import/ember_compact_map_extension_preview.gd")
const FILE := "user://ember-tests/terrain-generation/terrain.res"
const SCENE := "user://ember-tests/terrain-generation/map.tscn"


func _initialize() -> void:
	_run.call_deferred()


func generate(source: Terrain, bounds: Rect2i, parameters: Dictionary, budget := 4000) -> RefCounted:
	var job := Generation.new()
	assert(job.begin(source, bounds, parameters), job.error)
	var count := 0
	while not job.finished:
		job.step(budget)
		count += 1
		assert(count < 10000, "generation did not finish")
	assert(job.candidate.validation_errors().is_empty())
	return job


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FILE.get_base_dir()))
	var creation := Creation.new()
	creation.scene_directory = FILE.get_base_dir()
	creation.terrain_directory = FILE.get_base_dir()
	assert(creation.prepare_sections("generator_fixture", 2, 2, 12))
	var initial: Terrain = creation.source.sectioned_copy()
	var snapshot := initial.working_copy()
	var params := TerrainMath.DEFAULTS.duplicate(true)
	var times := {}
	var outputs := {}
	for profile in TerrainMath.PROFILES:
		params.profile = profile
		var job := generate(initial, Rect2i(0, 0, 48, 48), params)
		times[profile] = {"calculate_ms": job.elapsed_us / 1000.0, "worst_step_ms": job.worst_step_us / 1000.0}
		outputs[profile] = job.candidate
		assert(initial.same_terrain_data(snapshot), "generation mutated its input")
		assert(job.candidate.height_limit > initial.height_limit)
		var center: int = job.candidate.column_index(384, 384)
		assert(job.candidate.column_value("heights", center) > 12 * 16 / 2, "no raised center")
		assert(job.candidate.column_value("water_levels", job.candidate.column_index(0, 0)) == 32, "full-map boundary retained a land ring")
		var repeat := generate(initial, Rect2i(0, 0, 48, 48), params, 900)
		assert(repeat.candidate.same_terrain_data(job.candidate), "result depends on work budget")
	assert(not outputs.hills.same_terrain_data(outputs.ridges))
	assert(not outputs.ridges.same_terrain_data(outputs.eroded))
	params.profile = "hills"
	params.seed += 1
	var variant := generate(initial, Rect2i(0, 0, 48, 48), params)
	assert(not outputs.hills.same_terrain_data(variant.candidate))
	var interrupted := Generation.new()
	assert(interrupted.begin(initial, Rect2i(0, 0, 48, 48), params))
	interrupted.step(1000)
	interrupted.cancel()
	assert(interrupted.candidate == null and initial.same_terrain_data(snapshot))
	assert(interrupted._heights.is_empty() and interrupted.before == null)
	assert(interrupted.begin(initial, Rect2i(0, 0, 24, 24), params))
	while not interrupted.finished: interrupted.step()
	assert(interrupted.candidate.validation_errors().is_empty())
	var bad_repeat := params.duplicate(true)
	bad_repeat.feature_m = NAN
	assert(not interrupted.begin(initial, Rect2i(0, 0, 24, 24), bad_repeat) and interrupted.candidate == null)
	var invalid := Generation.new()
	params.feature_m = NAN
	assert(not invalid.begin(initial, Rect2i(0, 0, 48, 48), params))
	params = TerrainMath.DEFAULTS.duplicate(true)
	assert(not invalid.begin(initial, Rect2i(0, 0, 97, 48), params))
	var sparse := Extension.at_address(initial, Vector2i(3, 0))
	assert(not invalid.begin(sparse, Rect2i(0, 0, 96, 24), params))
	var legacy_snapshot := creation.source.working_copy()
	var legacy_result := generate(creation.source, Rect2i(8, 8, 8, 8), params)
	assert(legacy_result.candidate.is_sectioned() and creation.source.same_terrain_data(legacy_snapshot))
	var unclassified := initial.working_copy()
	unclassified.palette_surface_roles = PackedStringArray()
	assert(not invalid.begin(unclassified, Rect2i(0, 0, 24, 24), params))
	var large_creation := Creation.new()
	large_creation.scene_directory = FILE.get_base_dir()
	large_creation.terrain_directory = FILE.get_base_dir()
	assert(large_creation.prepare_sections("large_generator_fixture", 4, 4, 12))
	var large_source: Terrain = large_creation.source.sectioned_copy()
	params.profile = "eroded"
	params.relief_m = 24.0
	var large_started := Time.get_ticks_usec()
	var large_result := generate(large_source, Rect2i(0, 0, 96, 96), params)
	times["96m"] = {"prepare_and_calculate_ms": (Time.get_ticks_usec() - large_started) / 1000.0,
		"calculate_ms": large_result.elapsed_us / 1000.0, "worst_step_ms": large_result.worst_step_us / 1000.0}
	assert(large_result.candidate.height_limit == 448)
	assert(large_source.height_limit == 128 and large_result.candidate.sections.size() == 16)
	assert(large_result.worst_step_us < 20000, "calculation cannot be sliced into editor frames")
	params = TerrainMath.DEFAULTS.duplicate(true)
	var partial := generate(sparse, Rect2i(8, 8, 24, 24), params)
	assert(partial.candidate.sections[Vector2i(3, 0)].same_terrain_geometry(sparse.sections[Vector2i(3, 0)], true))
	for point in [Vector2i(0, 0), Vector2i(127, 180), Vector2i(512, 180), Vector2i(250, 600), Vector2i(1400, 20)]:
		for channel in Terrain.Sections.CHANNELS:
			assert(partial.candidate.column_value(channel, partial.candidate.column_index(point.x, point.y)) == sparse.column_value(channel, sparse.column_index(point.x, point.y)), "outside selection changed")
	# First coarse group at a boundary adjoining existing terrain is exact.
	for channel in Terrain.Sections.CHANNELS:
		assert(partial.candidate.column_value(channel, partial.candidate.column_index(128, 200)) == sparse.column_value(channel, sparse.column_index(128, 200)))
	var frame := Node3D.new()
	frame.scene_file_path = SCENE
	root.add_child(frame)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = "generator_fixture"
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i(48, 48)
	assert(ResourceSaver.save(initial, FILE) == OK)
	map.compact_terrain = ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain
	frame.add_child(map)
	map.owner = frame
	var editor := Editor.new()
	root.add_child(editor)
	editor.scene = frame
	editor.sessions.recovery_directory = FILE.get_base_dir().path_join("recovery")
	var history := UndoRedo.new()
	editor.sessions.configure(history, func() -> int:
		var packed := PackedScene.new()
		var result := packed.pack(frame)
		return ResourceSaver.save(packed, SCENE) if result == OK else result)
	var draft := editor.sessions.open_map(map, frame)
	var before: Terrain = draft.resource
	assert(editor.commit_terrain_generation(map, draft, before.working_copy(), outputs.hills).is_empty())
	assert(editor.sessions.dirty(draft))
	history.undo()
	assert(draft.resource.same_terrain_data(initial))
	history.redo()
	assert(draft.resource.same_terrain_data(outputs.hills))
	# A stale preview must not replace a later brush operation.
	assert(not editor.commit_terrain_generation(map, draft, before.working_copy(), outputs.eroded).is_empty())
	assert(editor.sessions.save_all(frame), editor.sessions.error)
	var reopened := ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain
	assert(reopened.same_terrain_data(outputs.hills))
	assert((ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene) != null)
	editor.sessions.discard(frame)
	assert(draft.resource.same_terrain_data(reopened))
	var projection := TerrainProjection.new()
	frame.add_child(projection)
	assert(projection.open_document(initial))
	while projection.pending_tile_count() > 0: projection._process(0)
	var untouched: Node = projection._tiles[Vector2i(0, 0)]
	var local_result := generate(initial, Rect2i(24, 24, 24, 24), params)
	assert(projection.open_document(local_result.candidate))
	assert(projection._tiles[Vector2i(0, 0)] == untouched, "height ceiling change rebuilt untouched terrain")
	while projection.pending_tile_count() > 0: projection._process(0)
	assert(projection.open_document(outputs.hills))
	while projection.pending_tile_count() > 0: projection._process(0)
	for point in [Vector3(384, 1000, 384), Vector3(380, 1000, 256), Vector3(388, 1000, 256)]:
		var floor_sample: Dictionary = projection.floor_surface_sample(point)
		assert(floor_sample.solid and is_finite(floor_sample.position.y))
		assert(absf(floor_sample.position.y - outputs.hills.column_value("heights", outputs.hills.column_index(floori(point.x), floori(point.z)))) < 0.01)
	assert(projection._build_navigation_grid().heights.size() == 48 * 48)
	map._visual_surface_projection = projection
	var regions := Node3D.new()
	regions.name = "Regions"
	map.add_child(regions)
	var entry_marker := EmberRegion.new()
	entry_marker.kind = "player_start"
	entry_marker.position = Vector3(384, 12, 384)
	regions.add_child(entry_marker)
	var marker_position := entry_marker.position
	var safe_entry := map.spawn_world()
	assert(safe_entry.y == projection.floor_surface_sample(safe_entry).position.y)
	assert(entry_marker.position == marker_position, "runtime entry resolution moved the authored marker")
	assert(map.safe_spawn_world(Vector3(384, -10, 384)).y == safe_entry.y, "saved entry remained below raised terrain")
	entry_marker.position.y = 1000
	assert(map.spawn_world().y == 1000, "an intentionally elevated entry was lowered")
	# Preview parity and cancel restoration use the shared tile mesher.
	var preview := Preview.new()
	map.add_child(preview)
	assert(preview.show_area(map, outputs.eroded, Rect2i(0, 0, 768, 768)))
	while not preview._pending.is_empty(): preview._process(0)
	var expected := MeshBuilder.build_tile(outputs.eroded, 384, 384, 64, projection.water_mesh_step, projection.water_volume_sides)
	var shown := preview.get_node("PreviewTile_6_6").get_child(0, true) as MeshInstance3D
	assert(shown.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == expected.terrain.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	preview.clear_preview()
	for key in projection._tiles: assert(projection._tiles[key].visible)
	preview.free()
	map._visual_surface_projection = null
	history.clear_history()
	editor.sessions.release()
	editor.free()
	history.free()
	frame.free()
	print("TERRAIN_GENERATION PASS deterministic/profiles/seed/cancel/validation/bounds/blend/Undo-Redo/stale/Save-Reopen/Discard/physics/navigation/preview-parity ", times)
	quit()
