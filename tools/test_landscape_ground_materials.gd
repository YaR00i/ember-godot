extends SceneTree
## landscape_compact carries the accepted painted ground materials and the soft cartoon light, and the ground
## shape/water are exactly as before. Reads only; nothing is written.
const PATH := "res://content/world_terrains/landscape_compact.res"
var errors: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL ", message)

func run() -> void:
	var terrain = load(PATH)
	check(terrain != null and terrain.width == 384 and terrain.depth == 400 and terrain.heights.size() == 153600, "terrain size unchanged (384x400)")
	check(terrain.validation_errors().is_empty() and terrain.material_id_errors().is_empty(), "terrain and material ids validate")
	check(terrain.palette_surface_roles == PackedStringArray(["", "soil", "grass", "sand", "grass", ""]), "palette roles: soil, grass, sand, grass (slot 4 is grass), none")
	check(terrain.palette_material_ids == PackedStringArray(["", "soil_grain", "cartoon_grass", "cartoon_sand", "cartoon_grass", ""]), "palette materials are the accepted painted ones")
	var top := {}
	for value in terrain.top_materials: top[value] = top.get(value, 0) + 1
	check(not top.has(4) and top.get(2, 0) == 21371 + 77600 and top.get(1, 0) == 29029 and top.get(3, 0) == 25600, "no column uses slot 4; the 77600 former slot-4 columns are grass")
	for value in terrain.base_materials: if value == 4: errors.append("a base column still uses slot 4"); break
	var low := 1 << 30; var high := -(1 << 30); var wet := 0
	for index in terrain.heights.size():
		low = mini(low, terrain.heights[index]); high = maxi(high, terrain.heights[index])
		if terrain.water_levels[index] > terrain.heights[index]: wet += 1
	check(low == 12 and high == 40 and wet == 80620, "ground heights and sea unchanged (12..40, 80620 wet columns)")
	var scene: Node = (load("res://scenes/landscape_compact.tscn") as PackedScene).instantiate()
	var map: EmberMapLoader = scene.get_node("Map")
	check(map.compact_ground_style == 1 and map.compact_smooth_material_blend and map.compact_material_light_mode == 1, "map uses the smooth painted ground and the soft cartoon light")
	var sun: DirectionalLight3D = scene.get_node("Map/Look/Sun")
	var environment: Environment = scene.get_node("Map/Look/WorldEnvironment").environment
	check(is_equal_approx(sun.light_energy, 1.15) and is_equal_approx(sun.directional_shadow_max_distance, 560.0), "day sun: 1.15 energy, shadows 35 m = 560 units")
	check(environment.ssao_enabled and is_equal_approx(environment.ssao_radius, 0.65 * 16.0) and is_equal_approx(environment.ambient_light_energy, 0.55), "environment: SSAO radius scaled to 16 units per metre, ambient 0.55")
	scene.free()
	print("LANDSCAPE_GROUND_MATERIALS ", "PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
