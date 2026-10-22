extends SceneTree
const Bake=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const Art=preload("res://scripts/ember_material_look_bake.gd")
const Fixture=preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
var errors: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize() -> void:
	var heights:=PackedFloat32Array();heights.resize(33*33)
	for z in 33:
		for x in 33:heights[x+z*33]=10.0+sin(x*0.14)*8.0+cos(z*0.19)*4.0
	var field:={"start":Vector2i.ZERO,"size":Vector2i(33,33),"heights":heights}
	var before:=hash(field)
	for x in range(0,25,8):
		for z in range(0,25,8):check(is_equal_approx(Bake.plane(field,Vector2(x,z)).height,heights[x+z*33]),"coarse anchors retained")
	for z in range(1,24):
		var left: float=Bake.plane(field,Vector2(8.0-0.00001,z)).height
		var right: float=Bake.plane(field,Vector2(8.0+0.00001,z)).height
		check(absf(left-right)<0.0001,"continuous cell boundary")
	for i in range(1,8):
		var a: float=Bake.plane(field,Vector2(i,8-i-0.00001)).height
		var b: float=Bake.plane(field,Vector2(i,8-i+0.00001)).height
		check(absf(a-b)<0.0001,"continuous diagonal")
	check(hash(field)==before,"field untouched")
	var source:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:source.set_pixel(x,y,Color(float(x)/64.0,float(y)/64.0,0.2,1.0))
	var pixels:=source.get_data();var result:=Bake.pixel_image(source,8)
	check(result.get_data()==Bake.pixel_image(source,8).get_data() and result.has_mipmaps(),"deterministic filtered derivative")
	for y in 64:
		for x in 64:check(result.get_pixel(x,y)==result.get_pixel((x/8)*8,(y/8)*8),"constant rectangular cells")
	check(source.get_data()==pixels,"art source untouched")
	var original:=Fixture.grass_tuft_mesh()
	var coarse:=Art.grass_mesh(original,2,Fixture.grass_tuft_outline(),{"pixel_m":0.0625,"coverage":true})
	check(coarse.get_surface_count()==1 and coarse.get_aabb().size.y>0.1,"coarse blades survive")
	check(coarse.get_faces().size()<Art.grass_mesh(original,2,Fixture.grass_tuft_outline()).get_faces().size(),"larger cells have fewer strips")
	print("TERRAIN_LOOK_BAKE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
