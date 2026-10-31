extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);push_error(label)
func material()->ShaderMaterial:
 var result:=ShaderMaterial.new();result.shader=Solid.solid_depth_shader();result.set_meta("ember_detailed_depth",true);return result
func _initialize():run.call_deferred()
func run():
 Engine.max_fps=0;OS.low_processor_usage_mode=false;OS.low_processor_usage_mode_sleep_usec=0
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Materials._bank_height_images.clear();Materials._bank_height_textures.clear()
 var roles:=PackedStringArray(["","stone"]);var ids:=PackedStringArray(["","audit_fixture"])
 for i in 36:
  var image:=Image.create(2,2,false,Image.FORMAT_RGBA8);image.fill(Color(float(i%4)/4.0,0,0))
  var texture:=ImageTexture.create_from_image(image)
  var pattern:=EmberCompactTerrainPattern.new();pattern.role_id="stone";pattern.pixels.resize(256);pattern.albedo_texture=texture;pattern.depth_texture=texture;pattern.depth_mm=2.0
  var current:=material();Materials.set_terrain_depth_profiles(current,roles,ids,{"audit_fixture":pattern})
  var bank:=current.get_shader_parameter("terrain_depth_bank") as Texture2DArray
  check(bank.get_layer_data(0).get_pixel(0,0).r==image.get_pixel(0,0).r,"exact restored pixels")
  bank=null;current=null;pattern=null;texture=null
 var bytes:=0
 for image:Image in Materials._bank_height_images.values():bytes+=image.get_data_size()
 check(Materials._bank_height_images.size()<=16 and bytes<=24*1024*1024,"upper cache bounded across reload/release")
 var input:=Image.create(2,2,false,Image.FORMAT_RGBA8);input.fill(Color(0.1,0,0))
 var source:=ImageTexture.create_from_image(input)
 var pattern:=EmberCompactTerrainPattern.new();pattern.role_id="stone";pattern.pixels.resize(256);pattern.albedo_texture=source;pattern.depth_texture=source;pattern.depth_mm=2.0
 var target:=material();Materials.set_terrain_depth_profiles(target,roles,ids,{"audit_fixture":pattern})
 var old_keys:Array=target.get_meta("ember_depth_keys").duplicate()
 input.fill(Color(0.8,0,0));source.update(input)
 Materials.set_terrain_depth_profiles(target,roles,ids,{"audit_fixture":pattern})
 var actual:=target.get_shader_parameter("terrain_depth_bank") as Texture2DArray
 check(absf(actual.get_layer_data(0).get_pixel(0,0).r-0.8)<0.01,"same Texture pixel update refreshes full GPU bank")
 check(target.get_meta("ember_depth_keys")!=old_keys,"pixel revision participates in bank key")
 for i in 32:
  pattern.depth_softness=0.5+float(i)*0.1
  Materials.set_terrain_depth_profiles(target,roles,ids,{"audit_fixture":pattern})
 var live_bytes:=Materials.depth_cache_bytes()
 check(Materials._bank_height_images.size()<=16 and live_bytes<=24*1024*1024,"live-source parameter churn also respects byte/entry budget")
 print("DEPTH_CACHE_AUDIT ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"entries":Materials._bank_height_images.size(),"bytes_before_update":bytes}))
 quit(0 if errors.is_empty() else 1)
