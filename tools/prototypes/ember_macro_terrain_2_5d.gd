extends RefCounted
## EXPERIMENT ONLY. No editor, Resource schema, save or runtime integration.
## Macro Base -> deterministic refinement -> absolute Fine overrides -> fine Surface.

const MACRO_PER_BLOCK := 8
const FINE_PER_BLOCK := 16
const FINE_PER_MACRO := 2
const REGION := 16 # macro samples; 2x2 gameplay blocks
const HALO := 2 # read-only macro samples around each target region

var blocks := Vector2i.ZERO
var width := 0
var depth := 0
var fine_height := 0
var seed := 0
var heights := PackedInt32Array() # filled fine-voxel count at each control sample
var semantics := PackedByteArray() # 1 inherit earth, 2 authored sand, 3 authored rock
var fine_overrides := {} # world fine-cell index -> palette index; 0 means deletion
var _dirty := {} # changed macro cells, accumulated for one gesture
var _last_dirty := {} # changed controls in one input sample, for preview only
var _bake_surface: EmberVoxelModelResource
var _bake_values := PackedByteArray()
var _bake_queue: Array[Vector2i] = []
var _bake_stats := {}
var last_changed_indices := PackedInt32Array()


func configure(next_blocks: Vector2i, next_fine_height: int, next_seed: int) -> void:
	blocks = next_blocks
	width = blocks.x * MACRO_PER_BLOCK
	depth = blocks.y * MACRO_PER_BLOCK
	fine_height = next_fine_height
	seed = next_seed
	heights.resize(width * depth)
	heights.fill(fine_height)
	semantics.resize(width * depth)
	semantics.fill(1)
	_dirty.clear()
	_last_dirty.clear()
	fine_overrides.clear()


func clear_dirty() -> void:
	_dirty.clear()
	_last_dirty.clear()


func dirty_count() -> int:
	return _dirty.size()


func set_fine_override(cell: Vector3i, value: int) -> void:
	assert(cell.x >= 0 and cell.x < width * FINE_PER_MACRO)
	assert(cell.z >= 0 and cell.z < depth * FINE_PER_MACRO)
	assert(cell.y >= 0 and cell.y < fine_height)
	assert(value >= 0 and value <= 255)
	var fine_width := width * FINE_PER_MACRO
	var fine_depth := depth * FINE_PER_MACRO
	fine_overrides[cell.x + cell.z * fine_width + cell.y * fine_width * fine_depth] = value


func set_semantic_control(cell: Vector2i, semantic: int) -> void:
	assert(cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < depth)
	assert(semantic >= 1 and semantic <= 3)
	var index := cell.x + cell.y * width
	if semantics[index] != semantic:
		semantics[index] = semantic
		_dirty[cell] = true
		_last_dirty[cell] = true


func apply_level_segment(from_fine: Vector3i, to_fine: Vector3i, target_top_y: int, radius_fine: int) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	_last_dirty.clear()
	var target_count := clampi(target_top_y + 1, 0, fine_height)
	var radius := float(radius_fine) - 0.25
	var minimum_x := maxi(0, floori(float(mini(from_fine.x, to_fine.x) - radius_fine) / FINE_PER_MACRO))
	var maximum_x := mini(width - 1, ceili(float(maxi(from_fine.x, to_fine.x) + radius_fine) / FINE_PER_MACRO))
	var minimum_z := maxi(0, floori(float(mini(from_fine.z, to_fine.z) - radius_fine) / FINE_PER_MACRO))
	var maximum_z := mini(depth - 1, ceili(float(maxi(from_fine.z, to_fine.z) + radius_fine) / FINE_PER_MACRO))
	var start_2d := Vector2(from_fine.x, from_fine.z)
	var end_2d := Vector2(to_fine.x, to_fine.z)
	var changed := 0
	var visited := 0
	for z in range(minimum_z, maximum_z + 1):
		for x in range(minimum_x, maximum_x + 1):
			visited += 1
			var fine_point := Vector2(x * FINE_PER_MACRO, z * FINE_PER_MACRO)
			if _distance_squared(fine_point, start_2d, end_2d) > radius * radius:
				continue
			var index := x + z * width
			if heights[index] == target_count:
				continue
			heights[index] = target_count
			# Shape does not silently paint sand/stone or change the water layer.
			_dirty[Vector2i(x, z)] = true
			_last_dirty[Vector2i(x, z)] = true
			changed += 1
	return {"changed_controls": changed, "visited_controls": visited, "cpu_usec": Time.get_ticks_usec() - start_usec}


func dirty_target_chunks() -> Array[Vector2i]:
	return _chunks_for_dirty(_dirty)


func preview_target_chunks() -> Array[Vector2i]:
	return _chunks_for_dirty(_last_dirty)


func _chunks_for_dirty(changed: Dictionary) -> Array[Vector2i]:
	var found := {}
	for raw_cell in changed:
		var cell: Vector2i = raw_cell
		# One control sample affects interpolation on the previous cell too.
		# Expand the WRITE target by this dependency, not merely the READ halo.
		for z in range(maxi(0, cell.y - 1), mini(depth - 1, cell.y + 1) + 1):
			for x in range(maxi(0, cell.x - 1), mini(width - 1, cell.x + 1) + 1):
				found[Vector2i(x / REGION, z / REGION)] = true
	var result: Array[Vector2i] = []
	for chunk in found:
		result.append(chunk)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


func all_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in ceili(float(depth) / REGION):
		for x in ceili(float(width) / REGION):
			result.append(Vector2i(x, z))
	return result


func _macro_chunk_rect(chunk: Vector2i) -> Rect2i:
	var origin := chunk * REGION
	return Rect2i(origin, Vector2i(mini(REGION, width - origin.x), mini(REGION, depth - origin.y)))


func bake_chunks(surface: EmberVoxelModelResource, chunks: Array[Vector2i]) -> Dictionary:
	begin_bake(surface, chunks)
	while not _bake_queue.is_empty():
		bake_next_chunk()
	return finish_bake()


func begin_bake(surface: EmberVoxelModelResource, chunks: Array[Vector2i]) -> void:
	assert(surface.grid_size() == Vector3i(width * FINE_PER_MACRO, fine_height, depth * FINE_PER_MACRO))
	_bake_surface = surface
	_bake_values = surface.voxels.duplicate()
	_bake_queue = chunks.duplicate()
	last_changed_indices.clear()
	_bake_stats = {"cpu_usec": 0, "columns": 0, "voxel_writes": 0, "changed_voxels": 0, "regions": 0, "halo_control_samples": 0}


func pending_bake_chunks() -> int:
	return _bake_queue.size()


func bake_next_chunk() -> void:
	assert(_bake_surface != null and not _bake_queue.is_empty())
	var started := Time.get_ticks_usec()
	var chunk: Vector2i = _bake_queue.pop_front()
	var columns := 0
	var voxel_writes := 0
	var halo_reads := 0
	var target := _macro_chunk_rect(chunk)
	if target.has_area():
		var read_halo := target.grow(HALO).intersection(Rect2i(Vector2i.ZERO, Vector2i(width, depth)))
		for z in range(target.position.y * FINE_PER_MACRO, target.end.y * FINE_PER_MACRO):
			for x in range(target.position.x * FINE_PER_MACRO, target.end.x * FINE_PER_MACRO):
				var refined: Dictionary = _refined_column(x, z, read_halo)
				var top := int(refined.height)
				var top_palette := int(refined.palette)
				var column_index := x + z * width * FINE_PER_MACRO
				var layer_stride := width * depth * FINE_PER_MACRO * FINE_PER_MACRO
				for y in fine_height:
					var fine_index := column_index + y * layer_stride
					var next_value := 0 if y >= top else top_palette if y == top - 1 else 1
					# Manual add AND delete take precedence after generated terrain.
					var final_value := int(fine_overrides.get(fine_index, next_value))
					if _bake_values[fine_index] != final_value:
						last_changed_indices.append(fine_index)
					_bake_values[fine_index] = final_value
					voxel_writes += 1
				columns += 1
		halo_reads += read_halo.size.x * read_halo.size.y - target.size.x * target.size.y
	_bake_stats.cpu_usec += Time.get_ticks_usec() - started
	_bake_stats.columns += columns
	_bake_stats.voxel_writes += voxel_writes
	_bake_stats.changed_voxels = last_changed_indices.size()
	_bake_stats.regions += 1
	_bake_stats.halo_control_samples += halo_reads


func finish_bake() -> Dictionary:
	assert(_bake_surface != null and _bake_queue.is_empty())
	_bake_surface.voxels = _bake_values
	_bake_surface = null
	_bake_values = PackedByteArray()
	return _bake_stats.duplicate()


func _refined_column(fine_x: int, fine_z: int, read_halo: Rect2i) -> Dictionary:
	var mx := fine_x / FINE_PER_MACRO
	var mz := fine_z / FINE_PER_MACRO
	var nx := mini(width - 1, mx + 1)
	var nz := mini(depth - 1, mz + 1)
	assert(read_halo.has_point(Vector2i(mx, mz)))
	assert(read_halo.has_point(Vector2i(nx, nz)))
	var h00 := heights[mx + mz * width]
	var h10 := heights[nx + mz * width]
	var h01 := heights[mx + nz * width]
	var h11 := heights[nx + nz * width]
	var tx := float(fine_x % FINE_PER_MACRO) / FINE_PER_MACRO
	var tz := float(fine_z % FINE_PER_MACRO) / FINE_PER_MACRO
	var blended := lerpf(lerpf(float(h00), float(h10), tx), lerpf(float(h01), float(h11), tx), tz)
	var slope := maxi(maxi(absi(h10 - h00), absi(h01 - h00)), maxi(absi(h11 - h10), absi(h11 - h01)))
	var semantic := int(semantics[mx + mz * width])
	# Quantized terraces are deliberate. Detail is world-coordinate keyed, so
	# bake order, chunk partition and previous attempts cannot alter the output.
	var terrace_step := 3 if semantic == 3 and slope >= 5 else 2
	var terrace := roundi(blended / float(terrace_step)) * terrace_step
	var noise := _stable_hash(fine_x, fine_z, semantic)
	var irregularity := 0
	if slope > 0:
		var frequency := 31 if semantic == 2 else 59 if semantic == 3 else 47
		irregularity = 1 if noise % frequency == 0 else -1 if noise % (frequency + 17) == 0 else 0
	var final_height := clampi(terrace + irregularity, 0, fine_height)
	return {"height": final_height, "palette": 4 if semantic == 3 else 3 if semantic == 2 else 1}


func preview_chunk(chunk: Vector2i) -> ArrayMesh:
	var target := _macro_chunk_rect(chunk)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for z in range(target.position.y, target.end.y):
		for x in range(target.position.x, target.end.x):
			var h00 := float(heights[x + z * width]) / FINE_PER_BLOCK
			var h10 := float(heights[mini(width - 1, x + 1) + z * width]) / FINE_PER_BLOCK
			var h01 := float(heights[x + mini(depth - 1, z + 1) * width]) / FINE_PER_BLOCK
			var h11 := float(heights[mini(width - 1, x + 1) + mini(depth - 1, z + 1) * width]) / FINE_PER_BLOCK
			var x0 := float(x) / MACRO_PER_BLOCK
			var z0 := float(z) / MACRO_PER_BLOCK
			var x1 := float(x + 1) / MACRO_PER_BLOCK
			var z1 := float(z + 1) / MACRO_PER_BLOCK
			var c := Color("#d1a55f") if semantics[x + z * width] == 2 else Color("#705447")
			c = c.darkened(0.38 * (1.0 - float(heights[x + z * width]) / fine_height))
			var p00 := Vector3(x0, h00, z0)
			var p01 := Vector3(x0, h01, z1)
			var p10 := Vector3(x1, h10, z0)
			var p11 := Vector3(x1, h11, z1)
			var first_normal := (p01 - p00).cross(p10 - p00).normalized()
			var second_normal := (p01 - p10).cross(p11 - p10).normalized()
			var quad := [p00, p01, p10, p10, p01, p11]
			for vertex_index in 6:
				vertices.append(quad[vertex_index])
				normals.append(first_normal if vertex_index < 3 else second_normal)
				colors.append(c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _stable_hash(x: int, z: int, semantic: int) -> int:
	var value := (seed ^ (x * 73856093) ^ (z * 19349663) ^ (semantic * 83492791)) & 0x7fffffff
	value = (value ^ (value >> 13)) * 1274126177 & 0x7fffffff
	return value ^ (value >> 16)


func _distance_squared(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	var factor := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0) if length_squared > 0.00001 else 0.0
	return point.distance_squared_to(start + segment * factor)
