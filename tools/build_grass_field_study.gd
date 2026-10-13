extends SceneTree
func _initialize() -> void:
	var fixture = load("res://scripts/prototypes/ember_painted_light_fixture.gd")
	assert(ResourceSaver.save(fixture.source(192,192),"res://content/world_terrains/grass_field_study.res")==OK)
	print("GRASS_FIELD_BUILD PASS 12x12m; same fine16 owner")
	quit()
