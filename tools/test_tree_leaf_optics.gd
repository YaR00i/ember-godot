extends SceneTree
const Materials=preload("res://scripts/prototypes/ember_painted_bark_projection.gd")
const Study=preload("res://scripts/prototypes/ember_tree_foliage21_study.gd")
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);push_error(message)
func run() -> void:
	var fixture:=Image.create(16,16,false,Image.FORMAT_RGBA8)
	fixture.fill(Color(0,0,0,0))
	for y in range(4,12):
		for x in range(4,12):fixture.set_pixel(x,y,Color(0.25,0.65,0.2,1))
	var path:="user://leaf-optics-edge-fixture.png"
	check(fixture.save_png(path)==OK,"private texture fixture")
	var original:=Materials.artwork(path)
	var fixed:=Materials.artwork(path,true)
	check(original!=fixed and Materials.artwork(path)==original and Materials.artwork(path,true)==fixed,"cache separates preparation and reuses each texture")
	check(original.get_image().get_pixel(3,6).g==0 and fixed.get_image().get_pixel(3,6).g>0.4,"colour padding replaces black transparent edge")
	var old_bytes:=original.get_image().get_data()
	var safe_bytes:=fixed.get_image().get_data()
	var all_alpha_same:=true
	for i in range(3,old_bytes.size(),4):
		if old_bytes[i]!=safe_bytes[i]:all_alpha_same=false;break
	check(all_alpha_same,"alpha-weighted colour mip preparation preserves every alpha level")
	var last:=fixed.get_image().get_mipmap_offset(fixed.get_image().get_mipmap_count())
	check(safe_bytes[last+1]>old_bytes[last+1]*2,"small colour mips avoid transparent-black darkening")
	for art in [Study.MINIMAL_ATLAS,Study.AIR_GAPS_ATLAS,Study.SEPARATE_LEAVES_ATLAS]:
		var raw:=Image.load_from_file(ProjectSettings.globalize_path(art))
		var raw_bytes:=raw.get_data()
		var before:=Materials.artwork(art).get_image().get_data()
		var after:=Materials.artwork(art,true).get_image().get_data()
		check(before.slice(0,raw_bytes.size())==raw_bytes,"default loading preserves exact original RGBA "+art)
		var alpha_same:=true
		for i in range(3,raw_bytes.size(),4):
			if raw_bytes[i]!=after[i]:alpha_same=false;break
		check(alpha_same,"preparation never changes base alpha silhouette "+art)
		check(Materials.artwork(art,true).get_image().has_mipmaps(),"safe texture retains mipmaps "+art)
	print("TREE_LEAF_OPTICS_TEST ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
