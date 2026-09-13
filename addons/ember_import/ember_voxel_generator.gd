@tool
extends RefCounted

## Creation UI descriptors share the provider's normalized parameters. Adding an
## object provider does not require another panel, preset format or batch owner.
static func creation_fields(generator_id: String) -> Array[Dictionary]:
	if generator_id == ROCK:
		var rock_fields: Array[Dictionary] = [
			{"key": "rock_type", "title": "Форма объекта", "options": ["Валун", "Угловатый камень", "Плоская плита", "Сросток кристаллов", "Ледяные глыбы"], "identity": true},
			{"key": "dimensions", "title": "Размеры · vox", "type": "vector3i", "min": 3, "max": Rock.OBJECT_MAX_DIMENSION},
			{"key": "roughness", "title": "Неровность · %", "min": 0, "max": 100},
			{"key": "chips", "title": "Сколы · %", "min": 0, "max": 100},
			{"key": "stone_color", "title": "Цвет камня", "type": "color"},
			{"key": "generation_version", "title": "Алгоритм · совместимость", "options": ["Прежний штамп", "Объёмные формы"], "offset": 1, "advanced": true},
			{"key": "density", "title": "Плотность сетки", "options": ["16 vox / блок", "32 vox / блок"], "values": [16,32], "advanced": true},
		]
		rock_fields.append_array(Rock.cluster_fields())
		rock_fields.append_array(Rock.Surface.fields())
		return rock_fields
	if generator_id != LARGE_TREE:
		return []
	var fields: Array[Dictionary] = [
		{"key": "tree_type", "title": "Тип дерева · выбор актуальной формы для новой генерации", "options": ["Саванна", "Дуб", "Берёза", "Клён", "Ель"], "identity": true},
		{"key": "branch_direction", "title": "Направление ветвей", "options": ["По типу дерева", "Вверх", "В стороны", "Слегка вниз"]},
		{"key": "crown_shape", "title": "Силуэт", "options": ["Широкая крона", "Вытянутая", "Ярусная"]},
		{"key": "height", "title": "Высота · vox", "min": 64, "max": 256},
		{"key": "trunk_width", "title": "Толщина ствола · vox", "min": 3, "max": 24},
		{"key": "crown_spread", "title": "Ширина кроны", "min": 25, "max": 85},
		{"key": "branchiness", "title": "Ветвистость", "min": 0, "max": 100},
		{"key": "structure_diversity", "title": "Разнообразие каркаса · %", "min": 0, "max": 100},
		{"key": "foliage_amount", "title": "Количество листвы", "min": 0, "max": 100},
		{"key": "foliage_style", "title": "Стиль листвы", "options": ["Прежняя", "Пиксель-арт · пробная", "Листовые побеги · пробные", "Лиственные облака · пробные"]},
		{"key": "foliage_leaf_size", "title": "Размер листика · vox", "min": 3, "max": 12},
		{"key": "foliage_leaf_accents", "title": "Выраженность листиков · %", "min": 0, "max": 100},
		{"key": "foliage_detail", "title": "Детализация листвы", "min": 0, "max": 100},
		{"key": "foliage_pattern_strength", "title": "Выраженность рисунка · %", "min": 0, "max": 100},
		{"key": "foliage_along", "title": "Листва вдоль ветвей · %", "min": 0, "max": 100},
		{"key": "bark_color", "title": "Кора", "type": "color"},
		{"key": "foliage_color", "title": "Листва", "type": "color"},
	]
	for item in [
		["branch_thickness", "Толщина ветвей", 25, 100],
		["branch_taper", "Сужение ветвей", 0, 100],
		["branch_curve", "Изгиб ветвей", 0, 100],
		["branch_start", "Начало ветвления", 20, 55],
		["cluster_size", "Размер масс листвы", 65, 180],
		["cluster_flatten", "Уплощение листвы", 0, 100],
		["canopy_cohesion", "Связность кроны", 0, 100],
		["irregularity", "Неровность", 0, 100],
		["root_flare", "Расширение корней", 0, 100],
	]:
		fields.append({"key": item[0], "title": item[1], "min": item[2], "max": item[3], "advanced": true})
	fields.append({"key": "generation_version", "title": "Совместимость · алгоритм", "options": ["Классический", "Крупные формы", "Характер дерева", "Дуб · развилки и крона", "Берёза · лёгкие ветви", "Клён · округлая крона", "Клён · высокая крона", "Дуб · взрослый раскидистый", "Саванна · зонтичная", "Ель · хвойные ярусы", "Дуб · разнообразный каркас", "Клён · разнообразный каркас", "Берёза · разнообразный каркас", "Саванна · разнообразный каркас", "Ель · разнообразный каркас", "Дуб · композиция и центральные развилки", "Дуб · боковое вторичное ветвление"], "offset": 1, "advanced": true})
	fields.append({"key": "leaf_density", "title": "Плотность · классический", "min": 20, "max": 100, "advanced": true})
	fields.append({"key": "density", "title": "Плотность сетки", "options": ["16 vox / блок", "32 vox / блок"], "values": [16, 32], "advanced": true})
	for field in LargeTreeProvider.BarkPattern.fields():
		field["advanced"] = true
		fields.append(field)
	return fields


static func creation_description(recipe: Resource) -> String:
	for field in creation_fields(recipe.generator_id):
		if not bool(field.get("identity", false)) or not field.has("options"): continue
		var value: int = int(recipe.parameters.get(field.key, 0))
		var index: int = field.values.find(value) if field.has("values") else value - int(field.get("offset", 0))
		if index >= 0 and index < field.options.size(): return str(field.options[index])
	return ""


static func creation_presets(generator_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if generator_id == ROCK:
		for item in [
			{"name": "Камни · Валун", "type": 0, "dimensions": Vector3i(24,18,21), "roughness": 35, "chips": 15},
			{"name": "Камни · Угловатый", "type": 1, "dimensions": Vector3i(24,23,20), "roughness": 15, "chips": 40},
			{"name": "Камни · Плоская плита", "type": 2, "dimensions": Vector3i(36,7,28), "roughness": 20, "chips": 20},
			{"name": "Оформление · Замшелый валун", "type": 0, "dimensions": Vector3i(24,18,21), "roughness": 25, "chips": 15, "surface": {"surface_strength": 65, "moss_coverage": 65, "moss_drape": 55, "moss_highlight_color": Color("586738"), "moss_highlight_strength": 25}},
			{"name": "Оформление · Камень с жилой", "type": 1, "dimensions": Vector3i(24,23,20), "roughness": 15, "chips": 40, "surface": {"surface_strength": 45, "mineral_pattern": 2, "mineral_vein_style": 1, "mineral_width": 2, "mineral_color": Color("8b8170")}},
			{"name": "Оформление · Слоистая плита", "type": 2, "dimensions": Vector3i(36,9,28), "roughness": 15, "chips": 20, "surface": {"stone_color": Color("63503c"), "surface_strength": 35, "mineral_pattern": 1, "mineral_direction": 0, "mineral_spacing": 5, "mineral_width": 2, "mineral_color": Color("a1845c")}},
			{"name": "Кристаллы · Острые сростки", "type": 3, "dimensions": Vector3i(36,40,30), "roughness": 0, "chips": 10, "surface": {"stone_color": Color("18334f"), "crystal_count": 5, "crystal_width": 9, "crystal_variation": 80, "crystal_lean": 55, "crystal_tip": 1, "crystal_base_size": 30, "surface_strength": 25, "surface_patch_size": 24}},
			{"name": "Кристаллы · Обломанные столбы", "type": 3, "dimensions": Vector3i(32,38,28), "roughness": 0, "chips": 30, "surface": {"stone_color": Color("20415a"), "crystal_count": 4, "crystal_width": 9, "crystal_variation": 75, "crystal_lean": 65, "crystal_tip": 0, "crystal_base_size": 35, "surface_strength": 20, "surface_patch_size": 24}},
			{"name": "Лёд · Крупные глыбы", "type": 4, "dimensions": Vector3i(40,30,34), "roughness": 0, "chips": 25, "surface": {"stone_color": Color("284e60"), "crystal_count": 3, "crystal_width": 16, "crystal_variation": 65, "crystal_lean": 35, "crystal_tip": 0, "crystal_base_size": 25, "surface_strength": 20, "surface_patch_size": 24, "mineral_pattern": 1, "mineral_direction": 0, "mineral_color": Color("527581"), "mineral_width": 2, "mineral_spacing": 9, "mineral_strength": 40}},
		]:
			var recipe := default_recipe(ROCK)
			recipe.parameters.merge({"generation_version": 2, "rock_type": item.type, "dimensions": item.dimensions, "roughness": item.roughness, "chips": item.chips}, true)
			recipe.parameters.merge(item.get("surface", {}), true)
			if int(item.type) >= 3: recipe.parameters.crystal_base_enabled = false
			recipe.parameters = normalized_parameters(ROCK, recipe.parameters)
			recipe.resource_name = item.name
			result.append({"name": item.name, "recipe": recipe})
		return result
	if generator_id != LARGE_TREE: return result
	for item in [
		{"name": "Тип · Саванна", "parameters": {"tree_type": 0, "generation_version": 14, "crown_shape": 0, "trunk_width": 8, "crown_spread": 80, "branch_thickness": 60, "branch_taper": 80, "branch_curve": 80, "cluster_size": 115, "cluster_flatten": 65, "branch_start": 38, "foliage_along": 85, "root_flare": 25}},
		{"name": "Тип · Дуб", "parameters": {"tree_type": 1, "generation_version": 17, "trunk_width": 14, "crown_spread": 78, "branch_thickness": 85, "branch_curve": 70, "branch_taper": 70, "cluster_size": 115, "cluster_flatten": 15, "branch_start": 26, "foliage_along": 75, "root_flare": 80, "bark_pattern": true, "bark_pattern_direction": 1, "bark_pattern_length": 14, "bark_pattern_density": 65, "bark_pattern_color": Color("3f2c23")}},
		{"name": "Тип · Берёза", "parameters": {"tree_type": 2, "generation_version": 13, "trunk_width": 6, "crown_spread": 55, "branch_thickness": 35, "branch_taper": 80, "cluster_size": 100, "cluster_flatten": 15, "foliage_along": 45, "root_flare": 35, "bark_color": Color("d6d2bd"), "bark_pattern": true, "bark_pattern_direction": 0, "bark_pattern_length": 5, "bark_pattern_density": 70, "bark_pattern_color": Color("302b29")}},
		{"name": "Тип · Клён", "parameters": {"tree_type": 3, "generation_version": 12, "trunk_width": 8, "crown_spread": 60, "branch_thickness": 65, "branch_taper": 70, "cluster_size": 115, "cluster_flatten": 15, "branch_start": 30, "foliage_along": 85, "root_flare": 45, "foliage_color": Color("659845")}},
		{"name": "Тип · Ель", "parameters": {"tree_type": 4, "generation_version": 15, "trunk_width": 6, "crown_spread": 55, "branch_thickness": 40, "branch_taper": 85, "branch_curve": 60, "branch_start": 20, "cluster_size": 115, "cluster_flatten": 15, "foliage_along": 85, "root_flare": 30, "foliage_color": Color("38654a")}},
		{"name": "База · Широкая крона", "parameters": {"crown_shape": 0}},
		{"name": "База · Стройное дерево", "parameters": {"crown_shape": 1, "crown_spread": 40}},
		{"name": "База · Осенние ярусы", "parameters": {"crown_shape": 2, "foliage_color": Color("c67432"), "foliage_amount": 85}},
	]:
		var recipe := default_recipe(generator_id)
		recipe.parameters.merge(item.parameters, true)
		recipe.parameters = normalized_parameters(generator_id, recipe.parameters)
		recipe.resource_name = item.name
		result.append({"name": item.name, "recipe": recipe})
	return result


static func candidate_limit(recipe: Resource) -> int:
	# Exact meshes, not lower-detail previews. Bound simultaneous CPU/GPU memory.
	if recipe.generator_id == LARGE_TREE:
		return 2 if int(recipe.parameters.get("height", 96)) > 128 else 4
	if recipe.generator_id == ROCK:
		var dimensions: Vector3i = normalized_parameters(ROCK, recipe.parameters).dimensions
		if maxi(dimensions.x, maxi(dimensions.y, dimensions.z)) > 64: return 1
		return 2 if maxi(dimensions.x, maxi(dimensions.y, dimensions.z)) > 48 else 4
	return 4
## Registry for modular editor-only voxel content providers.

const Recipe = preload("res://addons/ember_import/ember_voxel_generator_recipe.gd")
const Rock = preload("res://addons/ember_import/ember_voxel_rock_generator.gd")
const TreeProvider = preload("res://addons/ember_import/ember_voxel_tree_generator.gd")
const BushProvider = preload("res://addons/ember_import/ember_voxel_bush_generator.gd")
const GrassProvider = preload("res://addons/ember_import/ember_voxel_grass_generator.gd")
const LargeTreeProvider = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")

const ROCK := "rock"
const TREE := "tree"
const BUSH := "bush"
const GRASS := "grass"
const LARGE_TREE := "large_tree"


static func default_recipe(generator_id: String) -> Resource:
	var recipe := Recipe.new()
	recipe.generator_id = generator_id
	recipe.seed = 0
	recipe.parameters = normalized_parameters(
		generator_id, LargeTreeProvider.defaults() if generator_id == LARGE_TREE else {}
	)
	return recipe


static func normalized_parameters(generator_id: String, parameters: Dictionary) -> Dictionary:
	match generator_id:
		ROCK:
			return Rock.normalize(parameters)
		TREE:
			return TreeProvider.normalize(parameters)
		BUSH:
			return BushProvider.normalize(parameters)
		GRASS:
			return GrassProvider.normalize(parameters)
		LARGE_TREE:
			return LargeTreeProvider.normalize(parameters)
	return {}


static func validation_errors(recipe: Resource) -> Array[String]:
	var errors: Array[String] = []
	if not recipe is Recipe:
		errors.append("У процедурного штампа нет корректного рецепта.")
		return errors
	if recipe.generator_id not in [ROCK, TREE, BUSH, GRASS, LARGE_TREE]:
		errors.append("Неизвестный генератор: %s" % recipe.generator_id)
	if recipe.seed < 0:
		errors.append("Seed генератора не может быть отрицательным.")
	if recipe.family_id.validate_filename() != recipe.family_id and not recipe.family_id.is_empty():
		errors.append("Некорректный ID семейства вариаций.")
	if recipe.variation_name.strip_edges().is_empty() or recipe.variation_name.length() > 80 or recipe.family_title.length() > 160:
		errors.append("Имя вариации должно содержать 1–80 символов, семейства — до 160.")
	if not recipe.structure.is_empty():
		if recipe.generator_id == LARGE_TREE:
			errors.append_array(LargeTreeProvider.structure_errors(recipe.structure))
		else:
			errors.append("Этот генератор ещё не поддерживает сохранённую структуру.")
	return errors


static func build(
	recipe: Resource,
	color: Color,
	material: Dictionary,
	title: String,
	model_id := "generated_voxel_source",
) -> Dictionary:
	var errors := validation_errors(recipe)
	if not errors.is_empty():
		return {"error": errors[0]}
	match recipe.generator_id:
		ROCK:
			return Rock.build(
				recipe.parameters, recipe.seed, color, material, title, model_id
			)
		TREE:
			return TreeProvider.build(
				recipe.parameters, recipe.seed, color, material, title, model_id
			)
		BUSH:
			return BushProvider.build(
				recipe.parameters, recipe.seed, color, material, title, model_id
			)
		GRASS:
			return GrassProvider.build(
				recipe.parameters, recipe.seed, color, material, title, model_id
			)
		LARGE_TREE:
			if not recipe.structure.is_empty():
				return LargeTreeProvider.build_on_structure(recipe.parameters, recipe.structure, recipe.seed, material, title, model_id)
			return LargeTreeProvider.build(
				recipe.parameters, recipe.seed, color, material, title, model_id
			)
	return {"error": "Для рецепта нет генератора."}


## Provider capabilities and UI descriptors. The panel contains no tree math.
static func editing_fields(recipe: Resource) -> Array:
	if validation_errors(recipe).is_empty() and recipe.generator_id == ROCK and int(recipe.parameters.get("generation_version", 1)) == 2:
		var fields: Array = []
		for descriptor in creation_fields(ROCK):
			if descriptor.get("advanced", false): continue
			if str(descriptor.key).begins_with("crystal_") and int(recipe.parameters.get("rock_type", 0)) < 3: continue
			var field := descriptor.duplicate(true)
			field["label"] = field.title
			field["group"] = field.get("section", "Форма камня")
			fields.append(field)
		return fields
	if not validation_errors(recipe).is_empty() or recipe.generator_id != LARGE_TREE or int(recipe.parameters.get("generation_version", 1)) < 2:
		return []
	var fields: Array = [
		{"key": "branch_thickness", "label": "Толщина ветвей · % ствола", "group": "Каркас", "min": 25, "max": 100},
		{"key": "branch_taper", "label": "Сужение ветвей · %", "group": "Каркас", "min": 0, "max": 100},
		{"key": "foliage_amount", "label": "Количество листвы · %", "group": "Листва", "min": 0, "max": 100},
		{"key": "cluster_size", "label": "Размер пучков · %", "group": "Листва", "min": 65, "max": 180},
		{"key": "cluster_flatten", "label": "Приплюснутость · %", "group": "Листва", "min": 0, "max": 100},
		{"key": "canopy_cohesion", "label": "Сомкнутость · %", "group": "Листва", "min": 0, "max": 100},
		{"key": "irregularity", "label": "Неровность листвы · %", "group": "Листва", "min": 0, "max": 100},
		{"key": "foliage_color", "label": "Цвет листвы", "group": "Цвета", "type": "color"},
		{"key": "bark_color", "label": "Цвет коры", "group": "Цвета", "type": "color"},
	]
	if int(recipe.parameters.get("tree_type", 0)) > 0 or int(recipe.parameters.get("generation_version", 1)) in [9, 14]:
		fields.insert(3, {"key": "foliage_along", "label": "Листва вдоль ветвей · %", "group": "Листва", "min": 0, "max": 100})
	if LargeTreeProvider.FoliagePattern.supported(recipe.parameters):
		fields.insert(2, {"key": "foliage_style", "label": "Стиль листвы", "group": "Листва", "options": ["Прежняя", "Пиксель-арт · пробная", "Листовые побеги · пробные", "Лиственные облака · пробные"]})
		if int(recipe.parameters.get("foliage_style", 0)) == 2:
			fields.insert(3, {"key": "foliage_leaf_size", "label": "Размер листика · vox", "group": "Листва", "min": 3, "max": 12})
		if int(recipe.parameters.get("foliage_style", 0)) == 3:
			fields.insert(3, {"key": "foliage_leaf_size", "label": "Размер деталей · vox", "group": "Листва", "min": 3, "max": 12})
			fields.insert(4, {"key": "foliage_leaf_accents", "label": "Выраженность листиков · %", "group": "Листва", "min": 0, "max": 100})
			if int(recipe.parameters.get("foliage_cloud_version", 1)) >= 2:
				fields.insert(5, {"key": "foliage_detail", "label": "Размер рисунка · детализация", "group": "Листва", "min": 0, "max": 100})
				fields.insert(6, {"key": "foliage_pattern_strength", "label": "Выраженность рисунка · %", "group": "Листва", "min": 0, "max": 100})
		if int(recipe.parameters.get("foliage_style", 0)) == 1:
			fields.insert(3, {"key": "foliage_detail", "label": "Детализация листвы", "group": "Листва", "min": 0, "max": 100})
			if int(recipe.parameters.get("foliage_pattern_version", 1)) >= 2:
				fields.insert(4, {"key": "foliage_pattern_strength", "label": "Выраженность рисунка · %", "group": "Листва", "min": 0, "max": 100})
	for descriptor in LargeTreeProvider.BarkPattern.fields():
		descriptor["label"] = descriptor.title
		descriptor["group"] = "Рисунок коры"
		fields.append(descriptor)
	return fields


static func freeze_structure(recipe: Resource) -> Dictionary:
	var errors := validation_errors(recipe)
	if not errors.is_empty():
		return {"error": errors[0]}
	if recipe.generator_id == ROCK and not editing_fields(recipe).is_empty():
		# Rocks have no branching frame to freeze: seed + planes are deterministic.
		return {"recipe": recipe.duplicate(true)}
	if not recipe.structure.is_empty():
		return {"recipe": recipe.duplicate(true)}
	if editing_fields(recipe).is_empty():
		return {"error": "Для этого рецепта ещё нет редактора структуры."}
	var built := build(recipe, Color.WHITE, {}, "Каркас")
	if built.has("error"):
		return built
	var frozen := recipe.duplicate(true)
	frozen.parameters = normalized_parameters(recipe.generator_id, recipe.parameters)
	frozen.structure = built.structure.duplicate(true)
	return {"recipe": frozen}


static func variant_cache_key(recipe: Resource, geometry: EmberVoxelModelResource) -> String:
	if recipe == null or geometry == null:
		return ""
	return "%s:%d:%s:%s:%d:%d:%d" % [
		str(recipe.get("generator_id")),
		int(recipe.get("seed")),
		var_to_str(recipe.get("parameters")),
		geometry.model_id,
		hash(geometry.voxels),
		hash(geometry.palette),
		hash(geometry.material),
	]


static func build_variants(
	recipe: Resource,
	base_geometry: EmberVoxelModelResource,
) -> Dictionary:
	var errors := validation_errors(recipe)
	if not errors.is_empty():
		return {"error": errors[0]}
	if base_geometry == null or not base_geometry.validation_errors().is_empty():
		return {"error": "Основная геометрия процедурного источника повреждена."}
	var settings := normalized_parameters(recipe.generator_id, recipe.parameters)
	var count := clampi(int(settings.get("variant_count", 1)), 1, 8)
	var variants: Array[EmberVoxelModelResource] = [base_geometry]
	if count == 1:
		return {"variants": variants, "parameters": settings}
	if base_geometry.palette.size() < 2:
		return {"error": "У процедурного источника нет рабочего цвета."}
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, int(recipe.seed)) + 32452843
	for variant_index in range(1, count):
		var variant_parameters := _variant_parameters(recipe.generator_id, settings, random)
		var variant_recipe := recipe.duplicate(true)
		variant_recipe.seed = maxi(0, int(recipe.seed)) + variant_index * 104729
		variant_recipe.parameters = variant_parameters
		var built := build(
			variant_recipe,
			base_geometry.palette[1],
			base_geometry.material,
			"%s · вариант %d" % [base_geometry.display_name, variant_index + 1],
			"%s_variant_%d" % [base_geometry.model_id, variant_index + 1],
		)
		if built.has("error"):
			return built
		variants.append(built.geometry)
	return {"variants": variants, "parameters": settings}


static func recommended_spacing(recipe: Resource) -> int:
	var errors := validation_errors(recipe)
	if not errors.is_empty():
		return 1
	var settings := normalized_parameters(recipe.generator_id, recipe.parameters)
	match recipe.generator_id:
		ROCK:
			return Rock.recommended_spacing(settings)
		TREE:
			return TreeProvider.recommended_spacing(settings)
		BUSH:
			return BushProvider.recommended_spacing(settings)
		GRASS:
			return GrassProvider.recommended_spacing(settings)
	return 1


static func placement_defaults(recipe: Resource) -> Dictionary:
	if validation_errors(recipe).is_empty() and recipe.generator_id == GRASS:
		return {
			"application": 3,
			"spread": 2,
			"conform": false,
			"allow_conform": false,
			"up_only": true,
		}
	return {}


static func _variant_parameters(
	generator_id: String,
	settings: Dictionary,
	random: RandomNumberGenerator,
) -> Dictionary:
	match generator_id:
		ROCK:
			return Rock.variant_parameters(settings, random)
		TREE:
			return TreeProvider.variant_parameters(settings, random)
		BUSH:
			return BushProvider.variant_parameters(settings, random)
		GRASS:
			return GrassProvider.variant_parameters(settings, random)
	return settings.duplicate(true)
