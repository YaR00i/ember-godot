extends "res://tools/test_savanna_species_study.gd"
func run() -> void:
	var p:=Species.spruce_parameters()
	check(p.generation_version==25 and p.tree_type==4,"spruce opt-in in same provider")
	for kind in [0,1,2,3]:check(Provider.normalize({"generation_version":25,"tree_type":kind}).generation_version!=25,"cross-species opt-in rejected")
	check(Provider.LATEST_VERSIONS==[14,17,13,12,15],"saved defaults unchanged")
	var built:=Provider.build(p,7,Color.WHITE,{},"Spruce","spruce25_lab")
	if built.has("error"):check(false,str(built));quit(1);return
	check(built.geometry.validation_errors().is_empty() and Provider.structure_errors(built.structure).is_empty(),"valid Source and attached bounded scaffold")
	check(signature(built)==signature(Provider.build(p,7,Color.WHITE,{},"Spruce","spruce25_lab")),"repeatability exact")
	var tree:=Species.spruce()
	var shape:=Species.crown_blockout(tree,0.0);var bounds:=shape.get_aabb()
	check(bounds.size.y>maxf(bounds.size.x,bounds.size.z),"upright silhouette")
	check(bounds.end.y>5.7 and bounds.position.y<2.0,"leader covered and foliage descends along trunk")
	check(tree.structure.groups.size()==50,"two supports per main limb plus continuous leader envelope")
	var joined: Dictionary={0:true}
	for _pass in tree.structure.groups.size():
		for i in tree.structure.groups.size():
			if joined.has(i):continue
			var a: Dictionary=tree.structure.groups[i]
			for j: int in joined.keys():
				var b: Dictionary=tree.structure.groups[j]
				if ((a.center-b.center)/(a.radii+b.radii)).length_squared()<1.0:joined[i]=true;break
	check(joined.size()==tree.structure.groups.size(),"crown supports overlap into one connected envelope, including upper whorls")
	for group: Dictionary in tree.structure.groups:check(group.has("branch_id"),"crown volume belongs to actual branch")
	for seed in [0,31,197]:
		var other:=Provider.build(p,seed,Color.WHITE,{},"Spruce","spruce25_lab")
		check(not other.has("error") and Provider.structure_errors(other.structure).is_empty(),"bounded attached alternate seed")
	for overrides: Dictionary in [{"main_branch_count":3,"branch_splits":1,"branch_levels":2},{"main_branch_count":10,"branch_splits":3,"branch_levels":4}]:
		var q:=p.duplicate(true);q.merge(overrides,true)
		var other:=Provider.build_on_structure(q,built.structure,31,{},"Spruce","spruce25_lab")
		check(not other.has("error") and Provider.structure_errors(other.structure).is_empty(),"extreme controls stay valid")
		check(signature(other)==signature(Provider.build(q,31,Color.WHITE,{},"Spruce","spruce25_lab")),"changed controls regenerate same Source as fresh build")
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7;recipe.parameters=p;recipe.structure=built.structure
	check(Generator.validation_errors(recipe).is_empty(),"Recipe25 validation")
	var directory:="user://spruce-shape-%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path:=directory.path_join("spruce25_lab.tres")
	check(ResourceSaver.save(recipe,path)==OK,"save Recipe25")
	var loaded: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var reopened:=Generator.build(loaded,Color.WHITE,{},"Spruce","spruce25_lab")
	check(reopened.geometry.voxels==built.geometry.voxels and reopened.geometry.collision_voxels==built.geometry.collision_voxels,"reopen Source/collision exact")
	check(reopened.structure.groups==built.structure.groups,"reopen crown supports exact")
	for i in built.structure.lines.size():
		var a: Dictionary=built.structure.lines[i];var b: Dictionary=reopened.structure.lines[i]
		check(a.start==b.start and a.finish==b.finish and a.branch_id==b.branch_id and a.parent_id==b.parent_id,"reopen branch positions and ownership exact")
		for key in ["r0","r1","t0","t1","parent_t"]:check(absf(float(a[key])-float(b[key]))<0.000001,"reopen scalar branch values within text Resource precision")
	var reopened_inputs:=Branching.from_built(reopened,loaded.parameters,loaded.seed)
	check(Species.crown_blockout(reopened_inputs,0.0).get_faces()==shape.get_faces(),"reopen reproduces diagnostic crown surface")
	var panel:=RecipePanel.new();root.add_child(panel);panel.recipe_directory=directory
	var keys: Array[String]=["main_branch_count","branch_splits","branch_levels","branch_count_variation","crown_spread","branch_start"]
	check(panel.open_source(built.geometry,{"field_keys":keys}) and panel.controls.size()==6,"same Recipe panel exposes six shape controls")
	panel.controls.main_branch_count.value=9;check(panel.creation==null,"draft does not regenerate")
	panel.undo_parameters();check(panel.recipe.parameters.main_branch_count==7,"Undo")
	panel.redo_parameters();panel.prepare();check(panel.creation!=null,"Redo and preview")
	if panel.creation!=null:check(Generator.build(panel.creation.recipe,Color.WHITE,{},"Spruce",panel.creation.source.model_id).geometry.voxels==panel.creation.source.voxels,"preview equals commit")
	panel.discard();check(panel.recipe.parameters.main_branch_count==7 and panel.creation==null,"discard initial shape")
	panel.free()
	print("SPRUCE_SHAPE_TEST ","PASS" if errors.is_empty() else errors," bounds=",bounds," lines=",built.structure.lines.size()," source=",built.geometry.voxels.hex_encode().sha256_text());quit(0 if errors.is_empty() else 1)
