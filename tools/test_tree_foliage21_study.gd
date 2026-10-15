extends SceneTree
const Fixture=preload("res://scripts/prototypes/ember_tree_branching_fixture.gd")
const Study=preload("res://scripts/prototypes/ember_tree_parametric_study.gd")
const Materials=preload("res://scripts/prototypes/ember_painted_bark_projection.gd")
var errors: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	for preset in Study.PRESETS:
		var inputs:=Fixture.build(7,21,preset)
		var before: PackedByteArray=inputs.source.voxels.duplicate()
		var offset:=Vector3(inputs.pivot_bias.x,0,inputs.pivot_bias.y)
		var cards:=Fixture.crown_cards(inputs.layout,inputs.structure,offset,16,7,{"branch_growth":true,"size":0.96})
		var repeated:=Fixture.crown_cards(inputs.layout,inputs.structure,offset,16,7,{"branch_growth":true,"size":0.96})
		check(cards.mesh.surface_get_arrays(0)==repeated.mesh.surface_get_arrays(0),"same supports/seed reproduce cards, UV and group normals")
		check(cards.cards>0 and cards.cards<4800 and cards.triangles==cards.cards*12,"bounded curved leaf batch")
		var arrays: Array=cards.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		var macro: PackedFloat32Array=arrays[Mesh.ARRAY_CUSTOM1]
		for anchor: Dictionary in cards.roots:
			check(vertices[anchor.vertex].distance_to(anchor.point)<0.0001,"stem vertex attached to real branch")
			check(anchor.point.distance_to((Fixture.point_at(inputs.layout[anchor.branch],anchor.t)+offset)/16.0)<0.0001,"Source supports own anchor")
			var local: Vector2=uv[anchor.vertex]*2-Vector2(anchor.tile%2,anchor.tile/2)
			check(local.distance_to(Vector2(0.5,0.94))<0.0001,"atlas variant retains stem UV")
		for i in vertices.size():
			var normal:=Vector3(macro[i*4],macro[i*4+1],macro[i*4+2])
			check(normal.is_finite() and absf(normal.length()-1)<0.003,"finite macro lighting normals")
		check(inputs.source.voxels==before and inputs.cards.is_empty(),"derived foliage never changes Source21 or bare21 fixture")
		check_density(cards)
		print("FOLIAGE21_PRESET cards=",cards.cards," triangles=",cards.triangles)
	var inputs:=Fixture.build(7,21,Study.PRESETS[1])
	var profile: Resource=load("res://content/terrain_materials/painted_light_grass.tres")
	var material:=Materials.leaf_cards_material(inputs.wood,profile,true,"res://content/material_studies/trees/leaf_cluster_atlas_v2.png")
	for key in ["low","cool","warm","tint_strength","shadow_color","shadow_fill"]:
		check(material.get_shader_parameter("painterly_grass_"+key)==profile.get("grass_light_"+key),"shared accepted light "+key)
	print("TREE_FOLIAGE21_TEST ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)

func check_density(full: Dictionary) -> void:
	var original: Array=full.mesh.surface_get_arrays(0)
	check(Fixture.thin_crown_cards(full,1.0).mesh==full.mesh,"100 percent returns the original mesh instance")
	check(Fixture.thin_crown_cards(full,0.0).cards==0,"zero percent removes all leaf puffs")
	var previous_ids: Dictionary={}
	for i in full.cards:previous_ids[i]=true
	var previous_puffs:=Fixture.crown_puff_count(full)
	var normal_roundtrip_error:=0.0
	for coverage in [0.75,0.60,0.45]:
		var reduced:=Fixture.thin_crown_cards(full,coverage)
		var repeated:=Fixture.thin_crown_cards(full,coverage)
		check(reduced.mesh.surface_get_arrays(0)==repeated.mesh.surface_get_arrays(0),"density reproduction exact")
		check(reduced.puffs<previous_puffs and reduced.cards<previous_ids.size(),"lower density removes puffs/cards")
		var actual: Array=reduced.mesh.surface_get_arrays(0)
		var ids: Dictionary={};var kept_sites: Dictionary={}
		for root: Dictionary in reduced.roots:
			var id: int=root.original_card;ids[id]=true
			check(previous_ids.has(id),"lower density is nested, no puff jumps to another location")
			var base: int=int(root.vertex)-7;var start: int=int(full.roots[id].vertex)-7
			for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1]:
				var stride:=4 if channel in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1] else 1
				check(actual[channel].slice(base*stride,(base+12)*stride)==original[channel].slice(start*stride,(start+12)*stride),"remaining card channel exact: "+str(channel))
			# ArrayMesh normal packing is quantized; decoding/repacking has a small
			# round-trip error. Positions/UV/custom macro normals above stay exact.
			for i in 12:normal_roundtrip_error=maxf(normal_roundtrip_error,actual[Mesh.ARRAY_NORMAL][base+i].distance_to(original[Mesh.ARRAY_NORMAL][start+i]))
			check(actual[Mesh.ARRAY_VERTEX][root.vertex]==full.roots[id].point,"remaining leaf stems stay attached")
			kept_sites["%d:%d"%[root.branch,roundi(root.t*10000)]]=true
		for i in full.roots.size():
			var root: Dictionary=full.roots[i]
			check(ids.has(i)==kept_sites.has("%d:%d"%[root.branch,roundi(root.t*10000)]),"whole puff retained/removed together")
		for index in actual[Mesh.ARRAY_INDEX]:check(index>=0 and index<actual[Mesh.ARRAY_VERTEX].size(),"subset index stays in bounds")
		previous_ids=ids;previous_puffs=reduced.puffs
	check(full.mesh.surface_get_arrays(0)==original,"thinning never mutates full crown buffers")
	check(normal_roundtrip_error<0.0005,"geometric normals retain direction within packed-buffer precision")
	var groups:=Fixture.crown_leaf_groups(full);var selected: int=groups.keys()[0]
	var baseline:=Fixture.thin_crown_cards(full,0.45)
	var baseline_ids: Dictionary={}
	for root: Dictionary in baseline.roots:baseline_ids[root.original_card]=true
	var half:=Fixture.thin_crown_cards(full,0.45,{selected:0.5})
	var half_ids: Dictionary={}
	for root: Dictionary in half.roots:half_ids[root.original_card]=true
	var removed:=0
	for id: int in baseline_ids:
		var owner: int=int(original[Mesh.ARRAY_CUSTOM1][(int(full.roots[id].vertex)-7)*4+3])
		if owner!=selected:check(half_ids.has(id),"local thinning retains every other part exactly")
		elif not half_ids.has(id):removed+=1
	for id: int in half_ids:check(baseline_ids.has(id),"local reduction nested within global density")
	check(removed>0,"selected part visibly loses puffs")
	check(half.mesh.surface_get_arrays(0)==Fixture.thin_crown_cards(full,0.45,{selected:0.5}).mesh.surface_get_arrays(0),"local density repeatable")
	check(Fixture.thin_crown_cards(full,1.0,{selected:1.0}).mesh==full.mesh,"neutral local setting preserves full original instance")
	print("FOLIAGE_DENSITY_NORMAL_ROUNDTRIP ",normal_roundtrip_error)
