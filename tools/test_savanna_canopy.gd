extends "res://tools/test_savanna_species_study.gd"
func run() -> void:
	var rejected:=Species.savanna()
	check(rejected.source.voxels.hex_encode().sha256_text()=="8d9a1c5a4c395a33a4a9d66aeeb09cb4fa06d26b7c9bc5952ec5ead5986b755f","rejected shape0 Source exact")
	var trial:=Species.savanna_umbrella()
	var p: Dictionary=trial.parameters
	check(p.generation_version==24 and p.crown_shape==1 and p.tree_type==0,"existing shape parameter, same provider")
	check(trial.source.validation_errors().is_empty() and Provider.structure_errors(trial.structure).is_empty(),"Source and hierarchy valid")
	check(trial.structure.groups.size()>=15 and trial.structure.groups.size()<=20,"bounded branch-attached crown groups")
	var volumes:=Species.crown_blockout(trial)
	var bounds:=volumes.get_aabb()
	print("CANOPY_BOUNDS ",bounds)
	check(bounds.size.y<maxf(bounds.size.x,bounds.size.z)*0.35,"shallow crown, not tall layers")
	var connected: Dictionary={0:true}
	for _pass in trial.structure.groups.size():
		for i in trial.structure.groups.size():
			if connected.has(i):continue
			for j: int in connected.keys():
				var a: Dictionary=trial.structure.groups[i];var b: Dictionary=trial.structure.groups[j]
				var delta: Vector3=a.center-b.center;delta.y/=0.28
				if delta.length()<float(a.radii.x+b.radii.x):connected[i]=true;break
	check(connected.size()==trial.structure.groups.size(),"one connected canopy, not isolated shelves")
	for group: Dictionary in trial.structure.groups:
		check(trial.layout[group.branch_id].order in [1,2],"groups attached to scaffold and secondary limbs")
		var main: bool=trial.layout[group.branch_id].order==1
		var local: Vector3=(Branching.point_at(trial.layout[group.branch_id],0.98 if main else 0.90)+Vector3.UP*float(p.height)*(0.045 if main else 0.025))
		check(group.center.distance_to(local)<0.22,"provider quarter-cell crown centres follow actual shoots")
	for seed in [0,7,31,197]:
		var built:=Provider.build(p,seed,Color.WHITE,{},"Savanna","canopy_test")
		check(not built.has("error") and Provider.structure_errors(built.structure).is_empty(),"seed bounded and attached "+str(seed))
	for count in [3,10]:
		var q:=p.duplicate(true);q.main_branch_count=count;q.branch_levels=4
		var built:=Provider.build(q,31,Color.WHITE,{},"Savanna","canopy_test")
		check(not built.has("error") and Provider.structure_errors(built.structure).is_empty(),"extreme branches "+str(count))
	var q:=p.duplicate(true);q.crown_shape=0
	check(signature(Provider.build_on_structure(q,trial.structure,7,{},"Savanna","canopy_test"))==signature(Provider.build(q,7,Color.WHITE,{},"Savanna","canopy_test")),"shape change rebuilds supports exactly")
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7;recipe.parameters=p;recipe.structure=trial.structure
	check(Generator.validation_errors(recipe).is_empty(),"Recipe validation")
	var directory:="user://savanna-canopy-%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var recipe_path:=directory.path_join(trial.source.model_id+".tres")
	check(ResourceSaver.save(recipe,recipe_path)==OK,"save Recipe")
	var loaded: Resource=ResourceLoader.load(recipe_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(Generator.build(loaded,Color.WHITE,{},"Savanna","canopy_test").geometry.voxels==trial.source.voxels,"reopen exact Source")
	var panel:=RecipePanel.new();root.add_child(panel);panel.recipe_directory=directory
	var keys: Array[String]=["main_branch_count","branch_splits","branch_levels","branch_count_variation"]
	check(panel.open_source(trial.source,{"field_keys":keys}) and panel.controls.size()==4,"same four controls")
	panel.controls.main_branch_count.value=7;check(panel.creation==null,"draft without regeneration")
	panel.undo_parameters();check(panel.recipe.parameters.main_branch_count==5,"Undo")
	panel.redo_parameters();panel.prepare();check(panel.creation!=null,"Redo and prepare")
	if panel.creation!=null:
		check(Generator.build(panel.creation.recipe,Color.WHITE,{},"Savanna",panel.creation.source.model_id).geometry.voxels==panel.creation.source.voxels,"preview equals commit")
	panel.discard();check(panel.recipe.parameters.crown_shape==1 and panel.recipe.parameters.main_branch_count==5 and panel.creation==null,"discard returns initial silhouette")
	panel.free()
	print("SAVANNA_CANOPY_TEST ","PASS" if errors.is_empty() else errors," branches=",trial.layout.size()," groups=",trial.structure.groups.size());quit(0 if errors.is_empty() else 1)
