extends SceneTree
const Recipe=preload("res://scripts/prototypes/ember_painted_bark_relief_recipe.gd")
var errors: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize() -> void:
	var source:=Image.load_from_file(Recipe.MASTER);var before:=source.get_data()
	var mask:=Recipe.mask_for(source);var count:=Recipe.bake_count
	check(Recipe.mask_for(source).get_data()==mask.get_data() and Recipe.bake_count==count,"deterministic cached selection")
	check(source.get_data()==before,"accepted artwork immutable")
	var peak:=0.0;var selected:=0
	for y in 256:
		for x in 256:
			var value:=mask.get_pixel(x,y).r
			peak=maxf(peak,value)
			if value>0.1:selected+=1
	check(peak>0.95 and selected>256 and selected<256*256/4,"sparse nonempty selected grooves, not whole paint surface")
	check(mask.has_mipmaps(),"recess filtering has mips")
	var flat:=Image.create(256,256,false,Image.FORMAT_RGB8);flat.fill(Color("896a4d"))
	var flat_mask:=Recipe.mask_for(flat)
	check(flat_mask.get_pixel(100,100).r==0.0,"uniform colour does not create recesses")
	var ramp:=Image.create(256,256,false,Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:ramp.set_pixel(x,y,Color(float(x)/255.0,float(x)/255.0,float(x)/255.0))
	var ramp_mask:=Recipe.mask_for(ramp)
	var ramp_peak:=0.0
	for y in 256:
		for x in 256:ramp_peak=maxf(ramp_peak,ramp_mask.get_pixel(x,y).r)
	check(ramp_peak==0.0,"broad monotonic painted gradient is not a groove")
	mask.set_pixel(0,0,Color.RED)
	check(Recipe.mask_for(source).get_pixel(0,0).r==0.0,"caller cannot mutate cached mask")
	var changed:=source.duplicate() as Image;changed.set_pixel(127,127,Color.RED)
	Recipe.mask_for(changed);check(Recipe.bake_count==count+3,"art content changes invalidate cache")
	print("PAINTED_BARK_RELIEF ","PASS" if errors.is_empty() else errors," selected=",selected," peak=",peak)
	quit(0 if errors.is_empty() else 1)
