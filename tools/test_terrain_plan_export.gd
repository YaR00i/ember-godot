extends SceneTree
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1, "Pass the exported planner fixture scene path")
	var packed := ResourceLoader.load(args[0]) as PackedScene
	assert(packed != null)
	var scene := packed.instantiate()
	var map := scene.get_node("Map") as EmberMapLoader
	assert(map != null and map.compact_terrain != null)
	assert(not map.has_meta(Plan.META), "Authoring plan leaked into exported scene")
	scene.free()
	print("TERRAIN_PLAN_EXPORT PASS plan omitted / applied terrain retained")
	quit()
