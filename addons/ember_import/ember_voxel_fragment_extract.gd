@tool
extends RefCounted
## Detached crop + remainder using the canonical voxel Resource.
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Groups = preload("res://addons/ember_import/ember_voxel_groups.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")

static func plan(source: EmberVoxelModelResource, indices: PackedInt32Array, cut: bool, limit := Selection.LIMIT) -> Dictionary:
	if source == null or not source.validation_errors().is_empty() or indices.is_empty() or indices.size() > limit:
		return {"error":"Выделите корректный фрагмент, не более %d вокселей." % Selection.LIMIT}
	if not source.emissive_lights.is_empty() or source.emissive_casts_light:
		return {"error":"Отделение модели с отдельными источниками света пока не поддержано."}
	if source.surface_fill_materials.count(0) != source.surface_fill_materials.size():
		return {"error":"Отделяется твёрдая геометрия; сначала уберите водную заливку из этой модели."}
	var selected := {}
	var locked := Groups.locked_indices(source.voxel_groups)
	var low := source.grid_size()
	var high := Vector3i.ZERO
	for index in indices:
		if index < 0 or index >= source.voxels.size() or source.voxels[index] == 0 or (cut and locked.has(index)):
			return {"error":"Выделение устарело или затрагивает защищённую группу."}
		selected[index] = true
		var cell := Selection.cell_of(index,source.grid_size())
		low = low.min(cell)
		high = high.max(cell)
	var piece := source.duplicate(true) as EmberVoxelModelResource
	var remainder := source.duplicate(true) as EmberVoxelModelResource
	var extent := high-low+Vector3i.ONE
	var density := source.normalized_density()
	piece.size_blocks = Vector3i(ceili(float(extent.x)/density),ceili(float(extent.y)/density),ceili(float(extent.z)/density))
	piece.height_voxels = extent.y
	piece.display_name = source.display_name + " · фрагмент"
	piece.imported_from = ""
	piece.imported_source_hash = ""
	piece.surface_fill_levels = PackedInt32Array()
	piece.surface_fill_materials = PackedByteArray()
	piece.surface_fill_palette = PackedByteArray()
	var size := piece.grid_size()
	var mapping := {}
	for index in selected:
		mapping[index] = Model.index_of(Selection.cell_of(index,source.grid_size())-low,size)
	for channel in Fragment.CHANNELS:
		var values: PackedByteArray = source.get(channel)
		if values.is_empty():
			continue
		var cropped := PackedByteArray()
		cropped.resize(size.x*size.y*size.z)
		var rest := values.duplicate()
		for index in mapping:
			cropped[mapping[index]] = values[index]
			if cut:
				rest[index] = 0
		piece.set(channel,cropped)
		remainder.set(channel,rest)
	piece.voxel_part_ids = preload("res://addons/ember_import/ember_voxel_parts.gd").remap(source,mapping,size.x*size.y*size.z)
	if cut and not remainder.voxel_part_ids.is_empty():
		for index in selected:
			remainder.voxel_part_ids[index] = 0
	piece.voxel_groups = []
	remainder.voxel_groups = []
	for group in source.voxel_groups:
		var members := PackedInt32Array()
		var retained := PackedInt32Array()
		for index in group.get("indices",[]):
			if mapping.has(index):
				members.append(mapping[index])
			if not cut or not mapping.has(index):
				retained.append(index)
		if not members.is_empty():
			var entry: Dictionary = group.duplicate(true)
			members.sort()
			entry.indices = members
			piece.voxel_groups.append(entry)
		if not retained.is_empty():
			var entry: Dictionary = group.duplicate(true)
			entry.indices = retained
			remainder.voxel_groups.append(entry)
	return {"piece":piece,"remainder":remainder,"origin":low,"count":selected.size()}
