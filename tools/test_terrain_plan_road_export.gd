extends SceneTree
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1,"Pass exported road fixture scene path")
	var scene := (ResourceLoader.load(args[0]) as PackedScene).instantiate()
	var map := scene.get_node("Map") as EmberMapLoader
	assert(not map.has_meta(Plan.META),"Authoring road plan/provenance leaked into export")
	var terrain := map.compact_terrain
	var center: int = terrain.column_index(384,384)
	assert(terrain.column_value("heights",center) == 96,"Road level lost in PCK")
	assert(terrain.surface_role_for_palette(terrain.column_value("top_materials",center)) == "soil","Road surface lost in PCK")
	assert(terrain.column_value("heights",terrain.column_index(384,480)) > 96,"Previous mountain lost in PCK")
	assert(terrain.column_value("water_levels",terrain.column_index(32,32)) == 32,"Sea changed in PCK")
	scene.free()
	print("TERRAIN_ROAD_EXPORT PASS plan omitted / applied road, surrounding mountain and sea retained")
	quit()
