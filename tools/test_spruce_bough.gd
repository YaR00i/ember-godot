extends "res://tools/test_savanna_canopy.gd"
func run() -> void:
	var tree:=Species.spruce_boughs();var p: Dictionary=tree.parameters
	check(tree.source.validation_errors().is_empty() and Provider.structure_errors(tree.structure).is_empty(),"valid Source and branch hierarchy")
	check(p.crown_shape==1 and p.main_branch_count==12 and tree.layout.size()==473 and tree.structure.lines.size()==552 and tree.structure.groups.size()==85,"bounded denser paired bough construction")
	var previous:=Species.spruce_boughs(7,{"main_branch_count":9})
	check(previous.source.voxels.hex_encode().sha256_text()=="007ce55b852965d40979746f0284457a1c2571176796cfc4e82974c392cd57cf","previous nine-tier wood preserved")
	check(tree.layout[1]==previous.layout[1],"first bough construction unchanged")
	check(max_tier_gap(tree.layout)<max_tier_gap(previous.layout)*0.85,"largest tier gap reduced by at least fifteen percent")
	check(upper_cards(tree)>upper_cards(previous)*1.20,"upper crown has more attached needle planes")
	check(Species.spruce_needles().source.voxels.hex_encode().sha256_text()=="dfd9f45476078d53b05505d7c586d559d0a74be273b31d4e8b616a76d6e677e0","previous spruce preserved")
	var children: Dictionary={}
	for branch: Dictionary in tree.layout:
		if branch.order<1:continue
		children[branch.parent]=int(children.get(branch.parent,0))+1
		check(branch.path[0].distance_to(Branching.point_at(tree.layout[branch.parent],branch.attachment))<0.0001,"every branch starts on parent")
	for branch: Dictionary in tree.layout:
		if branch.order==1:check(children.get(branch.id,0)==6,"three pairs of lateral twigs")
		if branch.order==2:check(children.get(branch.id,0)==1,"fine hanging shoot on each lateral")
	var full: Dictionary=tree.full_leaves;var arrays: Array=full.mesh.surface_get_arrays(0)
	check(full.cards==2166,"bounded denser needle planes")
	var offset:=Vector3(tree.pivot_bias.x,0,tree.pivot_bias.y)
	for entry: Dictionary in full.roots:
		var expected: Vector3=(Branching.point_at(tree.layout[entry.branch],entry.t)+offset)/16.0
		check(entry.point.distance_to(expected)<0.0001 and arrays[Mesh.ARRAY_VERTEX][entry.vertex].distance_to(expected)<0.0001,"spray stem attached to actual shoot")
	var covered: Dictionary={}
	for entry: Dictionary in tree.leaves.roots:
		if is_equal_approx(entry.t,1.0):covered[entry.branch]=true
	for branch: Dictionary in tree.layout:
		if branch.order>=0:check(covered.has(branch.id),"endpoint tuft retained at baseline")
	check(arrays==Species.spruce_boughs().full_leaves.mesh.surface_get_arrays(0),"deterministic needle vertices UV and normals")
	var thirty:=Branching.thin_crown_cards(full,0.30);var sixty: Dictionary=tree.leaves;var kept: Dictionary={}
	for entry: Dictionary in sixty.roots:kept[entry.original_card]=true
	for entry: Dictionary in thirty.roots:check(kept.has(entry.original_card),"density nested subset")
	var limb:=Species.spruce_limb(tree,1)
	check(limb.layout.size()==13 and limb.leaves.cards>0,"one actual primary subtree")
	var displayed: Array=tree.leaves.mesh.surface_get_arrays(0);var sample: Array=limb.leaves.mesh.surface_get_arrays(0)
	for entry: Dictionary in limb.leaves.roots:
		var original: Dictionary=tree.leaves.roots[entry.original_card]
		check(sample[Mesh.ARRAY_VERTEX].slice(entry.vertex-7,entry.vertex+5)==displayed[Mesh.ARRAY_VERTEX].slice(original.vertex-7,original.vertex+5),"sample uses unchanged displayed tree leaf geometry")
		check(int(sample[Mesh.ARRAY_CUSTOM1][(entry.vertex-7)*4+3])==1,"sample belongs to selected limb")
	var empty:=tree.duplicate();empty.leaves=Branching.thin_crown_cards(full,0.0)
	check(Species.spruce_limb(empty,1).leaves.cards==0,"bare limb at zero density")
	for overrides: Dictionary in [{"main_branch_count":3,"branch_splits":1,"branch_levels":2},{"main_branch_count":12,"branch_splits":3,"branch_levels":4},{"crown_shape":0}]:
		var q:=p.duplicate(true);q.merge(overrides,true)
		var fresh:=Provider.build(q,31,Color.WHITE,{},"Spruce","spruce25_lab")
		var edited:=Provider.build_on_structure(q,tree.structure,31,{},"Spruce","spruce25_lab")
		check(not fresh.has("error") and Provider.structure_errors(fresh.structure).is_empty(),"control extremes valid")
		if overrides.get("branch_levels")==4:check(fresh.structure.lines.size()==768,"maximum controls fit existing segment budget")
		check(signature(fresh)==signature(edited),"shape and hierarchy edits regenerate same Source as fresh build")
	for seed in [0,197]:
		var built:=Provider.build(p,seed,Color.WHITE,{},"Spruce","spruce25_lab")
		check(not built.has("error") and Provider.structure_errors(built.structure).is_empty(),"alternate seed bounded")
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7;recipe.parameters=p;recipe.structure=tree.structure
	var directory:="user://spruce-bough-%d"%Time.get_ticks_usec();DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path:=directory.path_join("spruce25_lab.tres");check(ResourceSaver.save(recipe,path)==OK,"save Recipe")
	var loaded: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var built:=Generator.build(loaded,Color.WHITE,{},"Spruce","spruce25_lab")
	check(built.geometry.voxels==tree.source.voxels and built.geometry.collision_voxels==tree.source.collision_voxels,"reopen Source and collision exact")
	var reopened:=Branching.from_built(built,loaded.parameters,loaded.seed)
	var cards:=Branching.crown_cards(reopened.layout,reopened.structure,offset,16.0,loaded.seed,{"branch_growth":true,"size":Species.SPRUCE_CARD_SIZE,"needle_sprays":true,"needle_boughs":true})
	check(cards.mesh.surface_get_arrays(0)==arrays,"reopen reproduces needle geometry")
	var panel:=RecipePanel.new();root.add_child(panel);panel.recipe_directory=directory
	var keys: Array[String]=["crown_shape","main_branch_count","branch_splits","branch_levels","branch_count_variation","crown_spread","branch_start"]
	check(panel.open_source(tree.source,{"field_keys":keys}) and panel.controls.size()==7,"same Recipe panel with shape and six branch controls")
	panel.controls.main_branch_count.value=7;check(panel.creation==null,"draft does not regenerate")
	panel.undo_parameters();check(panel.recipe.parameters.main_branch_count==12,"Undo draft")
	panel.redo_parameters();panel.prepare();check(panel.creation!=null,"Redo preview")
	if panel.creation!=null:check(Generator.build(panel.creation.recipe,Color.WHITE,{},"Spruce",panel.creation.source.model_id).geometry.voxels==panel.creation.source.voxels,"preview equals commit")
	panel.discard();check(panel.recipe.parameters.main_branch_count==12 and panel.creation==null,"discard initial shape");panel.free()
	print("SPRUCE_BOUGH_TEST ","PASS" if errors.is_empty() else errors," full=",full.cards," base=",tree.leaves.cards," source=",tree.source.voxels.hex_encode().sha256_text());quit(0 if errors.is_empty() else 1)

func max_tier_gap(layout: Array) -> float:
	var heights: Array[float]=[]
	for branch: Dictionary in layout:
		if branch.order==1:heights.append(branch.path[0].y)
	var gap:=0.0;var previous: float=(heights[0]+heights[1]+heights[2])/3.0
	for index in range(3,heights.size(),3):
		var current: float=(heights[index]+heights[index+1]+heights[index+2])/3.0
		gap=maxf(gap,current-previous);previous=current
	return gap

func upper_cards(tree: Dictionary) -> int:
	var count:=0
	for entry: Dictionary in tree.leaves.roots:
		if entry.point.y>float(tree.parameters.height)/16.0*0.65:count+=1
	return count
