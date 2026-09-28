@tool
class_name EmberTerrainPilotProjection
extends Node3D
## Temporary single-path terrain projection: this node runs unchanged in the
## editor viewport and in the playable pilot scene.

signal all_tiles_ready

const TILE_SIZE := 64
const REPEAT_EDIT_BUILD_INTERVAL_US := 50000
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const SurfacePhysics = preload("res://scripts/ember_voxel_surface_physics.gd")

@export var source: TerrainResource
@export var camera_anchor := Vector2i(192, 200)
var document: TerrainResource
var first_tile_ms := -1
var all_tiles_ms := -1
var _started_ms := 0
var _last_process_started_us := 0
var _tiles: Dictionary = {}
var _pending: Array[Vector2i] = []
var _pending_flags := PackedByteArray()
var _pending_edit_flags := PackedByteArray()
var _pending_since_us := PackedInt64Array()
var _last_edit_build_us := PackedInt64Array()
var _pending_tile_columns := 0
var _pending_tile_rows := 0
var _pending_needs_sort := false
var _repeat_edit_build_interval_us := REPEAT_EDIT_BUILD_INTERVAL_US
var _live_brush_active := false
var _tile_revisions := PackedInt32Array()
var _ground_material: Material
var _water_material: Material
var _water_hidden := false
var _water_revision := 0
var _navigation_grid := {}
var _column_revision := 0
var _editor_hidden_edge_keys := {}
var _editor_hover_overlay: Material
var _editor_hover_tiles := {}
var _profile: Dictionary = {}


func _ready() -> void:
	_ground_material = Materials.opaque_material()
	_water_material = Materials.water_material().duplicate() as Material
	(_water_material as ShaderMaterial).set_shader_parameter("coordinate_scale", float(TerrainResource.CELLS_PER_BLOCK))
	if source != null:
		open_document(source)


func open_document(next_source: TerrainResource) -> bool:
	if next_source == null:
		return false
	var stage_started := Time.get_ticks_usec()
	# Entering edit mode and opening the extension dialog can hand us a fresh
	# draft with identical terrain data. Keep the live tiles and pending edits.
	if document != null and document.same_terrain_data(next_source):
		source = next_source
		return true
	var compare_us := Time.get_ticks_usec() - stage_started
	_profile_reset("open")
	_profile["compare_us"] = compare_us
	stage_started = Time.get_ticks_usec()
	if not next_source.validation_errors().is_empty():
		return false
	_profile["validation_us"] = Time.get_ticks_usec() - stage_started
	for tile in _tiles.values():
		var old_tile := tile as Node3D
		remove_child(old_tile)
		old_tile.queue_free()
	_tiles.clear()
	_editor_hidden_edge_keys.clear()
	_pending.clear()
	source = next_source
	stage_started = Time.get_ticks_usec()
	document = next_source.working_copy()
	_profile["copy_us"] = Time.get_ticks_usec() - stage_started
	_reset_pending_flags()
	_column_revision += 1
	_reset_tile_revisions()
	_navigation_grid.clear()
	_water_revision += 1
	_started_ms = Time.get_ticks_msec()
	_last_process_started_us = 0
	first_tile_ms = -1
	all_tiles_ms = -1
	_profile["focused_on_open"] = DisplayServer.window_is_focused()
	_profile["sleep_us_on_open"] = OS.low_processor_usage_mode_sleep_usec
	stage_started = Time.get_ticks_usec()
	for z in ceili(float(document.depth) / TILE_SIZE):
		for x in ceili(float(document.width) / TILE_SIZE):
			_queue_tile(Vector2i(x, z), false)
	_prioritize_pending()
	_profile["queue_us"] = Time.get_ticks_usec() - stage_started
	set_process(true)
	return true


func open_resized_document(next_source: TerrainResource, previous_source: TerrainResource, direction: String, section_cells: int) -> bool:
	# A section changes only one edge of the existing Resource. Reuse every
	# interior tile, including its collision, and queue the strip and seam.
	# The extension owner validates the candidate when it is created. Avoid
	# scanning every column again on Apply/Undo; check its shape before reuse.
	if document == null or source != previous_source or not document.same_terrain_data(previous_source) or section_cells <= 0 or section_cells % TILE_SIZE != 0 or direction not in ["west", "east", "north", "south"] or next_source == null:
		return false
	var old_size := Vector2i(document.width, document.depth)
	var new_size := Vector2i(next_source.width, next_source.depth)
	var delta := new_size - old_size
	if (direction in ["west", "east"] and (absi(delta.x) != section_cells or delta.y != 0)) or (direction in ["north", "south"] and (absi(delta.y) != section_cells or delta.x != 0)):
		return false
	var count := next_source.width * next_source.depth
	if next_source.schema_version != TerrainResource.SCHEMA_VERSION or next_source.unsupported_holes != 0 or next_source.origin_y != document.origin_y or next_source.height_limit != document.height_limit or next_source.palette != document.palette:
		return false
	for channel in [next_source.heights, next_source.top_materials, next_source.base_materials, next_source.cap_depths, next_source.water_levels, next_source.water_materials]:
		if channel.size() != count:
			return false
	var growing := delta.x > 0 or delta.y > 0
	var tile_delta := section_cells / TILE_SIZE * (1 if growing else -1)
	var offset := Vector2i(tile_delta if direction == "west" else 0, tile_delta if direction == "north" else 0)
	var new_tile_size := Vector2i(ceili(float(new_size.x) / TILE_SIZE), ceili(float(new_size.y) / TILE_SIZE))
	var kept := {}
	var shifted_pending: Array[Vector2i] = []
	if offset != Vector2i.ZERO:
		for tile in _tiles.values():
			(tile as Node3D).name = "MovingTile_%d" % (tile as Node3D).get_instance_id()
	for key in _tiles:
		var next_key: Vector2i = key + offset
		var tile := _tiles[key] as Node3D
		if next_key.x < 0 or next_key.y < 0 or next_key.x >= new_tile_size.x or next_key.y >= new_tile_size.y:
			remove_child(tile)
			tile.queue_free()
			continue
		tile.position += Vector3(offset.x * TILE_SIZE, 0, offset.y * TILE_SIZE)
		tile.show()
		kept[next_key] = tile
	for key in kept:
		(kept[key] as Node3D).name = "TerrainTile_%d_%d" % [key.x, key.y]
	for key in _pending:
		var next_key: Vector2i = key + offset
		if next_key.x >= 0 and next_key.y >= 0 and next_key.x < new_tile_size.x and next_key.y < new_tile_size.y and next_key not in shifted_pending:
			shifted_pending.append(next_key)
	_tiles = kept
	_pending = shifted_pending
	_editor_hidden_edge_keys.clear()
	source = next_source
	_profile_reset("resize")
	var copy_started := Time.get_ticks_usec()
	document = next_source.working_copy()
	_profile["copy_us"] = Time.get_ticks_usec() - copy_started
	_reset_pending_flags()
	_column_revision += 1
	_reset_tile_revisions()
	_navigation_grid.clear()
	_water_revision += 1
	_started_ms = Time.get_ticks_msec()
	_last_process_started_us = 0
	first_tile_ms = -1
	all_tiles_ms = -1
	_profile["focused_on_open"] = DisplayServer.window_is_focused()
	_profile["sleep_us_on_open"] = OS.low_processor_usage_mode_sleep_usec
	var queue_started := Time.get_ticks_usec()
	for z in new_tile_size.y:
		for x in new_tile_size.x:
			var key := Vector2i(x, z)
			var on_seam := (direction == "west" and x == (section_cells / TILE_SIZE if growing else 0)) or (direction == "east" and x == (old_size.x / TILE_SIZE - 1 if growing else new_tile_size.x - 1)) or (direction == "north" and z == (section_cells / TILE_SIZE if growing else 0)) or (direction == "south" and z == (old_size.y / TILE_SIZE - 1 if growing else new_tile_size.y - 1))
			if not _tiles.has(key) or on_seam:
				_queue_tile(key, false)
	_prioritize_pending()
	_profile["queue_us"] = Time.get_ticks_usec() - queue_started
	set_process(not _pending.is_empty())
	return true


func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	if _last_process_started_us > 0:
		var gap_us := started - _last_process_started_us
		_profile_add("between_process_us", gap_us)
		_profile["max_between_process_us"] = maxi(int(_profile.get("max_between_process_us", 0)), gap_us)
	_last_process_started_us = started
	_profile_add("focused_process_calls" if DisplayServer.window_is_focused() else "unfocused_process_calls", 1)
	_profile["max_sleep_us"] = maxi(int(_profile.get("max_sleep_us", 0)), OS.low_processor_usage_mode_sleep_usec)
	if _pending_needs_sort:
		_prioritize_pending()
	var remaining := _pending.size()
	while remaining > 0 and not _pending.is_empty() and (Time.get_ticks_usec() - started < 4000 or Time.get_ticks_usec() == started):
		var key: Vector2i = _pending.pop_front()
		remaining -= 1
		var index := key.x + key.y * _pending_tile_columns
		var now := Time.get_ticks_usec()
		if _live_brush_active and _pending_edit_flags[index] != 0 and _last_edit_build_us[index] > 0 and now - _last_edit_build_us[index] < _repeat_edit_build_interval_us:
			_pending.append(key)
			_profile_add("deferred_repeat_builds", 1)
			continue
		_pending_flags[index] = 0
		var edited := _pending_edit_flags[index] != 0
		_pending_edit_flags[index] = 0
		_profile["max_pending_age_us"] = maxi(int(_profile.get("max_pending_age_us", 0)), now - _pending_since_us[index])
		_rebuild_tile(key)
		if edited:
			if _last_edit_build_us[index] > 0: _profile_add("repeat_edit_builds", 1)
			_last_edit_build_us[index] = Time.get_ticks_usec()
		if first_tile_ms < 0:
			first_tile_ms = Time.get_ticks_msec() - _started_ms
	if _pending.is_empty():
		if all_tiles_ms < 0:
			all_tiles_ms = Time.get_ticks_msec() - _started_ms
			all_tiles_ready.emit()
			set_process(false)
	var elapsed := Time.get_ticks_usec() - started
	_profile_add("process_us", elapsed)
	_profile_add("process_calls", 1)
	_profile["max_process_us"] = maxi(int(_profile.get("max_process_us", 0)), elapsed)


func _rebuild_tile(key: Vector2i) -> void:
	var tile_started := Time.get_ticks_usec()
	var started := tile_started
	var generated: Dictionary = MeshBuilder.build_tile(document, key.x * TILE_SIZE, key.y * TILE_SIZE, TILE_SIZE)
	_profile_add("mesh_us", Time.get_ticks_usec() - started)
	_profile_add("geometry_us", int(generated.get("geometry_us", 0)))
	_profile_add("top_us", int(generated.get("top_us", 0)))
	_profile_add("side_us", int(generated.get("side_us", 0)))
	_profile_add("water_us", int(generated.get("water_us", 0)))
	_profile_add("uniform_us", int(generated.get("uniform_us", 0)))
	_profile_add("mesh_resource_us", int(generated.get("mesh_resource_us", 0)))
	_profile_add("ground_vertices", (generated["collision_faces"] as PackedVector3Array).size())
	_profile_add("water_vertices", int(generated.get("water_vertices", 0)))
	if bool(generated.get("uniform_dry", false)):
		_profile_add("uniform_dry_tiles", 1)
	if bool(generated.get("grouped_8", false)):
		_profile_add("grouped_8_tiles", 1)
	started = Time.get_ticks_usec()
	var tile := _tiles.get(key) as Node3D
	if tile == null:
		tile = Node3D.new()
		tile.name = "TerrainTile_%d_%d" % [key.x, key.y]
		add_child(tile)
		var ground := MeshInstance3D.new()
		ground.name = "Ground"
		tile.add_child(ground)
		var water := MeshInstance3D.new()
		water.name = "Water"
		tile.add_child(water)
		var body := StaticBody3D.new()
		body.name = "GroundPhysics"
		tile.add_child(body)
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		body.add_child(shape)
		_tiles[key] = tile
		_profile_add("new_tile_nodes", 5)
	_profile_add("node_us", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	tile.position = Vector3.ZERO
	var ground_mesh := generated["terrain"] as ArrayMesh
	if ground_mesh.get_surface_count() > 0:
		ground_mesh.surface_set_material(0, _ground_material)
	(tile.get_node("Ground") as MeshInstance3D).mesh = ground_mesh
	(tile.get_node("Ground") as MeshInstance3D).material_overlay = _editor_hover_overlay if _editor_hover_tiles.has(key) else null
	var water_mesh := generated["water"] as ArrayMesh
	if water_mesh.get_surface_count() > 0:
		water_mesh.surface_set_material(0, _water_material)
	(tile.get_node("Water") as MeshInstance3D).mesh = water_mesh
	(tile.get_node("Water") as MeshInstance3D).visible = not _water_hidden
	_profile_add("visual_us", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	var faces := generated["collision_faces"] as PackedVector3Array
	var collision := ConcavePolygonShape3D.new()
	collision.set_faces(faces)
	_profile_add("collision_shape_us", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	(tile.get_node("GroundPhysics/Shape") as CollisionShape3D).shape = collision
	tile.visible = not _editor_hidden_edge_keys.has(key)
	_profile_add("collision_attach_us", Time.get_ticks_usec() - started)
	_profile_add("tile_builds", 1)
	_profile["max_tile_us"] = maxi(int(_profile.get("max_tile_us", 0)), Time.get_ticks_usec() - tile_started)


func _profile_reset(operation: String) -> void:
	_profile = {"operation": operation, "compare_us": 0, "validation_us": 0, "copy_us": 0, "queue_us": 0,
		"mesh_us": 0, "geometry_us": 0, "top_us": 0, "side_us": 0, "water_us": 0, "uniform_us": 0,
		"mesh_resource_us": 0, "node_us": 0, "visual_us": 0,
		"collision_shape_us": 0, "collision_attach_us": 0, "process_us": 0,
		"process_calls": 0, "max_process_us": 0, "tile_builds": 0, "max_tile_us": 0,
		"coalesced_tile_requests": 0, "deferred_repeat_builds": 0, "repeat_edit_builds": 0, "max_pending_age_us": 0,
		"between_process_us": 0, "max_between_process_us": 0,
		"focused_process_calls": 0, "unfocused_process_calls": 0, "max_sleep_us": 0,
		"ground_vertices": 0, "water_vertices": 0, "uniform_dry_tiles": 0, "grouped_8_tiles": 0, "new_tile_nodes": 0}


func _profile_add(key: String, value: int) -> void:
	_profile[key] = int(_profile.get(key, 0)) + value


func begin_live_brush() -> void:
	_live_brush_active = true
	_last_edit_build_us.fill(0)


func end_live_brush() -> void:
	_live_brush_active = false


func profile_snapshot() -> Dictionary:
	var result := _profile.duplicate()
	result["scope"] = "accumulated_since_last_open_or_resize"
	result["built_tiles"] = built_tile_count()
	result["pending_tiles"] = pending_tile_count()
	result["first_tile_ms"] = first_tile_ms
	result["all_tiles_ms"] = all_tiles_ms
	result["width"] = document.width if document != null else 0
	result["depth"] = document.depth if document != null else 0
	return result


func set_editor_extension_edge_hidden(direction: String, hidden: bool) -> void:
	_editor_hidden_edge_keys.clear()
	if hidden and document != null:
		var last_x := ceili(float(document.width) / TILE_SIZE) - 1
		var last_z := ceili(float(document.depth) / TILE_SIZE) - 1
		if direction in ["west", "east"]:
			for z in last_z + 1:
				_editor_hidden_edge_keys[Vector2i(0 if direction == "west" else last_x, z)] = true
		elif direction in ["north", "south"]:
			for x in last_x + 1:
				_editor_hidden_edge_keys[Vector2i(x, 0 if direction == "north" else last_z)] = true
	for key in _tiles:
		(_tiles[key] as Node3D).visible = not _editor_hidden_edge_keys.has(key)


func set_editor_hover_overlay(overlay: Material, tile_keys: Array[Vector2i]) -> int:
	# Editor-only presentation. The terrain Resource, mesh, and collision remain
	# unchanged; rebuilt tiles inherit the overlay while they are in range.
	var requested := {}
	if overlay != null:
		for key in tile_keys:
			requested[key] = true
	var changes := 0
	for key in _editor_hover_tiles:
		if requested.has(key): continue
		var tile := _tiles.get(key) as Node3D
		if tile != null:
			(tile.get_node("Ground") as MeshInstance3D).material_overlay = null
			changes += 1
	for key in requested:
		if _editor_hover_tiles.has(key) and overlay == _editor_hover_overlay: continue
		var tile := _tiles.get(key) as Node3D
		if tile != null:
			(tile.get_node("Ground") as MeshInstance3D).material_overlay = overlay
			changes += 1
	_editor_hover_overlay = overlay
	_editor_hover_tiles = requested
	return changes


func pending_physics_chunk_count() -> int:
	return _pending.size()


func column_revision() -> int:
	return _column_revision


func set_editor_water_hidden(hidden: bool) -> void:
	_water_hidden = hidden
	for tile in _tiles.values():
		(tile.get_node("Water") as MeshInstance3D).visible = not hidden


func floor_surface_sample(global_point: Vector3) -> Dictionary:
	if document == null:
		return {"solid": false}
	var local := to_local(global_point)
	var cell := Vector2i(floori(local.x), floori(local.z))
	if cell.x < 0 or cell.y < 0 or cell.x >= document.width or cell.y >= document.depth:
		return {"solid": false, "cell": cell}
	var height: int = document.heights[document.column_index(cell.x, cell.y)]
	if height <= 0:
		return {"solid": false, "cell": cell}
	return {
		"solid": true,
		"cell": cell,
		"height_voxel": height - 1,
		"position": to_global(Vector3(local.x, document.origin_y + height, local.z)),
	}


func pick_ground_top(ray_start: Vector3, ray_end: Vector3) -> Dictionary:
	# Read the same columns that build the mesh. Physics shapes can be one tile
	# behind a live brush stroke, so editor hover must not depend on them.
	if document == null:
		return {}
	var origin := to_local(ray_start)
	var segment := to_local(ray_end) - origin
	var length := segment.length()
	if length <= 0.00001:
		return {}
	var direction := segment / length
	var enter := 0.0
	var leave := length
	for axis in 2:
		var coordinate := origin.x if axis == 0 else origin.z
		var speed := direction.x if axis == 0 else direction.z
		var extent := float(document.width if axis == 0 else document.depth)
		if absf(speed) < 0.000001:
			if coordinate < 0.0 or coordinate >= extent:
				return {}
			continue
		var first := -coordinate / speed
		var last := (extent - coordinate) / speed
		enter = maxf(enter, minf(first, last))
		leave = minf(leave, maxf(first, last))
	if enter > leave:
		return {}
	var distance := enter
	var start := origin + direction * minf(leave, enter + 0.0001)
	var x := clampi(floori(start.x), 0, document.width - 1)
	var z := clampi(floori(start.z), 0, document.depth - 1)
	var step_x := -1 if direction.x < -0.000001 else 1 if direction.x > 0.000001 else 0
	var step_z := -1 if direction.z < -0.000001 else 1 if direction.z > 0.000001 else 0
	var next_x := ((float(x + 1 if step_x > 0 else x) - origin.x) / direction.x) if step_x != 0 else INF
	var next_z := ((float(z + 1 if step_z > 0 else z) - origin.z) / direction.z) if step_z != 0 else INF
	var delta_x := absf(1.0 / direction.x) if step_x != 0 else INF
	var delta_z := absf(1.0 / direction.z) if step_z != 0 else INF
	while x >= 0 and z >= 0 and x < document.width and z < document.depth and distance <= leave:
		var end_distance := minf(leave, minf(next_x, next_z))
		var index := document.column_index(x, z)
		var height: int = document.heights[index]
		if height > 0 and document.top_materials[index] > 0:
			var entry_y := origin.y + direction.y * distance
			if distance > 0.00001 and entry_y >= float(document.origin_y) and entry_y < float(document.origin_y + height):
				return {"cell": Vector2i(x, z), "world": to_global(origin + direction * distance)}
			if absf(direction.y) >= 0.000001:
				var hit_distance := (float(document.origin_y + height) - origin.y) / direction.y
				if hit_distance >= distance - 0.00001 and hit_distance <= end_distance + 0.00001:
					return {"cell": Vector2i(x, z), "world": to_global(origin + direction * hit_distance)}
		if next_x < next_z:
			distance = next_x
			next_x += delta_x
			x += step_x
		else:
			distance = next_z
			next_z += delta_z
			z += step_z
	return {}


func water_surface_sample(global_point: Vector3) -> Dictionary:
	if document == null:
		return {"wet": false}
	var local := to_local(global_point)
	var cell := Vector2i(floori(local.x), floori(local.z))
	var block_world_size := to_global(Vector3.RIGHT).distance_to(to_global(Vector3.ZERO)) * float(TerrainResource.CELLS_PER_BLOCK)
	if cell.x < 0 or cell.y < 0 or cell.x >= document.width or cell.y >= document.depth:
		return {"wet": false, "cell": cell, "block_world_size": block_world_size}
	var index := document.column_index(cell.x, cell.y)
	var level: int = document.water_levels[index]
	if level <= document.heights[index] or document.water_materials[index] == 0:
		return {"wet": false, "cell": cell, "block_world_size": block_world_size}
	return {
		"wet": true,
		"cell": cell,
		"position": to_global(Vector3(local.x, document.origin_y + level + 0.085, local.z)),
		"block_world_size": block_world_size,
	}


func water_revision() -> int:
	return _water_revision


func navigation_path(global_start: Vector3, global_goal: Vector3, max_step_voxels := 4) -> PackedVector3Array:
	var result := PackedVector3Array()
	if document == null or document.width % TerrainResource.CELLS_PER_BLOCK != 0 or document.depth % TerrainResource.CELLS_PER_BLOCK != 0:
		return result
	if _navigation_grid.is_empty():
		_navigation_grid = _build_navigation_grid()
	var width: int = _navigation_grid.width
	var block_heights: PackedInt32Array = _navigation_grid.heights
	var start_local := to_local(global_start)
	var goal_local := to_local(global_goal)
	var blocks: Array[Vector2i] = SurfacePhysics.find_block_path_from_grid(
		_navigation_grid,
		Vector2i(floori(start_local.x / float(TerrainResource.CELLS_PER_BLOCK)), floori(start_local.z / float(TerrainResource.CELLS_PER_BLOCK))),
		Vector2i(floori(goal_local.x / float(TerrainResource.CELLS_PER_BLOCK)), floori(goal_local.z / float(TerrainResource.CELLS_PER_BLOCK))),
		max_step_voxels,
	)
	for block in blocks:
		var height := block_heights[block.x + block.y * width]
		result.append(to_global(Vector3((block.x + 0.5) * TerrainResource.CELLS_PER_BLOCK, document.origin_y + height + 1, (block.y + 0.5) * TerrainResource.CELLS_PER_BLOCK)))
	return result


func _build_navigation_grid() -> Dictionary:
	var width := document.width / TerrainResource.CELLS_PER_BLOCK
	var depth := document.depth / TerrainResource.CELLS_PER_BLOCK
	var block_heights := PackedInt32Array()
	block_heights.resize(width * depth)
	block_heights.fill(-1)
	for bz in depth:
		for bx in width:
			var samples: Array[int] = []
			for oz in [TerrainResource.CELLS_PER_BLOCK / 4, TerrainResource.CELLS_PER_BLOCK / 2, TerrainResource.CELLS_PER_BLOCK * 3 / 4]:
				for ox in [TerrainResource.CELLS_PER_BLOCK / 4, TerrainResource.CELLS_PER_BLOCK / 2, TerrainResource.CELLS_PER_BLOCK * 3 / 4]:
					var height: int = document.heights[document.column_index(bx * TerrainResource.CELLS_PER_BLOCK + ox, bz * TerrainResource.CELLS_PER_BLOCK + oz)]
					if height > 0:
						samples.append(height - 1)
			if samples.size() >= 5:
				samples.sort()
				block_heights[bx + bz * width] = samples[samples.size() / 2]
	return {"width": width, "depth": depth, "heights": block_heights}


func apply_heights(indices: PackedInt32Array, values: PackedInt32Array) -> void:
	if document == null or indices.size() != values.size():
		return
	for index in indices:
		if index < 0 or index >= document.heights.size():
			return
	var tops := PackedByteArray()
	var waters := PackedInt32Array()
	var water_colors := PackedByteArray()
	for index in indices:
		tops.append(document.top_materials[index])
		waters.append(document.water_levels[index])
		water_colors.append(document.water_materials[index])
	apply_columns(indices, values, tops, waters, water_colors)


func apply_columns(indices: PackedInt32Array, heights: PackedInt32Array, tops: PackedByteArray, waters: PackedInt32Array, water_colors: PackedByteArray) -> void:
	if document == null or indices.size() != heights.size() or indices.size() != tops.size() or indices.size() != waters.size() or indices.size() != water_colors.size():
		return
	var all_heights := document.heights
	var all_tops := document.top_materials
	var all_waters := document.water_levels
	var all_water_colors := document.water_materials
	var tile_columns := (document.width + TILE_SIZE - 1) / TILE_SIZE
	var tile_rows := (document.depth + TILE_SIZE - 1) / TILE_SIZE
	var dirty := PackedByteArray()
	dirty.resize(tile_columns * tile_rows)
	var grid_dirty := PackedByteArray()
	grid_dirty.resize(tile_columns * tile_rows)
	var changed_ground := false
	var changed_water := false
	for i in indices.size():
		var index := indices[i]
		if index < 0 or index >= all_heights.size():
			continue
		if all_heights[index] == heights[i] and all_tops[index] == tops[i] and all_waters[index] == waters[i] and all_water_colors[index] == water_colors[i]:
			continue
		var grid_changed := all_heights[index] != heights[i] or (all_tops[index] == 0) != (tops[i] == 0)
		changed_ground = changed_ground or all_heights[index] != heights[i]
		changed_water = changed_water or all_waters[index] != waters[i] or all_water_colors[index] != water_colors[i]
		all_heights[index] = clampi(heights[i], 0, document.height_limit)
		all_tops[index] = tops[i]
		all_waters[index] = maxi(0, waters[i])
		all_water_colors[index] = water_colors[i]
		var x := index % document.width
		var z := index / document.width
		var tile_index := x / TILE_SIZE + z / TILE_SIZE * tile_columns
		dirty[tile_index] = 1
		if grid_changed: grid_dirty[tile_index] = 1
		if x % TILE_SIZE == 0 and x > 0:
			dirty[tile_index - 1] = 1
			if grid_changed: grid_dirty[tile_index - 1] = 1
		if x % TILE_SIZE == TILE_SIZE - 1 and x + 1 < document.width:
			dirty[tile_index + 1] = 1
			if grid_changed: grid_dirty[tile_index + 1] = 1
		if z % TILE_SIZE == 0 and z > 0:
			dirty[tile_index - tile_columns] = 1
			if grid_changed: grid_dirty[tile_index - tile_columns] = 1
		if z % TILE_SIZE == TILE_SIZE - 1 and z + 1 < document.depth:
			dirty[tile_index + tile_columns] = 1
			if grid_changed: grid_dirty[tile_index + tile_columns] = 1
	var has_dirty := false
	for tile_index in dirty.size():
		if dirty[tile_index] == 0:
			continue
		has_dirty = true
		var key := Vector2i(tile_index % tile_columns, tile_index / tile_columns)
		_queue_tile(key, true)
	if has_dirty:
		document.heights = all_heights
		document.top_materials = all_tops
		document.water_levels = all_waters
		document.water_materials = all_water_colors
		_column_revision += 1
		for tile_index in grid_dirty.size():
			if grid_dirty[tile_index] != 0:
				_tile_revisions[tile_index] = _column_revision
		if changed_ground:
			_navigation_grid.clear()
		if changed_water:
			_water_revision += 1
	set_process(true)


func _reset_pending_flags() -> void:
	_pending_tile_columns = ceili(float(document.width) / TILE_SIZE)
	_pending_tile_rows = ceili(float(document.depth) / TILE_SIZE)
	_pending_flags.resize(_pending_tile_columns * _pending_tile_rows)
	_pending_flags.fill(0)
	_pending_edit_flags.resize(_pending_flags.size())
	_pending_edit_flags.fill(0)
	_pending_since_us.resize(_pending_flags.size())
	_pending_since_us.fill(Time.get_ticks_usec())
	_last_edit_build_us.resize(_pending_flags.size())
	_last_edit_build_us.fill(0)
	for key in _pending:
		_pending_flags[key.x + key.y * _pending_tile_columns] = 1
	_pending_needs_sort = not _pending.is_empty()


func _reset_tile_revisions() -> void:
	_tile_revisions.resize(_pending_tile_columns * _pending_tile_rows)
	_tile_revisions.fill(_column_revision)


func tile_revision(key: Vector2i) -> int:
	if key.x < 0 or key.y < 0 or key.x >= _pending_tile_columns or key.y >= _pending_tile_rows:
		return -1
	return _tile_revisions[key.x + key.y * _pending_tile_columns]


func _queue_tile(key: Vector2i, front: bool) -> void:
	if key.x < 0 or key.y < 0 or key.x >= _pending_tile_columns or key.y >= _pending_tile_rows:
		return
	var index := key.x + key.y * _pending_tile_columns
	if _pending_flags[index] != 0:
		if front: _pending_edit_flags[index] = 1
		_profile_add("coalesced_tile_requests", 1)
		return
	_pending_flags[index] = 1
	_pending_edit_flags[index] = 1 if front else 0
	_pending_since_us[index] = Time.get_ticks_usec()
	if front:
		_pending.push_front(key)
	else:
		_pending.append(key)
	_pending_needs_sort = true


func _prioritize_pending() -> void:
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var distance_a := (Vector2(a * TILE_SIZE) - Vector2(camera_anchor)).length_squared()
		var distance_b := (Vector2(b * TILE_SIZE) - Vector2(camera_anchor)).length_squared()
		return distance_a < distance_b if distance_a != distance_b else a.y < b.y if a.y != b.y else a.x < b.x
	)
	_pending_needs_sort = false


func pending_tile_count() -> int:
	return _pending.size()


func built_tile_count() -> int:
	return _tiles.size()


func save_document(path: String) -> Error:
	if document == null or not document.validation_errors().is_empty():
		return ERR_INVALID_DATA
	return ResourceSaver.save(document, path)


func reopen_document(path: String) -> bool:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	return open_document(loaded)
