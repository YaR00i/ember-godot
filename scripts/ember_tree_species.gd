extends RefCounted
## LAB presentation derives from the existing provider/branch layout. The five
## old silhouettes retain every crown support, rather than oak's cap selection.
const Provider=preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const Rounded=preload("res://scripts/ember_tree_rounded_geometry.gd")
const Branching=preload("res://scripts/ember_tree_surface_geometry.gd")
const NAMES: Array[String]=["РЎР°РІР°РЅРЅР°14","Р”СѓР±17","Р‘РµСЂС‘Р·Р°13","РљР»С‘РЅ12","Р•Р»СЊ15"]
const BIRCH_ART:="res://content/material_studies/trees/birch_v1/leaf-atlas-v1.png"
const BIRCH_BARK:="res://content/material_studies/trees/bark_species_v1/birch-v1.png"
const MAPLE_ART:="res://content/material_studies/trees/maple_v1/leaf-atlas-v2-rooted.png"
const MAPLE_BARK:="res://content/material_studies/trees/bark_species_v1/maple-v1.png"
const SAVANNA_ART:="res://content/material_studies/trees/savanna_v1/leaf-atlas-v2-calm.png"
const SAVANNA_PATCH_ART:="res://content/material_studies/trees/savanna_v1/leaf-atlas-v3-small-patches.png"
const SAVANNA_BARK:="res://content/material_studies/trees/bark_species_v1/savanna-v1.png"
const SPRUCE_ART:="res://content/material_studies/trees/spruce_v1/needle-atlas-v1.png"
const SPRUCE_BARK:="res://content/material_studies/trees/bark_species_v1/spruce-v1.png"
const SPRUCE_CARD_SIZE:=1.10
const TITLES: Array[String]=["Саванна","Дуб","Берёза","Клён","Ель"]
const LEAF_ART: Array[String]=[SAVANNA_PATCH_ART,"res://content/material_studies/trees/leaf_cluster_atlas_v8_separate_leaves.png",BIRCH_ART,MAPLE_ART,SPRUCE_ART]
const BARK_ART: Array[String]=[SAVANNA_BARK,"res://content/material_studies/trees/bark_species_v1/oak-v3-painted.png",BIRCH_BARK,MAPLE_BARK,SPRUCE_BARK]
const CARD_SIZE: Array[float]=[1.05,0.96,0.64,0.82,1.10]

static func accepted_parameters(kind: int) -> Dictionary:
	var p: Dictionary
	match kind:
		0:
			p=savanna_parameters();p.merge({"crown_shape":1,"main_branch_count":5,"branch_splits":3,"branch_levels":3,"branch_count_variation":30,"branch_start":36,"trunk_width":10,"branch_thickness":82,"branch_curve":70},true)
		1:
			p=Provider.defaults();p.merge({"tree_type":1,"generation_version":21,"height":96,"foliage_style":3,"foliage_amount":0,"main_branch_count":8,"branch_splits":3,"branch_levels":4,"branch_count_variation":40},true)
		2:p=birch_parameters()
		3:p=maple_parameters();p.crown_shape=1
		_:p=spruce_parameters();p.merge({"crown_shape":1,"main_branch_count":12,"branch_splits":3,"branch_levels":3,"branch_start":24},true)
	p["painted_tree"]=true;p["tree_leaf_density"]=45 if kind==1 else 60
	p["tree_leaf_depth"]=100;p["tree_leaf_receive"]=40;p["tree_rim_enabled"]=true
	p["tree_wood_rim"]=45;p["tree_leaf_rim"]=18;p["tree_leaf_local"]={};p["tree_leaf_revision"]=""
	return Provider.normalize(p)

static func card_options(kind: int) -> Dictionary:
	var options:={"branch_growth":true,"size":CARD_SIZE[kind]}
	if kind==0:options["canopy_envelope"]=true
	if kind==4:options.merge({"needle_sprays":true,"needle_boughs":true})
	return options
static func parameters(kind: int) -> Dictionary:
	var result:=Provider.defaults()
	result.merge(Provider.SPECIES_DEFAULTS[kind],true)
	result.height=96;result.foliage_style=3
	return Provider.normalize(result)
static func birch_parameters() -> Dictionary:
	var result:=parameters(2)
	result.merge({"generation_version":22,"main_branch_count":9,"branch_splits":3,
		"branch_levels":3,"branch_count_variation":35,"branch_start":31,
		"foliage_amount":0,"bark_pattern":false},true)
	return Provider.normalize(result)
static func legacy(kind: int,seed:=7) -> Dictionary:
	var p:=parameters(kind)
	var built:=Provider.build(p,seed,Color.WHITE,{},NAMES[kind],"species_%d"%kind)
	assert(not built.has("error"))
	var offset:=Vector3(built.pivot_bias.x,0,built.pivot_bias.y)
	var smooth:=Rounded.new()
	for line: Dictionary in built.structure.lines:
		smooth.wood_lines.append({"a":(line.start+offset)/16.0,"b":(line.finish+offset)/16.0,"r0":float(line.r0)/16.0,"r1":float(line.r1)/16.0})
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for group: Dictionary in built.structure.groups:
		# Exact provider supports/radii; no new species silhouette plan here.
		smooth.add_dome(st,(group.center+offset)/16.0,group.radii/16.0,0.0,p.foliage_color)
	return {"source":built.geometry,"structure":built.structure,"parameters":p,
		"pivot_bias":built.pivot_bias,"wood":smooth.smooth_wood(),"leaves":st.commit(),
		"presentation":"rounded provider crown supports, not a source mesh replacement"}
static func birch(seed:=7,overrides: Dictionary={}) -> Dictionary:
	var p:=birch_parameters();p.merge(overrides,true);p=Provider.normalize(p)
	var built:=Provider.build(p,seed,Color.WHITE,{},"Birch22 LAB","birch22_lab")
	assert(not built.has("error"))
	var result:=Branching.from_built(built,p,seed)
	var offset:=Vector3(result.pivot_bias.x,0,result.pivot_bias.y)
	result["full_leaves"]=Branching.crown_cards(result.layout,result.structure,offset,16.0,seed,{"branch_growth":true,"size":0.64})
	result["leaves"]=Branching.thin_crown_cards(result.full_leaves,0.60)
	return result

static func maple_parameters() -> Dictionary:
	var result:=parameters(3)
	result.merge({"generation_version":23,"main_branch_count":6,"branch_splits":3,
		"branch_levels":4,"branch_count_variation":30,"branch_start":30,
		"trunk_width":9,"crown_spread":68,"branch_thickness":65,"branch_curve":60,
		"root_flare":65,"foliage_amount":0,"bark_pattern":false},true)
	return Provider.normalize(result)
static func maple(seed:=7,overrides: Dictionary={}) -> Dictionary:
	var p:=maple_parameters();p.merge(overrides,true);p=Provider.normalize(p)
	var built:=Provider.build(p,seed,Color.WHITE,{},"Maple23 LAB","maple23_lab")
	assert(not built.has("error"))
	var result:=Branching.from_built(built,p,seed)
	var offset:=Vector3(result.pivot_bias.x,0,result.pivot_bias.y)
	result["full_leaves"]=Branching.crown_cards(result.layout,result.structure,offset,16.0,seed,{"branch_growth":true,"size":0.82})
	result["leaves"]=Branching.thin_crown_cards(result.full_leaves,0.60)
	return result

static func savanna_parameters() -> Dictionary:
	var result:=parameters(0)
	result.merge({"generation_version":24,"main_branch_count":7,"branch_splits":3,
		"branch_levels":4,"branch_count_variation":30,"branch_start":38,
		"trunk_width":8,"crown_spread":80,"branch_thickness":70,"branch_curve":65,
		"root_flare":35,"foliage_amount":0,"bark_pattern":false},true)
	return Provider.normalize(result)
static func savanna(seed:=7,overrides: Dictionary={}) -> Dictionary:
	var p:=savanna_parameters();p.merge(overrides,true);p=Provider.normalize(p)
	var built:=Provider.build(p,seed,Color.WHITE,{},"Savanna24 LAB","savanna24_lab")
	assert(not built.has("error"))
	var result:=Branching.from_built(built,p,seed)
	var offset:=Vector3(result.pivot_bias.x,0,result.pivot_bias.y)
	result["full_leaves"]=Branching.crown_cards(result.layout,result.structure,offset,16.0,seed,{"branch_growth":true,"size":0.88})
	result["leaves"]=Branching.thin_crown_cards(result.full_leaves,0.60)
	return result

static func savanna_umbrella(seed:=7,overrides: Dictionary={}) -> Dictionary:
	var settings: Dictionary={"crown_shape":1,"main_branch_count":5,"branch_splits":3,
		"branch_levels":3,"branch_count_variation":30,"branch_start":36,
		"trunk_width":10,"branch_thickness":82,"branch_curve":70}
	settings.merge(overrides,true)
	return savanna(seed,settings)

static func savanna_umbrella_foliage(seed:=7,overrides: Dictionary={}) -> Dictionary:
	var result:=savanna_umbrella(seed,overrides)
	var offset:=Vector3(result.pivot_bias.x,0,result.pivot_bias.y)
	result.full_leaves=Branching.crown_cards(result.layout,result.structure,offset,16.0,seed,{"branch_growth":true,"size":1.05,"canopy_envelope":true})
	result.leaves=Branching.thin_crown_cards(result.full_leaves,0.60)
	return result

static func spruce_parameters() -> Dictionary:
	var result:=parameters(4)
	result.merge({"generation_version":25,"main_branch_count":7,"branch_splits":2,
		"branch_levels":3,"branch_count_variation":55,"branch_start":25,
		"foliage_amount":0,"bark_pattern":false},true)
	return Provider.normalize(result)
static func spruce(seed:=7,overrides: Dictionary={}) -> Dictionary:
	var p:=spruce_parameters();p.merge(overrides,true);p=Provider.normalize(p)
	var built:=Provider.build(p,seed,Color.WHITE,{},"Spruce25 LAB","spruce25_lab")
	assert(not built.has("error"))
	var result:=Branching.from_built(built,p,seed)
	var offset:=Vector3(result.pivot_bias.x,0,result.pivot_bias.y)
	# Hidden controller input only during the silhouette gate, not needle art.
	result.full_leaves=Branching.crown_cards(result.layout,result.structure,offset,16.0,seed,{"branch_growth":true,"size":0.50})
	result.leaves=Branching.thin_crown_cards(result.full_leaves,0.60)
	return result

static func spruce_needles(seed:=7,overrides: Dictionary={}) -> Dictionary:
	var result:=spruce(seed,overrides)
	var offset:=Vector3(result.pivot_bias.x,0,result.pivot_bias.y)
	result.full_leaves=Branching.crown_cards(result.layout,result.structure,offset,16.0,seed,{"branch_growth":true,"size":SPRUCE_CARD_SIZE,"needle_sprays":true})
	result.leaves=Branching.thin_crown_cards(result.full_leaves,0.60)
	return result

static func spruce_boughs(seed:=7,overrides: Dictionary={}) -> Dictionary:
	var settings: Dictionary={"crown_shape":1,"main_branch_count":12,"branch_splits":3,"branch_levels":3,"branch_start":24}
	settings.merge(overrides,true)
	var result:=spruce(seed,settings)
	var offset:=Vector3(result.pivot_bias.x,0,result.pivot_bias.y)
	result.full_leaves=Branching.crown_cards(result.layout,result.structure,offset,16.0,seed,{"branch_growth":true,"size":SPRUCE_CARD_SIZE,"needle_sprays":true,"needle_boughs":true})
	result.leaves=Branching.thin_crown_cards(result.full_leaves,0.60)
	return result

static func spruce_limb(inputs: Dictionary,owner: int) -> Dictionary:
	var selected: Array=[]
	for branch: Dictionary in inputs.layout:
		var parent:=int(branch.id)
		while parent>0 and parent!=owner:parent=int(inputs.layout[parent].parent)
		if parent==owner:selected.append(branch)
	var coverage: Dictionary={}
	for id: int in Branching.crown_leaf_groups(inputs.full_leaves):coverage[id]=1.0 if id==owner else 0.0
	var offset:=Vector3(inputs.pivot_bias.x,0,inputs.pivot_bias.y)
	return {"layout":selected,"wood":Branching.wood_mesh(selected,offset,float(inputs.parameters.density)),
		"leaves":Branching.thin_crown_cards(inputs.leaves,1.0,coverage) if inputs.leaves.cards>0 else inputs.leaves,"owner":owner}

## Diagnostic volumes consume provider groups; they are not final foliage.
static func crown_blockout(inputs: Dictionary,flatten:=0.28) -> ArrayMesh:
	# Reuse the existing implicit-volume union/extractor, then undo the common
	# vertical stretch. Overlapping supports form one surface, not stacked domes.
	var smooth:=Rounded.new();smooth.bark_tone=Color("4f8f50")
	var offset:=Vector3(inputs.pivot_bias.x,0,inputs.pivot_bias.y)
	if flatten<=0.0:
		for group: Dictionary in inputs.structure.groups:
			var centre: Vector3=(group.center+offset)/float(inputs.parameters.density)
			var radii: Vector3=group.radii/float(inputs.parameters.density)
			smooth.wood_lines.append({"a":centre,"b":centre,"r0":radii.x,"r1":radii.x,"ellipsoid_radii":radii})
		return smooth.smooth_wood(0.08,0.045)
	for group: Dictionary in inputs.structure.groups:
		var centre: Vector3=(group.center+offset)/16.0
		centre.y/=flatten
		var radius_m:=float(group.radii.x)/16.0
		smooth.wood_lines.append({"a":centre,"b":centre,"r0":radius_m,"r1":radius_m})
	var sphere_union:=smooth.smooth_wood(0.16,0.16)
	var arrays:=sphere_union.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		vertices[i].y*=flatten;normals[i].y/=flatten;normals[i]=normals[i].normalized()
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
