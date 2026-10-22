extends SceneTree
const Road=preload("res://scripts/prototypes/ember_sand_road_recipe.gd")
const Soil=preload("res://scripts/prototypes/ember_soil_look_recipe.gd")
var errors: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize() -> void:
	var legacy:=Road.colour_image();var old:=legacy.get_data()
	var soil:=Soil.colour_image();var before:=soil.get_data()
	var master:=Road.painted_image();var images:=Road.painted_variants(master)
	check(master.get_data()==before,"same accepted source artwork; no new image generation")
	check(images[0]==master and master.get_data()==before,"ordinary master retained")
	check(images[1].get_data()!=before and images[2].get_data()!=before,"distinct derivatives")
	check(images[1].get_data()==Road.painted_variants(master)[1].get_data(),"deterministic calm variant")
	check(soil.get_data()==before and Road.colour_image().get_data()==old,"soil and original road remain reproducible")
	check(Road.PAINTED_BASE_COLOR.get_luminance()<Color("d7c08c").get_luminance(),"road tint quieter than existing sand")
	check(is_equal_approx(Road.SPAN_M/16.0,0.09375),"retained world-space colour grid")
	for y in master.get_height():
		for x in master.get_width():
			check(images[2].get_pixel(x,y)==images[2].get_pixel((x/16)*16,(y/16)*16),"only voxel derivative has square cells")
	check(master.has_mipmaps() and images[1].has_mipmaps() and images[2].has_mipmaps(),"all looks filtered at distance")
	print("SAND_ROAD_PAINTED ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
