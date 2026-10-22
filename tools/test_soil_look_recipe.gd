extends SceneTree
const Recipe=preload("res://scripts/prototypes/ember_soil_look_recipe.gd")
var errors: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize() -> void:
	var soil=load("res://content/terrain_materials/soil_grain.tres")
	var old_artwork:=soil.to_image() as Image;var old_before:=old_artwork.get_data()
	var artwork:=Recipe.colour_image();var before:=artwork.get_data()
	var relief: PackedByteArray=soil.surface_pixels("relief").duplicate()
	var rough: PackedByteArray=soil.surface_pixels("roughness").duplicate()
	var images:=Recipe.colours(artwork)
	check(images[0]==artwork and artwork.get_data()==before,"ordinary artwork is exact and master immutable")
	check(images[1].get_data()!=before and images[2].get_data()!=before,"two distinct colour derivatives")
	check(images[1].get_data()==Recipe.colours(artwork)[1].get_data(),"calm pigment reproducible")
	check(artwork.get_size()==Vector2i(256,256) and before==Recipe.colour_image().get_data(),"detailed master is high resolution and deterministic")
	check(before!=Recipe.colour_image(256,0).get_data(),"new generated master differs from preserved procedural trial")
	var source_image:=Image.load_from_file(Recipe.MASTER_PATH)
	check(source_image!=null and source_image.get_width()>=1024 and source_image.get_width()==source_image.get_height(),"generated master is present as a full-resolution project asset")
	check(old_artwork.get_data()==old_before,"legacy source artwork preserved")
	var distinct: Dictionary={}
	for x in 256:distinct[artwork.get_pixel(x,103).to_rgba32()]=true
	check(distinct.size()>8,"detailed pigment is not a three-tone 16-cell drawing")
	var varying_cells:=0
	for cell in 16:
		if artwork.get_pixel(cell*16,103)!=artwork.get_pixel(cell*16+15,103):varying_cells+=1
	check(varying_cells>8,"colour varies within former 16-cell boundaries")
	for i in 20:
		var p:=Vector2(i/20.0,0.37)
		check(Recipe.sample(p).is_equal_approx(Recipe.sample(p+Vector2.ONE)),"previous procedural control remains periodic")
	var atlas:=Image.create(16,16*6,false,Image.FORMAT_RGBA8)
	for y in atlas.get_height():
		for x in 16:atlas.set_pixel(x,y,Color(x/15.0,y/95.0,0.2,float((x+y)%3)/2.0))
	var atlas_before:=atlas.get_data()
	var legacy:=Recipe.colours(old_artwork)
	for look in [1,2]:
		var derived:=Recipe.colour_row(atlas,legacy[look],4)
		check(atlas.get_data()==atlas_before,"source atlas immutable")
		for y in atlas.get_height():
			for x in 16:
				var old:=atlas.get_pixel(x,y);var value:=derived.get_pixel(x,y)
				check(value.a==old.a,"every optical-height byte retained")
				if y<64 or y>=80:check(value==old,"other material rows retained")
	for y in 256:
		for x in 256:check(images[2].get_pixel(x,y)==images[2].get_pixel((x/32)*32,(y/32)*32),"only voxel derivative uses 8 square cells")
	check(soil.surface_pixels("relief")==relief and soil.surface_pixels("roughness")==rough,"authored relief and roughness retained")
	print("SOIL_LOOK_RECIPE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
