@tool
class_name EmberVoxelEditorPerfPolicy
extends RefCounted
## Pure editor rendering policy. Canonical voxel data and gameplay scale never
## depend on these values.

const CHUNK_LEGACY := 16
const CHUNK_MEDIUM := 32
const CHUNK_LARGE := 64

const SMALL_GRID_LIMIT := 160
const MEDIUM_GRID_LIMIT := 640

const DEFAULT_CONTEXT_RADIUS_BLOCKS := 8.0
const MAX_CONTEXT_RADIUS_BLOCKS := 32.0


static func adaptive_preview_chunk_size(grid_size: Vector3i) -> int:
	var longest := maxi(grid_size.x, grid_size.z)
	if longest <= SMALL_GRID_LIMIT:
		return CHUNK_LEGACY
	if longest <= MEDIUM_GRID_LIMIT:
		return CHUNK_MEDIUM
	return CHUNK_LARGE


static func preview_chunk_count(grid_size: Vector3i, chunk_size: int) -> Vector2i:
	var chunk := maxi(1, chunk_size)
	return Vector2i(
		ceili(float(grid_size.x) / float(chunk)),
		ceili(float(grid_size.z) / float(chunk)),
	)


static func context_radius_world(target: Node3D, radius_blocks: float) -> float:
	var blocks := clampf(radius_blocks, 0.0, MAX_CONTEXT_RADIUS_BLOCKS)
	var block_world_size := 16.0
	if target != null and target.get("block_world_size") != null:
		block_world_size = maxf(0.001, float(target.get("block_world_size")))
	return blocks * block_world_size


static func full_rebuild_queue_threshold(adaptive: bool) -> int:
	# Exact legacy Canvas behavior used >64 before the performance pass.
	return 16 if adaptive else 64


static func should_queue_full_rebuild(chunk_count: int, adaptive: bool) -> bool:
	return chunk_count > full_rebuild_queue_threshold(adaptive)


static func context_batching_allowed(optimized: bool, opacity: float) -> bool:
	return optimized and opacity >= 0.999


static func context_opacity_requires_rebuild(
	optimized: bool,
	previous_batching_allowed: bool,
	next_opacity: float,
) -> bool:
	if not optimized:
		return false
	return previous_batching_allowed != context_batching_allowed(
		optimized,
		next_opacity,
	)
