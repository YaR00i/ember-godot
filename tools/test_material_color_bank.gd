extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Pattern=preload("res://scripts/ember_compact_terrain_pattern.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("COLOR_BANK_FAIL ",label)
func artwork(size:Vector2i,seed_value:int)->Image:
	var image:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:image.set_pixel(x,y,Color(float((x*17+y*31+seed_value)%256)/255.0,float((x*7+y*3)%256)/255.0,0.2,float((x+y)%5)/4.0))
	return image
func pattern(role:String,texture:Texture2D)->Resource:
	var result:=Pattern.new();result.role_id=role;result.pixels.resize(256);result.albedo_texture=texture
	return result
func material(a:Resource,b:Resource)->ShaderMaterial:
	var result:=Materials.compact_grass_material()
	Materials.set_compact_terrain_roles(result,PackedStringArray(["","grass","stone","grass"]),PackedStringArray(["","fixture_a","fixture_b","fixture_a"]),PackedColorArray(),{"fixture_a":a,"fixture_b":b})
	return result
func bytes(material:ShaderMaterial,name:String)->PackedByteArray:
	return (material.get_shader_parameter(name) as Texture2D).get_image().get_data()
func render_parity(material:ShaderMaterial,reference:Texture2DArray)->void:
	Engine.time_scale=0;root.size=Vector2i(640,480);root.use_taa=false;root.msaa_3d=Viewport.MSAA_DISABLED
	var scene:=Node3D.new();root.add_child(scene)
	var plane:=PlaneMesh.new();plane.size=Vector2(2,2)
	var arrays:=plane.surface_get_arrays(0);var count:int=arrays[Mesh.ARRAY_VERTEX].size()
	var colors:=PackedColorArray();colors.resize(count);colors.fill(Color(1,0,0,1.0/255))
	var uv:=PackedVector2Array();uv.resize(count);uv.fill(Vector2.ONE/255)
	var uv2:=PackedVector2Array();uv2.resize(count);uv2.fill(Vector2(1.0/255,0))
	arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.material_override=material;scene.add_child(visual)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-20,0);light.light_energy=2;scene.add_child(light)
	var camera:=Camera3D.new();scene.add_child(camera);camera.look_at_from_position(Vector3(1,1.5,2),Vector3.ZERO);camera.make_current()
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image()
	material.set_shader_parameter("png_albedo_bank",reference)
	for i in 6:await process_frame
	await RenderingServer.frame_post_draw
	var expected:=root.get_texture().get_image()
	check(actual.get_data()==expected.get_data(),"native pixels match independent legacy bank")
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0]);actual.save_png(args[0].path_join("material.png"))
	scene.queue_free();await process_frame
func _initialize():run.call_deferred()
func run():
	if DisplayServer.get_name()=="headless":quit(2);return
	var source_a:=artwork(Vector2i(16,32),23);var source_b:=artwork(Vector2i(32,16),71)
	var original_a:=source_a.get_data();var original_b:=source_b.get_data()
	var texture_a:=ImageTexture.create_from_image(source_a);var texture_b:=ImageTexture.create_from_image(source_b)
	var a:=pattern("grass",texture_a);var b:=pattern("stone",texture_b)
	a.albedo_relief_enabled=false;a.albedo_periodic=true;a.base_color=Color(0.3,0.7,0.2)
	var first:=material(a,b);var variant:Resource=a.duplicate();variant.pattern_size_m=8;variant.base_color=Color(0.7,0.2,0.3)
	var second:=material(variant,b)
	var bank:Texture2DArray=first.get_shader_parameter("png_albedo_bank")
	check(bank==second.get_shader_parameter("png_albedo_bank"),"same artwork shares GPU bank across different settings")
	check(bank.get_layers()==2 and bank.get_width()==32 and bank.get_height()==32,"deduplication and common dimensions")
	var originals:Array[Image]=[source_a,source_b]
	var reference_layers:Array[Image]=[]
	for layer in 2:
		# Previous byte-for-byte normalization and mean, before resize/mips.
		var reference:=originals[layer].duplicate() as Image;var mean:=Color(0,0,0,0);var samples:=0
		for y in range(0,reference.get_height(),16):
			for x in range(0,reference.get_width(),16):mean+=reference.get_pixel(x,y).srgb_to_linear();samples+=1
		reference.resize(32,32,Image.INTERPOLATE_LANCZOS);reference.generate_mipmaps()
		reference_layers.append(reference)
		check(bank.get_layer_data(layer).get_data()==reference.get_data(),"legacy layer/mipmap bytes %d"%layer)
		var lookup:Texture2D=first.get_shader_parameter("png_mean_lookup")
		check(lookup.get_image().get_pixel(layer+1,0)==mean/samples,"legacy linear mean %d"%layer)
	var lookup:Texture2D=first.get_shader_parameter("png_lookup")
	var slot:=lookup.get_image().get_pixel(1,0)
	check(slot.r==1 and slot.g==4 and slot.b<0 and slot.a==1,"slot/size/colour-only/periodic metadata")
	check(lookup.get_image().get_pixel(3,0).r==1,"duplicate texture retains palette slots")
	for name in ["png_lookup","png_tint_lookup","grass_light_lookup","surface_lookup","style_rim_lookup"]:
		check(first.get_shader_parameter(name)!=second.get_shader_parameter(name),"private lookup "+name)
	var second_lookup:=bytes(second,"png_lookup");var second_light:=bytes(second,"grass_light_lookup")
	var second_tint:=bytes(second,"png_tint_lookup")
	var edited:Resource=a.duplicate();edited.pattern_size_m=12;edited.grass_light_low=0.44
	Materials.update_grass_light_profile(first,1,edited)
	check(bytes(second,"png_lookup")==second_lookup and bytes(second,"grass_light_lookup")==second_light and bytes(second,"png_tint_lookup")==second_tint,"preview cannot change sibling material")
	check(source_a.get_data()==original_a and source_b.get_data()==original_b,"immutable source images")
	var legacy_bank:=Texture2DArray.new();legacy_bank.create_from_images(reference_layers)
	await render_parity(first,legacy_bank)
	var replacement:=artwork(Vector2i(16,32),132);texture_a.set_image(replacement)
	var changed:=material(a,b);var new_bank:Texture2DArray=changed.get_shader_parameter("png_albedo_bank")
	check(new_bank!=bank,"source changed signal invalidates cache")
	check(new_bank.get_layer_data(0).get_data()!=bank.get_layer_data(0).get_data(),"changed source has new layers")
	var empty:=Materials._png_bank([]);var empty_again:=Materials._png_bank([])
	check(empty.bank==empty_again.bank and empty.bank.get_layer_data(0).get_pixel(0,0)==Color.WHITE,"shared white fallback")
	print("MATERIAL_COLOR_BANK ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
