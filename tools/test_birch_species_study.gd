extends SceneTree
const Provider=preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const Generator=preload("res://addons/ember_import/ember_voxel_generator.gd")
const Branching=preload("res://scripts/prototypes/ember_tree_branching_fixture.gd")
const Species=preload("res://scripts/prototypes/ember_tree_species_fixture.gd")
const Recipe=preload("res://addons/ember_import/ember_voxel_generator_recipe.gd")
const RecipePanel=preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
var errors: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func _initialize() -> void:run.call_deferred()
func settings(kind: int) -> Dictionary:
	var p:=Provider.defaults()
	p.merge(Generator.creation_presets(Generator.LARGE_TREE,true)[kind].recipe.parameters,true)
	p.height=96;p.foliage_style=3
	return Provider.normalize(p)
func signature(built: Dictionary) -> Dictionary:
	return {"voxels":built.geometry.voxels.hex_encode().sha256_text(),"collision":built.geometry.collision_voxels.hex_encode().sha256_text(),"structure":var_to_bytes(built.structure).hex_encode().sha256_text(),"palette":var_to_bytes(built.geometry.palette).hex_encode().sha256_text()}
func run() -> void:
	var output:=OS.get_cmdline_user_args()[0]
	var golden_path:=output.path_join("legacy.json")
	var actual:={}
	for kind in 5:
		var p:=settings(kind)
		for seed in [7,31]:
			var b:=Provider.build(p,seed,Color.WHITE,{},"species LAB","species_%d"%kind)
			check(not b.has("error"),"legacy builds")
			actual["%d-%d"%[kind,seed]]=signature(b)
	actual["oak21"]=signature(Provider.build(Branching.build(7,21,{"main_branch_count":8,"branch_splits":3,"branch_levels":4,"branch_count_variation":40}).parameters,7,Color.WHITE,{},"oak","oak"))
	if OS.get_cmdline_user_args().has("--baseline"):
		var file:=FileAccess.open(golden_path,FileAccess.WRITE);file.store_string(JSON.stringify(actual,"\t"));file.close()
		print("SPECIES_BASELINE PASS");quit();return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(golden_path))
	check(expected==actual,"all five old species and oak21 stay byte exact")
	var p:=Species.birch_parameters()
	check(p.generation_version==22 and p.tree_type==2 and Provider.LATEST_VERSIONS[2]==13,"birch22 opt-in, legacy default13 retained")
	check(Provider.normalize({"generation_version":22,"tree_type":1}).generation_version==17,"22 cannot silently upgrade oak")
	var first:=Provider.build(p,7,Color.WHITE,{},"Birch","birch_test")
	check(not first.has("error") and Provider.structure_errors(first.structure).is_empty() and first.geometry.validation_errors().is_empty(),"birch provider/Source validation")
	var repeated:=Provider.build(p,7,Color.WHITE,{},"Birch","birch_test")
	check(signature(first)==signature(repeated),"new branch hierarchy repeatable")
	var full:=Species.birch()
	check(full.leaves.cards>0 and full.leaves.cards<1200 and full.layout.size()>40,"bounded connected branch/foliage layout")
	for anchor: Dictionary in full.leaves.roots:
		var expected_point: Vector3=(Branching.point_at(full.layout[anchor.branch],anchor.t)+Vector3(full.pivot_bias.x,0,full.pivot_bias.y))/16.0
		check(anchor.point.distance_to(expected_point)<0.0001,"every new leaf group attached to actual shoot")
	for seed in [0,31,197]:
		var built:=Provider.build(p,seed,Color.WHITE,{},"Birch","birch_test")
		check(not built.has("error") and Provider.structure_errors(built.structure).is_empty(),"bounded varied seed "+str(seed))
	var changed:=p.duplicate();changed.main_branch_count=5
	var rebuilt:=Provider.build_on_structure(changed,first.structure,7,{},"Birch","birch_test")
	check(rebuilt.structure.parameters.main_branch_count==5 and rebuilt.geometry.voxels!=first.geometry.voxels,"count rebuilds provider structure")
	var mismatched:=p.duplicate();mismatched.tree_type=1
	check(Provider.build_on_structure(mismatched,first.structure,7,{},"Birch","birch_test").has("error"),"cross-species recipe mismatch rejected")
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7
	recipe.parameters=p;recipe.structure=first.structure
	check(Generator.validation_errors(recipe).is_empty(),"existing recipe validation accepts22")
	var directory:="user://birch-species-tests-%d"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path:=directory.path_join("birch_test.tres")
	check(ResourceSaver.save(recipe,path)==OK,"existing Recipe save")
	var reopened: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var rebuilt_reopen:=Generator.build(reopened,Color.WHITE,{},"Birch","birch_test")
	check(rebuilt_reopen.geometry.voxels==first.geometry.voxels and rebuilt_reopen.geometry.collision_voxels==first.geometry.collision_voxels and rebuilt_reopen.geometry.palette==first.geometry.palette,"Recipe reopen/rebuild exact")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory.path_join("sources")))
	var source_path:=directory.path_join("sources/source.tres")
	check(ResourceSaver.save(first.geometry,source_path)==OK,"Source save")
	var source: Resource=ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(source.voxels==first.geometry.voxels and source.collision_voxels==first.geometry.collision_voxels,"Source reopen exact")
	var panel:=RecipePanel.new();root.add_child(panel);panel.recipe_directory=directory
	var keys: Array[String]=["main_branch_count","branch_splits","branch_levels","branch_count_variation"]
	check(panel.open_source(first.geometry,{"field_keys":keys}) and panel.controls.size()==4,"same editor panel exposes22 fields")
	panel.controls.main_branch_count.value=5
	check(panel.recipe.parameters.main_branch_count==5 and panel.creation==null,"draft input no rebuild")
	panel.undo_parameters();check(panel.recipe.parameters.main_branch_count==9,"Undo")
	panel.redo_parameters();check(panel.recipe.parameters.main_branch_count==5,"Redo")
	panel.prepare();check(panel.creation!=null,"existing preview transaction")
	if panel.creation!=null:
		var baked:=Generator.build(panel.creation.recipe,Color.WHITE,{},"Birch",panel.creation.source.model_id)
		check(baked.geometry.voxels==panel.creation.source.voxels,"preview equals recipe commit")
	panel.discard();check(panel.creation==null and panel.recipe.parameters.main_branch_count==9,"discard returns baseline")
	check(signature(first)==signature(repeated),"preview leaves original Source unchanged")
	panel.free()
	print("BIRCH_SPECIES_TEST ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
