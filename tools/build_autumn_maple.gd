extends SceneTree
## An ordinary editable maple variation, published through the existing library.
const Creation = preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
const ID := "vox_painted_maple_autumn"
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var two_colours := OS.get_cmdline_user_args().has("--palette")
	var id := ID + "_palette" if two_colours else ID
	if FileAccess.file_exists("res://content/voxel_models/" + id + ".tres"):
		printerr("Autumn maple already exists; rebuild must be explicit"); quit(1); return
	var recipe: Resource = load("res://content/editor/voxel_generators/vox_painted_maple.tres").duplicate(true)
	recipe.parameters.foliage_color = Color("e5a143")
	recipe.variation_name = "Золотая осень"
	if two_colours:
		recipe.parameters.foliage_color = Color("c7a15c")
		recipe.parameters.tree_leaf_secondary_color = Color("9a683c")
		recipe.parameters.tree_leaf_palette_strength = 100
		recipe.variation_name = "Спокойная осень · два цвета"
	var creation := Creation.new()
	if not creation.prepare_recipe(recipe, "Клён · спокойная осень" if two_colours else "Клён · золотая осень", "", id):
		printerr(creation.error); quit(1); return
	var stage := Node3D.new(); root.add_child(stage)
	var history := UndoRedo.new()
	if not creation.save_to_library(stage, history):
		printerr(creation.error); quit(1); return
	var original: EmberVoxelModelResource = load("res://content/voxel_models/vox_painted_maple.tres")
	assert(creation.source.voxels == original.voxels, "Autumn must retain accepted maple geometry")
	assert(creation.source.validation_errors().is_empty())
	history.clear_history()
	stage.free()
	creation = null
	await process_frame
	await process_frame
	print("PASS autumn maple: existing recipe/Source/prefab library; unchanged maple occupancy; shared foliage shader")
	quit()
