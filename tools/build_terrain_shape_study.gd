extends SceneTree
const Fixture=preload("res://scripts/prototypes/ember_terrain_shape_fixture.gd")
func _initialize() -> void:
	assert(ResourceSaver.save(Fixture.source(),"res://content/world_terrains/terrain_shape_study.res")==OK)
	print("TERRAIN_SHAPE_FIXTURE PASS");quit()
