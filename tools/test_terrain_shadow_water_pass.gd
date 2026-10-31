extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const OUT="D:/Codex/ember-active-frame-20261030/shadow-pass-test"
var failures:Array[String]=[]
func _init()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
 if not ok:failures.append(label);printerr("SHADOW_PASS_FAIL ",label)
func frames(n:int)->void:
 for i in n:await process_frame
func picture()->Image:
 await frames(12);await RenderingServer.frame_post_draw
 return root.get_texture().get_image()
func difference(a:Image,b:Image)->float:
 var total:=0.0
 for y in a.get_height():
  for x in a.get_width():
   var ca:=a.get_pixel(x,y);var cb:=b.get_pixel(x,y)
   total+=absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
 return total/float(a.get_width()*a.get_height()*3)
func run()->void:
 if DisplayServer.get_name()=="headless":quit(2);return
 DirAccess.make_dir_recursive_absolute(OUT)
 root.size=Vector2i(320,320);root.use_taa=false
 var scene:=Node3D.new();root.add_child(scene);current_scene=scene
 var world:=WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color(0.2,0.2,0.2);world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=0.15;scene.add_child(world)
 var receiver:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(20,20);receiver.mesh=plane
 var receiver_material:=StandardMaterial3D.new();receiver_material.albedo_color=Color(0.7,0.7,0.7);receiver_material.roughness=1.0;receiver.material_override=receiver_material;scene.add_child(receiver)
 var caster:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(3,3,3);caster.mesh=box;caster.position.y=1.5;scene.add_child(caster)
 var material:=Materials.compact_terrain_material();material.set_shader_parameter("reflection_pass_enabled",true);material.set_shader_parameter("caustic_water_level",-10.0);caster.material_override=material
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-60,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=40;sun.shadow_normal_bias=0.5;sun.shadow_bias=0.02;scene.add_child(sun)
 var camera:=Camera3D.new();scene.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=14;camera.cull_mask=1;camera.look_at_from_position(Vector3(8,12,10),Vector3(0,0,0));camera.make_current()
 var body:=FileAccess.get_file_as_string("res://shaders/ember_compact_terrain_body.gdshaderinc")
 var shader:=Shader.new()
 var clean:="shader_type spatial;\n"+body.replace("CAMERA_VISIBLE_LAYERS","(IN_SHADOW_PASS ? 0u : CAMERA_VISIBLE_LAYERS)")
 shader.code=clean;material.shader=shader
 var reference:=await picture();reference.save_png(OUT.path_join("reference.png"))
 # Model a shadow pass with a camera-layer value containing the refraction bit.
 # It must never act as a refraction camera, regardless of that unrelated value.
 shader.code="shader_type spatial;\n"+body.replace("CAMERA_VISIBLE_LAYERS","(IN_SHADOW_PASS ? (1u<<18u) : CAMERA_VISIBLE_LAYERS)")
 var actual:=await picture();actual.save_png(OUT.path_join("refraction-bit.png"))
 var error:=difference(reference,actual)
 check(error<0.0001,"shadow pass ignores refraction camera classification")
 material.set_shader_parameter("caustic_water_level",10.0)
 shader.code=clean
 reference=await picture()
 shader.code="shader_type spatial;\n"+body.replace("CAMERA_VISIBLE_LAYERS","(IN_SHADOW_PASS ? (1u<<19u) : CAMERA_VISIBLE_LAYERS)")
 actual=await picture();var reflection_error:=difference(reference,actual)
 check(reflection_error<0.0001,"shadow pass ignores reflection camera classification")
 # Real camera passes still clip their intended side of the water plane.
 for bit in [18,19]:
  material.set_shader_parameter("caustic_water_level",-10.0 if bit==18 else 10.0)
  shader.code=clean;camera.cull_mask=1;caster.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
  var shadow_only:=await picture()
  caster.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
  var visible:=await picture()
  check(difference(shadow_only,visible)>0.001,"visible caster negative control "+str(bit))
  camera.cull_mask=1|(1<<bit)
  var camera_pass:=await picture()
  check(difference(shadow_only,camera_pass)<0.0001,"real water camera retains clipping "+str(bit))
 print("TERRAIN_SHADOW_PASS ",JSON.stringify({"pass":failures.is_empty(),"refraction_error":error,"reflection_error":reflection_error,"errors":failures}))
 quit(0 if failures.is_empty() else 1)
