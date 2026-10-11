extends SceneTree
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1,"Pass exported river fixture scene path")
	var scene := (ResourceLoader.load(args[0]) as PackedScene).instantiate()
	var map := scene.get_node("Map") as EmberMapLoader
	assert(not map.has_meta(Plan.META),"Authoring river plan/provenance leaked into export")
	var terrain := map.compact_terrain
	assert(terrain.column_value("water_levels",terrain.column_index(352,448)) == 80,"Lake lost in PCK")
	assert(terrain.column_value("water_levels",terrain.column_index(400,208)) == 53,"River slope lost in PCK")
	assert(terrain.flow_at_cell(400,208).y < 0,"Curve flow lost in PCK")
	scene.free()
	print("TERRAIN_RIVER_EXPORT PASS plan omitted / applied lake, slope and flow retained")
	quit()
