extends "res://tools/test_voxel_light_render.gd"
## Regression for grass-face shadow shimmer. Main scene is instantiated only in
## memory; fixture/session writes stay in user://, never in the authored map.
const Fixture = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
var map: EmberMapLoader
var sphere: Node3D
var patch: Node3D
var scene: Node3D
func _init() -> void:
 Fixture.prepare(self,"user://ember-tests/grass-light-"+str(OS.get_process_id()))
 run.call_deferred()
func frames(count: int) -> void:
 for i in count: await process_frame
func settle(local_look := false) -> void:
 var deadline := Time.get_ticks_msec()+90000
 await frames(2)
 while Time.get_ticks_msec()<deadline:
  var projection=map._visual_surface_projection
  if not patch._dirty and not patch._rebuilding and projection.pending_tile_count()==0 and projection._look_pending.is_empty() and (not local_look or sphere._prepared): return
  await process_frame
 check(false,"terrain/grass/local look settles before capture")
func image(label: String) -> Image:
 await RenderingServer.frame_post_draw
 var picture:=root.get_texture().get_image()
 picture.save_png(output.path_join(label+".png"))
 return picture
func grain(label: String) -> float:
 # Two interiors of the reproduced grass shadows; excludes their boundaries.
 # Pixel coordinates refer to the fixed 1440x810 production-map view below.
 var regions: Array[Rect2i]=[Rect2i(450,405,120,32),Rect2i(1150,237,110,38)]
 var pictures: Array[Image]=[]
 for i in 8:
  await process_frame
  pictures.append(await image(label+"-"+str(i)))
 var worst:=0.0
 for region in regions:
  var total:=0.0
  for y in range(region.position.y,region.end.y):
   for x in range(region.position.x,region.end.x):
    var sum:=Vector3.ZERO;var square:=Vector3.ZERO
    for picture in pictures:
     var value:=rgb(picture.get_pixel(x,y));sum+=value;square+=value*value
    var mean:=sum/pictures.size();var variance: Vector3=(square/pictures.size()-mean*mean).max(Vector3.ZERO)
    total+=(sqrt(variance.x)+sqrt(variance.y)+sqrt(variance.z))/3.0
  worst=maxf(worst,total/float(region.get_area()))
 return worst
func motion(label: String) -> void:
 for i in 24:
  camera.position.x+=0.1;await process_frame
  if i in [8,16,23]:await image(label+"-"+str(i))
func near_view() -> void:
 camera.look_at_from_position(Vector3(81,24,248),Vector3(64,4,216))
func run() -> void:
 if DisplayServer.get_name()=="headless":printerr("Native Forward+ required");quit(2);return
 output="user://ember-tests/grass-voxel-light-render"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("out="):output=arg.trim_prefix("out=")
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 DisplayServer.window_set_size(Vector2i(1440,900))
 scene=load("res://scenes/landscape_compact.tscn").instantiate()
 scene.sandbox_storage_root="user://ember-tests/grass-light-"+str(OS.get_process_id())
 map=scene.get_node("Map");map.world_look=2
 sphere=map.get_node("WorldAnomaly");sphere.enabled=false
 root.add_child(scene);current_scene=scene
 var deadline:=Time.get_ticks_msec()+90000
 while not scene._startup_complete and Time.get_ticks_msec()<deadline:await process_frame
 check(scene._startup_complete,"main map startup completes")
 scene._player.set_physics_process(false);scene._party_followers.set_physics_process(false);scene.get_node("CanvasLayer").hide()
 patch=map.get_node("Props/GrassPatch");await settle()
 camera=Camera3D.new();scene.add_child(camera);camera.far=2000;camera.near=0.1;camera.fov=58;near_view();camera.make_current()
 var sun: DirectionalLight3D=map.get_node("Look/Sun")
 var authored:=[sun.light_angular_distance,map.directional_shadow_filter,map.use_taa]
 check(root.use_taa==map.use_taa,"runtime viewport follows authored TAA setting")
 # Fixed diagnostic quality only in memory; author's saved settings can differ.
 map.use_taa=true
 var visual: MultiMeshInstance3D=patch._visual
 var material: ShaderMaterial=visual.material_override
 var scatter_id:=visual.multimesh.get_instance_id()
 var mesh_id:=visual.multimesh.mesh.get_instance_id()
 check(material.get_shader_parameter("voxel_light_enabled")==true,"voxel light remains enabled on grass")
 check(is_equal_approx(material.get_shader_parameter("voxel_light_cell"),map.voxel_light_cell_m*map.imported_tile_size),"grass cell size still follows map metres")
 check(is_equal_approx(material.get_shader_parameter("voxel_light_levels"),map.voxel_light_levels),"grass keeps authored light gradations")
 var metrics:={}
 for hard in [false,true]:
  sun.light_angular_distance=0.0 if hard else 1.0;map.directional_shadow_filter=0 if hard else 5
  near_view();await frames(80)
  var label: String="hard" if hard else "soft"
  var value:=await grain(label)
  metrics[label+"_temporal_std"]=value
  check(value<0.003,label+": grass shadow interiors do not shimmer")
  await motion(label+"-moving")
  camera.look_at_from_position(Vector3(128,47,283),Vector3(82,12,161));await frames(60);await image(label+"-far")
  check(visual.multimesh.get_instance_id()==scatter_id and visual.multimesh.mesh.get_instance_id()==mesh_id,"light/camera changes do not rebuild grass")
 sun.light_angular_distance=authored[0];map.directional_shadow_filter=authored[1];map.use_taa=authored[2]
 for look in [0,1]:
  map.world_look=look;await settle();near_view();await frames(60);await image("look-"+str(look))
  check(patch._visual.material_override.get_shader_parameter("voxel_light_enabled")==false,"detailed/low-poly grass bypass voxel sampling")
 map.world_look=0;sphere.inner_look=2;sphere.enabled=true
 await settle(true);near_view();await frames(60);await image("sphere-voxel")
 var grass_bindings:=0
 for binding in sphere._bindings:
  if not binding.source is MultiMeshInstance3D:continue
  for bound in binding.materials:
   grass_bindings+=1
   check(bound.get_shader_parameter("painterly_blades")==true and bound.get_shader_parameter("voxel_light_anomaly")==true,"sphere grass keeps same shader and voxel-light binding")
 check(grass_bindings>0,"actual sphere includes grass")
 var prepared: int=sphere.preparations
 var targets: int=sphere.Correspondence.builds
 sphere.position.x+=8;await frames(30);await image("sphere-moved");await motion("sphere-camera")
 check(sphere.preparations==prepared and sphere.Correspondence.builds==targets,"moving sphere/camera does not rebuild local look")
 check([sun.light_angular_distance,map.directional_shadow_filter,map.use_taa]==authored,"author shadow settings restored in memory")
 metrics["grass_instances"]=visual.multimesh.instance_count
 metrics["sphere_grass_bindings"]=grass_bindings
 print("GRASS_VOXEL_LIGHT_RENDER ",JSON.stringify({"pass":failures.is_empty(),"errors":failures,"metrics":metrics,"images":ProjectSettings.globalize_path(output)}))
 quit(0 if failures.is_empty() else 1)
