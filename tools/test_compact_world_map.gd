extends SceneTree

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const WorldEditor = preload("res://addons/ember_import/ember_world_editor.gd")
const SOURCE := "res://content/terrain_pilot/beach_region.res"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1200,800)
	var source := load(SOURCE) as TerrainResource
	assert(source != null and source.validation_errors().is_empty())
	var map := EmberMapLoader.new()
	map.map_id = "compact_world_fixture"
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i(source.width / 16, source.depth / 16)
	map.compact_terrain = source
	root.add_child(map)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	assert(projection != null)
	assert(map.resolved_visual_surface() == null)
	while projection.pending_tile_count() > 0:
		await process_frame
	var initial_ready_ms := projection.all_tiles_ms
	var found_ground := false
	var found_water := false
	for z in source.depth:
		for x in source.width:
			var index := source.column_index(x, z)
			if not found_ground and source.heights[index] > 0:
				var point := Vector3(x + 0.5, 0, z + 0.5)
				var sample := map.surface_floor_sample(point)
				assert(sample.solid)
				assert(is_equal_approx(sample.position.y, float(source.origin_y + source.heights[index])))
				found_ground = true
			if not found_water and source.water_levels[index] > source.heights[index] and source.water_materials[index] > 0:
				var point := Vector3(x + 0.5, 0, z + 0.5)
				var water := projection.water_surface_sample(point)
				assert(water.wet)
				assert(is_equal_approx(water.position.y, float(source.origin_y + source.water_levels[index]) + 0.085))
				found_water = true
			if found_ground and found_water:
				break
		if found_ground and found_water:
			break
	assert(found_ground and found_water)
	var landscape_pack := load("res://scenes/landscape_compact.tscn") as PackedScene
	assert(landscape_pack != null)
	var landscape := landscape_pack.instantiate()
	var landscape_map := landscape.get_node("Map") as EmberMapLoader
	assert(landscape_map != null and landscape_map.compact_terrain != null)
	assert(landscape_map.visual_surface == null)
	assert(landscape_map.compact_terrain.resource_path == "res://content/world_terrains/landscape_compact.res")
	landscape.free()
	var sessions := Sessions.new()
	var undo := UndoRedo.new()
	sessions.configure(undo)
	var entry: Dictionary = sessions.open_map(map, map)
	assert(entry.get("compact", false))
	var brush := Brush.new()
	brush.configure(entry, undo, map)
	var sample_index := source.column_index(80, 80)
	var original_height := source.heights[sample_index]
	var probe_top := projection.to_global(Vector3(80.5, source.origin_y + original_height + 20, 80.5))
	var probe_bottom := projection.to_global(Vector3(80.5, source.origin_y, 80.5))
	var before_hover := projection.pick_ground_top(probe_top, probe_bottom)
	assert(before_hover.get("cell") == Vector2i(80, 80))
	assert(is_equal_approx(before_hover.world.y, float(source.origin_y + original_height)))
	assert(brush.begin("raise", 0.0625, 4, 2, 0, 16, 0, 1, 0))
	brush.stamp(Vector2i(80, 80))
	var live_hover := projection.pick_ground_top(probe_top, probe_bottom)
	assert(live_hover.get("cell") == Vector2i(80, 80))
	assert(is_equal_approx(live_hover.world.y, float(source.origin_y + entry.resource.heights[sample_index])))
	var wall_y := float(source.origin_y + entry.resource.heights[sample_index] - 1)
	var side_hover := projection.pick_ground_top(projection.to_global(Vector3(79.5, wall_y, 80.5)), projection.to_global(Vector3(80.5, wall_y, 80.5)))
	assert(side_hover.get("cell") == Vector2i(80, 80))
	assert(projection.pending_tile_count() > 0)
	brush.end()
	assert(entry.resource.heights[sample_index] > original_height)
	assert(sessions.dirty(entry))
	var other_entry := {"target":weakref(map),"resource":source.working_copy()}
	brush.configure(other_entry,undo,map)
	undo.undo()
	assert(entry.resource.heights[sample_index] == original_height)
	assert(other_entry.resource.heights[sample_index] == original_height)
	brush.configure(entry,undo,map)
	undo.redo()
	assert(entry.resource.heights[sample_index] > original_height)
	sessions.discard(map)
	assert(not sessions.dirty(entry))
	undo.clear_history()
	undo.free()
	var large_undo := UndoRedo.new()
	var large_sessions := Sessions.new()
	large_sessions.configure(large_undo)
	var large_entry := large_sessions.open_map(map,map)
	var large_brush := Brush.new()
	large_brush.configure(large_entry,large_undo,map)
	var brush_started := Time.get_ticks_msec()
	assert(large_brush.begin("generator",8.0,8,2,0,16,3,371,0))
	large_brush.stamp(Vector2i(192,200))
	var input_ms := Time.get_ticks_msec() - brush_started
	large_brush.end()
	while projection.pending_tile_count() > 0: await process_frame
	var visible_ms := Time.get_ticks_msec() - brush_started
	large_sessions.discard(map)
	large_undo.clear_history()
	large_undo.free()
	var built_tiles := projection.built_tile_count()
	map.queue_free()
	await process_frame
	if not await _save_roundtrip(source):
		printerr("COMPACT_WORLD_MAP save roundtrip failed")
		quit(1)
		return
	print("COMPACT_WORLD_MAP surface=single ground=ok water=ok tiles=", built_tiles, " initial_ready_ms=", initial_ready_ms, " big_brush_input_ms=", input_ms, " big_brush_all_tiles_ms=", visible_ms)
	quit()


func _save_roundtrip(source: TerrainResource) -> bool:
	var terrain_path := "user://compact_world_map_source.res"
	var scene_path := "user://compact_world_map_scene.tscn"
	if ResourceSaver.save(source.working_copy(),terrain_path) != OK:
		return false
	var initial := Node3D.new()
	initial.name = "CompactWorldFixture"
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = "compact_world_fixture"
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i(source.width / 16,source.depth / 16)
	map.compact_terrain = ResourceLoader.load(terrain_path) as TerrainResource
	initial.add_child(map)
	map.owner = initial
	var packed := PackedScene.new()
	if packed.pack(initial) != OK or ResourceSaver.save(packed,scene_path) != OK:
		initial.free()
		return false
	initial.free()
	var reopened := (ResourceLoader.load(scene_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(reopened)
	map = reopened.get_node("Map") as EmberMapLoader
	if map == null or map.compact_terrain == null or map.visual_surface != null:
		return false
	var undo := UndoRedo.new()
	var editor := WorldEditor.new()
	reopened.add_child(editor)
	editor.configure(null,undo)
	editor.build_toolbar()
	editor.build_sidebar()
	editor.scene = reopened
	editor.map = map
	editor._target_changed(0)
	if not editor._compact_active() or editor.radius.min_value != 0.5 or editor._mode() != "raise":
		return false
	editor._category_changed(2)
	if editor._mode() != "water": return false
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	while projection.pending_tile_count() > 0: await process_frame
	var camera := Camera3D.new()
	reopened.add_child(camera)
	var look := Vector3(80.5,float(source.origin_y+source.heights[source.column_index(80,80)]),80.5)
	camera.position = look + Vector3(0,130,130)
	camera.look_at(look)
	camera.current = true
	await process_frame
	editor.camera = camera
	if editor._pick_compact(Vector2(600,400)).is_empty(): return false
	editor._category_changed(0)
	editor.active = true
	assert(editor._compact_trace.start_brush_recording({"map_id": "hover_input_fixture"}, root, projection))
	var hover_event := InputEventMouseMotion.new()
	hover_event.position = Vector2(600, 400)
	editor.forward_input(camera, hover_event)
	var hover_trace: Dictionary = editor._compact_trace.stop_brush_recording()
	if hover_trace.hovers.size() != 1 or not hover_trace.strokes.is_empty() or not hover_trace.hovers[0].grid.has("sync_usec"):
		printerr("COMPACT_WORLD_MAP hover trace did not capture the live input path")
		return false
	var stroke_cell: Vector2i = editor._pick_compact(Vector2(600,400)).cell
	editor.hover = {"cell": stroke_cell}
	editor.radius.value = 0.5
	editor._update_overlay()
	var small_grid_width := editor._compact_grid_visible_bounds().size.x
	editor.radius.value = 4.0
	editor._update_overlay()
	var large_grid_width := editor._compact_grid_visible_bounds().size.x
	if large_grid_width <= small_grid_width + 32.0:
		printerr("COMPACT_WORLD_MAP grid does not follow brush radius: ", small_grid_width, " -> ", large_grid_width)
		return false
	editor.radius.value = 0.5
	editor._update_overlay()
	if not is_equal_approx(editor._compact_grid_visible_bounds().size.x, small_grid_width):
		printerr("COMPACT_WORLD_MAP grid did not shrink with brush radius")
		return false
	print("COMPACT_GRID_RADIUS small_width=", small_grid_width, " large_width=", large_grid_width)
	var warm_tile_key := Vector2i(stroke_cell.x / EmberTerrainPilotProjection.TILE_SIZE, stroke_cell.y / EmberTerrainPilotProjection.TILE_SIZE)
	var warm_ground := projection.get_node("TerrainTile_%d_%d/Ground" % [warm_tile_key.x, warm_tile_key.y]) as MeshInstance3D
	if warm_ground == null or warm_ground.material_overlay != editor._compact_grid_material: return false
	var warm_mesh := warm_ground.mesh
	editor.hover = {"cell": Vector2i(source.width - 24, source.depth - 24)}
	editor._update_overlay()
	editor.hover = {"cell": stroke_cell}
	editor._update_overlay()
	if warm_ground.material_overlay != editor._compact_grid_material or warm_ground.mesh != warm_mesh:
		printerr("COMPACT_WORLD_MAP nearby return rebuilt unchanged terrain")
		return false
	var stroke_index: int = entry_index_for_cell(map.compact_terrain, stroke_cell)
	var stroke_before: int = editor.entry.resource.heights[stroke_index]
	var hover_tile_key := Vector2i(stroke_cell.x / EmberTerrainPilotProjection.TILE_SIZE, stroke_cell.y / EmberTerrainPilotProjection.TILE_SIZE)
	var hover_ground := projection.get_node("TerrainTile_%d_%d/Ground" % [hover_tile_key.x, hover_tile_key.y]) as MeshInstance3D
	var hover_mesh_before := hover_ground.mesh
	var hover_revision_before := projection.tile_revision(hover_tile_key)
	var press := InputEventMouseButton.new()
	press.position = Vector2(600,400)
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.position = press.position
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	editor.forward_input(camera, press)
	editor.forward_input(camera, release)
	if editor.entry.resource.heights[stroke_index] <= stroke_before:
		printerr("COMPACT_WORLD_MAP click did not change terrain height")
		return false
	editor._update_overlay()
	while projection.pending_tile_count() > 0: await process_frame
	if projection.tile_revision(hover_tile_key) <= hover_revision_before or hover_ground.mesh == hover_mesh_before or hover_ground.material_overlay != editor._compact_grid_material:
		printerr("COMPACT_WORLD_MAP ground mesh or shader overlay did not refresh after terrain edit")
		return false
	editor.sessions.discard(reopened)
	editor.terrain_edit_scale.select(2)
	editor.brush_shape.select(1)
	editor._refresh_brush_scale_settings()
	editor._tool_changed()
	editor.tools.select(4)
	editor._tool_changed()
	editor.radius.value = 4.0
	editor.depth.value = 8.0
	editor.compact_detail.value = 3.0
	press.position = Vector2(600,400)
	release.position = Vector2(760,400)
	editor.forward_input(camera, press)
	if not editor.dragging or not editor._compact_brush.active():
		printerr("COMPACT_EDITOR_DRAG did not start")
		return false
	var worst_move_us := 0
	var total_move_us := 0
	for move_index in 16:
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(610 + move_index * 10,400)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		var move_started := Time.get_ticks_usec()
		editor.forward_input(camera, motion)
		var move_us := Time.get_ticks_usec() - move_started
		worst_move_us = maxi(worst_move_us, move_us)
		total_move_us += move_us
		await process_frame
	editor.forward_input(camera, release)
	if not editor.sessions.dirty(editor.entry):
		printerr("COMPACT_EDITOR_DRAG did not change terrain")
		return false
	print("COMPACT_EDITOR_DRAG radius=4 generator_detail=3 moves=16 worst_move_us=", worst_move_us, " total_move_us=", total_move_us)
	while projection.pending_tile_count() > 0: await process_frame
	editor.sessions.discard(reopened)
	editor.active = false
	camera.free()
	editor.toolbar.free()
	editor.sidebar.free()
	editor.queue_free()
	await process_frame
	var sessions := Sessions.new()
	sessions.recovery_directory = "user://compact_world_map_test_recovery"
	sessions.configure(undo,func() -> int:
		var repacked := PackedScene.new()
		var packed_error := repacked.pack(reopened)
		return ResourceSaver.save(repacked,scene_path) if packed_error == OK else packed_error
	)
	var entry := sessions.open_map(map,reopened)
	var brush := Brush.new()
	brush.configure(entry,undo,reopened)
	var index := source.column_index(80,80)
	var original: int = entry.resource.heights[index]
	if not brush.begin("raise",0.0625,2,2,0,16,0,1,0): return false
	brush.stamp(Vector2i(80,80))
	brush.end()
	if not sessions.save_all(reopened):
		push_error(sessions.error)
		return false
	if sessions.dirty(entry): return false
	var saved := ResourceLoader.load(terrain_path,"",ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	var okay := saved != null and saved.heights[index] > original
	if not okay: return false
	var saved_hash := FileAccess.get_sha256(terrain_path)
	if not brush.begin("lower",0.0625,2,2,0,16,0,1,0): return false
	brush.stamp(Vector2i(80,80))
	brush.end()
	sessions.save_scene = func() -> int: return ERR_CANT_CREATE
	if sessions.save_all(reopened): return false
	if FileAccess.get_sha256(terrain_path) != saved_hash or not sessions.dirty(entry): return false
	sessions.discard(reopened)
	if sessions.dirty(entry): return false
	undo.clear_history()
	undo.free()
	reopened.queue_free()
	return okay


func entry_index_for_cell(source: TerrainResource, cell: Vector2i) -> int:
	return source.column_index(cell.x, cell.y)
