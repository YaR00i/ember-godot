extends SceneTree
const Bake=preload("res://scripts/ember_material_look_bake.gd")
const Fixture=preload("res://scripts/prototypes/ember_painted_light_fixture.gd")
var errors: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var source:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	var height:=Image.create(64,64,false,Image.FORMAT_R8)
	for y in 64:
		for x in 64:
			source.set_pixel(x,y,Color(0.3+0.3*x/64.0,0.4+0.1*y/64.0,0.2,0.0 if x<4 else 1.0))
			height.set_pixel(x,y,Color(0.0 if x in [31,32] else 1.0,0,0))
	var before:=source.get_data();var before_height:=height.get_data()
	var recipe:={"resolution":64,"cell":16,"min_cell":4,"tolerance":0.06,"periodic":true}
	check(Bake.image_variant(source,0,recipe,height).image.get_data()==before,"zero identity")
	for look in [1,2]:
		var a:=Bake.image_variant(source,look,recipe,height);var b:=Bake.image_variant(source,look,recipe,height)
		check(a.image.get_data()==b.image.get_data(),"deterministic recipe")
		check(a.image.has_mipmaps() and a.regions>0,"filtered derived artwork")
		check(a.image.get_pixel(31,30)==source.get_pixel(31,30),"deep groove colour protected")
		check(a.image.get_pixel(0,20)==source.get_pixel(0,20) and a.image.get_pixel(63,20)==source.get_pixel(63,20),"periodic edges retained")
		for y in 64:
			for x in 64:check(a.image.get_pixel(x,y).a==source.get_pixel(x,y).a,"alpha untouched by colour recipe")
	check(source.get_data()==before and height.get_data()==before_height,"source and physical relief input unchanged")
	var calm:=Bake.calm_variant(source,8,0.3)
	check(calm.get_size()==source.get_size() and calm.has_mipmaps(),"calm artwork keeps resolution and filtering")
	check(calm.get_data()==Bake.calm_variant(source,8,0.3).get_data(),"calm artwork deterministic")
	check(absf(calm.get_pixel(58,30).r-calm.get_pixel(8,30).r)<absf(source.get_pixel(58,30).r-source.get_pixel(8,30).r)*0.5,"calm artwork reduces colour variation")
	check(source.get_data()==before and height.get_data()==before_height,"calm artwork keeps authoring inputs untouched")
	var grass:=Fixture.grass_tuft_mesh()
	check(Bake.grass_mesh(grass,0,Fixture.grass_tuft_outline())==grass,"grass zero identity")
	for look in [1,2]:
		var a:=Bake.grass_mesh(grass,look,Fixture.grass_tuft_outline());var b:=Bake.grass_mesh(grass,look,Fixture.grass_tuft_outline())
		check(a.surface_get_arrays(0)==b.surface_get_arrays(0),"grass deterministic")
		check(a.get_aabb().size.y<=0.141 and a.get_aabb().size.x<=0.26,"grass scale retained")
		for vertex: Vector3 in a.get_faces():check(vertex.is_finite(),"finite grass")
	print("MATERIAL_SHAPE_RECIPES ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
