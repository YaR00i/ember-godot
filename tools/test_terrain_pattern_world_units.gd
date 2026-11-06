extends SceneTree
## Texture repeats must use map metres in every saved world look.
const TerrainProjection := preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Materials := preload("res://scripts/ember_voxel_surface_materials.gd")


func _initialize() -> void:
	var map := EmberMapLoader.new()
	map.imported_tile_size = 24.0
	var projection := TerrainProjection.new()
	map.add_child(projection)
	var ground := Materials.compact_terrain_material()
	projection._ground_material = ground
	var regional := Materials.compact_terrain_material()
	projection._water_regions[Vector2i.ZERO] = {"ground": regional}
	var passed := true
	for look in [0, 1, 2, -1]:
		projection.set_world_look(look)
		for material in [ground, regional]:
			var units: Variant = material.get_shader_parameter("ember_texture_world_unit")
			if units != map.imported_tile_size:
				printerr("TERRAIN_PATTERN_UNITS look=%d expected=%f actual=%s" % [look, map.imported_tile_size, units])
				passed = false
	map.free()
	print("TERRAIN_PATTERN_UNITS pass=", passed)
	quit(0 if passed else 1)
