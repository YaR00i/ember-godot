@tool
extends SceneTree
const Height=preload("res://scripts/ember_material_height.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("HEIGHT_CACHE_FAIL ",label)
func _initialize():
	check(not Height.cache_directory.is_empty(),"cache defaults initialized in runtime/editor")
	Height.cache_directory="user://ember-tests/height-cache-%d"%Time.get_ticks_usec()
	var input:=Image.create(64,48,false,Image.FORMAT_RGBA8)
	for y in input.get_height():
		for x in input.get_width():input.set_pixel(x,y,Color(float((x*17+y*31)%256)/255.0,float((x*7+y*3)%256)/255.0,0.2))
	var original:=input.get_data()
	var expected:=Height.bake(input)
	var first:=Height.cached_bake(input)
	check(first.get_data()==expected.get_data(),"cold byte parity")
	first.fill(Color.WHITE);first.generate_mipmaps()
	check(Height.cached_bake(input).get_data()==expected.get_data(),"caller cannot mutate shared cache")
	Height.clear_cache();var hits:=Height.disk_hits;var bakes:=Height.bakes
	var reopened:=Height.cached_bake(input)
	check(Height.disk_hits==hits+1 and Height.bakes==bakes,"disk hit without computation")
	check(reopened.get_data()==expected.get_data(),"disk byte parity including mip layout")
	Height.cached_bake(input,3.75,0.1)
	check(Height.bakes==bakes+1,"changed softness invalidates")
	Height.cached_bake(input,2.5,0.7)
	check(Height.bakes==bakes+2,"changed sharpness invalidates")
	input.set_pixel(5,8,Color.WHITE);Height.cached_bake(input)
	check(Height.bakes==bakes+3,"changed pixels invalidate without new Image identity")
	input.set_data(64,48,false,Image.FORMAT_RGBA8,original)
	Height.clear_cache()
	# Existing transport rejects corrupt data and rebuilds only the disposable result.
	for name in DirAccess.get_files_at(Height.cache_directory):
		var file:=FileAccess.open(Height.cache_directory.path_join(name),FileAccess.WRITE);file.store_string("corrupt");file.close()
	check(Height.cached_bake(input).get_data()==expected.get_data(),"corrupt cache falls back exactly")
	check(input.get_data()==original,"immutable albedo")
	for name in DirAccess.get_files_at(Height.cache_directory):DirAccess.remove_absolute(Height.cache_directory.path_join(name))
	DirAccess.remove_absolute(Height.cache_directory)
	print("MATERIAL_HEIGHT_CACHE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
