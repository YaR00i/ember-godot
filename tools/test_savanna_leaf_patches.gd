extends "res://tools/test_savanna_canopy.gd"
func run() -> void:
	var accepted:=Species.savanna_umbrella();var tree:=Species.savanna_umbrella_foliage()
	check(tree.source.voxels==accepted.source.voxels and tree.source.voxels.hex_encode().sha256_text()=="b2c04fd021ae17c0bc30387743ff6803e1ff84ebcdead5f5b5a94ba8eeac8497","accepted wood Source exact")
	check(tree.source.collision_voxels==accepted.source.collision_voxels,"accepted collision Source exact")
	check(tree.structure==accepted.structure and tree.layout==accepted.layout and tree.wood.get_faces()==accepted.wood.get_faces(),"accepted supports and wood mesh exact")
	var full: Dictionary=tree.full_leaves
	check(full.cards>300 and full.cards<1800 and tree.leaves.cards>150,"bounded usable leaf coverage")
	var offset:=Vector3(tree.pivot_bias.x,0,tree.pivot_bias.y)
	for entry: Dictionary in full.roots:
		var point: Vector3=(Branching.point_at(tree.layout[entry.branch],entry.t)+offset)/16.0
		check(entry.attachment.distance_to(point)<0.0001,"every group attached to an actual shoot")
		if bool(entry.get("tip_cover",false)):
			check(tree.layout[entry.branch].order==tree.parameters.branch_levels and is_equal_approx(entry.t,1.0),"tip fans only at terminal shoot ends")
			var vertices: PackedVector3Array=full.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			check((vertices[entry.vertex-7]-vertices[entry.vertex-5]).length()<0.75,"tip fans stay smaller than regular crown patches")
			var on_shoot: bool=false
			for t in [0.60,0.80,1.0]:
				if entry.point.distance_to((Branching.point_at(tree.layout[entry.branch],t)+offset)/16.0)<0.37:on_shoot=true
			check(on_shoot,"small fans remain along final shoot segment")
		else:
			check(Branching.crown_envelope_contains(entry.point,tree.structure,offset,16.0,0.20),"volume cards within accepted crown envelope")
		var vertex: Vector3=full.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][entry.vertex]
		check(vertex.distance_to(entry.point)<0.0001,"card anchor agrees with mesh; group attachment recorded separately")
	var same:=Species.savanna_umbrella_foliage()
	check(full.mesh.surface_get_arrays(0)==same.full_leaves.mesh.surface_get_arrays(0),"repeatability of buffers and UVs")
	var thirty:=Branching.thin_crown_cards(full,0.30)
	var sixty:=Branching.thin_crown_cards(full,0.60)
	var covered: Dictionary={}
	for entry: Dictionary in sixty.roots:
		if bool(entry.get("tip_cover",false)):covered[entry.branch]=int(covered.get(entry.branch,0))+1
	for branch: Dictionary in tree.layout:
		if branch.order==tree.parameters.branch_levels:check(covered.get(branch.id,0)==3,"baseline retains three small fans on every terminal shoot")
	check(Branching.thin_crown_cards(full,0.0).cards==0,"zero density still removes all foliage, including tip fans")
	var kept: Dictionary={}
	for entry: Dictionary in sixty.roots:kept[entry.original_card]=true
	for entry: Dictionary in thirty.roots:check(kept.has(entry.original_card),"density nested subset")
	for count in [1,6]:
		var sample:=Branching.crown_card_sample(full,count)
		check(sample.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==full.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].slice(0,count*12),"sample preserves original vertices")
		check(sample.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()==count*36,"sample has real card topology")
	var path:="user://savanna-patches-%d.tres"%Time.get_ticks_usec()
	var recipe:=Recipe.new();recipe.generator_id="large_tree";recipe.seed=7;recipe.parameters=tree.parameters;recipe.structure=tree.structure
	check(ResourceSaver.save(recipe,path)==OK,"save Recipe")
	var loaded: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var built:=Generator.build(loaded,Color.WHITE,{},"Savanna","savanna24_lab")
	check(built.geometry.voxels==tree.source.voxels,"reopen Source exact")
	var rebuilt:=Branching.from_built(built,loaded.parameters,loaded.seed)
	var rebuilt_cards:=Branching.crown_cards(rebuilt.layout,rebuilt.structure,offset,16.0,loaded.seed,{"branch_growth":true,"size":1.05,"canopy_envelope":true})
	check(rebuilt_cards.mesh.surface_get_arrays(0)==full.mesh.surface_get_arrays(0),"recipe plus same LAB artwork options reproduce all cards")
	print("SAVANNA_PATCH_TEST ","PASS" if errors.is_empty() else errors," full=",full.cards," base=",tree.leaves.cards);quit(0 if errors.is_empty() else 1)
