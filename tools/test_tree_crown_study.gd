extends SceneTree
const Fixture = preload("res://scripts/prototypes/ember_tree_branching_fixture.gd")
const Provider = preload("res://addons/ember_import/ember_voxel_large_tree_generator.gd")
const Generator = preload("res://addons/ember_import/ember_voxel_generator.gd")
const Recipe = preload("res://addons/ember_import/ember_voxel_generator_recipe.gd")
const Materials = preload("res://scripts/prototypes/ember_painted_bark_projection.gd")
var errors: Array[String] = []
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var previous := Fixture.build(7,18)
	check(previous.source.voxels.hex_encode().sha256_text()=="2a003243b29d7c75c18523018b81ac834ebebfc502ea346639941d0268bc111d","saved18 Source unchanged")
	var inputs := Fixture.build(7,19)
	var again := Fixture.build(7,19)
	check(inputs.source.validation_errors().is_empty() and Provider.structure_errors(inputs.structure).is_empty(),"canonical Source19 and hierarchy")
	check(inputs.layout.size()==56 and inputs.structure.lines.size()<=128,"bounded natural scaffold")
	check(Provider.LATEST_VERSIONS[1]==17 and Provider.normalize({"generation_version":22,"tree_type":1}).generation_version==17,"presets unchanged")
	check(inputs.source.voxels==again.source.voxels and inputs.cards.mesh.surface_get_arrays(0)==again.cards.mesh.surface_get_arrays(0),"deterministic Source/cards/UV/normals")
	var arrays: Array = inputs.cards.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var macro: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	var tiles := {}; var directions := Vector3.ZERO
	for root: Dictionary in inputs.cards.roots:
		check(vertices[root.vertex].distance_to(root.point)<0.0001,"curved-card stem vertex stays on real shoot")
		var offset := Vector3(inputs.pivot_bias.x,0,inputs.pivot_bias.y)
		check(root.point.distance_to((Fixture.point_at(inputs.layout[root.branch],root.t)+offset)/16.0)<0.0001,"same Source support owns leaf anchor")
		var local: Vector2 = uv[root.vertex]*2.0-Vector2(root.tile%2,root.tile/2)
		check(local.distance_to(Vector2(0.5,0.94))<0.0001,"atlas variant keeps stem UV")
		tiles[root.tile]=true
	for i in vertices.size():
		var normal := Vector3(macro[i*4],macro[i*4+1],macro[i*4+2])
		check(normal.is_finite() and absf(normal.length()-1.0)<0.003,"finite unit canopy lighting normals")
		directions += normal
	check(tiles.size()==4 and inputs.cards.groups==6,"four variants across five unequal masses and a central leader bridge")
	check(inputs.cards.cards<1800 and inputs.cards.triangles==inputs.cards.cards*12,"bounded curved card batch")
	var recipe := Recipe.new(); recipe.generator_id=Generator.LARGE_TREE; recipe.seed=7
	recipe.parameters=inputs.parameters; recipe.structure=inputs.structure
	check(ResourceSaver.save(recipe,"user://crown-recipe.tres")==OK and ResourceSaver.save(inputs.source,"user://crown-source.tres")==OK,"private save")
	var reopened: Resource = ResourceLoader.load("user://crown-recipe.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	var rebuilt := Generator.build(reopened,Color.WHITE,{},"Reopened","crown_lab")
	check(not rebuilt.has("error") and rebuilt.geometry.voxels==inputs.source.voxels and rebuilt.geometry.collision_voxels==inputs.source.collision_voxels,"existing recipe router/reopen/rebuild exact")
	var image := Image.load_from_file("res://content/material_studies/trees/leaf_cluster_atlas_v2.png")
	check(image.get_format()==Image.FORMAT_RGBA8,"true RGBA atlas")
	var profile: Resource = load("res://content/terrain_materials/painted_light_grass.tres")
	var material := Materials.leaf_cards_material(inputs.cards.mesh,profile,true,"res://content/material_studies/trees/leaf_cluster_atlas_v2.png")
	for key in ["low","cool","warm","tint_strength","shadow_color","shadow_fill"]:
		check(material.get_shader_parameter("painterly_grass_"+key)==profile.get("grass_light_"+key),"accepted shared light "+key)
	print("TREE_CROWN_TEST ","PASS" if errors.is_empty() else errors," supports=",inputs.structure.lines.size()," cards=",inputs.cards.cards," triangles=",inputs.cards.triangles)
	quit(0 if errors.is_empty() else 1)
