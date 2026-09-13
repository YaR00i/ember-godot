@tool
extends RefCounted
## Pure integer transforms. No source mutation, renderer, or saved selection state.
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Groups = preload("res://addons/ember_import/ember_voxel_groups.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const CHANNELS = ["voxels", "emissive", "shine", "transparency", "transmittance", "collision_voxels"]

static func rotate_cell(cell: Vector3i, span: Vector3i, axis: int) -> Dictionary:
	if axis == 0:
		return {"cell":Vector3i(cell.x,span.z-1-cell.z,cell.y),"extent":Vector3i(span.x,span.z,span.y)}
	if axis == 1:
		return {"cell":Vector3i(cell.z,cell.y,span.x-1-cell.x),"extent":Vector3i(span.z,span.y,span.x)}
	return {"cell":Vector3i(span.y-1-cell.y,cell.x,cell.z),"extent":Vector3i(span.y,span.x,span.z)}

static func bend(source: EmberVoxelModelResource, indices: PackedInt32Array, along: int, direction: int, amount: int, profile := 0, region := Rect2i(), height := -1, clip_bounds := false) -> Dictionary:
	if along < 0 or along > 2 or direction < 0 or direction > 2 or along == direction or profile < 0 or profile > 1:
		return {"error":"Выберите разные оси длины и изгиба."}
	if amount == 0:
		return {"error":"Задайте ненулевую силу изгиба в вокселях."}
	if source != null and (not source.surface_fill_levels.is_empty() or not source.surface_fill_materials.is_empty() or not source.surface_fill_palette.is_empty()):
		return {"error":"Изгиб пока не переносит заливку уровня. Используйте объект без заливки воды."}
	if source != null and not source.emissive_lights.is_empty():
		return {"error":"Изгиб пока не переносит отдельные источники света. Используйте объект без них."}
	return _remap_plan(source, indices, Vector3i.ZERO, 0, 0, false, region, height, {"along":along,"direction":direction,"amount":amount,"profile":profile}, clip_bounds)

static func plan(source: EmberVoxelModelResource, indices: PackedInt32Array, offset: Vector3i, axis: int, turns: int, copy: bool, region := Rect2i(), height := -1, clip_bounds := false) -> Dictionary:
	return _remap_plan(source, indices, offset, axis, turns, copy, region, height, {}, clip_bounds)

static func _remap_plan(source: EmberVoxelModelResource, indices: PackedInt32Array, offset: Vector3i, axis: int, turns: int, copy: bool, region: Rect2i, height: int, deformation := {}, clip_bounds := false) -> Dictionary:
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
		if clip_bounds and not _allowed(cell, source, region, height):
			continue
		if not _allowed(cell, source, region, height) or locked.has(index):
			return {"error":"Выделение вне рабочей области или защищено группой."}
		selected[index] = true
		low = low.min(cell)
		high = high.max(cell)
	if selected.is_empty():
		return {"error":"В рабочей области нет выбранных вокселей."}
	var extent := high - low + Vector3i.ONE
	if not deformation.is_empty() and extent[deformation.along] < 2:
		return {"error":"Для изгиба нужна длина хотя бы два вокселя вдоль выбранной оси."}
	var mapping := {}
	var clipped := 0
	for index in selected:
		var cell := Selection.cell_of(index, size) - low
		if not deformation.is_empty():
			var t := float(cell[deformation.along]) / float(extent[deformation.along] - 1)
			var weight := 4.0 * t * (1.0 - t) if deformation.profile == 0 else t * t * (3.0 - 2.0 * t)
			cell[deformation.direction] += roundi(float(deformation.amount) * weight)
		var span := extent
		for turn in posmod(turns, 4):
			var rotated := rotate_cell(cell,span,axis)
			cell = rotated.cell
			span = rotated.extent
		cell += low + offset
		if not _allowed(cell, source, region, height):
			if clip_bounds:
				clipped += 1
				continue
			return {"error":"Фрагмент выходит за холст, рабочую область или срез. Сначала расширьте область."}
		var destination := Model.index_of(cell, size)
		if locked.has(destination) or (source.voxels[destination] != 0 and (copy or not selected.has(destination))):
			return {"error":"На месте назначения занятые или защищённые воксели. Измените смещение."}
		mapping[index] = destination
	var destination_sources := {}
	for index in mapping:
		destination_sources[mapping[index]] = index
	var result := _mapped_plan(source, {} if copy else selected, destination_sources, "Изгиб объёма" if not deformation.is_empty() else ("Копировать фрагмент" if copy else "Переместить фрагмент"))
	result.clipped_voxels = clipped
	return result

static func _mapped_plan(source: EmberVoxelModelResource, removed: Dictionary, destination_sources: Dictionary, label: String) -> Dictionary:
	# One shared resampling transaction for rigid transforms, Bend and Grab.
	var source_destinations := {}
	for destination in destination_sources:
		var index: int = destination_sources[destination]
		if not source_destinations.has(index):
			source_destinations[index] = []
		source_destinations[index].append(destination)
	var properties := {}
	if not source.voxel_part_ids.is_empty():
		var owners := source.voxel_part_ids.duplicate()
		for index in removed:
			owners[index] = 0
		for destination in destination_sources:
			owners[destination] = source.voxel_part_ids[destination_sources[destination]]
		properties.voxel_part_ids = owners
	for channel in CHANNELS:
		var before: PackedByteArray = source.get(channel)
		if before.is_empty():
			continue
		var after := before.duplicate()
		for index in removed:
			after[index] = 0
		for destination in destination_sources:
			after[destination] = before[destination_sources[destination]]
		properties[channel] = after
	var groups: Array[Dictionary] = source.voxel_groups.duplicate(true)
	for group in groups:
		var members := {}
		for index in group.get("indices", []):
			if not removed.has(index):
				members[index] = true
			for destination in source_destinations.get(index, []):
				members[destination] = true
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
	var dirty := removed.duplicate()
	for destination in destination_sources:
		dirty[destination] = true
	return {"properties":properties, "before":before, "selected":PackedInt32Array(destination_sources.keys()), "changed_indices":PackedInt32Array(dirty.keys()), "label":label}

static func start_grab(source: EmberVoxelModelResource, center: Vector3, radius: float, displacement: Vector3, softness := 75.0, region := Rect2i(), height := -1, clip_bounds := false) -> GrabJob:
	var job := GrabJob.new()
	job.source = source
	job.center = center
	job.radius = radius
	job.displacement = displacement
	job.softness = clampf(softness, 0, 100)
	job.region = region
	job.height = height
	job.clip_bounds = clip_bounds
	job.finish = func(removed: Dictionary, mapping: Dictionary) -> Dictionary: return _mapped_plan(source, removed, mapping, "Тянуть · мягкая деформация")
	job.allowed = func(cell: Vector3i) -> bool: return _allowed(cell, source, region, height)
	job.initialize()
	return job

class GrabJob extends RefCounted:
	# Incremental pure volume warp. The moving compact field is integrated in
	# both directions; inverse sampling fills stretched gaps, forward seeds keep
	# thin details. All sampling reads the immutable pointer-down source.
	const MAX_CANDIDATES := 524288
	const SAMPLE_OFFSETS = [Vector3.ZERO, Vector3(0.35,0,0), Vector3(-0.35,0,0), Vector3(0,0.35,0), Vector3(0,-0.35,0), Vector3(0,0,0.35), Vector3(0,0,-0.35)]
	var source: EmberVoxelModelResource
	var center: Vector3
	var radius: float
	var displacement: Vector3
	var softness: float
	var region: Rect2i
	var height: int
	var clip_bounds := false
	var clipped := 0
	var finish: Callable
	var allowed: Callable
	var done := false
	var result := {}
	var affected := {}
	var mapping := {}
	var locked := {}
	var size: Vector3i
	var low: Vector3i
	var span: Vector3i
	var output_low := Vector3i(2147483647,2147483647,2147483647)
	var output_high := Vector3i(-2147483647,-2147483647,-2147483647)
	var cursor := 0
	var phase := 0
	var steps := 1
	var elapsed_usec := 0

	func fail(message: String) -> void:
		result = {"error":message}
		done = true

	func complete() -> void:
		result = finish.call(affected, mapping)
		result.clipped_voxels = clipped
		done = true

	func initialize() -> void:
		if source == null or not source.validation_errors().is_empty() or not center.is_finite() or not displacement.is_finite() or radius < 1 or radius > 32:
			fail("Некорректная модель или радиус деформации (1–32 vox).")
			return
		if not source.surface_fill_levels.is_empty() or not source.emissive_lights.is_empty():
			fail("Тянуть пока нельзя объекты с заливкой уровня или отдельными источниками света.")
			return
		if displacement.length() < 0.25:
			fail("Изменений нет.")
			return
		steps = maxi(1, ceili(displacement.length() / maxf(0.25, radius * 0.1)))
		if steps > 64:
			fail("Слишком длинный жест. Примените несколько более коротких перетаскиваний.")
			return
		size = source.grid_size()
		locked = Groups.locked_indices(source.voxel_groups)
		low = Vector3i((center.min(center + displacement) - Vector3.ONE * radius).floor()).max(Vector3i.ZERO)
		var high := Vector3i((center.max(center + displacement) + Vector3.ONE * radius).ceil()).min(size - Vector3i.ONE)
		span = high - low + Vector3i.ONE
		if span.x * span.y * span.z > MAX_CANDIDATES:
			fail("Область деформации слишком велика. Уменьшите радиус или длину жеста.")
		if span.x < 1 or span.y < 1 or span.z < 1:
			fail("Точка захвата вне холста.")

	func weight(point: Vector3) -> float:
		var distance := point.length() / radius
		var core := 0.75 * (1.0 - softness / 100.0)
		var t := clampf((distance - core) / (1.0 - core), 0, 1)
		return 1.0 - t * t * (3.0 - 2.0 * t)

	func warp(point: Vector3, inverse := false) -> Vector3:
		var h := displacement / float(steps)
		for iteration in steps:
			var stage := steps - iteration if inverse else iteration
			var t := float(stage) / float(steps)
			var sign_value := -1.0 if inverse else 1.0
			var first := h * sign_value * weight(point - center - displacement * t)
			var middle := center + displacement * (t + sign_value * 0.5 / float(steps))
			point += h * sign_value * weight(point + first * 0.5 - middle)
		return point

	func step(maximum := 1024, budget_usec := 4000) -> void:
		if done:
			return
		var started := Time.get_ticks_usec()
		var total := span.x * span.y * span.z
		for iteration in maximum:
			if cursor >= total:
				if phase == 0:
					if affected.is_empty():
						fail("В радиусе захвата нет доступных вокселей.")
						break
					if mapping.is_empty():
						complete()
						break
					low = output_low - Vector3i.ONE
					span = output_high - low + Vector3i.ONE * 2
					if span.x * span.y * span.z > MAX_CANDIDATES:
						fail("Область деформации слишком велика. Уменьшите радиус или длину жеста.")
						break
					cursor = 0
					phase = 1
					total = span.x * span.y * span.z
				else:
					complete()
					break
			var cell := low + Selection.cell_of(cursor, span)
			cursor += 1
			if phase == 0:
				_gather(cell)
			else:
				_sample(cell)
			if done or Time.get_ticks_usec() - started >= budget_usec:
				break
		elapsed_usec += Time.get_ticks_usec() - started

	func _gather(cell: Vector3i) -> void:
		var index := Model.index_of(cell, size)
		var point := Vector3(cell) + Vector3.ONE * 0.5
		var t := clampf((point - center).dot(displacement) / displacement.length_squared(),0,1)
		if source.voxels[index] == 0 or weight(point - center - displacement * t) <= 0:
			return
		# Outside the editable mask is context, never part of the removed source.
		if clip_bounds and not allowed.call(cell):
			return
		if not allowed.call(cell) or locked.has(index):
			fail("Радиус затрагивает защищённые воксели, рабочую границу или срез.")
			return
		affected[index] = true
		if affected.size() > Selection.LIMIT:
			fail("Один жест ограничен %d вокселями. Уменьшите радиус." % Selection.LIMIT)
			return
		var destination := Vector3i(warp(Vector3(cell) + Vector3.ONE * 0.5).floor())
		if not allowed.call(destination):
			if clip_bounds:
				clipped += 1
				return
			fail("Деформация выходит за холст, рабочую область или срез. Добавьте запас в холсте.")
			return
		output_low = output_low.min(destination)
		output_high = output_high.max(destination)
		var target := Model.index_of(destination, size)
		# Seed priority is deterministic. Inverse center samples refine materials.
		if not mapping.has(target):
			mapping[target] = index

	func _sample(cell: Vector3i) -> void:
		if clip_bounds and not allowed.call(cell):
			return
		var destination := -1
		if cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < size.x and cell.y < size.y and cell.z < size.z:
			destination = Model.index_of(cell, size)
		var sampled := -1
		var original_point := warp(Vector3(cell) + Vector3.ONE * 0.5, true)
		for offset in SAMPLE_OFFSETS:
			# Reconstruct thin coverage around one inverse sample, not seven full
			# integrations per destination. Forward seeds cover stretched detail.
			var original := Vector3i((original_point + offset).floor())
			if original.x < 0 or original.y < 0 or original.z < 0 or original.x >= size.x or original.y >= size.y or original.z >= size.z:
				continue
			var index := Model.index_of(original, size)
			if affected.has(index):
				sampled = index
				break
			if offset == Vector3.ZERO and destination >= 0 and source.voxels[destination] != 0 and not affected.has(destination) and not mapping.has(destination):
				# Conservative side samples must not bleed across the stationary edge.
				return
		if sampled < 0 and not mapping.has(destination):
			return
		if not allowed.call(cell) or locked.has(destination) or (source.voxels[destination] != 0 and not affected.has(destination)):
			fail("На пути деформации занятые или защищённые воксели либо граница холста (%s). Измените жест." % cell)
			return
		if sampled >= 0:
			mapping[destination] = sampled

static func _allowed(cell: Vector3i, source: EmberVoxelModelResource, region: Rect2i, height: int) -> bool:
	var size := source.grid_size()
	if cell.x < 0 or cell.y < 0 or cell.z < 0 or cell.x >= size.x or cell.y >= size.y or cell.z >= size.z:
		return false
	if height >= 0 and cell.y >= preload("res://scripts/ember_voxel_edit_bounds.gd").visible_size(size, height).y:
		return false
	var density := source.normalized_density()
	return not region.has_area() or Rect2i(region.position * density, region.size * density).has_point(Vector2i(cell.x, cell.z))
