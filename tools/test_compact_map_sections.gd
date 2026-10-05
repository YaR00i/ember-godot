extends SceneTree

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Extension = preload("res://addons/ember_import/ember_compact_map_extension.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const Editor = preload("res://addons/ember_import/ember_world_editor.gd")
const FILE := "user://ember-tests/addressed-map/source.res"
const SCENE := "user://ember-tests/addressed-map/map.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FILE.get_base_dir()))
	var creation := Creation.new()
	creation.scene_directory = FILE.get_base_dir()
	creation.terrain_directory = FILE.get_base_dir()
	assert(creation.prepare_sections("section_fixture", 2, 2, 12))
	var legacy: Terrain = creation.source
	legacy.top_materials[12] = 4
	legacy.column_material_overrides[12] = {2: 3}
	legacy.water_flow.resize(48 * 48)
	legacy.water_flow[47] = Vector2(0.25, 0.0)
	for z in 32:
		for x in range(legacy.width - 64, legacy.width):
			var i := legacy.column_index(x, z)
			legacy.water_levels[i] = 16
			legacy.water_materials[i] = 5
	assert(legacy.validation_errors().is_empty())
	var initial := legacy.sectioned_copy()
	assert(initial.validation_errors().is_empty())
	assert(initial.sections.size() == 4 and initial.heights.is_empty())
	var roundtrip := initial.dense_window(Rect2i(0, 0, legacy.width, legacy.depth))
	for channel in Terrain.Sections.CHANNELS: assert(roundtrip.get(channel) == legacy.get(channel))
	assert(roundtrip.water_flow == legacy.water_flow)
	assert(roundtrip.column_material_overrides == legacy.column_material_overrides)
	assert(initial.flow_at_cell(legacy.width - 8, 8) == legacy.flow_at_cell(legacy.width - 8, 8))
	var started := Time.get_ticks_usec()
	var enlarged := Extension.expanded(initial, "east", Extension.MODE_FLAT, 0)
	var growth_ms := float(Time.get_ticks_usec() - started) / 1000.0
	assert(enlarged != null and enlarged.validation_errors().is_empty())
	assert(enlarged.sections.size() == 5)
	assert(enlarged.stored_column_count() == 5 * 384 * 384)
	assert(enlarged.has_column(800, 200) and not enlarged.has_column(800, 500))
	assert(enlarged.column_value("water_levels", enlarged.column_index(768, 8)) == 16)
	assert(enlarged.column_value("water_materials", enlarged.column_index(768, 8)) == 5)
	assert(enlarged.column_value("heights", enlarged.column_index(768, 8)) == 12)
	for address: Vector2i in initial.sections: assert(enlarged.sections[address] == initial.sections[address])
	for direction in ["west", "north", "south"]:
		var expanded := Extension.expanded(initial, direction, Extension.MODE_CONTINUE, 0)
		assert(expanded != null and expanded.sections.size() == 5)
		var shifted := Vector2i(384 if direction == "west" else 0, 384 if direction == "north" else 0)
		assert(expanded.column_value("top_materials", expanded.column_index(12 + shifted.x, shifted.y)) == 4)
	var far := Extension.at_address(enlarged, Vector2i(21, 21))
	assert(far != null and far.sections.size() == 6 and far.heights.is_empty())
	assert(far.width == 8448 and far.depth == 8448)
	assert(far.stored_column_count() == 6 * 384 * 384)
	assert(far.tile_keys(64).size() == 216)
	assert(not far.has_column(4000, 4000))
	assert(Extension.at_address(far, Vector2i(21, 21)) == null)
	assert(Extension.at_address(far, Vector2i(22, 0)) == null)
	var missing := far.working_copy()
	missing.sections[Vector2i(20, 21)] = "bad payload"
	assert(not missing.validation_errors().is_empty())
	var dual := far.working_copy()
	dual.heights.append(1)
	assert(not dual.validation_errors().is_empty())
	assert(initial.validation_errors().is_empty() and far.validation_errors().is_empty())
	var frame := Node3D.new()
	frame.scene_file_path = SCENE
	root.add_child(frame)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = "addressed_fixture"
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = Vector2i(48, 48)
	assert(ResourceSaver.save(initial, FILE) == OK)
	map.compact_terrain = ResourceLoader.load(FILE, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain
	frame.add_child(map)
	map.owner = frame
	var sessions := Sessions.new()
	sessions.recovery_directory = FILE.get_base_dir().path_join("recovery")
	var history := UndoRedo.new()
	sessions.configure(history, func() -> int:
		var packed := PackedScene.new()
		var result := packed.pack(frame)
		return ResourceSaver.save(packed, SCENE) if result == OK else result
	)
	var entry := sessions.open_map(map, frame)
	assert(not entry.is_empty(), sessions.error)
	var projection := map._visual_surface_projection as TerrainProjection
	assert(projection != null)
	await _ready_tiles(projection)
	var retained := projection._tiles[Vector2i.ZERO] as Node3D
	var editor := Editor.new()
	editor.sessions = sessions
	var before: Terrain = entry.resource
	var after := Extension.expanded(before, "east", Extension.MODE_FLAT, 0)
	history.create_action("One addressed section", UndoRedo.MERGE_DISABLE)
	history.add_do_method(Callable(editor, "_apply_compact_extension").bind(map, entry, after, Vector2i(72, 48), {}, "east"))
	history.add_undo_method(Callable(editor, "_apply_compact_extension").bind(map, entry, before, Vector2i(48, 48), {}, "east"))
	history.commit_action()
	# Engine.is_editor_hint() is false in this fixture. Native editor preview is
	# checked separately; give its same draft explicitly to the live projection.
	assert(projection.open_document(entry.resource))
	await _ready_tiles(projection)
	assert(projection._tiles[Vector2i.ZERO] == retained)
	assert(projection.built_tile_count() == 180, "built=%d pending=%d source=%d sections=%d editor=%s" % [projection.built_tile_count(), projection.pending_tile_count(), projection.document.width, projection.document.sections.size(), sessions.error])
	assert(not projection._tiles.has(Vector2i(12, 9)))
	assert(not projection.floor_surface_sample(Vector3(800, 30, 500)).solid)
	assert(projection.floor_surface_sample(Vector3(800, 30, 200)).solid)
	assert(projection.water_surface_sample(Vector3(768, 30, 8)).wet)
	assert(not projection.pick_ground_top(Vector3(800, 80, 500), Vector3(800, -20, 500)).has("cell"))
	assert(projection.pick_ground_top(Vector3(800, 80, 200), Vector3(800, -20, 200)).cell == Vector2i(800, 200))
	var brush := Brush.new()
	brush.configure(entry, history, frame)
	var source: Terrain = entry.resource
	var baseline := source.working_copy()
	assert(brush.begin("raise", 1, 4, 2, 0, 16, 1, 9, 0, -99999, "coarse"))
	brush.stamp(Vector2i(766, 200))
	brush.stamp(Vector2i(770, 200))
	brush.end()
	var left := source.column_index(764, 200)
	var right := source.column_index(772, 200)
	assert(source.column_value("heights", left) > 12 and source.column_value("heights", right) > 12)
	assert(baseline.column_value("heights", left) == 12 and baseline.column_value("heights", right) == 12)
	assert(source.validation_errors().is_empty())
	var undo := history
	undo.undo()
	assert(source.column_value("heights", left) == 12 and source.column_value("heights", right) == 12)
	undo.redo()
	assert(source.column_value("heights", right) > 12)
	await _ready_tiles(projection)
	var hit := projection.floor_surface_sample(Vector3(772.5, 80, 200.5))
	assert(hit.position.y == source.column_value("heights", right))
	var query := PhysicsRayQueryParameters3D.create(Vector3(772.5, 80, 200.5), Vector3(772.5, -10, 200.5))
	await physics_frame
	await physics_frame
	var physical := frame.get_world_3d().direct_space_state.intersect_ray(query)
	assert(not physical.is_empty() and is_equal_approx(physical.position.y, hit.position.y))
	var ground_query := projection.navigation_path(Vector3(740, 30, 208), Vector3(800, 30, 208))
	assert(not ground_query.is_empty())
	assert(brush.begin("level", 0.0625, 2, 2, 0, 16, 0, 9, 0, 1))
	brush.stamp(Vector2i(772, 200))
	brush.end()
	assert(source.column_value("heights", right) == 1 and source.column_value("cap_depths", right) == 1)
	assert(source.validation_errors().is_empty())
	undo.undo()
	assert(source.column_value("heights", right) > 12 and source.column_value("cap_depths", right) == 3)
	await _ready_tiles(projection)
	assert(sessions.save_all(frame))
	map.set_editor_terrain_preview(null)
	var packed := PackedScene.new()
	assert(packed.pack(frame) == OK and ResourceSaver.save(packed, SCENE) == OK)
	var reopened_scene := ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := reopened_scene.instantiate() as Node3D
	var runtime_map := reopened.get_node("Map") as EmberMapLoader
	assert(runtime_map.compact_terrain.is_sectioned())
	assert(runtime_map.compact_terrain.sections.size() == 5)
	assert(runtime_map.compact_terrain.column_value("heights", right) == source.column_value("heights", right))
	assert(runtime_map.compact_terrain.palette_material_ids == source.palette_material_ids)
	reopened.free()
	# Discard after a second edit returns to the explicit saved baseline.
	var saved_height := source.column_value("heights", right)
	assert(brush.begin("raise", 1, 4, 2, 0, 16, 1, 9, 0, -99999, "coarse"))
	brush.stamp(Vector2i(772, 200))
	brush.cancel()
	assert(source.column_value("heights", right) == saved_height)
	sessions.discard(frame)
	assert(sessions.dirty_count(frame) == 0)
	assert(map.compact_terrain.column_value("heights", right) == saved_height)
	# Recovery takes an immutable snapshot while further strokes replace payloads.
	entry = sessions.open_map(map, frame)
	brush.configure(entry, history, frame)
	assert(brush.begin("raise", 0.0625, 4, 2, 0, 16, 0, 9, 0))
	brush.stamp(Vector2i(772, 200)); brush.end()
	var recovery_height: int = entry.resource.column_value("heights", right)
	var saved_hash := FileAccess.get_sha256(FILE)
	assert(sessions.start_periodic_recovery())
	assert(brush.begin("raise", 0.0625, 4, 2, 0, 16, 0, 9, 0))
	brush.stamp(Vector2i(772, 200)); brush.end()
	assert(entry.resource.column_value("heights", right) > recovery_height)
	while sessions._recovery_task_id >= 0:
		sessions.poll_recovery()
		await process_frame
	assert(sessions.last_recovery_profile.result == OK)
	assert(sessions.restore_recovery(frame) == 0 and not sessions.error.is_empty())
	sessions.entries.clear()
	assert(sessions.restore_recovery(frame) == 1, sessions.error)
	entry = sessions.open_map(map, frame)
	assert(entry.resource.is_sectioned() and entry.resource.sections.size() == 5)
	assert(entry.resource.column_value("heights", right) == recovery_height)
	assert(FileAccess.get_sha256(FILE) == saved_hash)
	sessions.discard(frame)
	assert(entry.resource.column_value("heights", right) == saved_height)
	history.clear_history()
	history.free()
	editor.free()
	sessions.entries.clear()
	frame.queue_free()
	await process_frame
	# The far envelope needs six sections, not the 484 possible addresses.
	var far_projection := TerrainProjection.new()
	root.add_child(far_projection)
	assert(far_projection.open_document(far))
	assert(far_projection.pending_tile_count() == 216)
	await _ready_tiles(far_projection)
	assert(far_projection.built_tile_count() == 216)
	var far_sample := far_projection.floor_surface_sample(Vector3(8256.5, 80, 8256.5))
	assert(far_sample.solid and far_sample.position.y == 12)
	await physics_frame
	await physics_frame
	var far_ray := PhysicsRayQueryParameters3D.create(Vector3(8256.5, 80, 8256.5), Vector3(8256.5, -10, 8256.5))
	var far_hit := root.world_3d.direct_space_state.intersect_ray(far_ray)
	assert(not far_hit.is_empty() and is_equal_approx(far_hit.position.y, 12))
	assert(not far_projection.navigation_path(Vector3(8256, 20, 8256), Vector3(8304, 20, 8256)).is_empty())
	var recolored := far.working_copy()
	recolored.palette[2] = Color(0.25, 0.4, 0.35)
	assert(far.palette[2] != recolored.palette[2])
	assert(far_projection.open_document(recolored))
	await _ready_tiles(far_projection)
	var color_mesh := far_projection._tiles[Vector2i(127, 127)].get_node("Ground") as MeshInstance3D
	var vertex_colors: PackedColorArray = color_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	# ArrayMesh packs vertex colors to RGBA8; allow only that quantization.
	assert(absf(vertex_colors[0].r - 0.25) <= 1.0 / 255.0 and absf(vertex_colors[0].g - 0.4) <= 1.0 / 255.0, str(vertex_colors[0]))
	far_projection.queue_free()
	await process_frame
	print("PASS addressed sections: legacy channels/flow/side colors, L-shaped edge, 528m sparse envelope, seams/physics/navigation, palette, brush Undo/Redo/cancel, save/reopen/discard/recovery; growth_ms=", growth_ms)
	quit()


func _ready_tiles(projection: TerrainProjection) -> void:
	for i in 4000:
		if projection.pending_tile_count() == 0: return
		await process_frame
	assert(false, "terrain queue did not finish")
