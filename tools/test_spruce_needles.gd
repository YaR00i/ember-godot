extends "res://tools/test_savanna_canopy.gd"
func run() -> void:
	var shape:=Species.spruce();var tree:=Species.spruce_needles()
	check(tree.source.voxels==shape.source.voxels and tree.source.voxels.hex_encode().sha256_text()=="dfd9f45476078d53b05505d7c586d559d0a74be273b31d4e8b616a76d6e677e0","provisional spruce wood Source exact")
	check(tree.source.collision_voxels==shape.source.collision_voxels and tree.structure==shape.structure and tree.layout==shape.layout and tree.wood.get_faces()==shape.wood.get_faces(),"same physical and branch-owned shape")
	var full: Dictionary=tree.full_leaves;var arrays: Array=full.mesh.surface_get_arrays(0)
	check(full.cards>500 and full.cards<1800,"bounded needle batch")
	var offset:=Vector3(tree.pivot_bias.x,0,tree.pivot_bias.y)
	for entry: Dictionary in full.roots:
		var expected: Vector3=(Branching.point_at(tree.layout[entry.branch],entry.t)+offset)/16.0
		check(entry.point.distance_to(expected)<0.0001 and arrays[Mesh.ARRAY_VERTEX][entry.vertex].distance_to(expected)<0.0001,"all sprays anchored to real shoot, including mesh stem vertex")
	var covered: Dictionary={}
	for entry: Dictionary in tree.leaves.roots:
		if is_equal_approx(entry.t,1.0):covered[entry.branch]=true
	for branch: Dictionary in tree.layout:
		if branch.order>=0:check(covered.has(branch.id),"baseline retains endpoint tuft on each branch")
	var repeated:=Species.spruce_needles()
	check(arrays==repeated.full_leaves.mesh.surface_get_arrays(0),"same seed reproduces cards and UVs")
	var thirty:=Branching.thin_crown_cards(full,0.30);var sixty:=Branching.thin_crown_cards(full,0.60)
	var kept: Dictionary={}
	for entry: Dictionary in sixty.roots:kept[entry.original_card]=true
	for entry: Dictionary in thirty.roots:check(kept.has(entry.original_card),"nested density")
	check(Branching.thin_crown_cards(full,0.0).cards==0,"zero density removes all needles")
	var first_branch:=0
	for i in full.roots.size():
		if tree.layout[full.roots[i].branch].order==1:first_branch=i;break
	for count in [1,6]:
		var sample:=Branching.crown_card_sample(full,count,first_branch)
		check(sample.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==arrays[Mesh.ARRAY_VERTEX].slice(first_branch*12,(first_branch+count)*12),"branch sample uses unchanged tree vertices")
		check(sample.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()==count*36,"branch sample index topology")
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7;recipe.parameters=tree.parameters;recipe.structure=tree.structure
	var path:="user://spruce-needles-%d.tres"%Time.get_ticks_usec();check(ResourceSaver.save(recipe,path)==OK,"save Recipe")
	var loaded: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var built:=Generator.build(loaded,Color.WHITE,{},"Spruce","spruce25_lab")
	check(built.geometry.voxels==tree.source.voxels,"reopen Source exact")
	var rebuilt:=Branching.from_built(built,loaded.parameters,loaded.seed)
	var cards:=Branching.crown_cards(rebuilt.layout,rebuilt.structure,offset,16.0,loaded.seed,{"branch_growth":true,"size":Species.SPRUCE_CARD_SIZE,"needle_sprays":true})
	check(cards.mesh.surface_get_arrays(0)==arrays,"reopen Recipe plus same LAB options reproduces needle cards")
	print("SPRUCE_NEEDLES_TEST ","PASS" if errors.is_empty() else errors," full=",full.cards," base=",tree.leaves.cards);quit(0 if errors.is_empty() else 1)
