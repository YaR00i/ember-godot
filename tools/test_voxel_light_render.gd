extends SceneTree
## Native Forward+ behaviour: stable per-cell lighting and real shadow reception.
## Memory-only fixture, no authored scene/source writes.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var failures: Array[String] = []
var camera: Camera3D
var output := "user://ember-tests/voxel-light-render"
func _init() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
 if not ok: failures.append(message)
func capture(label: String) -> Image:
 for i in 5: await process_frame
 await RenderingServer.frame_post_draw
 var picture := root.get_texture().get_image()
 picture.save_png(output.path_join(label+".png"))
 return picture
func rgb(c: Color) -> Vector3: return Vector3(c.r,c.g,c.b)
func pixel(picture: Image, point: Vector3) -> Vector3:
 var screen := camera.unproject_position(point) * Vector2(picture.get_size()) / root.get_visible_rect().size
 return rgb(picture.get_pixel(clampi(roundi(screen.x),0,picture.get_width()-1),clampi(roundi(screen.y),0,picture.get_height()-1)))
func spreads(picture: Image) -> float:
 var total := 0.0;var count := 0
 for z in range(-5,5):
  for x in range(-5,5):
   var a := pixel(picture,Vector3((x+0.2)*0.25,0,(z+0.2)*0.25))
   var b := pixel(picture,Vector3((x+0.8)*0.25,0,(z+0.8)*0.25))
   total += (a-b).length();count+=1
 return total/count
func run() -> void:
 if DisplayServer.get_name()=="headless":printerr("Native Forward+ required");quit(2);return
 DisplayServer.window_set_size(Vector2i(900,600))
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 var scene := Node3D.new();root.add_child(scene);current_scene=scene
 var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.BLACK;scene.add_child(environment)
 camera=Camera3D.new();scene.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=4;camera.look_at_from_position(Vector3(0,6,0),Vector3.ZERO,Vector3.FORWARD);camera.make_current()
 var ground := MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(4,4);ground.mesh=plane;scene.add_child(ground)
 var lamp := OmniLight3D.new();scene.add_child(lamp);lamp.position=Vector3(-0.5,1.4,-0.7);lamp.omni_range=6;lamp.light_energy=0.3
 var results := {}
 var object := ShaderMaterial.new();object.shader=load("res://shaders/ember_tree_bark.gdshader");object.set_shader_parameter("painted_bark_enabled",false);object.set_shader_parameter("surface_response_enabled",false)
 var terrain := Materials.compact_terrain_material();Materials.set_compact_terrain_roles(terrain,PackedStringArray(["",""]),PackedStringArray(["",""]),PackedColorArray([Color.TRANSPARENT,Color.WHITE]));terrain.set_shader_parameter("material_light_mode",1);terrain.set_shader_parameter("surface_detail_enabled",false)
 # A valid palette-bearing plane exercises the actual terrain/rock shader.
 var arrays := plane.get_mesh_arrays();var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var colors:=PackedColorArray();colors.resize(vertices.size());colors.fill(Color(1,0,0,1.0/255.0));arrays[Mesh.ARRAY_COLOR]=colors
 var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);ground.mesh=mesh
 for kind in ["object","terrain"]:
  var material: ShaderMaterial=object if kind=="object" else terrain
  ground.material_override=material
  material.set_shader_parameter("voxel_light_cell",0.25);material.set_shader_parameter("voxel_light_levels",32.0)
  material.set_shader_parameter("voxel_light_enabled",false)
  var before := await capture(kind+"-continuous");var previous_spread:=spreads(before)
  material.set_shader_parameter("voxel_light_enabled",true)
  var after := await capture(kind+"-texel");var cell_spread:=spreads(after)
  check(previous_spread>0.005,kind+": negative control has continuous intra-cell light")
  check(cell_spread<previous_spread*0.25 and cell_spread<0.006,kind+": one stable illumination sample per visible cell")
  var anchors: Array[Vector3]=[]
  for z in range(-4,4):
   for x in range(-4,4):anchors.append(pixel(after,Vector3((x+0.5)*0.25,0,(z+0.5)*0.25)))
  camera.position.x+=0.073;camera.position.z+=0.037
  var moved:=await capture(kind+"-moved");var drift:=0.0;var index:=0
  for z in range(-4,4):
   for x in range(-4,4):
    drift+=(pixel(moved,Vector3((x+0.5)*0.25,0,(z+0.5)*0.25))-anchors[index]).length();index+=1
  drift/=anchors.size();check(drift<0.006,kind+": light cells stay anchored under camera translation")
  camera.position.x-=0.073;camera.position.z-=0.037
  material.set_shader_parameter("voxel_light_enabled",false)
  var restored:=await capture(kind+"-restored");check(before.get_data()==restored.get_data(),kind+": disabling restores exact original render")
  results[kind]={"continuous_spread":previous_spread,"cell_spread":cell_spread,"motion_drift":drift}
 # Real directional shadow, not a painted dark mask.
 lamp.hide();var sun:=DirectionalLight3D.new();scene.add_child(sun);sun.rotation_degrees=Vector3(-55,-30,0);sun.shadow_enabled=true;sun.light_angular_distance=3;sun.directional_shadow_max_distance=20
 var caster:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(0.7,0.5,1.2);caster.mesh=box;caster.position=Vector3(0,0.8,0);caster.rotation.y=0.4;scene.add_child(caster)
 ground.material_override=object;object.set_shader_parameter("voxel_light_enabled",true)
 await capture("shadow-texel")
 object.set_shader_parameter("voxel_light_enabled",false);await capture("shadow-continuous")
 # Isolate texel-centre shadow sampling from Godot's stochastic soft filter.
 sun.light_angular_distance=0.0;RenderingServer.directional_soft_shadow_filter_set_quality(0)
 object.set_shader_parameter("voxel_light_enabled",true)
 var hard:=await capture("shadow-hard-texel")
 var shadow_spread:=0.0;var tested:=0
 for z in range(-6,6):
  for x in range(-6,6):
   var a:=Vector3((x+0.2)*0.25,0,(z+0.2)*0.25);var b:=Vector3((x+0.8)*0.25,0,(z+0.8)*0.25)
   var la:=caster.to_local(a);var lb:=caster.to_local(b)
   if (absf(la.x)<0.4 and absf(la.z)<0.65) or (absf(lb.x)<0.4 and absf(lb.z)<0.65):continue
   shadow_spread+=(pixel(hard,a)-pixel(hard,b)).length();tested+=1
 shadow_spread/=tested;check(shadow_spread<0.006,"hard directional shadow shares the lighting cell")
 caster.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var unshadowed:=await capture("shadow-disabled");var effect:=0.0
 for y in range(0,hard.get_height(),3):
  for x in range(0,hard.get_width(),3):effect+=(rgb(hard.get_pixel(x,y))-rgb(unshadowed.get_pixel(x,y))).length()
 check(effect>10.0,"actual caster must affect shadowed receiver")
 results["shadow"]={"hard_cell_spread":shadow_spread,"caster_effect":effect,"soft_filter":"native PCSS grain remains; production Sun unchanged"}
 print("VOXEL_LIGHT_RENDER ",JSON.stringify({"pass":failures.is_empty(),"errors":failures,"metrics":results,"images":ProjectSettings.globalize_path(output)}))
 quit(0 if failures.is_empty() else 1)
