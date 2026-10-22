extends SceneTree
const Bake=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const Recipe=preload("res://scripts/prototypes/ember_natural_rock_recipe.gd")
var errors: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize() -> void:
	var heights:=PackedFloat32Array();heights.resize(33*33)
	for z in 33:
		for x in 33:
			var p:=Vector2(x,z)
			heights[x+z*33]=8+maxf(0,13-p.distance_to(Vector2(9,12))*2)+maxf(0,8-p.distance_to(Vector2(24,23))*2.4)
	var field:={"start":Vector2i.ZERO,"size":Vector2i(33,33),"heights":heights}
	var before:=hash(field)
	var baked:=Bake.adaptive_heights(field,Rect2i(0,0,32,32))
	check(baked.max_error_m<=0.0375 and hash(field)==before,"bounded adaptive approximation without source writes")
	for z in 33:
		for x in 33:
			var i:=x+z*33
			check(absf(baked.heights[i]-heights[i])<=0.601,"every fine vertex within budget")
			if x==0 or z==0 or x==32 or z==32:check(is_equal_approx(baked.heights[i],heights[i]),"tile boundary retained")
	for n: Vector3 in baked.normals:check(n.is_finite() and n.y>0 and is_equal_approx(n.length(),1.0),"complete finite plane normals")
	check(baked.heights==Bake.adaptive_heights(field,Rect2i(0,0,32,32)).heights,"deterministic topology sampling")
	var maps:=Recipe.maps(128);var again:=Recipe.maps(128)
	check(maps.colour.get_data()==again.colour.get_data() and maps.height.get_data()==again.height.get_data(),"deterministic paired art")
	var previous:=Recipe.maps(128,0)
	check(maps.height.get_data()==previous.height.get_data(),"paint refinement preserves every optical height byte and mip")
	check(maps.colour.get_data()!=previous.colour.get_data(),"new pigment is distinct from the retained control")
	for p in [Vector2(0.03,0.17),Vector2(0.4,0.9),Vector2(0.99,0.01)]:
		var c: Color=Recipe.painted_pigment(p)
		for step in [Vector2.RIGHT,Vector2.DOWN]:
			var other: Color=Recipe.painted_pigment(p+step)
			check(Vector3(c.r,c.g,c.b).distance_to(Vector3(other.r,other.g,other.b))<0.00001,"pigment repeats continuously in world span")
	var low:=1.0;var high:=0.0;var deep:=0
	for y in 128:
		for x in 128:
			var h: float=maps.height.get_pixel(x,y).r;low=minf(low,h);high=maxf(high,h)
			if h<0.4:deep+=1
	check(low<0.3 and high>0.75 and deep>0 and deep<128*128/8,"sparse deep fractures in continuous stone")
	check(maps.height.has_mipmaps() and maps.colour.has_mipmaps(),"distance filtering present")
	print("NATURAL_ROCK_TEST ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
