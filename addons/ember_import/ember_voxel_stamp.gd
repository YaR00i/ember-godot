@tool
extends RefCounted
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Extract = preload("res://addons/ember_import/ember_voxel_fragment_extract.gd")
const Preset = preload("res://addons/ember_import/ember_voxel_stamp_preset.gd")
const DIRECTORY := "res://content/editor/voxel_stamps"

static func capture(source: EmberVoxelModelResource, indices: PackedInt32Array, title: String) -> Dictionary:
	var cropped := Extract.plan(source,indices,false)
	if cropped.has("error"):
		return cropped
	var preset := Preset.new()
	preset.display_name = title.strip_edges()
	if preset.display_name.is_empty():
		return {"error":"Введите название штампа."}
	preset.geometry = cropped.piece
	preset.geometry.display_name = preset.display_name
	preset.geometry.tags = PackedStringArray(["stamp"])
	preset.geometry.voxel_groups = []
	preset.geometry.merge_parts = PackedStringArray()
	preset.geometry.voxel_part_ids = PackedInt32Array()
	return {"preset":preset}

static func save_new(preset: Resource, directory := DIRECTORY, sources := "res://content/voxel_models") -> Dictionary:
	if not preset is Preset or preset.geometry == null or not preset.geometry.validation_errors().is_empty():
		return {"error":"Некорректный штамп."}
	for folder in [directory,sources]:
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
			return {"error":"Не удалось создать папку библиотеки."}
	var id := "vox_stamp_%d" % Time.get_ticks_usec()
	while FileAccess.file_exists(sources.path_join(id+".tres")) or FileAccess.file_exists(directory.path_join(id+".tres")):
		id += "x"
	var saved: Resource = preset.duplicate(true)
	saved.geometry.model_id = id
	var source_path := sources.path_join(id+".tres")
	if ResourceSaver.save(saved.geometry,source_path) != OK:
		return {"error":"Не удалось сохранить геометрию штампа."}
	saved.geometry = ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var path := directory.path_join(id+".tres")
	if ResourceSaver.save(saved,path) != OK:
		return {"error":"Пресет не сохранён. Геометрия оставлена для восстановления: " + source_path}
	return {"path":path}

static func library(directory := DIRECTORY) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(directory):
		return entries
	var files := DirAccess.get_files_at(directory)
	files.sort()
	for file in files:
		if not file.ends_with(".tres"):
			continue
		var path := directory.path_join(file)
		var resource := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		if resource is Preset and resource.geometry != null and resource.geometry.validation_errors().is_empty():
			entries.append({"name":resource.display_name,"path":path,"density":resource.geometry.normalized_density()})
	return entries

static func plan(target: EmberVoxelModelResource, preset: Resource, position: Vector3i, axis: int, turns: int, mirror: int, anchor: int, replace: bool, part: int, region := Rect2i(), height := -1) -> Dictionary:
	if target == null or preset == null or not preset is Preset or preset.geometry == null:
		return {"error":"Выберите штамп."}
	var stamp: EmberVoxelModelResource = preset.geometry
	if axis not in [0,1,2] or mirror not in [-1,0,1,2] or anchor not in [0,1,2]:
		return {"error":"Некорректные параметры штампа."}
	if not target.validation_errors().is_empty() or not stamp.validation_errors().is_empty():
		return {"error":"Некорректный voxel-источник."}
	if stamp.emissive_casts_light or not stamp.emissive_lights.is_empty() or stamp.surface_fill_materials.count(0) != stamp.surface_fill_materials.size():
		return {"error":"Штамп переносит воксели, а не водную заливку или отдельные источники света. Уберите их из модели штампа."}
	if target.normalized_density() != stamp.normalized_density():
		return {"error":"Плотности объекта и штампа должны совпадать (16/32). Размер не меняется скрыто."}
	if target.material != stamp.material:
		return {"error":"Общие настройки материала отличаются. Штамп не будет менять материал всего объекта."}
	var indices := PackedInt32Array()
	var low := stamp.grid_size()
	var high := Vector3i.ZERO
	for index in stamp.voxels.size():
		if stamp.voxels[index] != 0:
			indices.append(index)
			var cell := Fragment.Selection.cell_of(index,stamp.grid_size())
			low = low.min(cell)
			high = high.max(cell)
	if indices.is_empty() or indices.size() > Fragment.Selection.LIMIT:
		return {"error":"Штамп должен содержать 1–32768 занятых вокселей."}
	var span := high-low+Vector3i.ONE
	var positions: Array[Vector3] = []
	for index in indices:
		var cell := Fragment.Selection.cell_of(index,stamp.grid_size())-low
		var extent := span
		if mirror in [0,1,2]:
			cell[mirror] = extent[mirror]-1-cell[mirror]
		for turn in posmod(turns,4):
			var rotated := Fragment.rotate_cell(cell,extent,axis)
			cell = rotated.cell
			extent = rotated.extent
		var pivot := Vector3i.ZERO
		if anchor > 0:
			pivot = Vector3i((extent.x-1)/2,0,(extent.z-1)/2)
		if anchor == 2:
			pivot.y = (extent.y-1)/2
		positions.append(Vector3(cell+position-pivot))
	var properties := {}
	for channel in Fragment.CHANNELS:
		var values: PackedByteArray = target.get(channel).duplicate()
		if values.is_empty():
			values.resize(target.voxels.size())
		properties[channel] = values
	properties.palette = target.palette.duplicate()
	var owners := target.voxel_part_ids.duplicate()
	var locked := Fragment.Groups.locked_indices(target.voxel_groups)
	var selected := PackedInt32Array()
	var colors := {}
	for i in indices.size():
		var cell := Vector3i(positions[i])
		if not Fragment._allowed(cell,target,region,height):
			return {"error":"Штамп выходит за холст или рабочий срез. Переместите его либо расширьте холст.","positions":positions}
		var dest := Fragment.Model.index_of(cell,target.grid_size())
		if not replace and target.voxels[dest] != 0:
			continue
		if locked.has(dest):
			return {"error":"Отпечаток затрагивает защищённую группу.","positions":positions}
		var index := indices[i]
		var color_index := stamp.voxels[index]
		if color_index >= stamp.palette.size():
			return {"error":"Индекс цвета штампа вне палитры.","positions":positions}
		if not colors.has(color_index):
			var mapped := -1
			for candidate in range(1,properties.palette.size()):
				if properties.palette[candidate] == stamp.palette[color_index]:
					mapped = candidate
					break
			if mapped == -1:
				if properties.palette.size() >= 256:
					return {"error":"Не хватает места в палитре. Цвета не округляются.","positions":positions}
				mapped = properties.palette.size()
				properties.palette.append(stamp.palette[color_index])
			colors[color_index] = mapped
		properties.voxels[dest] = colors[color_index]
		for channel in Fragment.CHANNELS:
			if channel == "voxels":
				continue
			var values: PackedByteArray = stamp.get(channel)
			properties[channel][dest] = values[index] if not values.is_empty() else 0
		if not owners.is_empty() and target.voxels[dest] == 0:
			owners[dest] = clampi(part,0,target.merge_parts.size())
		selected.append(dest)
	if not owners.is_empty():
		properties.voxel_part_ids = owners
	var before := {}
	for key in properties.keys():
		if key in Fragment.CHANNELS and key != "voxels" and target.get(key).is_empty() and properties[key].count(0) == properties[key].size():
			properties.erase(key)
		elif target.get(key) == properties[key]:
			properties.erase(key)
		else:
			before[key] = target.get(key)
	if properties.is_empty():
		return {"error":"Изменений нет: место занято или отпечаток уже совпадает.","positions":positions}
	return {"before":before,"properties":properties,"selected":selected,"positions":positions,"label":"Штамп · " + preset.display_name}
