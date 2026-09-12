@tool
extends RefCounted
## Pure merge plan, in the primary mesh's block frame. No scene or asset writes.
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Extract = preload("res://addons/ember_import/ember_voxel_fragment_extract.gd")
const MAX_CELLS := 524288

static func plan(inputs: Array[Dictionary], align_grid := false) -> Dictionary:
	if inputs.size() < 2 or inputs.size() > 32:
		return {"error":"Выберите от 2 до 32 деталей."}
	var density := 16
	for item in inputs:
		var source: EmberVoxelModelResource = item.source
		if source == null or not source.validation_errors().is_empty():
			return {"error":"Некорректный voxel-источник."}
		if source.emissive_casts_light or not source.emissive_lights.is_empty() or not source.surface_fill_levels.is_empty():
			return {"error":"Склейка пока предназначена для твёрдых деталей без воды и отдельных источников света."}
		density = maxi(density,source.normalized_density())
	var first: EmberVoxelModelResource = inputs[0].source
	var base: Transform3D = inputs[0].frame
	if absf(base.basis.determinant()) < 0.000001:
		return {"error":"Нулевой масштаб не поддерживается."}
	var slots: Array[Dictionary] = []
	var adjustments: Array[Dictionary] = []
	var low := Vector3i(2147483647,2147483647,2147483647)
	var high := -low
	var palette := PackedColorArray([Color.TRANSPARENT])
	var names := PackedStringArray()
	for item in inputs:
		var source: EmberVoxelModelResource = item.source
		for property in ["material","physical","emissive_strength","emissive_suppress_host_shadow"]:
			if source.get(property) != first.get(property):
				return {"error":"У деталей различаются общие настройки материала или физики: " + property}
		var relative: Transform3D = base.affine_inverse()*item.frame
		var snapped := Basis(relative.basis.x.round(),relative.basis.y.round(),relative.basis.z.round())
		if not relative.basis.is_equal_approx(snapped) or not is_equal_approx(snapped.determinant(),1.0) or not snapped.transposed().is_equal_approx(snapped.inverse()):
			return {"error":"Нужны согласованный масштаб и повороты на 90°. Произвольные повороты, отражение и масштаб не округляются: сначала явно выровняйте детали."}
		var offset := relative.origin*density
		if not offset.is_equal_approx(offset.round()) and not align_grid:
			return {"error":"Сетки деталей не совпадают. Нажмите «Совместить сетки», чтобы увидеть ближайшее положение без изменения сцены."}
		var delta := offset.round()-offset
		if align_grid and not offset.is_equal_approx(offset.round()):
			adjustments.append({"name":str(item.get("name",source.display_name)),"before":item.frame,"delta_vox":delta,"delta_world":base.basis*(delta/density),"source_index":slots.size()})
		var origin := Vector3i(offset.round())
		var ratio := density/source.normalized_density()
		var extent := source.grid_size()*ratio
		for x in [0,extent.x]:
			for y in [0,extent.y]:
				for z in [0,extent.z]:
					var corner := Vector3i(snapped*Vector3(x,y,z))+origin
					low = low.min(corner)
					high = high.max(corner)
		var colors := PackedByteArray()
		colors.resize(source.palette.size())
		for i in range(1,source.palette.size()):
			var mapped := -1
			for candidate in range(1,palette.size()):
				if palette[candidate] == source.palette[i]:
					mapped = candidate
					break
			if mapped < 0:
				if palette.size() == 256:
					return {"error":"Общая палитра превышает 255 цветов. Склейка остановлена без потери цветов."}
				mapped = palette.size()
				palette.append(source.palette[i])
			colors[i] = mapped
		var part_offset := names.size()
		if source.merge_parts.is_empty():
			names.append(str(item.get("name",source.display_name)))
		else:
			names.append_array(source.merge_parts)
		if names.size() > 32:
			return {"error":"В склейке получится больше 32 исходных частей. Склейте меньший участок."}
		slots.append({"source":source,"basis":snapped,"origin":origin,"ratio":ratio,"colors":colors,"part_offset":part_offset})
	var size := high-low
	size.x = ceili(float(size.x)/density)*density
	size.z = ceili(float(size.z)/density)*density
	if size.x > 256 or size.z > 256 or size.y > 8*density or size.x*size.y*size.z > MAX_CELLS:
		return {"error":"Общий холст превышает 524 288 ячеек, 256 vox по XZ или допустимую высоту. Склейте меньший участок."}
	var result := first.duplicate(true) as EmberVoxelModelResource
	var has_collision_channel := false
	for input in inputs:
		has_collision_channel = has_collision_channel or not (input.source as EmberVoxelModelResource).collision_voxels.is_empty()
	result.model_id = "merge_draft"
	result.display_name = "Склейка"
	result.schema_version = EmberVoxelModelResource.SCHEMA_VERSION
	result.imported_from = ""
	result.imported_source_hash = ""
	result.voxels_per_block = density
	result.size_blocks = Vector3i(size.x/density,ceili(float(size.y)/density),size.z/density)
	result.height_voxels = size.y
	result.palette = palette
	result.merge_parts = names
	result.voxel_groups = []
	result.voxel_part_ids = PackedInt32Array()
	result.voxel_part_ids.resize(size.x*size.y*size.z)
	var channels := {}
	for channel in Fragment.CHANNELS:
		var values := PackedByteArray()
		values.resize(result.voxel_part_ids.size())
		channels[channel] = values
	var overlap := {}
	for slot_index in slots.size():
		var slot := slots[slot_index]
		var source: EmberVoxelModelResource = slot.source
		var mapping := {}
		for index in source.voxels.size():
			if source.voxels[index] == 0:
				continue
			if source.voxels[index] >= slot.colors.size():
				return {"error":"Индекс вокселя вне палитры."}
			var cell := Selection.cell_of(index,source.grid_size())*int(slot.ratio)
			var destinations := PackedInt32Array()
			for y in slot.ratio:
				for z in slot.ratio:
					for x in slot.ratio:
						var point: Vector3 = slot.basis*(Vector3(cell+Vector3i(x,y,z))+Vector3.ONE*0.5)+Vector3(slot.origin-low)
						var target := Vector3i(point.floor())
						var destination := VoxMesher.cell_index(target.x,target.y,target.z,size.x,size.z)
						if channels.voxels[destination] != 0:
							overlap[destination] = true
							continue
						channels.voxels[destination] = slot.colors[source.voxels[index]]
						for channel in Fragment.CHANNELS:
							var values: PackedByteArray = source.get(channel)
							if channel == "collision_voxels" and has_collision_channel:
								channels[channel][destination] = values[index] if not values.is_empty() else 1
							elif channel != "voxels" and not values.is_empty():
								channels[channel][destination] = values[index]
						var owner := 1 if source.voxel_part_ids.is_empty() else source.voxel_part_ids[index]
						result.voxel_part_ids[destination] = owner+int(slot.part_offset) if owner != 0 else 0
						destinations.append(destination)
			mapping[index] = destinations
		for group in source.voxel_groups:
			var members := PackedInt32Array()
			for index in group.get("indices",[]):
				members.append_array(mapping.get(index,PackedInt32Array()))
			if not members.is_empty():
				members.sort()
				var copy: Dictionary = group.duplicate(true)
				copy.id = "%d_%s" % [slot_index,str(group.id)]
				copy.indices = members
				result.voxel_groups.append(copy)
	for channel in channels:
		if channel == "collision_voxels" and not has_collision_channel:
			result.collision_voxels = PackedByteArray()
		else:
			result.set(channel,channels[channel])
	return {"source":result,"frame":base*Transform3D(Basis.IDENTITY,Vector3(low)/density),"overlap":PackedInt32Array(overlap.keys()),"adjustments":adjustments}

static func separate(source: EmberVoxelModelResource) -> Dictionary:
	if source == null or source.merge_parts.is_empty() or not source.validation_errors().is_empty():
		return {"error":"У выбранной модели нет сохранённых частей склейки."}
	var members := {}
	for index in source.voxels.size():
		if source.voxels[index] != 0:
			var owner := source.voxel_part_ids[index]
			if not members.has(owner):
				members[owner] = PackedInt32Array()
			members[owner].append(index)
	if members.is_empty():
		return {"error":"Модель пуста — нечего разбирать."}
	var pieces: Array[Dictionary] = []
	for owner in members:
		var extracted := Extract.plan(source,members[owner],false,MAX_CELLS)
		if extracted.has("error"):
			return extracted
		var piece: EmberVoxelModelResource = extracted.piece
		piece.display_name = "Добавленное" if owner == 0 else source.merge_parts[owner-1]
		piece.merge_parts = PackedStringArray()
		piece.voxel_part_ids = PackedInt32Array()
		pieces.append({"source":piece,"origin":extracted.origin})
	return {"pieces":pieces}
