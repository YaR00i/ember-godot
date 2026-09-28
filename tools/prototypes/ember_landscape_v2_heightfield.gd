@tool
extends RefCounted
## Disposable Landscape v2 proof. This is not an editor or save-system owner.
## One height/control sample per existing fine XZ column (16 per block).

const SAMPLES_PER_BLOCK := 16
const REGION := 64 # fine columns, independent of the renderer's 16/32 chunks

var size := Vector3i.ZERO
var heights := PackedInt32Array() # filled voxel count, 0..size.y
var controls := PackedByteArray() # base earth material; no implicit repaint
var detail_overrides := {} # absolute voxel index -> 0/remove or 1..255/add/replace
var dirty_regions := {}
var last_input_regions := {}
var last_changed_samples: Array[Vector2i] = []
var last_changed_indices := PackedInt32Array()


func configure(blocks: Vector2i, height_voxels: int) -> void:
	size = Vector3i(blocks.x * SAMPLES_PER_BLOCK, height_voxels, blocks.y * SAMPLES_PER_BLOCK)
	heights.resize(size.x * size.z)
	heights.fill(size.y)
	controls.resize(size.x * size.z)
	controls.fill(1)
	detail_overrides.clear()
	dirty_regions.clear()
	last_input_regions.clear()
	last_changed_samples.clear()


func set_detail_override(cell: Vector3i, value: int) -> void:
	assert(cell.x >= 0 and cell.x < size.x and cell.y >= 0 and cell.y < size.y and cell.z >= 0 and cell.z < size.z)
	assert(value >= 0 and value <= 255)
	var index := cell.x + cell.z * size.x + cell.y * size.x * size.z
	detail_overrides[index] = value
	dirty_regions[Vector2i(cell.x / REGION, cell.z / REGION)] = true


func set_control(cell: Vector2i, value: int) -> void:
	assert(cell.x >= 0 and cell.x < size.x and cell.y >= 0 and cell.y < size.z)
	assert(value >= 0 and value <= 255)
	var index := cell.x + cell.y * size.x
	if controls[index] == value:
		return
	controls[index] = value
	var region := Vector2i(cell.x / REGION, cell.y / REGION)
	dirty_regions[region] = true
	_mark_preview_sample(cell.x, cell.y)
	last_changed_samples.append(cell)


func set_height_sample(cell: Vector2i, filled_count: int) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.z:
		return false
	var index := cell.x + cell.y * size.x
	var next := clampi(filled_count, 0, size.y)
	if heights[index] == next:
		return false
	heights[index] = next
	dirty_regions[Vector2i(cell.x / REGION, cell.y / REGION)] = true
	_mark_preview_sample(cell.x, cell.y)
	last_changed_samples.append(cell)
	return true


func apply_level_segment(from: Vector3i, to: Vector3i, target_top_y: int, radius: int, scope := Rect2i()) -> Dictionary:
	var started := Time.get_ticks_usec()
	last_input_regions.clear()
	last_changed_samples.clear()
	var target_count := clampi(target_top_y, 0, size.y - 1) + 1
	var minimum_x := maxi(0, mini(from.x, to.x) - radius + 1)
	var maximum_x := mini(size.x, maxi(from.x, to.x) + radius)
	var minimum_z := maxi(0, mini(from.z, to.z) - radius + 1)
	var maximum_z := mini(size.z, maxi(from.z, to.z) + radius)
	if scope.has_area():
		minimum_x = maxi(minimum_x, scope.position.x)
		maximum_x = mini(maximum_x, scope.end.x)
		minimum_z = maxi(minimum_z, scope.position.y)
		maximum_z = mini(maximum_z, scope.end.y)
	var start_2d := Vector2(from.x, from.z)
	var end_2d := Vector2(to.x, to.z)
	var changed := 0
	var visited := 0
	for z in range(minimum_z, maximum_z):
		for x in range(minimum_x, maximum_x):
			visited += 1
			if _distance_to_segment(Vector2(x, z), start_2d, end_2d) > float(radius) - 0.25:
				continue
			if set_height_sample(Vector2i(x, z), target_count):
				changed += 1
	return {"changed_columns": changed, "visited_columns": visited, "cpu_usec": Time.get_ticks_usec() - started}


func sorted_regions(source: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for region in source:
		result.append(region)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


func all_regions() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for z in ceili(float(size.z) / REGION):
		for x in ceili(float(size.x) / REGION):
			result.append(Vector2i(x, z))
	return result


func region_rect(region: Vector2i) -> Rect2i:
	var origin := region * REGION
	return Rect2i(origin, Vector2i(mini(REGION, size.x - origin.x), mini(REGION, size.z - origin.y)))


func bake_region(surface: EmberVoxelModelResource, region: Vector2i) -> Dictionary:
	assert(surface.grid_size() == size)
	var started := Time.get_ticks_usec()
	var values := surface.voxels
	var rect := region_rect(region)
	var writes := 0
	var changed := 0
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var column := x + z * size.x
			var top := heights[column]
			var control := controls[column]
			for y in size.y:
				var index := column + y * size.x * size.z
				var base := control if y < top else 0
				var final_value := int(detail_overrides.get(index, base))
				if values[index] != final_value:
					values[index] = final_value
					last_changed_indices.append(index)
					changed += 1
				writes += 1
	surface.voxels = values
	return {"cpu_usec": Time.get_ticks_usec() - started, "columns": rect.size.x * rect.size.y, "writes": writes, "changed_voxels": changed}


func begin_bake() -> void:
	last_changed_indices.clear()


func _mark_preview_sample(x: int, z: int) -> void:
	var rx := x / REGION
	var rz := z / REGION
	last_input_regions[Vector2i(rx, rz)] = true
	# Each preview grid samples one halo vertex on its right/bottom border.
	if x % REGION == 0 and rx > 0:
		last_input_regions[Vector2i(rx - 1, rz)] = true
	if z % REGION == 0 and rz > 0:
		last_input_regions[Vector2i(rx, rz - 1)] = true
	if x % REGION == 0 and z % REGION == 0 and rx > 0 and rz > 0:
		last_input_regions[Vector2i(rx - 1, rz - 1)] = true


func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var delta := to - from
	var length_squared := delta.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(from)
	var along := clampf((point - from).dot(delta) / length_squared, 0.0, 1.0)
	return point.distance_to(from + delta * along)
