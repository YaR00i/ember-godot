extends SceneTree

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const SCENE := "res://scenes/large_landscape_test.tscn"
const DRAFT := "user://large_landscape_test_draft.res"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := ResourceLoader.load(SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	assert(packed != null)
	var authored := packed.instantiate()
	var saved_map := authored.get_node("Map") as EmberMapLoader
	assert(saved_map != null and saved_map.authored_size_blocks == Vector2i(96, 96))
	assert(saved_map.visual_surface == null and saved_map.compact_terrain != null)
	var source: TerrainResource = saved_map.compact_terrain
	assert(source.width == 1536 and source.depth == 1536 and source.validation_errors().is_empty())
	authored.free()
	var map := EmberMapLoader.new()
	map.map_id = "large_landscape_test_diagnostic"
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i(96, 96)
	map.compact_terrain = source
	root.add_child(map)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	assert(projection != null)
	while projection.pending_tile_count() > 0:
		await process_frame
	assert(projection.built_tile_count() == 576)
	var draft := source.working_copy()
	var entry := {"target": weakref(map), "resource": draft}
	var undo := UndoRedo.new()
	var brush := Brush.new()
	brush.configure(entry, undo, map)
	var center := Vector2i(768, 768)
	var center_index := draft.column_index(center.x, center.y)
	var original_height := draft.heights[center_index]
	var started := Time.get_ticks_usec()
	assert(brush.begin("raise", 2.0, 4, 2, 0, 16, 0, 1, 0, -99999, "coarse"))
	var raise_begin_us := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	brush.stamp(center)
	var raise_stamp_us := Time.get_ticks_usec() - started
	brush.end()
	assert(draft.heights[center_index] > original_height)
	assert(brush.begin("water", 2.0, 4, 5, 24, 16, 0, 1, 0, -99999, "coarse"))
	brush.stamp(center)
	brush.end()
	assert(draft.water_levels[center_index] > draft.heights[center_index])
	var water_tile: Dictionary = MeshBuilder.build_tile(draft, 12 * 64, 12 * 64, 64)
	assert((water_tile.water as ArrayMesh).get_surface_count() > 0)
	assert(ResourceSaver.save(draft, DRAFT) == OK)
	var reopened := ResourceLoader.load(DRAFT, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	assert(reopened != null and reopened.validation_errors().is_empty())
	assert(reopened.heights[center_index] == draft.heights[center_index])
	assert(reopened.water_levels[center_index] == draft.water_levels[center_index])
	undo.undo()
	assert(draft.water_levels[center_index] == 0)
	undo.undo()
	assert(draft.heights[center_index] == original_height)
	undo.redo()
	undo.redo()
	assert(draft.water_levels[center_index] > draft.heights[center_index])
	print("LARGE_LANDSCAPE_TEST tiles=", projection.built_tile_count(), " first_tile_ms=", projection.first_tile_ms, " all_tiles_ms=", projection.all_tiles_ms, " raise_begin_us=", raise_begin_us, " raise_stamp_us=", raise_stamp_us, " relief_water_undo_save=ok")
	undo.clear_history()
	undo.free()
	map.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DRAFT))
	quit()
