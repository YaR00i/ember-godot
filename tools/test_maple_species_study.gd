extends "res://tools/test_birch_species_study.gd"
func run() -> void:
	var p:=Species.maple_parameters()
	check(p.generation_version==23 and p.tree_type==3 and Provider.LATEST_VERSIONS==[14,17,13,12,15],"maple opt-in, old defaults unchanged")
	for kind in [0,1,2,4]:check(Provider.normalize({"generation_version":23,"tree_type":kind}).generation_version!=23,"cross species opt-in rejected")
	var first:=Provider.build(p,7,Color.WHITE,{},"Maple","maple_test")
	check(not first.has("error") and Provider.structure_errors(first.structure).is_empty() and first.geometry.validation_errors().is_empty(),"provider hierarchy and Source validation")
	check(signature(first)==signature(Provider.build(p,7,Color.WHITE,{},"Maple","maple_test")),"seed repeatability exact")
	var tree:=Species.maple()
	check(tree.layout.size()>40 and tree.leaves.cards>0 and tree.leaves.cards<1800,"bounded branched tree and cards")
	for anchor: Dictionary in tree.leaves.roots:
		var expected: Vector3=(Branching.point_at(tree.layout[anchor.branch],anchor.t)+Vector3(tree.pivot_bias.x,0,tree.pivot_bias.y))/16.0
		check(anchor.point.distance_to(expected)<0.0001,"leaves anchored to real shoots")
	for seed in [0,31,197]:
		var built:=Provider.build(p,seed,Color.WHITE,{},"Maple","maple_test")
		check(not built.has("error") and Provider.structure_errors(built.structure).is_empty(),"other seed bounds "+str(seed))
	var birch:=Provider.build(Species.birch_parameters(),7,Color.WHITE,{},"Birch","birch_test")
	check(birch.geometry.voxels.hex_encode().sha256_text()=="eb98aaa7043c412e3ecdf9fc611fb32bbc261230d2c42a2f29be6c74bd2fffde","accepted birch22 Source exact")
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7;recipe.parameters=p;recipe.structure=first.structure
	check(Generator.validation_errors(recipe).is_empty(),"recipe validation23")
	var directory:="user://maple-species-%d"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(ResourceSaver.save(recipe,directory.path_join("maple_test.tres"))==OK,"save Recipe")
	var reopened: Resource=ResourceLoader.load(directory.path_join("maple_test.tres"),"",ResourceLoader.CACHE_MODE_IGNORE)
	var rebuilt:=Generator.build(reopened,Color.WHITE,{},"Maple","maple_test")
	check(rebuilt.geometry.voxels==first.geometry.voxels and rebuilt.geometry.collision_voxels==first.geometry.collision_voxels,"reopen Recipe Source exact")
	var panel:=RecipePanel.new();root.add_child(panel);panel.recipe_directory=directory
	var keys: Array[String]=["main_branch_count","branch_splits","branch_levels","branch_count_variation"]
	check(panel.open_source(first.geometry,{"field_keys":keys}) and panel.controls.size()==4,"same panel fields23")
	panel.controls.main_branch_count.value=4
	check(panel.recipe.parameters.main_branch_count==4 and panel.creation==null,"draft without regeneration")
	panel.undo_parameters();check(panel.recipe.parameters.main_branch_count==6,"Undo")
	panel.redo_parameters();panel.prepare();check(panel.creation!=null,"Redo and prepare")
	if panel.creation!=null:
		var committed:=Generator.build(panel.creation.recipe,Color.WHITE,{},"Maple",panel.creation.source.model_id)
		check(committed.geometry.voxels==panel.creation.source.voxels and panel.creation.recipe.structure.parameters.main_branch_count==4,"preview equals commit and count changes structure")
	panel.discard();check(panel.recipe.parameters.main_branch_count==6 and panel.creation==null,"discard")
	panel.free()
	print("MAPLE_SPECIES_TEST ","PASS" if errors.is_empty() else errors," branches=",tree.layout.size()," cards=",tree.leaves.cards)
	quit(0 if errors.is_empty() else 1)
