@tool
extends RefCounted
## Incremental 6-neighbour volume selection, independent of UI and mutations.
## Unlike water's existing coplanar flood, this includes walls and inner voxels.
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Bounds = preload("res://scripts/ember_voxel_edit_bounds.gd")
const LIMIT := 32768
const OFFSETS = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
var indices := PackedInt32Array()
var done := false
var error := ""
var _values: PackedByteArray
var _size: Vector3i
var _box: AABB
var _matches := PackedByteArray()
var _queue: Array[Vector3i] = []
var _visited: Dictionary = {}
var _cursor := 0
var _scan := 0
var _mode := 0
var _maximum := LIMIT


func start(resource: EmberVoxelModelResource, seed: Vector3i, mode: int, tolerance: float,
		region := Rect2i(), height := -1, maximum := LIMIT) -> void:
	indices.clear()
	done = false
	error = ""
	_queue.clear()
	_visited.clear()
	_cursor = 0
	_scan = 0
	_mode = mode # 0 single, 1 connected similar, 2 all similar.
	_maximum = maxi(1, maximum)
	if resource == null:
		_fail("Нет модели")
		return
	_size = resource.grid_size()
	_values = resource.voxels # Packed snapshot; no full-volume dictionary/copy.
	var visible := Bounds.visible_size(_size, height)
	var density := resource.normalized_density()
	var rect := Rect2i(0, 0, _size.x, _size.z)
	if region.has_area():
		rect = rect.intersection(Rect2i(region.position * density, region.size * density))
	_box = AABB(Vector3(rect.position.x, 0, rect.position.y), Vector3(rect.size.x, visible.y, rect.size.y))
	if not _inside(seed) or _values.size() != _size.x * _size.y * _size.z:
		_fail("Кликните по вокселю внутри рабочей области и среза")
		return
	var value := int(_values[Model.index_of(seed, _size)])
	if value <= 0 or value >= resource.palette.size():
		_fail("Нет доступного цвета")
		return
	_matches.resize(resource.palette.size())
	_matches.fill(0)
	for i in range(1, resource.palette.size()):
		_matches[i] = int(Model._normalized_rgb_distance(resource.palette[value], resource.palette[i]) <= clampf(tolerance, 0, 1))
	_queue.append(seed)
	_visited[Model.index_of(seed, _size)] = true


func step(budget := 256) -> void:
	if done:
		return
	for iteration in maxi(1, budget):
		var cell: Vector3i
		if _mode == 2 or _mode == 3:
			var extent := Vector3i(_box.size)
			if _scan >= extent.x * extent.y * extent.z:
				done = true
				return
			cell = cell_of(_scan, extent) + Vector3i(_box.position)
			_scan += 1
		else:
			if _cursor >= _queue.size():
				done = true
				return
			cell = _queue[_cursor]
			_cursor += 1
		var index := Model.index_of(cell, _size)
		var value := int(_values[index])
		if value == 0 or value >= _matches.size() or _matches[value] == 0:
			continue
		indices.append(index)
		if indices.size() > _maximum:
			_fail("Больше %d вокселей. Уменьшите область или допуск; прежнее выделение сохранено." % _maximum)
			return
		if _mode != 1:
			continue
		for offset in OFFSETS:
			var neighbor: Vector3i = cell + offset
			if not _inside(neighbor):
				continue
			var next := Model.index_of(neighbor, _size)
			if not _visited.has(next):
				_visited[next] = true
				_queue.append(neighbor)

func start_box(resource: EmberVoxelModelResource, low: Vector3i, high: Vector3i, region := Rect2i(), height := -1) -> void:
	indices.clear()
	done = false
	error = ""
	_scan = 0
	_maximum = LIMIT
	if resource == null:
		_fail("Нет модели")
		return
	_size = resource.grid_size()
	_values = resource.voxels
	if _values.size() != _size.x * _size.y * _size.z:
		_fail("Некорректная сетка")
		return
	var density := resource.normalized_density()
	var rect := Rect2i(0,0,_size.x,_size.z)
	if region.has_area():
		rect = rect.intersection(Rect2i(region.position*density,region.size*density))
	_box = AABB(Vector3(rect.position.x,0,rect.position.y),Vector3(rect.size.x,Bounds.visible_size(_size,height).y,rect.size.y))
	_box = _box.intersection(AABB(Vector3(low.min(high)), Vector3(high.max(low)-low.min(high)+Vector3i.ONE)))
	_mode = 3
	_matches.resize(resource.palette.size())
	_matches.fill(1)


static func cell_of(index: int, size: Vector3i) -> Vector3i:
	return Vector3i(index % size.x, index / (size.x * size.z), (index / size.x) % size.z)


static func combine(previous: Dictionary, next: PackedInt32Array, operation: int) -> Dictionary:
	var result := {} if operation == 0 else previous.duplicate()
	for index in next:
		if operation == 2:
			result.erase(index)
		else:
			result[index] = true
	return result


func _inside(cell: Vector3i) -> bool:
	var end := _box.end
	return cell.x >= _box.position.x and cell.y >= 0 and cell.z >= _box.position.z and cell.x < end.x and cell.y < end.y and cell.z < end.z


func _fail(message: String) -> void:
	error = message
	done = true
	indices.clear()
