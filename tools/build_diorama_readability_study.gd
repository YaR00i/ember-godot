extends SceneTree
func _initialize() -> void:
	var source=preload("res://scripts/prototypes/ember_diorama_readability_fixture.gd").source()
	assert(source.validation_errors().is_empty())
	assert(ResourceSaver.save(source,"res://content/world_terrains/diorama_readability_study.res")==OK)
	print("DIORAMA_BUILD PASS existing Source + one step + soil patch")
	quit()
