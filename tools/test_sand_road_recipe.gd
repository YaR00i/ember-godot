extends SceneTree
const Recipe=preload("res://scripts/prototypes/ember_sand_road_recipe.gd")
var errors: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize() -> void:
	var image:=Recipe.colour_image();var before:=image.get_data()
	check(before==Recipe.colour_image().get_data(),"reproducible master")
	for p in [Vector2(0.011,0.063),Vector2(0.31,0.42),Vector2(0.973,0.953)]:
		var c:=Recipe.sample(p);var plain:=Recipe.sample(p,0.0)
		check(absf(c.r-plain.r)<=0.0061,"grain remains quiet")
		for step in [Vector2.RIGHT,Vector2.DOWN]:
			var other:=Recipe.sample(p+step)
			check(Vector3(c.r,c.g,c.b).distance_to(Vector3(other.r,other.g,other.b))<0.00001,"seamless periodic pigment and grain")
	var variants:=Recipe.variants(image)
	check(before==image.get_data() and variants[0]==image,"derived looks preserve master")
	check(variants[1].get_data()!=before and variants[2].get_data()!=before,"two distinct derived presentations")
	for look in 3:
		check(variants[look].get_size()==image.get_size() and variants[look].has_mipmaps(),"resolution and filtering retained")
		for y in 256:
			for x in 256:check(variants[look].get_pixel(x,y).a==1.0,"opaque surface retained")
	for y in 16:
		for x in 16:
			var c:=variants[2].get_pixel(x*16,y*16)
			check(c==variants[2].get_pixel(x*16+15,y*16+15),"voxel pigment has exact square cells")
	print("SAND_ROAD_RECIPE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
