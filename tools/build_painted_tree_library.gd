extends SceneTree
## Rebuild the five accepted library Sources into an explicit output directory.
## Never changes author maps or overwrites a library asset automatically.
const Generator=preload("res://addons/ember_import/ember_voxel_generator.gd")
const IDS: Array[String]=["vox_painted_savanna","vox_painted_oak","vox_painted_birch","vox_painted_maple","vox_painted_spruce"]
func _initialize() -> void:
	var output:=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var presets:=Generator.creation_presets(Generator.LARGE_TREE)
	var manifest: Array=[]
	for kind in 5:
		var recipe: Resource=presets[kind].recipe.duplicate(true)
		var title: String=load("res://scripts/ember_tree_species.gd").TITLES[kind]+" · рисованная основа"
		var built:=Generator.build(recipe,Color.WHITE,{},title,IDS[kind])
		assert(not built.has("error"));assert(built.geometry.validation_errors().is_empty())
		recipe.structure=built.structure.duplicate(true);recipe.family_id=IDS[kind];recipe.family_title=title;recipe.variation_name="Принятая основа"
		var source_path:=output.path_join(IDS[kind]+".tres")
		var recipe_path:=output.path_join(IDS[kind]+"-recipe.tres")
		assert(not FileAccess.file_exists(source_path) and not FileAccess.file_exists(recipe_path))
		assert(ResourceSaver.save(built.geometry,source_path)==OK);assert(ResourceSaver.save(recipe,recipe_path)==OK)
		manifest.append({"id":IDS[kind],"title":title,"source_sha256":FileAccess.get_sha256(source_path),"recipe_sha256":FileAccess.get_sha256(recipe_path)})
	var file:=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE);file.store_string(JSON.stringify(manifest,"\t"));file.close()
	print("PAINTED_TREE_LIBRARY PASS");quit()
