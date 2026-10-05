extends SceneTree
## A separate authored diorama; the existing river study is read-only.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const OUTPUT := "res://content/world_terrains/compact_waterfall_study.res"

func _initialize() -> void:
	_build.call_deferred()

static func fixture(palette_source: EmberTerrainPilotResource = null) -> EmberTerrainPilotResource:
	var terrain := Terrain.new()
	terrain.width = 128
	terrain.depth = 192
	terrain.palette = palette_source.palette.duplicate() if palette_source != null else PackedColorArray([Color.TRANSPARENT, Color(0.72, 0.68, 0.4), Color(0.1, 0.7, 0.8), Color(0.3, 0.7, 0.2)])
	if palette_source != null:
		terrain.palette_surface_roles = palette_source.palette_surface_roles.duplicate()
		terrain.palette_material_ids = palette_source.palette_material_ids.duplicate()
	var sand := maxi(terrain.palette_surface_roles.find("sand"), 1)
	var grass := maxi(terrain.palette_surface_roles.find("grass"), 3)
	var water := 2
	if palette_source != null:
		for slot in palette_source.water_materials:
			if slot > 0:
				water = slot
				break
	var count := terrain.width * terrain.depth
	for channel in ["heights", "top_materials", "base_materials", "cap_depths", "water_levels", "water_materials"]:
		var data = terrain.get(channel)
		data.resize(count)
		terrain.set(channel, data)
	for z in terrain.depth:
		var level := 40 if z >= 90 else 16
		var center := 64.0 + sin(minf(z, 90.0) * 0.045) * 5.0
		var half_width := 17.0 + (11.0 * exp(-pow((z - 65.0) / 27.0, 2.0)) if z < 90 else 0.0)
		for x in terrain.width:
			var i := terrain.column_index(x, z)
			var edge := absf(x + 0.5 - center) - half_width
			var height := level - 12 if edge < -5.0 else level - 4 if edge < 0.0 else level + mini(28, ceili(edge / 7.0) * 4)
			terrain.heights[i] = height
			terrain.top_materials[i] = sand if edge < 15 else grass
			terrain.base_materials[i] = sand
			terrain.cap_depths[i] = mini(height, 4)
			terrain.water_levels[i] = level if edge < 0 else 0
			terrain.water_materials[i] = water if edge < 0 else 0
	terrain.water_flow.resize(8 * 12)
	terrain.water_flow.fill(Vector2(0, -0.7))
	return terrain

func _build() -> void:
	var source := load("res://content/world_terrains/compact_river_water_study.res") as Terrain
	var terrain := fixture(source)
	assert(terrain.validation_errors().is_empty())
	assert(ResourceSaver.save(terrain, OUTPUT) == OK)
	terrain.take_over_path(OUTPUT)
	var scene := (load("res://scenes/compact_sky_reflection_study.tscn") as PackedScene).instantiate()
	scene.name = "CompactWaterfallStudy"
	scene.map_id = "compact_waterfall_study"
	scene.sandbox_storage_root = "user://ember-compact-waterfall-study"
	var map := scene.get_node("Map")
	map.compact_terrain = terrain
	map.map_id = "compact_waterfall_study"
	map.authored_size_blocks = Vector2i(8, 12)
	map.compact_water_mesh_step = 2
	for prop in scene.get_node("Map/Props").get_children(): prop.free()
	var start := scene.get_node("Map/Regions/PlayerStart")
	start.position = Vector3(22, 74, 150)
	start.map_id = "compact_waterfall_study"
	start.region_id = "compact_waterfall_study_start"
	scene.get_node("CanvasLayer/Gate").text = "EMBER · WATERFALL STUDY"
	var study := scene.get_node("PlanarReflection")
	study.wave_height_voxels = 1.1
	study.river_flow_speed = 1.0
	study.river_wave_spacing_blocks = 5.0
	study.river_arc_opening = 0.4
	study.river_crest_whiteness = 0.12
	study.river_crest_width_voxels = 0.75
	study.shore_foam_width_voxels = 1.4
	study.sea_swash_height = 0.0
	study.sky_roughness = 0.18
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/compact_waterfall_study.tscn") == OK)
	scene.free()
	print("PASS waterfall diorama: separate terrain and scene, existing map unchanged")
	quit()
