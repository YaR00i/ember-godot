extends SceneTree
const Recipe=preload("res://scripts/prototypes/ember_natural_rock_recipe.gd")
const Terrain=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
var errors: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize() -> void:
	var source:=Recipe.painted_image();var before:=source.get_data()
	var height:=Recipe.painted_structure(source);var count:=Recipe.structure_bake_count
	var repeated:=Recipe.painted_structure(source)
	check(height.get_data()==repeated.get_data() and Recipe.structure_bake_count==count,"deterministic cached structure")
	check(source.get_data()==before,"paint master unchanged")
	var lo:=1.0;var hi:=0.0
	for y in height.get_height():
		for x in height.get_width():
			var h:=height.get_pixel(x,y).r;lo=minf(lo,h);hi=maxf(hi,h)
	check(lo>=0.245 and hi<=0.755 and hi-lo>0.3,"bounded nonflat height guide")
	check((hi-lo)*Recipe.PAINT_RELIEF_RANGE_M<=0.0031,"actual relief no more than3.1mm")
	var uniform:=Image.create(256,256,false,Image.FORMAT_RGBA8);uniform.fill(Color("aaaaaa"))
	var flat:=Recipe.painted_structure(uniform)
	check(absf(flat.get_pixel(80,80).r-0.5)<0.005,"uniform pigment gives neutral height")
	var changed:=source.duplicate() as Image;changed.set_pixel(127,127,Color.RED)
	Recipe.painted_structure(changed)
	check(Recipe.structure_bake_count==count+2,"content change invalidates cached guide")
	var voxel:=Terrain.pixel_image(height,16)
	for y in 256:
		for x in 256:check(voxel.get_pixel(x,y)==voxel.get_pixel((x/16)*16,(y/16)*16),"same16-cell grid as voxel pigment")
	check(height.has_mipmaps() and voxel.has_mipmaps(),"filtered height derivatives")
	print("ROCK_PAINT_RELIEF ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
