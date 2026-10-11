extends SceneTree
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1,"Pass exported mountain fixture scene path")
	var scene := (ResourceLoader.load(args[0]) as PackedScene).instantiate()
	var map := scene.get_node("Map") as EmberMapLoader
	assert(not map.has_meta(Plan.META),"Authoring mountain plan/provenance leaked into export")
	var terrain := map.compact_terrain
	assert(terrain.column_value("heights",terrain.column_index(384,384)) == 192,"Mountain lost in PCK")
	assert(terrain.column_value("heights",terrain.column_index(704,384)) == 96,"Outside terrain changed in PCK")
	assert(terrain.column_value("water_levels",terrain.column_index(32,32)) == 32,"Sea changed in PCK")
	scene.free()
	print("TERRAIN_MOUNTAIN_EXPORT PASS plan omitted / applied mountain and unchanged sea retained")
	quit()
