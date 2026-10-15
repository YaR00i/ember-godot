extends SceneTree
const Provider=preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const Layout=preload("res://addons/ember_import/ember_tree_branch_layout.gd")
const Generator=preload("res://addons/ember_import/ember_voxel_generator.gd")
const Recipe=preload("res://addons/ember_import/ember_voxel_generator_recipe.gd")
const RecipePanel=preload("res://addons/ember_import/ember_voxel_generator_panel.gd")
const Creation=preload("res://addons/ember_import/ember_voxel_tree_object_creation.gd")
var errors: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func _initialize() -> void:run.call_deferred()
func recipe_for(main: int,splits: int,levels: int,variation:=0) -> Resource:
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7
	var p:=Provider.defaults();p.generation_version=21;p.tree_type=1;p.foliage_amount=0
	p.main_branch_count=main;p.branch_splits=splits;p.branch_levels=levels;p.branch_count_variation=variation
	recipe.parameters=Provider.normalize(p);return recipe
func run() -> void:
	check(Provider.LATEST_VERSIONS[1]==17 and Provider.normalize({"generation_version":22,"tree_type":1}).generation_version==17,"opt-in21 retains presets")
	var counts: Array=[]
	for input in [[3,1,2],[6,2,3],[10,3,4]]:
		var recipe:=recipe_for(input[0],input[1],input[2])
		var a:=Generator.build(recipe,Color.WHITE,{},"Count","count_lab")
		check(not a.has("error") and a.geometry.validation_errors().is_empty() and Provider.structure_errors(a.structure).is_empty(),"bounded valid Source "+str(input))
		var branches: Array=Layout.plan(recipe.parameters,recipe.seed)
		var main:=0;var orders:={};var children:={}
		for branch: Dictionary in branches:
			if branch.order==1:main+=1
			orders[branch.order]=int(orders.get(branch.order,0))+1
			if branch.order>1:children[branch.parent]=int(children.get(branch.parent,0))+1
			if branch.parent>=0:
				check(branch.path[0].distance_to(Layout.sample(branches[branch.parent].path,branch.attachment))<0.0001,"actual parent attachment")
				check(branch.radius<Layout.radius(branches[branch.parent],branch.attachment),"child thinner at fork")
		for branch: Dictionary in branches:
			if branch.order>0 and branch.order<input[2]:check(children.get(branch.id)==input[1],"configured split count without jitter")
		check(main==input[0] and orders.has(input[2]) and not orders.has(input[2]+1),"main count and depth are independent")
		check(a.structure.lines.size()<=768 and a.structure.groups.size()<=128,"bounded worst case")
		counts.append(branches.size())
		var frozen: Resource=Generator.freeze_structure(recipe).recipe
		var restored:=Generator.build(frozen,Color.WHITE,{},"Reopen","count_lab")
		check(restored.geometry.voxels==a.geometry.voxels and restored.geometry.collision_voxels==a.geometry.collision_voxels,"freeze keeps exact Source")
	check(counts[0]<counts[1] and counts[1]<counts[2],"density settings really change branch counts")
	var recipe:=recipe_for(8,3,4,75)
	var first:=Generator.build(recipe,Color.WHITE,{},"Tree","parametric_test")
	var repeat:=Generator.build(recipe,Color.WHITE,{},"Tree","parametric_test")
	check(first.geometry.voxels==repeat.geometry.voxels and first.structure.lines==repeat.structure.lines,"same seed and settings reproduce Source/supports")
	var variation_counts:={}
	for seed in [0,1,7,31,197,74019]:
		var plan:=Layout.plan(recipe.parameters,seed);variation_counts[plan.size()]=true
	check(variation_counts.size()>1,"count variation works across seeds")
	recipe.structure=first.structure.duplicate(true)
	var changed:=recipe.duplicate(true);changed.parameters.main_branch_count=10
	var dense:=Generator.build(changed,Color.WHITE,{},"Dense","dense_test")
	check(dense.structure.lines!=first.structure.lines and dense.structure.parameters.main_branch_count==10,"frozen recipe rebuilds topology on count edit")
	for pair in [["branch_splits",1],["branch_levels",2],["branch_count_variation",0]]:
		changed=recipe.duplicate(true);changed.parameters[pair[0]]=pair[1]
		var revised:=Generator.build(changed,Color.WHITE,{},"Revised","revised_test")
		check(not revised.has("error") and revised.structure.lines!=first.structure.lines and revised.structure.parameters[pair[0]]==pair[1],"frozen recipe responds to "+pair[0])
	changed=recipe.duplicate(true);changed.seed=31
	check(Generator.build(changed,Color.WHITE,{},"Seed","seed_test").structure.branch_seed==31,"seed edit updates stored hierarchy")
	changed=recipe.duplicate(true);changed.parameters.tree_type=2
	check(Generator.build(changed,Color.WHITE,{},"Mismatch","mismatch_test").has("error"),"reject incompatible frozen profile without missing-key access")
	changed=recipe.duplicate(true);changed.parameters.bark_color=Color("a06a45")
	check(Generator.build(changed,Color.WHITE,{},"Colour","colour_test").structure.lines==first.structure.lines,"appearance edit keeps supports")
	var directory:="user://tree-parametric-tests-%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory.path_join("sources")))
	check(ResourceSaver.save(recipe,directory.path_join("parametric_test.tres"))==OK and ResourceSaver.save(first.geometry,directory.path_join("sources/source.tres"))==OK,"private Recipe and Source save")
	var reopened_source: Resource=ResourceLoader.load(directory.path_join("sources/source.tres"),"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened_source.voxels==first.geometry.voxels and reopened_source.palette==first.geometry.palette and reopened_source.collision_voxels==first.geometry.collision_voxels,"Source reopen exact")
	var reopen: Resource=ResourceLoader.load(directory.path_join("parametric_test.tres"),"",ResourceLoader.CACHE_MODE_IGNORE)
	check(Generator.build(reopen,Color.WHITE,{},"Reopen","parametric_test").geometry.voxels==first.geometry.voxels,"save/reopen exact")
	var panel:=RecipePanel.new();root.add_child(panel);panel.recipe_directory=directory
	var keys: Array[String]=["main_branch_count","branch_splits","branch_levels","branch_count_variation"]
	check(panel.open_source(first.geometry,{"field_keys":keys}),"existing recipe panel opens21")
	check(panel.controls.size()==4 and panel.controls.has("main_branch_count"),"same descriptors supply focused LAB fields")
	panel.controls.main_branch_count.value=10
	check(panel.recipe.parameters.main_branch_count==10 and panel.creation==null,"input changes draft without rebuilding")
	panel.undo_parameters();check(panel.recipe.parameters.main_branch_count==8,"parameter Undo")
	panel.redo_parameters();check(panel.recipe.parameters.main_branch_count==10,"parameter Redo")
	panel.prepare();check(panel.creation!=null,"existing prepared-preview transaction")
	if panel.creation!=null:
		check(panel.creation.recipe.structure.parameters.main_branch_count==10,"prepared recipe stores regenerated hierarchy")
		var baked:=Generator.build(panel.creation.recipe,Color.WHITE,{},"Exact",panel.creation.source.model_id)
		check(baked.geometry.voxels==panel.creation.source.voxels,"preview equals saved recipe output")
	panel.discard();check(panel.recipe.parameters.main_branch_count==8 and panel.creation==null,"discard restores recipe and removes preview")
	check(first.geometry.voxels==repeat.geometry.voxels,"original Source remains unchanged")
	panel.free()
	print("TREE_PARAMETRIC_TEST ","PASS" if errors.is_empty() else errors," counts=",counts)
	quit(0 if errors.is_empty() else 1)
