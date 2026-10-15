extends "res://tools/test_maple_species_study.gd"
func run() -> void:
	var wide:=Species.maple()
	var upright:=Species.maple(7,{"crown_shape":1})
	check(wide.source.voxels.hex_encode().sha256_text()=="6d913467e81eea357731f93eef0b7cc2971c56e2fce2b1942110db941a52bb7c","saved wide Source exact")
	var a: Vector3=wide.leaves.mesh.get_aabb().size
	var b: Vector3=upright.leaves.mesh.get_aabb().size
	print("MAPLE_SHAPE_BOUNDS wide=",a," upright=",b)
	check(maxf(b.x,b.z)<maxf(a.x,a.z)*0.85 and b.y>a.y*1.15,"new crown materially narrower and taller")
	check(upright.source.voxels!=wide.source.voxels and Provider.structure_errors(upright.structure).is_empty(),"real support/Source change, valid hierarchy")
	for seed in [0,7,31,197]:
		var p:=Species.maple_parameters();p.crown_shape=1
		var built:=Provider.build(p,seed,Color.WHITE,{},"Maple","maple_shapes_test")
		check(not built.has("error") and Provider.structure_errors(built.structure).is_empty() and built.geometry.validation_errors().is_empty(),"upright seed valid "+str(seed))
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7
	recipe.parameters=wide.parameters;recipe.structure=wide.structure
	var directory:="user://maple-shape-tests-%d"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(ResourceSaver.save(recipe,directory.path_join("maple_shapes_test.tres"))==OK,"wide Recipe saved")
	var first:=Generator.build(recipe,Color.WHITE,{},"Maple","maple_shapes_test")
	var panel:=RecipePanel.new();root.add_child(panel);panel.recipe_directory=directory
	var keys: Array[String]=["crown_shape","main_branch_count","branch_splits","branch_levels","branch_count_variation"]
	check(panel.open_source(first.geometry,{"field_keys":keys}) and panel.controls.size()==5,"shared recipe editor has form selector")
	panel.controls.crown_shape.select(1);panel.controls.crown_shape.item_selected.emit(1)
	check(panel.recipe.parameters.crown_shape==1 and panel.creation==null,"shape draft without regeneration")
	panel.undo_parameters();check(panel.recipe.parameters.crown_shape==0,"Undo shape")
	panel.redo_parameters();panel.prepare()
	check(panel.creation!=null,"Redo/prepare shape")
	if panel.creation!=null:
		var prepared=panel.creation
		check(prepared.recipe.structure.parameters.crown_shape==1 and prepared.source.voxels==upright.source.voxels,"new form regenerated through existing provider")
		check(ResourceSaver.save(prepared.recipe,directory.path_join("upright.tres"))==OK,"upright Recipe saved")
		var reopened: Resource=ResourceLoader.load(directory.path_join("upright.tres"),"",ResourceLoader.CACHE_MODE_IGNORE)
		check(Generator.build(reopened,Color.WHITE,{},"Maple","maple_shapes_test").geometry.voxels==upright.source.voxels,"reopen reproduces upright Source")
	panel.discard();check(panel.recipe.parameters.crown_shape==0 and panel.creation==null,"discard returns saved wide")
	panel.free()
	print("MAPLE_SHAPES_TEST ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
