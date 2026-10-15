extends SceneTree
const Fixture = preload("res://scripts/prototypes/ember_tree_branching_fixture.gd")
const Provider = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const Layout = preload("res://addons/ember_import/ember_tree_branch_layout.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Recipe = preload("res://addons/ember_import/ember_voxel_generator_recipe.gd")
const Materials = preload("res://scripts/prototypes/ember_painted_bark_projection.gd")
var errors: Array[String] = []
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	check(Provider.LATEST_VERSIONS[1]==17 and Provider.normalize({"generation_version":22,"tree_type":1}).generation_version==17,"saved presets and invalid versions unchanged")
	var inputs := Fixture.build(7,20)
	check(inputs.source.validation_errors().is_empty() and Provider.structure_errors(inputs.structure).is_empty(),"canonical Source20 and hierarchy")
	check(inputs.structure.lines.size()<=256 and inputs.structure.groups.size()<=128 and inputs.cards.is_empty(),"bounded bare network")
	var counts := {}; var supports := 0
	for seed in [0,1,7,31,197,74019]:
		var plan := Layout.plan(Provider.normalize(inputs.parameters),seed)
		for branch: Dictionary in plan:
			check(branch.radius>branch.tip_radius and branch.tip_radius>0,"progressive taper")
			if seed==7: counts[branch.order]=int(counts.get(branch.order,0))+1; supports+=branch.path.size()-1
			if branch.parent>=0:
				var parent: Dictionary = plan[branch.parent]
				check(branch.path[0].distance_to(Layout.sample(parent.path,branch.attachment))<0.0001,"child attached to actual parent")
				check(branch.radius<Layout.radius(parent,branch.attachment),"child thinner at fork")
	check(counts.get(1)==5 and counts.get(2)==15 and counts.get(3)==45 and counts.get(4)==60 and supports==233,"four connected branch levels")
	var again := Provider.build(inputs.parameters,7,Color.WHITE,{},"Repeat","network_lab")
	check(again.geometry.voxels==inputs.source.voxels and again.structure.lines==inputs.structure.lines,"seed preserves actual Source and branch network")
	var damaged: Dictionary = inputs.structure.duplicate(true); damaged.lines[8].parent_id=999
	check(not Provider.structure_errors(damaged).is_empty(),"reject invalid parent")
	damaged=inputs.structure.duplicate(true); damaged.lines[8].start+=Vector3.ONE
	check(not Provider.structure_errors(damaged).is_empty(),"reject detached fork")
	damaged=inputs.structure.duplicate(true); damaged.parameters.generation_version=19
	check(not Provider.structure_errors(damaged).is_empty(),"old versions retain128 support limit")
	damaged=inputs.structure.duplicate(true)
	while damaged.lines.size()<=256: damaged.lines.append(inputs.structure.lines[-1].duplicate())
	check(not Provider.structure_errors(damaged).is_empty(),"reject over-budget network")
	var recipe := Recipe.new(); recipe.generator_id=Generator.LARGE_TREE; recipe.seed=7
	recipe.parameters=inputs.parameters; recipe.structure=inputs.structure
	check(ResourceSaver.save(recipe,"user://network-recipe.tres")==OK and ResourceSaver.save(inputs.source,"user://network-source.tres")==OK,"private save")
	var reopened: Resource = ResourceLoader.load("user://network-recipe.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	var source: Resource = ResourceLoader.load("user://network-source.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	var rebuilt := Generator.build(reopened,Color.WHITE,{},"Reopened","network_lab")
	check(not rebuilt.has("error") and rebuilt.geometry.voxels==source.voxels and rebuilt.geometry.collision_voxels==source.collision_voxels,"Source/Recipe reopen and rebuild exact")
	var mapped := Materials.mesh(inputs.wood,inputs.structure,inputs.pivot_bias)
	var material := Materials.material(inputs.structure,inputs.pivot_bias,Materials.CALM_ART)
	var table: Texture2D = material.get_shader_parameter("painted_bark_supports")
	check(table.get_height()==233 and mapped.get_faces().size()>0,"bark frame table covers full network")
	print("TREE_NETWORK_TEST ","PASS" if errors.is_empty() else errors," counts=",counts," supports=",supports)
	quit(0 if errors.is_empty() else 1)
