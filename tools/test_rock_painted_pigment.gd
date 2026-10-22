extends SceneTree
const Recipe=preload("res://scripts/prototypes/ember_natural_rock_recipe.gd")
const Bake=preload("res://scripts/ember_material_look_bake.gd")
const Terrain=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
var errors: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize() -> void:
	var source:=Image.load_from_file(Recipe.PAINTED_MASTER_PATH);var source_bytes:=source.get_data()
	var a:=Recipe.maps();var a_bytes: PackedByteArray=a.colour.get_data()
	var b:=Recipe.maps(256,2);var repeated:=Recipe.maps(256,2)
	check(a.height.get_data()==b.height.get_data(),"full accepted height and all mips retained")
	check(b.colour.get_data()!=a_bytes and b.colour.get_data()==repeated.colour.get_data(),"distinct deterministic pigment")
	check(Recipe.maps().colour.get_data()==a_bytes,"previous accepted recipe still default")
	check(source.get_data()==source_bytes and Image.load_from_file(Recipe.PAINTED_MASTER_PATH).get_data()==source_bytes,"generated source immutable")
	var before: PackedByteArray=b.colour.get_data();var calm:=Bake.calm_variant(b.colour,256,0.65);var voxel:=Terrain.pixel_image(b.colour,16)
	check(b.colour.get_data()==before and calm.get_size()==b.colour.get_size(),"derived looks preserve master and full calm resolution")
	for y in 256:
		for x in 256:check(voxel.get_pixel(x,y)==voxel.get_pixel((x/16)*16,(y/16)*16),"voxel colour uses retained 15cm grid")
	check(Terrain.pixel_image(a.height,16).get_data()==Terrain.pixel_image(b.height,16).get_data(),"voxel height unchanged on same grid")
	check(b.colour.has_mipmaps() and calm.has_mipmaps() and voxel.has_mipmaps(),"filtered distance variants")
	print("ROCK_PAINTED_PIGMENT ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
