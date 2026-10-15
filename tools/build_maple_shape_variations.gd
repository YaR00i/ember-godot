extends SceneTree
const Species=preload("res://scripts/prototypes/ember_tree_species_fixture.gd")
const Recipe=preload("res://addons/ember_import/ember_voxel_generator_recipe.gd")
const Generator=preload("res://addons/ember_import/ember_voxel_generator.gd")
func _initialize() -> void:
	var directory:=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(directory)
	for variant in 2:
		var inputs:=Species.maple(7,{"crown_shape":variant})
		var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7
		recipe.family_id="maple23_shape_lab";recipe.family_title="Клён23 · варианты кроны"
		recipe.variation_name="Широкий · сохранённый" if variant==0 else "Вытянутый · проба"
		recipe.parameters=inputs.parameters;recipe.structure=inputs.structure
		assert(Generator.validation_errors(recipe).is_empty())
		var path:=directory.path_join("maple-%s-v23.tres"%["wide","upright"][variant])
		assert(ResourceSaver.save(recipe,path)==OK)
		var reopened=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		assert(Generator.build(reopened,Color.WHITE,{},"Variant","maple_shape_variant").geometry.voxels==inputs.source.voxels)
	print("MAPLE_VARIATIONS_SAVED PASS");quit()
