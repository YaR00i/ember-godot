extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
class SavedContext extends Preparation:
	var fixture_path:String
	func material_patterns(_roles:PackedStringArray,ids:PackedStringArray)->Dictionary:
		var preset:=_saved_material_pattern(fixture_path)
		_material_saved[ids[1]]=_saved_material_patterns.get(fixture_path,{}) if preset!=null else {}
		return {ids[1]:preset}
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("DETAIL_MATERIAL_FAIL ",label)
func images(material:ShaderMaterial)->Dictionary:
	var result:Dictionary={}
	for entry in material.shader.get_shader_uniform_list():
		var value=material.get_shader_parameter(entry.name)
		if value is ImageTexture:result[entry.name]=value.get_image().get_data()
	return result
func _initialize()->void:run.call_deferred()
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	var context:=Preparation.new()
	var roles:=PackedStringArray(["","soil","grass","sand","grass","","stone"])
	var ids:=PackedStringArray(["","cartoon_soil","cartoon_grass","cartoon_sand","cartoon_grass","","cartoon_stone"])
	var palette:=PackedColorArray([Color.TRANSPARENT,Color.SADDLE_BROWN,Color.GREEN,Color.BEIGE,Color.DARK_GREEN,Color.BLACK,Color.GRAY])
	var reference:=Materials.compact_flower_material()
	Materials.set_compact_terrain_roles(reference,roles,ids,palette)
	var expected:=images(reference)
	var patterns:=context.material_patterns(roles,ids)
	var first:=Materials.compact_flower_material()
	context.bind_saved_material_roles(first,roles,ids,palette)
	var second:=Materials.compact_flower_material()
	context.bind_saved_material_roles(second,roles,ids,palette)
	check(images(first)==expected and images(second)==expected,"prepared bindings match direct texture bytes")
	for uniform in reference.shader.get_shader_uniform_list():
		var value=reference.get_shader_parameter(uniform.name)
		if not value is Texture:
			check(first.get_shader_parameter(uniform.name)==value,"same non-texture parameter "+str(uniform.name))

	check(context._role_payloads.size()==1,"same layout reuses one CPU payload")
	var third:=Materials.compact_grass_material()
	context.bind_saved_material_roles(third,roles,ids,palette)
	check(images(third)==expected and context._role_payloads.size()==1,"other grass shader reuses exact role payload")
	for entry in first.shader.get_shader_uniform_list():
		var value=first.get_shader_parameter(entry.name)
		if value is ImageTexture:check(value!=second.get_shader_parameter(entry.name),"private texture "+entry.name)
	var edited=patterns.cartoon_grass.duplicate()
	edited.pattern_size_m=12;edited.grass_light_low=0.44
	Materials.update_grass_light_profile(first,2,edited)
	check(images(second)==expected,"preview cannot mutate sibling binding")
	var fourth:=Materials.compact_flower_material()
	context.bind_saved_material_roles(fourth,roles,ids,palette)
	check(images(fourth)==expected,"preview cannot mutate cached payload")
	Materials.update_style_rim_profile(first,2,edited)
	check(images(second)==expected and images(fourth)==expected,"rim preview is private too")
	var changed_palette:=palette.duplicate();changed_palette[2]=Color.MAGENTA
	var recolored:=Materials.compact_flower_material()
	context.bind_saved_material_roles(recolored,roles,ids,changed_palette)
	check(images(recolored)!=expected and context._role_payloads.size()==2,"palette change selects new payload")
	# An in-memory edit during one batch must not become a persistent preset cache.
	var original:Color=patterns.cartoon_grass.base_color
	patterns.cartoon_grass.base_color=Color.MAGENTA
	var edited_frame:=Engine.get_process_frames()
	while Engine.get_process_frames()==edited_frame:await process_frame
	var fresh:=context.material_patterns(roles,ids)
	check(fresh.cartoon_grass.base_color==original,"next frame reloads saved preset")
	var subsets:=context.material_patterns(PackedStringArray(["stone"]),PackedStringArray(["cartoon_stone"]))
	check(subsets.size()==1 and subsets.has("cartoon_stone"),"different layout selects its own presets")
	check(context.material_patterns(PackedStringArray([""]),PackedStringArray()).is_empty(),"empty role unchanged")
	# Disposable saved files exercise invalidation without touching author presets.
	var folder:="user://ember-tests/saved-material-"+str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("pattern.tres")
	var saved=patterns.cartoon_grass.duplicate()
	saved.base_color=Color.GREEN;saved.pixels[0]=0
	var channels:=["pixels","side_pixels","relief_pixels","side_relief_pixels","roughness_pixels","side_roughness_pixels"]
	for channel in channels:
		var artwork:=PackedByteArray();artwork.resize(256);artwork.fill(0);saved.set(channel,artwork)
	check(ResourceSaver.save(saved,path)==OK,"write isolated preset")
	var one=context._saved_material_pattern(path)
	var two=context._saved_material_pattern(path)
	one.base_color=Color.MAGENTA;one.pixels[0]=2
	check(two.base_color==Color.GREEN and two.pixels[0]==0,"cached snapshots keep private values and artwork")
	for channel in channels:
		var artwork:PackedByteArray=one.get(channel);artwork[0]=2
		check((two.get(channel) as PackedByteArray)[0]==0,"private authored channel "+channel)
	check(one.albedo_texture==two.albedo_texture,"snapshot copies retain shared imported textures")
	check(context._saved_material_pattern(path).base_color==Color.GREEN,"caller cannot alter saved template")
	saved.base_color=Color.BLUE
	check(ResourceSaver.save(saved,path)==OK,"replace preset immediately")
	check(context._saved_material_pattern(path).base_color==Color.BLUE,"same-second save invalidates saved snapshot")
	DirAccess.remove_absolute(path)
	check(context._saved_material_pattern(path)==null,"removed saved preset is not served from cache")
	check(ResourceSaver.save(saved,path)==OK and context._saved_material_pattern(path)!=null,"recreated preset returns")
	for i in context.SAVED_MATERIAL_LIMIT+2:
		var other:=folder.path_join("pattern_%d.tres"%i)
		ResourceSaver.save(saved,other);context._saved_material_pattern(other)
	check(context._saved_material_patterns.size()<=context.SAVED_MATERIAL_LIMIT,"saved snapshot cache stays bounded")
	var artwork:=Image.create(4,4,false,Image.FORMAT_RGBA8);artwork.fill(Color.GREEN)
	saved.albedo_texture=ImageTexture.create_from_image(artwork)
	ResourceSaver.save(saved,path)
	var disposable_pattern=saved.duplicate()
	disposable_pattern.albedo_texture=ImageTexture.create_from_image(artwork)
	var payload:=Materials.prepare_terrain_roles(PackedStringArray(["","grass"]),PackedStringArray(["","qa_private"]),palette,{"qa_private":disposable_pattern})
	var disposable:=Materials.compact_flower_material()
	Materials.apply_prepared_terrain_roles(disposable,payload)
	var bank_reference:WeakRef=weakref(disposable.get_shader_parameter("png_albedo_bank"))
	disposable.set_shader_parameter("png_albedo_bank",null)
	check(bank_reference.get_ref()==null,"prepared CPU payload does not retain GPU bank without a consumer")
	var saved_context:=SavedContext.new();saved_context.fixture_path=path
	var test_roles:=PackedStringArray(["","grass"]);var test_ids:=PackedStringArray(["","qa_grass"])
	var test_material:=Materials.compact_flower_material()
	saved_context.bind_saved_material_roles(test_material,test_roles,test_ids,palette)
	var source_texture:ImageTexture=saved_context._material_saved.qa_grass.source.albedo_texture
	var first_bank:Texture2DArray=test_material.get_shader_parameter("png_albedo_bank")
	artwork.fill(Color.BLUE);source_texture.set_image(artwork);source_texture.emit_changed()
	saved_context.bind_saved_material_roles(test_material,test_roles,test_ids,palette)
	var changed_bank:Texture2DArray=test_material.get_shader_parameter("png_albedo_bank")
	check(first_bank!=changed_bank and changed_bank.get_layer_data(0).get_pixel(0,0).b>0.9,"texture revision refreshes prepared PNG bank without saving preset")
	var saved_bytes:=images(test_material)
	saved.base_color=Color.RED;ResourceSaver.save(saved,path)
	saved_context.bind_saved_material_roles(test_material,test_roles,test_ids,palette)
	check(images(test_material)!=saved_bytes,"same-second saved change invalidates prepared payload")
	var replacement:=images(test_material)
	DirAccess.remove_absolute(path)
	saved_context.bind_saved_material_roles(test_material,test_roles,test_ids,palette)
	check(images(test_material)!=replacement,"removed file cannot reuse prepared payload")
	ResourceSaver.save(saved,path)
	saved_context.bind_saved_material_roles(test_material,test_roles,test_ids,palette)
	check(images(test_material)==replacement,"recreated preset restores exact binding")
	for i in saved_context.SAVED_MATERIAL_LIMIT+2:
		var colors:=palette.duplicate();colors[2]=Color(float(i)/32.0,0.3,0.7)
		saved_context.bind_saved_material_roles(test_material,test_roles,test_ids,colors)
	check(saved_context._role_payloads.size()<=saved_context.SAVED_MATERIAL_LIMIT,"CPU payload cache stays bounded")
	saved_context._release()
	check(saved_context._role_payloads.is_empty(),"release drops prepared payloads")
	context._release()
	check(context._saved_material_patterns.is_empty() and context._material_patterns.is_empty() and context._material_saved.is_empty() and context._role_payloads.is_empty(),"release drops saved and batch snapshots")
	print("DETAIL_MATERIAL_PREPARATION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
