@tool
extends RefCounted
## Prepares one flat compact map without touching the current scene.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const BrushMath = preload("res://scripts/prototypes/ember_terrain_pilot_brush_math.gd")
const WorldCanvas = preload("res://scripts/world_canvas.gd")
const Region = preload("res://scripts/ember_region.gd")
const SECTION_BLOCKS := 24
const MAX_INITIAL_SECTIONS := 4
const MAX_EXTENDED_SECTIONS := 5

var scene_directory := "res://scenes"
var terrain_directory := "res://content/world_terrains"
var source: TerrainResource
var map_id := ""
var blocks := Vector2i.ZERO
var height := 0
var error := ""


func prepare_sections(raw_id: String, width_sections: int, depth_sections: int, ground_height: int) -> bool:
	if width_sections < 1 or width_sections > MAX_INITIAL_SECTIONS or depth_sections < 1 or depth_sections > MAX_INITIAL_SECTIONS:
		source = null
		error = "При создании выберите от 1 до %d участков по каждой оси." % MAX_INITIAL_SECTIONS
		return false
	return prepare(raw_id, width_sections * SECTION_BLOCKS, depth_sections * SECTION_BLOCKS, ground_height)


func prepare_coast_sections(raw_id: String, width_sections: int, depth_sections: int, ground_height: int, water_height: int, relief_voxels: int, seed: int) -> bool:
	if water_height < 4 or water_height >= ground_height or water_height % BrushMath.QUARTER_BLOCK_HEIGHT_STEP != 0:
		source = null
		error = "Уровень воды должен быть кратен 4 и ниже высоты суши."
		return false
	if relief_voxels < 0 or relief_voxels > 48 or relief_voxels % BrushMath.QUARTER_BLOCK_HEIGHT_STEP != 0:
		source = null
		error = "Неровность берега: от 0 до 48 вокселей с шагом 4."
		return false
	if not prepare_sections(raw_id, width_sections, depth_sections, ground_height):
		return false
	_generate_coast(water_height, relief_voxels, seed)
	var errors := source.validation_errors()
	error = "" if errors.is_empty() else errors[0]
	if not error.is_empty():
		source = null
	return source != null


func _generate_coast(water_height: int, relief_voxels: int, seed: int) -> void:
	# Sample one world-space field for the whole map. Section borders have no
	# special sampling path, and every 8×8 square keeps one four-voxel step.
	var coast := FastNoiseLite.new()
	coast.seed = seed
	coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	coast.frequency = 1.0 / 360.0
	coast.fractal_type = FastNoiseLite.FRACTAL_FBM
	coast.fractal_octaves = 2
	var hills := FastNoiseLite.new()
	hills.seed = seed + 1009
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 1.0 / 192.0
	hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	hills.fractal_octaves = 2
	var heights := source.heights
	var tops := source.top_materials
	var waters := source.water_levels
	var water_colors := source.water_materials
	var square := TerrainResource.CELLS_PER_BLOCK / 2
	var coast_range := minf(160.0, float(source.depth) * 0.12)
	var shore_width := 128.0
	for square_z in source.depth / square:
		var world_z := square_z * square
		for square_x in source.width / square:
			var world_x := square_x * square
			var shoreline := float(source.depth) * 0.42 + coast.get_noise_2d(float(world_x), 0.0) * coast_range
			var blend := clampf((float(world_z) - shoreline + shore_width * 0.5) / shore_width, 0.0, 1.0)
			blend = blend * blend * (3.0 - 2.0 * blend)
			var rolling := hills.get_noise_2d(float(world_x), float(world_z)) * float(relief_voxels) * blend
			var raw_height := lerpf(float(water_height - 8), float(height), blend) + rolling
			var ground := clampi(roundi(raw_height / 4.0) * 4, 4, source.height_limit)
			var top := 3 if ground <= water_height + 8 else 2
			var liquid := water_height if ground < water_height else 0
			for dz in square:
				var row := (world_z + dz) * source.width + world_x
				for dx in square:
					var index := row + dx
					heights[index] = ground
					tops[index] = top
					waters[index] = liquid
					water_colors[index] = 5 if liquid > 0 else 0
	source.heights = heights
	source.top_materials = tops
	source.water_levels = waters
	source.water_materials = water_colors


func prepare(raw_id: String, width_blocks: int, depth_blocks: int, ground_height: int) -> bool:
	source = null
	map_id = raw_id.strip_edges().to_lower()
	blocks = Vector2i(width_blocks, depth_blocks)
	height = ground_height
	if map_id.length() < 3 or map_id.length() > 48 or map_id[0] not in "abcdefghijklmnopqrstuvwxyz":
		error = "ID карты: 3–48 символов, сначала латинская буква."
		return false
	for letter in map_id:
		if letter not in "abcdefghijklmnopqrstuvwxyz0123456789_":
			error = "ID карты может содержать только a–z, 0–9 и _."
			return false
	if width_blocks < 4 or width_blocks > 96 or depth_blocks < 4 or depth_blocks > 96:
		error = "Размер карты: от 4 до 96 блоков по каждой оси."
		return false
	if ground_height < 1 or ground_height > 128:
		error = "Высота ровной земли: от 1 до 128 ячеек."
		return false
	if ground_height % BrushMath.QUARTER_BLOCK_HEIGHT_STEP != 0:
		error = "Высота ровной земли должна быть кратна ступени 4 вокселя."
		return false
	if FileAccess.file_exists(scene_path()) or FileAccess.file_exists(terrain_path()):
		error = "Карта или земля с таким ID уже существует. Выберите другое имя."
		return false
	source = TerrainResource.new()
	source.width = width_blocks * TerrainResource.CELLS_PER_BLOCK
	source.depth = depth_blocks * TerrainResource.CELLS_PER_BLOCK
	source.height_limit = 128
	source.palette = PackedColorArray([
		Color(1, 1, 1, 0), Color8(125, 105, 80), Color8(127, 163, 106),
		Color8(214, 189, 133), Color8(179, 185, 144), Color8(80, 170, 163),
	])
	var columns := source.width * source.depth
	source.heights.resize(columns)
	source.heights.fill(ground_height)
	source.top_materials.resize(columns)
	source.top_materials.fill(2)
	source.base_materials.resize(columns)
	source.base_materials.fill(1)
	source.cap_depths.resize(columns)
	source.cap_depths.fill(mini(3, ground_height))
	source.water_levels.resize(columns)
	source.water_materials.resize(columns)
	var errors := source.validation_errors()
	error = "" if errors.is_empty() else errors[0]
	if not error.is_empty():
		source = null
	return source != null


func scene_path() -> String:
	return scene_directory.path_join(map_id + ".tscn")


func terrain_path() -> String:
	return terrain_directory.path_join(map_id + ".res")


func commit() -> String:
	if source == null or not error.is_empty():
		error = "Сначала обновите предпросмотр."
		return ""
	if FileAccess.file_exists(scene_path()) or FileAccess.file_exists(terrain_path()):
		error = "Карта или земля с таким ID уже существует. Файлы не изменены."
		return ""
	for directory in [scene_directory, terrain_directory]:
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
			error = "Не удалось подготовить папку новой карты."
			return ""
	if ResourceSaver.save(source, terrain_path()) != OK:
		error = "Не удалось сохранить компактную землю."
		return ""
	var saved := ResourceLoader.load(terrain_path(), "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	if saved == null or not saved.validation_errors().is_empty():
		_rollback_terrain()
		error = "Созданная земля не прошла повторную загрузку."
		return ""
	var root := _scene_root(saved)
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	if pack_error != OK or FileAccess.file_exists(scene_path()) or ResourceSaver.save(packed, scene_path()) != OK:
		_rollback_terrain()
		error = "Не удалось сохранить сцену. Файл земли откатан."
		return ""
	error = ""
	return scene_path()


func _rollback_terrain() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(terrain_path()))


func _scene_root(saved: TerrainResource) -> Node3D:
	var root := Node3D.new()
	root.name = "CompactMap"
	root.set_script(WorldCanvas)
	root.set("map_id", map_id)
	root.set("sandbox_storage_root", "user://ember-" + map_id)
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = map_id
	map.hydrate_legacy_regions = false
	map.authored_size_blocks = blocks
	map.compact_terrain = saved
	map.camera_distance = 200.0
	map.camera_polar = 0.88
	map.camera_yaw = 0.35
	map.camera_look_height = float(height + 2)
	map.camera_far = maxf(2400.0, float(maxi(saved.width, saved.depth) * 2))
	_owned(root, map, root)
	var look := Node3D.new()
	look.name = "Look"
	_owned(map, look, root)
	var environment := Environment.new()
	environment.background_mode = 1
	environment.background_color = Color(0.43, 0.57, 0.6)
	environment.ambient_light_source = 3
	environment.ambient_light_color = Color(0.77, 0.84, 0.8)
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = 2
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	_owned(look, world_environment, root)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-58, -30, 0)
	sun.light_color = Color(1, 0.96, 0.87)
	sun.light_energy = 0.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 800.0
	_owned(look, sun, root)
	for name in ["Terrain", "Props"]:
		var group := Node3D.new()
		group.name = name
		_owned(map, group, root)
	var regions := Node3D.new()
	regions.name = "Regions"
	_owned(map, regions, root)
	var player_start := Area3D.new()
	player_start.name = "PlayerStart"
	player_start.set_script(Region)
	player_start.set("region_id", map_id + "_start")
	player_start.set("map_id", map_id)
	player_start.set("kind", "player_start")
	player_start.position = Vector3(saved.width * 0.5, float(height + 2), saved.depth * 0.5)
	player_start.collision_layer = 0
	player_start.collision_mask = 0
	player_start.monitoring = false
	player_start.monitorable = false
	_owned(regions, player_start, root)
	var canvas := CanvasLayer.new()
	canvas.name = "CanvasLayer"
	_owned(root, canvas, root)
	var gate := Label.new()
	gate.name = "Gate"
	gate.text = "EMBER · НОВАЯ КАРТА"
	_owned(canvas, gate, root)
	return root


func _owned(parent: Node, child: Node, scene_root: Node) -> void:
	parent.add_child(child)
	child.owner = scene_root
