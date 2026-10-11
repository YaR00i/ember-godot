extends SceneTree
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const Objects = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
func _initialize() -> void:
	assert(ProjectSettings.globalize_path("res://").contains("ember-river-preview-"),"QA copy only")
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	assert(creation.prepare_sections("placement_native",1,1,96),creation.error)
	assert(not creation.commit().is_empty(),creation.error)
	var objects := Objects.new()
	var recipe := Generator.default_recipe(Generator.ROCK); recipe.seed = 19
	assert(objects.prepare_recipe(recipe,"Тестовый камень","","vox_qa_placement_rock"),objects.error)
	var scene := Node3D.new(); root.add_child(scene); var history := UndoRedo.new()
	assert(objects.save_to_library(scene,history),objects.error)
	history.clear_history(); history.free(); scene.free()
	print("PLACEMENT_FIXTURE PASS scene=placement_native / existing rock workshop transaction")
	quit()
