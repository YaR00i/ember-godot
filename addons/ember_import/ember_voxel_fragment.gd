@tool
extends RefCounted
## Pure integer transforms. No source mutation, renderer, or saved selection state.
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Groups = preload("res://addons/ember_import/ember_voxel_groups.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const CHANNELS = ["voxels", "emissive", "shine", "transparency", "transmittance"]

static func rotate_cell(cell: Vector3i, span: Vector3i, axis: int) -> Dictionary:
	if axis == 0:
		return {"cell":Vector3i(cell.x,span.z-1-cell.z,cell.y),"extent":Vector3i(span.x,span.z,span.y)}
	if axis == 1:
		return {"cell":Vector3i(cell.z,cell.y,span.x-1-cell.x),"extent":Vector3i(span.z,span.y,span.x)}
	return {"cell":Vector3i(span.y-1-cell.y,cell.x,cell.z),"extent":Vector3i(span.y,span.x,span.z)}

static func plan(source: EmberVoxelModelResource, indices: PackedInt32Array, offset: Vector3i, axis: int, turns: int, copy: bool, region := Rect2i(), height := -1) -> Dictionary:
	if source == null or indices.is_empty() or indices.size() > Selection.LIMIT:
		return {"error":"Выделите от 1 до %d вокселей." % Selection.LIMIT}
	if axis < 0 or axis > 2 or not source.validation_errors().is_empty():
		return {"error":"Некорректная модель или ось."}
	var size := source.grid_size()
	var selected := {}
	var low := size
	var high := Vector3i.ZERO
	var locked := Groups.locked_indices(source.voxel_groups)
	for index in indices:
		if index < 0 or index >= source.voxels.size() or source.voxels[index] == 0:
			return {"error":"Выделение устарело. Выберите фрагмент заново."}
		var cell := Selection.cell_of(index, size)
		if not _allowed(cell, source, region, height) or locked.has(index):
			return {"error":"Выделение вне рабочей области или защищено группой."}
		selected[index] = true
		low = low.min(cell)
		high = high.max(cell)
	var extent := high - low + Vector3i.ONE
	var mapping := {}
	for index in selected:
		var cell := Selection.cell_of(index, size) - low
		var span := extent
		for turn in posmod(turns, 4):
			var rotated := rotate_cell(cell,span,axis)
			cell = rotated.cell
			span = rotated.extent
		cell += low + offset
		if not _allowed(cell, source, region, height):
			return {"error":"Фрагмент выходит за холст, рабочую область или срез. Сначала расширьте область."}
		var destination := Model.index_of(cell, size)
		if locked.has(destination) or (source.voxels[destination] != 0 and (copy or not selected.has(destination))):
			return {"error":"На месте назначения занятые или защищённые воксели. Измените смещение."}
		mapping[index] = destination
	var properties := {}
	if not source.voxel_part_ids.is_empty():
		var owners := source.voxel_part_ids.duplicate()
		if not copy:
			for index in selected:
				owners[index] = 0
		for index in mapping:
			owners[mapping[index]] = source.voxel_part_ids[index]
		properties.voxel_part_ids = owners
	for channel in CHANNELS:
		var before: PackedByteArray = source.get(channel)
		if before.is_empty():
			continue
		var after := before.duplicate()
		if not copy:
			for index in selected:
				after[index] = 0
		for index in mapping:
			after[mapping[index]] = before[index]
		properties[channel] = after
	var groups: Array[Dictionary] = source.voxel_groups.duplicate(true)
	for group in groups:
		var members := {}
		for index in group.get("indices", []):
			if copy or not mapping.has(index):
				members[index] = true
			if mapping.has(index):
				members[mapping[index]] = true
		group.indices = PackedInt32Array(members.keys())
		group.indices.sort()
	properties.voxel_groups = groups
	var before := {}
	var changed := false
	for key in properties:
		before[key] = source.get(key)
		changed = changed or before[key] != properties[key]
	if not changed:
		return {"error":"Изменений нет."}
	return {"properties":properties, "before":before, "selected":PackedInt32Array(mapping.values()), "label":"Копировать фрагмент" if copy else "Переместить фрагмент"}

static func _allowed(cell: Vector3i, source: EmberVoxelModelResource, region: Rect2i, height: int) -> bool:
	var size := source.grid_size()
	if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= size.x or cell.y >= size.y or cell.z >= size.z:
		return false
	if height >= 0 and cell.y >= preload("res://scripts/ember_voxel_edit_bounds.gd").visible_size(size, height).y:
		return false
	var density := source.normalized_density()
	return not region.has_area() or Rect2i(region.position * density, region.size * density).has_point(Vector2i(cell.x, cell.z))
