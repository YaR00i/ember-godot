@tool
extends RefCounted
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Extract = preload("res://addons/ember_import/ember_voxel_fragment_extract.gd")
const Preset = preload("res://addons/ember_import/ember_voxel_stamp_preset.gd")
const Placement = preload("res://addons/ember_import/ember_voxel_brush_placement.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
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
	var validation_error := _preset_validation_error(preset)
	if not validation_error.is_empty():
		return {"error": validation_error}
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

static func save_existing(preset: Resource, path: String, source_path: String) -> Dictionary:
	var validation_error := _preset_validation_error(preset)
	if not validation_error.is_empty():
		return {"error": validation_error}
	if path.is_empty() or source_path.is_empty() or not FileAccess.file_exists(path) or not FileAccess.file_exists(source_path):
		return {"error":"Исходный пресет не найден. Сохраните источник как новый."}
	var previous := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not previous is Preset or previous.geometry == null:
		return {"error":"Исходный пресет повреждён."}
	var saved: Resource = preset.duplicate(true)
	saved.geometry.model_id = previous.geometry.model_id
	if ResourceSaver.save(saved.geometry,source_path) != OK:
		return {"error":"Не удалось обновить геометрию источника."}
	saved.geometry = ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if ResourceSaver.save(saved,path) != OK:
		return {"error":"Не удалось обновить пресет источника."}
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
		if resource is Preset and _preset_validation_error(resource).is_empty():
			var generator_id := ""
			var variant_count := 1
			if resource.generator_recipe != null:
				generator_id = str(resource.generator_recipe.get("generator_id"))
				var settings := Generator.normalized_parameters(
					generator_id, resource.generator_recipe.get("parameters")
				)
				variant_count = int(settings.get("variant_count", 1))
			entries.append({
				"name":resource.display_name,
				"path":path,
				"density":resource.geometry.normalized_density(),
				"kind":resource.kind,
				"pattern_size":resource.pattern_size,
				"pattern_depth":resource.pattern_depth,
				"generator_id":generator_id,
				"variant_count":variant_count,
			})
	return entries


static func _preset_validation_error(preset: Resource) -> String:
	if not preset is Preset or preset.geometry == null:
		return "Некорректный штамп."
	var geometry_errors: Array[String] = preset.geometry.validation_errors()
	if not geometry_errors.is_empty():
		return "Некорректная геометрия штампа: " + geometry_errors[0]
	if preset.kind not in [Preset.KIND_VOLUME, Preset.KIND_PATTERN, Preset.KIND_GENERATED_VOLUME]:
		return "Неизвестный тип источника штампа."
	if preset.kind == Preset.KIND_GENERATED_VOLUME:
		var generator_errors := Generator.validation_errors(preset.generator_recipe)
		if not generator_errors.is_empty():
			return generator_errors[0]
	return ""


static func prepare_generated_variants(preset: Resource) -> Dictionary:
	if not preset is Preset or preset.geometry == null:
		return {"error": "Некорректный штамп."}
	var variants: Array[EmberVoxelModelResource] = [preset.geometry]
	if preset.kind != Preset.KIND_GENERATED_VOLUME:
		return {"variants": variants}
	var cache_key := Generator.variant_cache_key(preset.generator_recipe, preset.geometry)
	if (
		preset.generated_variants_key == cache_key
		and not preset.generated_variants.is_empty()
	):
		return {"variants": preset.generated_variants}
	var built := Generator.build_variants(preset.generator_recipe, preset.geometry)
	if built.has("error"):
		return built
	preset.generated_variants.assign(built.variants)
	preset.generated_variants_key = cache_key
	return {"variants": preset.generated_variants}


static func recommended_spacing(preset: Resource) -> int:
	if (
		not preset is Preset
		or preset.kind != Preset.KIND_GENERATED_VOLUME
		or preset.generator_recipe == null
	):
		return 1
	var settings := Generator.normalized_parameters(
		preset.generator_recipe.generator_id, preset.generator_recipe.parameters
	)
	if (
		int(settings.get("variant_count", 1)) <= 1
		and Generator.placement_defaults(preset.generator_recipe).is_empty()
	):
		return 1
	return Generator.recommended_spacing(preset.generator_recipe)


static func recommended_placement(preset: Resource) -> Dictionary:
	if (
		not preset is Preset
		or preset.kind != Preset.KIND_GENERATED_VOLUME
		or preset.generator_recipe == null
	):
		return {}
	return Generator.placement_defaults(preset.generator_recipe)


static func plan(target: EmberVoxelModelResource, preset: Resource, position: Vector3i, axis: int, turns: int, mirror: int, anchor: int, replace: bool, part: int, region := Rect2i(), height := -1, surface_normal := Vector3i.ZERO, indent := false) -> Dictionary:
	return plan_many(target,preset,[position],axis,turns,mirror,anchor,replace,part,region,height,PackedInt32Array(),surface_normal,false,2,indent)

static func sample_line(from: Vector3i, to: Vector3i, spacing: int) -> Array[Vector3i]:
	return Placement.sample_line(from, to, spacing)

static func sample_path(knots: Array[Vector3i], spacing: int) -> Array[Vector3i]:
	return Placement.sample_path(knots, spacing)


static func scatter_instances(
	target: EmberVoxelModelResource,
	placements: Array[Vector3i],
	normal: Vector3i,
	spread: int,
	seed: int,
	add_outward: bool,
	variant_count := 1,
) -> Dictionary:
	return Placement.scatter_instances(
		target, placements, normal, spread, seed, add_outward, variant_count
	)


static func plan_scatter(
	target: EmberVoxelModelResource,
	preset: Resource,
	placements: Array[Vector3i],
	normal: Vector3i,
	spread: int,
	seed: int,
	random_turns: bool,
	turns: int,
	mirror: int,
	anchor: int,
	replace: bool,
	part: int,
	region := Rect2i(),
	height := -1,
	conform_surface := false,
	max_bend := 2,
	indent := false,
) -> Dictionary:
	var prepared := prepare_generated_variants(preset)
	if prepared.has("error"):
		return prepared
	var variants: Array[EmberVoxelModelResource] = []
	variants.assign(prepared.variants)
	var scatter := scatter_instances(
		target, placements, normal, spread, seed, not replace and not indent, variants.size()
	)
	if scatter.has("error"):
		return scatter
	var instances: Array = scatter.instances
	var scattered_placements: Array[Vector3i] = []
	var scattered_turns := PackedInt32Array()
	var scattered_variants := PackedInt32Array()
	for instance in instances:
		scattered_placements.append(instance.position)
		scattered_turns.append(instance.turns if random_turns else turns)
		scattered_variants.append(instance.variant)
	var result := _plan_many_variants(
		target,preset,variants,scattered_variants,
		scattered_placements,Fragment.Model.axis_index(normal),turns,
		mirror,anchor,replace,part,region,height,scattered_turns,normal,
		conform_surface,max_bend,indent,
	)
	if not result.has("error"):
		result.label = "%s · %s · %d точек" % ["Россыпь-вдавливание" if indent else "Россыпь",preset.display_name,scattered_placements.size()]
		result.scatter_seed = seed
		result.scatter_base_placements = placements.duplicate()
		result.scatter_turns = scattered_turns
		result.scatter_variants = scattered_variants
	return result


static func _scatter_surface_placement(
	target: EmberVoxelModelResource,
	candidate: Vector3i,
	outward: Vector3i,
	add_outward: bool,
	snap_distance: int,
) -> Vector3i:
	return Placement.surface_placement(
		target, candidate, outward, add_outward, snap_distance
	)


static func _conform_offsets(
	target: EmberVoxelModelResource,
	placement: Vector3i,
	offsets: Array,
	outward: Vector3i,
	add_outward: bool,
	max_bend: int,
	indent: bool,
) -> Dictionary:
	var normal := Fragment.Model.axis_normal(outward)
	if normal == Vector3i.ZERO:
		return {"error":"Облегание требует видимую грань поверхности."}
	var tangents := Fragment.Model.tangent_axes(normal)
	var tangent_a: Vector3i = tangents[0]
	var tangent_b: Vector3i = tangents[1]
	var column_contacts := {}
	for raw_offset in offsets:
		var offset: Vector3i = raw_offset
		var key := Vector2i(_dot_i(offset,tangent_a),_dot_i(offset,tangent_b))
		var depth := _dot_i(offset,normal)
		if (
			not column_contacts.has(key)
			or (indent and depth > int(column_contacts[key]))
			or (not indent and depth < int(column_contacts[key]))
		):
			column_contacts[key] = depth
	var column_shifts := {}
	for key in column_contacts:
		var rigid_contact: Vector3i = (
			placement
			+tangent_a*key.x
			+tangent_b*key.y
			+normal*int(column_contacts[key])
		)
		var snapped := _scatter_surface_placement(
			target,rigid_contact,normal,add_outward,clampi(max_bend,1,8)
		)
		if snapped == Fragment.Model.INVALID_CELL:
			return {
				"error":"Облегание не нашло поверхность в пределах %d vox. Увеличьте «Макс. изгиб» или выключите облегание." % clampi(max_bend,1,8),
			}
		column_shifts[key] = _dot_i(snapped-rigid_contact,normal)
	var conformed: Array[Vector3i] = []
	for raw_offset in offsets:
		var offset: Vector3i = raw_offset
		var key := Vector2i(_dot_i(offset,tangent_a),_dot_i(offset,tangent_b))
		conformed.append(offset+normal*int(column_shifts[key]))
	return {"offsets":conformed}


static func _dot_i(a: Vector3i, b: Vector3i) -> int:
	return a.x*b.x+a.y*b.y+a.z*b.z


static func _stamp_offsets(
	stamp: EmberVoxelModelResource,
	indices: PackedInt32Array,
	low: Vector3i,
	high: Vector3i,
	axis: int,
	turns: int,
	mirror: int,
	anchor: int,
	surface_normal: Vector3i,
	indent: bool,
) -> Array[Vector3i]:
	var span := high-low+Vector3i.ONE
	var offsets: Array[Vector3i] = []
	var oriented_normal := Fragment.Model.axis_normal(surface_normal)
	var rotation_axis := 1 if oriented_normal != Vector3i.ZERO else axis
	for index in indices:
		var cell := Fragment.Selection.cell_of(index,stamp.grid_size())-low
		var extent := span
		if mirror in [0,1,2]:
			cell[mirror] = extent[mirror]-1-cell[mirror]
		for turn in posmod(turns,4):
			var rotated := Fragment.rotate_cell(cell,extent,rotation_axis)
			cell = rotated.cell
			extent = rotated.extent
		var pivot := Vector3i.ZERO
		if anchor > 0:
			pivot = Vector3i((extent.x-1)/2,0,(extent.z-1)/2)
		if anchor == 2 and not indent:
			pivot.y = (extent.y-1)/2
		var relative := cell-pivot
		if oriented_normal == Vector3i.ZERO:
			offsets.append(relative)
		else:
			var tangents := Fragment.Model.tangent_axes(oriented_normal)
			var normal_depth := -relative.y if indent else relative.y
			offsets.append(
				tangents[0]*relative.x
				+oriented_normal*normal_depth
				+tangents[1]*relative.z
			)
	return offsets


static func plan_many(target: EmberVoxelModelResource, preset: Resource, placements: Array[Vector3i], axis: int, turns: int, mirror: int, anchor: int, replace: bool, part: int, region := Rect2i(), height := -1, instance_turns := PackedInt32Array(), surface_normal := Vector3i.ZERO, conform_surface := false, max_bend := 2, indent := false) -> Dictionary:
	var variants: Array[EmberVoxelModelResource] = []
	if preset is Preset and preset.geometry != null:
		variants.append(preset.geometry)
	return _plan_many_variants(
		target, preset, variants, PackedInt32Array(), placements, axis, turns,
		mirror, anchor, replace, part, region, height, instance_turns,
		surface_normal, conform_surface, max_bend, indent,
	)


static func _plan_many_variants(
	target: EmberVoxelModelResource,
	preset: Resource,
	variants: Array[EmberVoxelModelResource],
	instance_variants: PackedInt32Array,
	placements: Array[Vector3i],
	axis: int,
	turns: int,
	mirror: int,
	anchor: int,
	replace: bool,
	part: int,
	region := Rect2i(),
	height := -1,
	instance_turns := PackedInt32Array(),
	surface_normal := Vector3i.ZERO,
	conform_surface := false,
	max_bend := 2,
	indent := false,
) -> Dictionary:
	if target == null or preset == null or not preset is Preset or preset.geometry == null:
		return {"error":"Выберите штамп."}
	if placements.is_empty():
		return {"error":"Задайте хотя бы одну точку штампа."}
	if axis not in [0,1,2] or mirror not in [-1,0,1,2] or anchor not in [0,1,2]:
		return {"error":"Некорректные параметры штампа."}
	if not target.validation_errors().is_empty() or variants.is_empty():
		return {"error":"Некорректный voxel-источник."}
	if not instance_variants.is_empty() and instance_variants.size() != placements.size():
		return {"error":"Внутренняя ошибка набора форм россыпи."}
	var contexts: Array[Dictionary] = []
	for stamp: EmberVoxelModelResource in variants:
		if stamp == null or not stamp.validation_errors().is_empty():
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
		contexts.append({"stamp": stamp, "indices": indices, "low": low, "high": high})
	var potential_cells := 0
	for placement_index in placements.size():
		var variant_index := int(instance_variants[placement_index]) if not instance_variants.is_empty() else 0
		if variant_index < 0 or variant_index >= contexts.size():
			return {"error":"Внутренняя ошибка выбора формы россыпи."}
		potential_cells += int(contexts[variant_index].indices.size())
	if potential_cells > Fragment.Selection.LIMIT*4:
		return {"error":"Путь слишком велик для одного preview. Увеличьте шаг или разделите его на несколько жестов."}
	if not instance_turns.is_empty() and instance_turns.size() != placements.size():
		return {"error":"Внутренняя ошибка вариантов россыпи."}
	if conform_surface and Fragment.Model.axis_normal(surface_normal) == Vector3i.ZERO:
		return {"error":"Облегание требует видимую грань поверхности."}
	if indent and Fragment.Model.axis_normal(surface_normal) == Vector3i.ZERO:
		return {"error":"Вдавливание должно начинаться на видимой грани поверхности."}
	var placement_defaults := recommended_placement(preset)
	if (
		bool(placement_defaults.get("up_only", false))
		and Fragment.Model.axis_normal(surface_normal) not in [Vector3i.ZERO, Vector3i.UP]
	):
		return {"error":"Трава растёт вверх: начните россыпь на верхней поверхности."}
	var offset_sets := {}
	var instance_offsets: Array = []
	var positions: Array[Vector3] = []
	for placement_index in placements.size():
		var variant_index := int(instance_variants[placement_index]) if not instance_variants.is_empty() else 0
		var context: Dictionary = contexts[variant_index]
		var stamp: EmberVoxelModelResource = context.stamp
		var indices: PackedInt32Array = context.indices
		var low: Vector3i = context.low
		var high: Vector3i = context.high
		var active_turns := int(instance_turns[placement_index]) if not instance_turns.is_empty() else turns
		var offset_key := "%d:%d" % [variant_index, active_turns]
		if not offset_sets.has(offset_key):
			offset_sets[offset_key] = _stamp_offsets(
				stamp,indices,low,high,axis,active_turns,mirror,anchor,surface_normal,indent
			)
		var offsets: Array = offset_sets[offset_key]
		var placement: Vector3i = placements[placement_index]
		if conform_surface:
			var conformed := _conform_offsets(
				target,placement,offsets,surface_normal,not replace and not indent,max_bend,indent
			)
			if conformed.has("error"):
				for raw_offset in offsets:
					positions.append(Vector3(placement+raw_offset))
				return {"error":conformed.error,"positions":positions}
			offsets = conformed.offsets
		instance_offsets.append(offsets)
		for raw_offset in offsets:
			var offset: Vector3i = raw_offset
			positions.append(Vector3(placement+offset))
	var requires_collision_channel := not target.collision_voxels.is_empty()
	for context: Dictionary in contexts:
		var context_stamp: EmberVoxelModelResource = context.stamp
		requires_collision_channel = (
			requires_collision_channel or not context_stamp.collision_voxels.is_empty()
		)
	var properties := {}
	for channel in Fragment.CHANNELS:
		var values: PackedByteArray = target.get(channel).duplicate()
		if values.is_empty():
			values.resize(target.voxels.size())
			if channel == "collision_voxels" and requires_collision_channel:
				for index in target.voxels.size():
					values[index] = 1 if target.voxels[index] != 0 else 0
		properties[channel] = values
	properties.palette = target.palette.duplicate()
	var owners := target.voxel_part_ids.duplicate()
	var locked := Fragment.Groups.locked_indices(target.voxel_groups)
	var selected := PackedInt32Array()
	var selected_set := {}
	var colors := {}
	for placement_index in placements.size():
		var variant_index := int(instance_variants[placement_index]) if not instance_variants.is_empty() else 0
		var context: Dictionary = contexts[variant_index]
		var stamp: EmberVoxelModelResource = context.stamp
		var indices: PackedInt32Array = context.indices
		var offsets: Array = instance_offsets[placement_index]
		var placement: Vector3i = placements[placement_index]
		for i in indices.size():
			var offset: Vector3i = offsets[i]
			var cell := placement+offset
			if not Fragment._allowed(cell,target,region,height):
				return {"error":("Вдавливание" if indent else "Штамп")+" выходит за холст или рабочий срез. Переместите его либо расширьте холст.","positions":positions}
			var dest := Fragment.Model.index_of(cell,target.grid_size())
			if indent:
				if target.voxels[dest] == 0:
					continue
				if locked.has(dest):
					return {"error":"Вдавливание затрагивает защищённую группу.","positions":positions}
				for channel in Fragment.CHANNELS:
					properties[channel][dest] = 0
				if not owners.is_empty():
					owners[dest] = 0
				if not selected_set.has(dest):
					if selected.size() >= Fragment.Selection.LIMIT:
						return {"error":"Результат превышает 32768 вокселей. Увеличьте шаг или разделите путь.","positions":positions}
					selected_set[dest] = true
					selected.append(dest)
				continue
			if not replace and target.voxels[dest] != 0:
				continue
			if locked.has(dest):
				return {"error":"Отпечаток затрагивает защищённую группу.","positions":positions}
			var index := indices[i]
			var color_index := stamp.voxels[index]
			if color_index >= stamp.palette.size():
				return {"error":"Индекс цвета штампа вне палитры.","positions":positions}
			var color_key := "%d:%d" % [variant_index, color_index]
			if not colors.has(color_key):
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
				colors[color_key] = mapped
			properties.voxels[dest] = colors[color_key]
			for channel in Fragment.CHANNELS:
				if channel == "voxels":
					continue
				var values: PackedByteArray = stamp.get(channel)
				if channel == "collision_voxels" and requires_collision_channel:
					properties[channel][dest] = values[index] if not values.is_empty() else 1
				else:
					properties[channel][dest] = values[index] if not values.is_empty() else 0
			if not owners.is_empty() and target.voxels[dest] == 0:
				owners[dest] = clampi(part,0,target.merge_parts.size())
			if not selected_set.has(dest):
				if selected.size() >= Fragment.Selection.LIMIT:
					return {"error":"Результат превышает 32768 вокселей. Увеличьте шаг или разделите путь.","positions":positions}
				selected_set[dest] = true
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
		return {"error":("Изменений нет: вдавливание попало только в пустые ячейки." if indent else "Изменений нет: место занято или отпечаток уже совпадает."),"positions":positions}
	var label: String = ("Вдавить · " if indent else "Штамп · ")+preset.display_name
	if placements.size() > 1:
		label += " · %d точек" % placements.size()
	return {
		"before":before,
		"properties":properties,
		"selected":selected,
		"positions":positions,
		"placements":placements,
		"instance_variants":instance_variants.duplicate(),
		"label":label,
		"removes":indent,
	}
