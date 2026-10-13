extends SceneTree
const Fixture=preload("res://scripts/prototypes/ember_material_depth_fixture.gd")
func _initialize() -> void:
	var maps:=Fixture.artwork()
	var directory:="res://content/terrain_materials/textures/material_depth_study"
	DirAccess.make_dir_recursive_absolute(directory)
	assert(maps.color.save_png(directory+"/stone_color.png")==OK)
	assert(maps.height.save_png(directory+"/stone_height.png")==OK)
	assert(ResourceSaver.save(Fixture.source(),"res://content/world_terrains/material_depth_study.res")==OK)
	print("MATERIAL_DEPTH_FIXTURE PASS generated explicit paired color/height and ordinary Source")
	quit()
