@tool
extends Node3D
## Derived, frame-budgeted projection of one EmberVoxelModelResource.
## The Resource remains the only source. World scenes may opt into derived
## collision/navigation; battle scenes keep using the same visual-only renderer.

signal projection_completed

const DEFAULT_CHUNK_SIZE := 16
const PHYSICS_CHUNK_SIZE := 64
const MAX_CHUNKS_PER_FRAME := 12
const REBUILD_BUDGET_USEC := 4000
const SurfaceMaterials = preload("res://scripts/ember_voxel_surface_materials.gd")
const SurfaceMesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const SurfacePhysics = preload("res://scripts/ember_voxel_surface_physics.gd")
const NativeMesher = preload("res://scripts/ember_voxel_native_mesher.gd")
const Heightfield = preload("res://scripts/ember_voxel_heightfield.gd")

var chunk_size := DEFAULT_CHUNK_SIZE
var _surface: EmberVoxelModelResource
var _fallback_visual: Node3D
var _fallback_collision: StaticBody3D
var _fallback_collision_layer := 1
var _physics_enabled := false
var _expected_blocks := Vector2i.ZERO
var _chunks: Dictionary = {}
var _collision_chunks: Dictionary = {}
var _pending: Array[Vector2i] = []
var _physics_pending: Array[Vector2i] = []
var _physics_live := false
var _completion_emitted := false
var _solid_height_cache := PackedInt32Array()
var _building_solid_heights := PackedInt32Array()
var _navigation_grid_cache: Dictionary = {}
var _water_height_cache: Dictionary = {}
var _water_revision := 0
var _native_mesher: RefCounted
var _heightfield_task_id := -1
var _heightfield_task_output: Dictionary = {}
var _heightfield_generation := 0
var _heightfield_task_generation := -1
var _heightfield_restart_requested := false


func _init() -> void:
	_native_mesher = NativeMesher.new()


func _enter_tree() -> void:
	add_to_group(&"ember_water_surface_projection")


func configure(
	next_surface: EmberVoxelModelResource,
	block_scale: float,
	expected_blocks: Vector2i,
	fallback_visual: Node3D,
	enable_physics := false,
	fallback_collision: StaticBody3D = null,
) -> void:
	var scale_value := maxf(0.001, block_scale)
	var configuration_changed := (
		not is_equal_approx(scale.x, scale_value)
		or expected_blocks != _expected_blocks
		or fallback_visual != _fallback_visual
		or enable_physics != _physics_enabled
		or fallback_collision != _fallback_collision
	)
	var source_changed := next_surface != _surface
	if not source_changed and not configuration_changed:
		return
	if _surface != null and _surface.changed.is_connected(_on_surface_changed):
		_surface.changed.disconnect(_on_surface_changed)
	_surface = next_surface
	_expected_blocks = expected_blocks
	_fallback_visual = fallback_visual
	_physics_enabled = enable_physics
	if fallback_collision != _fallback_collision:
		if is_instance_valid(_fallback_collision):
			_fallback_collision.visible = true
			_fallback_collision.collision_layer = _fallback_collision_layer
		_fallback_collision = fallback_collision
		if _fallback_collision != null and _fallback_collision.collision_layer != 0:
			_fallback_collision_layer = _fallback_collision.collision_layer
	scale = Vector3.ONE * scale_value
	if _surface != null:
		_surface.changed.connect(_on_surface_changed)
	_begin_rebuild(not source_changed and not _chunks.is_empty())


func surface() -> EmberVoxelModelResource:
	return _surface


func refresh_geometry() -> void:
	# configure intentionally ignores the same Resource. Explicit editor refresh
	# must invalidate derived chunks even though canonical data did not change.
	if _surface != null:
		_begin_rebuild(true)


func pending_chunk_count() -> int:
	return _pending.size()


func rendered_chunk_count() -> int:
	return _chunks.size()


func pending_physics_chunk_count() -> int:
	return _physics_pending.size() + (1 if _heightfield_task_id >= 0 else 0)


func collision_chunk_count() -> int:
	return _collision_chunks.size()


func physics_is_ready() -> bool:
	return (
		_physics_enabled and _surface_is_valid() and _heightfield_task_id < 0
		and _physics_pending.is_empty()
		and not _collision_chunks.is_empty() and _physics_live
	)


func is_projection_complete() -> bool:
	return (
		_surface_is_valid() and _pending.is_empty()
		and (
			not _physics_enabled
			or (_heightfield_task_id < 0 and _physics_pending.is_empty())
		)
	)


func floor_surface_sample(global_point: Vector3) -> Dictionary:
	if not _surface_is_valid():
		return {"solid": false}
	var local_point := to_local(global_point)
	var density := _surface.normalized_density()
	var cell := Vector2i(
		floori(local_point.x * float(density)),
		floori(local_point.z * float(density)),
	)
	var size := _surface.grid_size()
	var height := -1
	if (
		cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.z
		and _solid_height_cache.size() == size.x * size.z
	):
		height = _solid_height_cache[cell.x + cell.y * size.x]
	else:
		height = SurfacePhysics.solid_height_at(_surface, cell)
	if height < 0:
		return {"solid": false, "cell": cell}
	return {
		"solid": true,
		"cell": cell,
		"height_voxel": height,
		"position": to_global(Vector3(
			local_point.x,
			float(height + 1) / float(density),
			local_point.z,
		)),
	}


func navigation_path(
	global_start: Vector3,
	global_goal: Vector3,
	max_step_voxels := 4,
) -> PackedVector3Array:
	var result := PackedVector3Array()
	if not _surface_is_valid():
		return result
	var local_start := to_local(global_start)
	var local_goal := to_local(global_goal)
	var start := Vector2i(floori(local_start.x), floori(local_start.z))
	var goal := Vector2i(floori(local_goal.x), floori(local_goal.z))
	var grid := _navigation_grid_cache
	if grid.is_empty():
		grid = SurfacePhysics.navigation_grid(_surface)
	var blocks: Array[Vector2i] = SurfacePhysics.find_block_path_from_grid(
		grid, start, goal, max_step_voxels
	)
	if blocks.is_empty():
		return result
	var width := int(grid.get("width", 0))
	var heights: PackedInt32Array = grid.get("heights", PackedInt32Array())
	var density := _surface.normalized_density()
	for block in blocks:
		var height := heights[block.x + block.y * width]
		result.append(to_global(Vector3(
			float(block.x) + 0.5,
			float(height + 1) / float(density),
			float(block.y) + 0.5,
		)))
	return result


func water_surface_sample(global_point: Vector3) -> Dictionary:
	## Converts one world-space footprint into the canonical X/Z water column.
	## Consumers never duplicate fill-height or overlay-mask interpretation.
	if not _surface_is_valid():
		return {"wet": false}
	var local_point := to_local(global_point)
	var density := _surface.normalized_density()
	var cell := Vector2i(
		floori(local_point.x * float(density)),
		floori(local_point.z * float(density)),
	)
	var origin := to_global(Vector3.ZERO)
	var block_world_size := origin.distance_to(to_global(Vector3.RIGHT))
	var size := _surface.grid_size()
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.z:
		return {"wet": false, "cell": cell, "block_world_size": block_world_size}
	if not _water_height_cache.has(cell):
		_water_height_cache[cell] = SurfaceMesher.water_height_at(_surface, cell)
	var height := int(_water_height_cache[cell])
	if height < 0:
		return {"wet": false, "cell": cell, "block_world_size": block_world_size}
	var local_surface := Vector3(
		local_point.x,
		(float(height + 1) + 0.085) / float(density),
		local_point.z,
	)
	return {
		"wet": true,
		"cell": cell,
		"position": to_global(local_surface),
		"block_world_size": block_world_size,
	}


func water_revision() -> int:
	return _water_revision


func rebuild(preserve_existing := true) -> void:
	_begin_rebuild(preserve_existing)


func drain_next_chunk() -> bool:
	if _pending.is_empty() or not _surface_is_valid():
		return false
	var chunk: Vector2i = _pending.pop_front()
	var size := _surface.grid_size()
	var region_min := Vector3i(chunk.x * chunk_size, 0, chunk.y * chunk_size)
	var region_size := Vector3i(
		mini(chunk_size, size.x - region_min.x),
		size.y,
		mini(chunk_size, size.z - region_min.z),
	)
	var voxel_size := 1.0 / float(_surface.normalized_density())
	var opaque := SurfaceMaterials.opaque_material()
	var transparent := SurfaceMaterials.water_material()
	var foam := SurfaceMaterials.foam_material()
	var has_water := SurfaceMesher.region_has_water_overlay(
		_surface, region_min, region_size
	)
	var native_projection: Dictionary = (
		_native_mesher.build_region(
			_surface.voxels,
			size,
			_surface.palette,
			PackedByteArray(),
			region_min,
			region_size,
			voxel_size,
			opaque,
			transparent,
		)
		if _native_mesher != null and NativeMesher.available() and not has_water
		else {}
	)
	var mesh := native_projection.get("mesh") as Mesh
	if mesh == null:
		mesh = SurfaceMesher.build_region(
			_surface, region_min, region_size, voxel_size
		)
		native_projection = {"position": Vector3.ZERO, "scale": Vector3.ONE}
	var visual := _chunks.get(chunk) as MeshInstance3D
	if mesh.get_surface_count() > 0:
		if visual == null:
			visual = MeshInstance3D.new()
			visual.name = "SurfaceChunk_%d_%d" % [chunk.x, chunk.y]
			add_child(visual)
			_chunks[chunk] = visual
		for surface_index in mesh.get_surface_count():
			var surface_name: StringName = mesh.surface_get_name(surface_index)
			mesh.surface_set_material(
				surface_index,
				transparent if surface_name == "water"
				else foam if surface_name == "water_foam"
				else opaque,
			)
		visual.position = native_projection.get("position", Vector3.ZERO)
		visual.scale = native_projection.get("scale", Vector3.ONE)
		visual.mesh = mesh
	elif visual != null:
		remove_child(visual)
		visual.queue_free()
		_chunks.erase(chunk)
	if _pending.is_empty():
		_set_fallback_visible(false)
	_finish_if_ready()
	return true


func drain_next_physics_chunk(wait_for_heightfield := true) -> bool:
	_consume_heightfield_task(wait_for_heightfield)
	if _physics_pending.is_empty() or not _surface_is_valid() or not _physics_enabled:
		return false
	var chunk: Vector2i = _physics_pending.pop_front()
	var size := _surface.grid_size()
	var region_min := Vector3i(chunk.x * PHYSICS_CHUNK_SIZE, 0, chunk.y * PHYSICS_CHUNK_SIZE)
	var region_size := Vector3i(
		mini(PHYSICS_CHUNK_SIZE, size.x - region_min.x),
		size.y,
		mini(PHYSICS_CHUNK_SIZE, size.z - region_min.z),
	)
	var collision_result := SurfacePhysics.build_collision_region_result(
		_surface,
		region_min,
		region_size,
		1.0 / float(_surface.normalized_density()),
		_building_solid_heights,
	)
	var mesh := collision_result.get("mesh", ArrayMesh.new()) as ArrayMesh
	var height_start: Vector2i = collision_result.get("start", Vector2i.ZERO)
	var height_extent: Vector2i = collision_result.get("extent", Vector2i.ZERO)
	var region_heights: PackedInt32Array = collision_result.get(
		"heights", PackedInt32Array()
	)
	if (
		_building_solid_heights.size() == size.x * size.z
		and region_heights.size() == height_extent.x * height_extent.y
	):
		for local_z in height_extent.y:
			for local_x in height_extent.x:
				_building_solid_heights[
					height_start.x + local_x + (height_start.y + local_z) * size.x
				] = region_heights[local_x + local_z * height_extent.x]
	var body := _collision_chunks.get(chunk) as StaticBody3D
	if mesh.get_surface_count() > 0:
		if body == null:
			body = StaticBody3D.new()
			body.name = "SurfaceCollision_%d_%d" % [chunk.x, chunk.y]
			body.collision_mask = 0
			body.collision_layer = 1 if _physics_live else 0
			var shape := CollisionShape3D.new()
			shape.name = "Shape"
			body.add_child(shape)
			add_child(body)
			_collision_chunks[chunk] = body
		var collision_shape := body.get_node("Shape") as CollisionShape3D
		var concave := mesh.create_trimesh_shape() as ConcavePolygonShape3D
		if concave != null:
			# Heightfield walls are gameplay boundaries from either side; enabling
			# backfaces also keeps ray/floor queries independent of winding.
			concave.backface_collision = true
		collision_shape.shape = concave
	elif body != null:
		remove_child(body)
		body.queue_free()
		_collision_chunks.erase(chunk)
	if _physics_pending.is_empty():
		if not _collision_chunks.is_empty():
			_solid_height_cache = _building_solid_heights
			_building_solid_heights = PackedInt32Array()
			_navigation_grid_cache = SurfacePhysics.navigation_grid_from_solid_heights(
				_surface, _solid_height_cache
			)
			_physics_live = true
			for collision in _collision_chunks.values():
				(collision as StaticBody3D).collision_layer = 1
			_set_fallback_collision_active(false)
		else:
			_building_solid_heights = PackedInt32Array()
			_navigation_grid_cache.clear()
			_set_fallback_collision_active(true)
	_finish_if_ready()
	return true


func clear_projection() -> void:
	_heightfield_generation += 1
	_heightfield_restart_requested = false
	_water_height_cache.clear()
	_water_revision += 1
	_pending.clear()
	_physics_pending.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_chunks.clear()
	_collision_chunks.clear()
	_physics_live = false
	_solid_height_cache = PackedInt32Array()
	_building_solid_heights = PackedInt32Array()
	_navigation_grid_cache.clear()
	visible = false
	_set_fallback_visible(true)
	_set_fallback_collision_active(true)


func _process(_delta: float) -> void:
	# A 24x24 map at the canonical 16-art-voxel density contains 576 small
	# chunks. One chunk per frame left the player's area on legacy terrain for
	# several seconds. Drain several cheap chunks, but stop at a wall-clock
	# budget so large edits never turn back into a single-frame remesh freeze.
	var started_at := Time.get_ticks_usec()
	var drained := 0
	# Physical chunks are coarser (4x4 gameplay blocks), so one early chunk per
	# frame advances collision without starving the visual queue.
	if _heightfield_task_id >= 0 or not _physics_pending.is_empty():
		drain_next_physics_chunk(false)
	while (
		drained < MAX_CHUNKS_PER_FRAME
		and not _pending.is_empty()
		and (drained == 0 or Time.get_ticks_usec() - started_at < REBUILD_BUDGET_USEC)
	):
		drain_next_chunk()
		drained += 1


func _exit_tree() -> void:
	if _surface != null and _surface.changed.is_connected(_on_surface_changed):
		_surface.changed.disconnect(_on_surface_changed)


func _on_surface_changed() -> void:
	_begin_rebuild(true)


func _begin_rebuild(preserve_existing := false) -> void:
	_heightfield_generation += 1
	_heightfield_restart_requested = false
	_water_height_cache.clear()
	_water_revision += 1
	_pending.clear()
	_physics_pending.clear()
	_completion_emitted = false
	if not preserve_existing:
		for child in get_children():
			remove_child(child)
			child.queue_free()
		_chunks.clear()
		_collision_chunks.clear()
		_physics_live = false
		_solid_height_cache = PackedInt32Array()
		_navigation_grid_cache.clear()
	if not _surface_is_valid():
		for collision in _collision_chunks.values():
			var body := collision as StaticBody3D
			if body != null:
				body.collision_layer = 0
		_physics_live = false
		_solid_height_cache = PackedInt32Array()
		_building_solid_heights = PackedInt32Array()
		_navigation_grid_cache.clear()
		visible = false
		_set_fallback_visible(true)
		_set_fallback_collision_active(true)
		return
	visible = true
	var size := _surface.grid_size()
	var count_x := ceili(float(size.x) / float(chunk_size))
	var count_z := ceili(float(size.z) / float(chunk_size))
	for z in count_z:
		for x in count_x:
			_pending.append(Vector2i(x, z))
	if _physics_enabled and _surface.physical:
		_building_solid_heights = PackedInt32Array()
		if _heightfield_task_id >= 0:
			_heightfield_restart_requested = true
		else:
			_start_heightfield_task()
	else:
		for collision in _collision_chunks.values():
			var body := collision as StaticBody3D
			if body != null:
				remove_child(body)
				body.queue_free()
		_collision_chunks.clear()
		_physics_live = false
		_solid_height_cache = PackedInt32Array()
		_building_solid_heights = PackedInt32Array()
		_navigation_grid_cache.clear()
		_set_fallback_collision_active(true)
	# Never flash an empty scene. Existing chunks remain visible during refresh;
	# otherwise the semantic fallback stays until the first exact pass completes.
	_set_fallback_visible(not preserve_existing or _chunks.is_empty())
	if _physics_enabled:
		_set_fallback_collision_active(not preserve_existing or _collision_chunks.is_empty())


func _start_heightfield_task() -> void:
	if not _surface_is_valid() or not _physics_enabled or not _surface.physical:
		return
	var size := _surface.grid_size()
	_heightfield_task_output = {}
	_heightfield_task_generation = _heightfield_generation
	# The worker receives an isolated immutable snapshot. Surface edits can then
	# continue safely; a stale result is discarded and rebuilt from the latest bytes.
	var values := _surface.voxels.duplicate()
	_heightfield_task_id = WorkerThreadPool.add_task(
		Heightfield.build_column_heights_into.bind(
			values, size, _surface.palette.size() - 1, _heightfield_task_output
		),
		false,
		"Ember Surface heightfield",
	)


func _consume_heightfield_task(wait_for_result: bool) -> bool:
	if _heightfield_task_id < 0:
		return false
	if not wait_for_result and not WorkerThreadPool.is_task_completed(_heightfield_task_id):
		return false
	var wait_error := WorkerThreadPool.wait_for_task_completion(_heightfield_task_id)
	var task_generation := _heightfield_task_generation
	var output := _heightfield_task_output
	_heightfield_task_id = -1
	_heightfield_task_generation = -1
	_heightfield_task_output = {}
	var restart := _heightfield_restart_requested
	_heightfield_restart_requested = false
	if (
		wait_error != OK
		or task_generation != _heightfield_generation
		or not _surface_is_valid()
		or not _physics_enabled
		or not _surface.physical
	):
		if restart and _surface_is_valid() and _physics_enabled and _surface.physical:
			_start_heightfield_task()
		return false
	var heights: PackedInt32Array = output.get("heights", PackedInt32Array())
	var size := _surface.grid_size()
	if heights.size() != size.x * size.z:
		_set_fallback_collision_active(true)
		return false
	_building_solid_heights = heights
	var physics_count_x := ceili(float(size.x) / float(PHYSICS_CHUNK_SIZE))
	var physics_count_z := ceili(float(size.z) / float(PHYSICS_CHUNK_SIZE))
	for z in physics_count_z:
		for x in physics_count_x:
			_physics_pending.append(Vector2i(x, z))
	return true


func _surface_is_valid() -> bool:
	if _surface == null:
		return false
	if _expected_blocks.x > 0 and _surface.size_blocks.x != _expected_blocks.x:
		return false
	if _expected_blocks.y > 0 and _surface.size_blocks.z != _expected_blocks.y:
		return false
	var size := _surface.grid_size()
	return (
		_surface.palette.size() >= 2
		and _surface.voxels.size() == size.x * size.y * size.z
	)


func _set_fallback_visible(next_visible: bool) -> void:
	if is_instance_valid(_fallback_visual):
		_fallback_visual.visible = next_visible


func _set_fallback_collision_active(active: bool) -> void:
	if is_instance_valid(_fallback_collision):
		_fallback_collision.visible = active
		_fallback_collision.collision_layer = _fallback_collision_layer if active else 0


func _finish_if_ready() -> void:
	if _completion_emitted or not is_projection_complete():
		return
	_completion_emitted = true
	projection_completed.emit()
