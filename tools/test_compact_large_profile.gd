extends SceneTree
## Disposable 16x-area terrain profile. The authored beach is never modified.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const SOURCE := "res://content/terrain_pilot/beach_region.res"
const DRAFT := "user://compact_large_profile.res"
const REPEAT := 4


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var beach := load(SOURCE) as TerrainResource
	assert(beach != null and beach.validation_errors().is_empty())
	var large := _repeat(beach, REPEAT)
	assert(large.validation_errors().is_empty())
	var started := Time.get_ticks_msec()
	assert(ResourceSaver.save(large, DRAFT) == OK)
	var save_ms := Time.get_ticks_msec() - started
	var file := FileAccess.open(DRAFT, FileAccess.READ)
	var source_bytes := file.get_length()
	file.close()
	large = null
	started = Time.get_ticks_msec()
	var reopened := ResourceLoader.load(DRAFT, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	var load_ms := Time.get_ticks_msec() - started
	assert(reopened != null and reopened.validation_errors().is_empty())
	var map := EmberMapLoader.new()
	map.map_id = "compact_large_profile"
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i(reopened.width / 16, reopened.depth / 16)
	map.compact_terrain = reopened
	root.add_child(map)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	assert(projection != null and map.resolved_visual_surface() == null)
	while projection.pending_tile_count() > 0:
		await process_frame
	var first_tile_ms := projection.first_tile_ms
	var all_tiles_ms := projection.all_tiles_ms
	var tiles := projection.built_tile_count()
	var undo := UndoRedo.new()
	var entry := {"target": weakref(map), "resource": reopened.working_copy()}
	var brush := Brush.new()
	brush.configure(entry, undo, map)
	var baseline: PackedInt32Array = entry.resource.heights.duplicate()
	started = Time.get_ticks_usec()
	assert(brush.begin("generator", 4.0, 8, 2, 0, 16, 3, 371, 0))
	var begin_us := Time.get_ticks_usec() - started
	var center := Vector2i(reopened.width / 2, reopened.depth / 2)
	started = Time.get_ticks_usec()
	brush.stamp(center)
	var first_stamp_us := Time.get_ticks_usec() - started
	var worst_move_us := 0
	var total_move_us := 0
	for step in 16:
		started = Time.get_ticks_usec()
		brush.stamp(center + Vector2i((step + 1) * 8, 0))
		var elapsed := Time.get_ticks_usec() - started
		worst_move_us = maxi(worst_move_us, elapsed)
		total_move_us += elapsed
		await process_frame
	brush.end()
	var after: PackedInt32Array = entry.resource.heights.duplicate()
	assert(after != baseline)
	while projection.pending_tile_count() > 0:
		await process_frame
	undo.undo()
	assert(entry.resource.heights == baseline)
	while projection.pending_tile_count() > 0:
		await process_frame
	undo.redo()
	assert(entry.resource.heights == after)
	while projection.pending_tile_count() > 0:
		await process_frame
	print("COMPACT_LARGE_PROFILE source=", reopened.width, "x", reopened.depth,
		" tiles=", tiles, " bytes=", source_bytes, " save_ms=", save_ms,
		" load_ms=", load_ms, " first_tile_ms=", first_tile_ms,
		" all_tiles_ms=", all_tiles_ms, " brush_begin_us=", begin_us,
		" first_stamp_us=", first_stamp_us, " worst_move_us=", worst_move_us,
		" total_move_us=", total_move_us, " undo_redo=ok")
	undo.clear_history()
	undo.free()
	map.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DRAFT))
	quit()


func _repeat(source: TerrainResource, count: int) -> TerrainResource:
	var result := TerrainResource.new()
	result.width = source.width * count
	result.depth = source.depth * count
	result.height_limit = source.height_limit
	result.origin_y = source.origin_y
	result.palette = source.palette.duplicate()
	var columns := result.width * result.depth
	result.heights.resize(columns)
	result.top_materials.resize(columns)
	result.base_materials.resize(columns)
	result.cap_depths.resize(columns)
	result.water_levels.resize(columns)
	result.water_materials.resize(columns)
	for z in result.depth:
		for x in result.width:
			var to_index := x + z * result.width
			var from_index := (x % source.width) + (z % source.depth) * source.width
			result.heights[to_index] = source.heights[from_index]
			result.top_materials[to_index] = source.top_materials[from_index]
			result.base_materials[to_index] = source.base_materials[from_index]
			result.cap_depths[to_index] = source.cap_depths[from_index]
			result.water_levels[to_index] = source.water_levels[from_index]
			result.water_materials[to_index] = source.water_materials[from_index]
			if source.column_material_overrides.has(from_index):
				result.column_material_overrides[to_index] = (source.column_material_overrides[from_index] as Dictionary).duplicate(true)
	return result
