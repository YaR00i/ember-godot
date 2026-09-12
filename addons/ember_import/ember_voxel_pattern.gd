@tool
extends RefCounted
## Pure editor-only flat-pattern authoring and atomic placement plans.
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Preset = preload("res://addons/ember_import/ember_voxel_stamp_preset.gd")
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")

const MAX_SIZE := 16


static func build_geometry(
	pattern_size: Vector2i,
	mask: PackedByteArray,
	density: int,
	title: String,
	model_id := "pattern_draft",
) -> Dictionary:
	if (
		pattern_size.x < 1 or pattern_size.y < 1
		or pattern_size.x > MAX_SIZE or pattern_size.y > MAX_SIZE
		or mask.size() != pattern_size.x * pattern_size.y
		or density not in [16, 32]
	):
		return {"error":"Паттерн должен быть 1–16 × 1–16 ячеек и иметь плотность 16/32."}
	if mask.count(0) == mask.size():
		return {"error":"Нарисуйте хотя бы одну ячейку паттерна."}
	var built := Shapes.build(
		"empty", Vector3i(pattern_size.x,1,pattern_size.y), density,
		Color.WHITE, model_id, title,
	)
	if not built.get("ok",false):
		return {"error":built.get("error","Не удалось создать геометрию паттерна.")}
	var geometry: EmberVoxelModelResource = built.source
	geometry.tags = PackedStringArray(["stamp","pattern"])
	var grid := geometry.grid_size()
	var origin := Vector2i((grid.x-pattern_size.x)/2,(grid.z-pattern_size.y)/2)
	for y in pattern_size.y:
		for x in pattern_size.x:
			if mask[x+y*pattern_size.x] != 0:
				geometry.voxels[Model.index_of(Vector3i(origin.x+x,0,origin.y+y),grid)] = 1
	return {"geometry":geometry}


static func mask_from_preset(preset: Resource) -> PackedByteArray:
	var result := PackedByteArray()
	if not preset is Preset or preset.geometry == null:
		return result
	var pattern_size: Vector2i = preset.pattern_size
	if pattern_size.x < 1 or pattern_size.y < 1:
		return result
	result.resize(pattern_size.x*pattern_size.y)
	var grid: Vector3i = preset.geometry.grid_size()
	var origin := Vector2i((grid.x-pattern_size.x)/2,(grid.z-pattern_size.y)/2)
	for y in pattern_size.y:
		for x in pattern_size.x:
			var cell := Vector3i(origin.x+x,0,origin.y+y)
			if Model.contains(cell,grid):
				result[x+y*pattern_size.x] = 1 if preset.geometry.voxels[Model.index_of(cell,grid)] != 0 else 0
	return result


static func validation_errors(preset: Resource) -> Array[String]:
	var errors: Array[String] = []
	if not preset is Preset or preset.kind != Preset.KIND_PATTERN:
		errors.append("Пресет не является плоским паттерном.")
		return errors
	if preset.geometry == null:
		errors.append("У паттерна нет геометрии.")
		return errors
	errors.append_array(preset.geometry.validation_errors())
	if preset.pattern_size.x < 1 or preset.pattern_size.y < 1 or preset.pattern_size.x > MAX_SIZE or preset.pattern_size.y > MAX_SIZE:
		errors.append("Размер паттерна должен быть от 1×1 до 16×16.")
	if preset.pattern_depth < 1 or preset.pattern_depth > 32:
		errors.append("Глубина паттерна должна быть от 1 до 32 vox.")
	var mask := mask_from_preset(preset)
	if mask.is_empty() or mask.count(0) == mask.size():
		errors.append("Паттерн не содержит занятых ячеек.")
	var grid: Vector3i = preset.geometry.grid_size()
	for index in preset.geometry.voxels.size():
		if preset.geometry.voxels[index] != 0 and Selection.cell_of(index,grid).y != 0:
			errors.append("Геометрия паттерна должна быть плоской.")
			break
	return errors


static func plan(
	target: EmberVoxelModelResource,
	preset: Resource,
	position: Vector3i,
	normal: Vector3i,
	turns: int,
	mirror: int,
	anchor: int,
	remove: bool,
	depth: int,
	palette_index: int,
	part: int,
	region := Rect2i(),
	height := -1,
) -> Dictionary:
	var placements: Array[Vector3i] = [position]
	return plan_many(
		target,preset,placements,normal,turns,mirror,anchor,remove,depth,
		palette_index,part,region,height,
	)


static func plan_many(
	target: EmberVoxelModelResource,
	preset: Resource,
	placements: Array[Vector3i],
	normal: Vector3i,
	turns: int,
	mirror: int,
	anchor: int,
	remove: bool,
	depth: int,
	palette_index: int,
	part: int,
	region := Rect2i(),
	height := -1,
) -> Dictionary:
	if target == null or not target.validation_errors().is_empty():
		return {"error":"Некорректный voxel-источник."}
	if placements.is_empty():
		return {"error":"Задайте хотя бы одну точку нанесения паттерна."}
	var errors := validation_errors(preset)
	if not errors.is_empty():
		return {"error":errors[0]}
	if target.normalized_density() != preset.geometry.normalized_density():
		return {"error":"Плотности объекта и паттерна должны совпадать (16/32)."}
	var outward := Model.axis_normal(normal)
	if outward == Vector3i.ZERO or mirror not in [-1,0,1,2] or anchor not in [0,1]:
		return {"error":"Некорректная ориентация паттерна."}
	if not remove and (palette_index < 1 or palette_index >= target.palette.size()):
		return {"error":"Выберите цвет для добавления паттерна."}
	var pattern_size: Vector2i = preset.pattern_size
	var mask := mask_from_preset(preset)
	var transformed: Array[Vector2i] = []
	var extent := pattern_size
	for y in pattern_size.y:
		for x in pattern_size.x:
			if mask[x+y*pattern_size.x] == 0:
				continue
			var point := Vector2i(x,y)
			if mirror in [0,2]:
				point.x = extent.x-1-point.x
			if mirror in [1,2]:
				point.y = extent.y-1-point.y
			var rotated_extent := extent
			for turn in posmod(turns,4):
				point = Vector2i(rotated_extent.y-1-point.y,point.x)
				rotated_extent = Vector2i(rotated_extent.y,rotated_extent.x)
			transformed.append(point)
	for turn in posmod(turns,4):
		extent = Vector2i(extent.y,extent.x)
	var pivot := Vector2i.ZERO if anchor == 0 else Vector2i((extent.x-1)/2,(extent.y-1)/2)
	var tangents := Model.tangent_axes(outward)
	var tangent_a: Vector3i = tangents[0]
	var tangent_b: Vector3i = tangents[1]
	var direction := -outward if remove else outward
	var safe_depth := clampi(depth,1,32)
	var candidate_count := placements.size()*transformed.size()*safe_depth
	if candidate_count > Selection.LIMIT*4:
		return {"error":"Путь паттерна слишком велик; увеличьте шаг или сократите жест."}
	var positions: Array[Vector3] = []
	var cells: Array[Vector3i] = []
	for position in placements:
		for point in transformed:
			var seed := position+tangent_a*(point.x-pivot.x)+tangent_b*(point.y-pivot.y)
			for layer in safe_depth:
				var cell := seed+direction*layer
				positions.append(Vector3(cell))
				cells.append(cell)
	var locked := Fragment.Groups.locked_indices(target.voxel_groups)
	var properties := {"voxels":target.voxels.duplicate()}
	for channel in Fragment.CHANNELS:
		if channel == "voxels":
			continue
		var values: PackedByteArray = target.get(channel).duplicate()
		if not values.is_empty():
			properties[channel] = values
	var owners := target.voxel_part_ids.duplicate()
	var selected := PackedInt32Array()
	var selected_set := {}
	for cell in cells:
		if not Fragment._allowed(cell,target,region,height):
			return {"error":"Паттерн выходит за холст или рабочий срез.","positions":positions}
		var index := Model.index_of(cell,target.grid_size())
		var before := int(target.voxels[index])
		if (remove and before == 0) or (not remove and before != 0):
			continue
		if locked.has(index):
			return {"error":"Паттерн затрагивает защищённую группу.","positions":positions}
		properties.voxels[index] = 0 if remove else palette_index
		if remove:
			for channel in Fragment.CHANNELS:
				if channel != "voxels" and properties.has(channel):
					properties[channel][index] = 0
		if not owners.is_empty():
			owners[index] = 0 if remove else clampi(part,0,target.merge_parts.size())
		if not selected_set.has(index):
			selected_set[index] = true
			selected.append(index)
			if selected.size() > Selection.LIMIT:
				return {"error":"Результат паттерна превышает лимит выделения; увеличьте шаг или сократите жест.","positions":positions}
	if not owners.is_empty():
		properties.voxel_part_ids = owners
	var before_properties := {}
	for key in properties.keys():
		if target.get(key) == properties[key]:
			properties.erase(key)
		else:
			before_properties[key] = target.get(key)
	if properties.is_empty():
		return {"error":"Изменений нет: паттерн попал только в занятые или пустые ячейки.","positions":positions}
	return {
		"before":before_properties,
		"properties":properties,
		"selected":selected,
		"positions":positions,
		"placements":placements.duplicate(),
		"label":"Паттерн · %s · %d точек · глубина %d" % [preset.display_name,placements.size(),safe_depth],
	}
