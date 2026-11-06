extends SceneTree
const Builder=preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const ProjectionScript=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
var errors:Array[String]=[]
var report:Array=[]
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);printerr("OVERVIEW_INDEX_FAIL ",label)
func _initialize()->void:run.call_deferred()
func frames(n:int)->void:
 for i in n:await process_frame
func picture(view:SubViewport,visual:MeshInstance3D,mesh:Mesh,visible:bool)->PackedByteArray:
 visual.mesh=mesh;visual.visible=visible;await frames(8);await RenderingServer.frame_post_draw
 return view.get_texture().get_image().get_data()
func update(projection:Node,entry:Dictionary,covered:Dictionary)->void:
 if projection.has_method("_update_overview_ground"):projection._update_overview_ground(entry,covered)
 else:
  var ground:MeshInstance3D=entry.node.get_node("Ground")
  ground.mesh=projection._overview_mesh(entry.data.arrays,entry.data.patches,covered)
  ground.visible=ground.mesh.get_surface_count()>0
func run()->void:
 create_timer(45).timeout.connect(func():printerr("OVERVIEW_INDEX_TIMEOUT");quit(2))
 var source=Fixture.base();source.width=384;source.depth=384
 for channel:String in source.Sections.CHANNELS:
  var values=PackedInt32Array() if channel in ["heights","water_levels"] else PackedByteArray()
  values.resize(384*384);values.fill(24 if channel=="heights" else 2 if channel=="top_materials" else 1 if channel=="base_materials" else 0)
  source.set(channel,values)
 var projection=ProjectionScript.new()
 var host:=Node3D.new();var ground:=MeshInstance3D.new();ground.name="Ground";host.add_child(ground)
 var view:=SubViewport.new();view.size=Vector2i(256,256);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view);view.add_child(host)
 var camera:=Camera3D.new();view.add_child(camera);camera.position=Vector3(500,450,500);camera.look_at(Vector3(192,24,192));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=650
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-30,0);sun.shadow_enabled=true;view.add_child(sun)
 var receiver:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(600,600);receiver.mesh=plane;receiver.position=Vector3(192,-4,192);view.add_child(receiver)
 var receiver_material:=StandardMaterial3D.new();receiver_material.albedo_color=Color(0.55,0.55,0.55);receiver.material_override=receiver_material
 var base:=Materials.compact_terrain_material();Materials.set_compact_terrain_roles(base,source.palette_surface_roles,source.palette_material_ids,source.palette);ground.material_override=Materials.compact_terrain_far_material(base)
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
 var previous_rid:=RID();var revision:=0
 var entry:Dictionary={"node":host}
 for kind in ["flat","slope","mixed"]:
  revision+=1
  var heights=source.heights;var tops=source.top_materials
  for z in 384:
   for x in 384:
    heights[x+z*384]=24 if kind=="flat" else 24+x/12+int(z/64)*2
    tops[x+z*384]=3 if kind=="mixed" and x>190 else 2
  source.heights=heights;source.top_materials=tops
  var job:=Builder.OverviewJob.new(source,Rect2i(0,0,384,384));job.run(func():return false)
  entry.data=job.result;entry.revision=revision
  var images:Array=[];var retained:RID
  for mode in [0,1,2,3,0]:
   var covered:Dictionary={}
   for key:Vector2i in entry.data.patches:
    if mode==3 or (mode==1 and key.x<3) or (mode==2 and (key.x+key.y)%2==0):covered[key]=true
   var reference:ArrayMesh=projection._overview_mesh(entry.data.arrays,entry.data.patches,covered)
   var expected:=await picture(view,ground,reference,reference.get_surface_count()>0)
   # Restore the production instance; reference capture must not invalidate retained state.
   if entry.has("ground_coverage"):ground.mesh=entry.ground_coverage.mesh
   update(projection,entry,covered)
   var candidate:Mesh=ground.mesh;var visible:=ground.visible
   check(expected==await picture(view,ground,candidate,visible),"exact native pixels/shadows "+kind+str(mode))
   images.append(expected)
   if mode==0 and not retained.is_valid():retained=candidate.get_rid()
   check(candidate.get_rid()==retained,"same mesh RID across coverage "+kind+str(mode))
   if mode==3:check(not visible,"fully covered ground hidden "+kind)
   if candidate.get_surface_count()>0 and visible:
    var actual:PackedInt32Array=candidate.surface_get_arrays(0)[Mesh.ARRAY_INDEX];var at:=0;var exact:=true
    for key:Vector2i in entry.data.patches:
     var span:Vector2i=entry.data.patches[key]
     for i in range(span.x,span.x+span.y):
      if at>=actual.size() or actual[at]!=(0 if covered.has(key) else i):exact=false
      at+=1
    check(exact,"GPU index content exact "+kind+str(mode))
  check(images[0]!=images[3] and images[1]!=images[2] and images[0]==images[4],"nonblank masks and return "+kind)
  check(retained!=previous_rid,"new source revision owns new mesh "+kind);previous_rid=retained
  var with_shadows:=await picture(view,ground,ground.mesh,true);sun.shadow_enabled=false
  check(with_shadows!=await picture(view,ground,ground.mesh,true),"shadow receiver active "+kind);sun.shadow_enabled=true
  var legacy:Array=[];var updates:Array=[];var half:Dictionary={}
  for key:Vector2i in entry.data.patches:
   if key.x<3:half[key]=true
  for i in 80:
   var mask:Dictionary=half if i%2==0 else {}
   var started:=Time.get_ticks_usec();var rebuilt:ArrayMesh=projection._overview_mesh(entry.data.arrays,entry.data.patches,mask);legacy.append(Time.get_ticks_usec()-started)
   started=Time.get_ticks_usec();update(projection,entry,mask);updates.append(Time.get_ticks_usec()-started)
   await process_frame
  legacy.sort();updates.sort()
  var began:=Time.get_ticks_usec()
  for i in 200:update(projection,entry,{})
  report.append({"kind":kind,"unchanged200_us":Time.get_ticks_usec()-began,"legacy_median_us":legacy[39],"legacy_p95_us":legacy[75],"update_median_us":updates[39],"update_p95_us":updates[75]})
 projection.free();view.free();await process_frame
 print("OVERVIEW_INDICES ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"report":report}));quit(0 if errors.is_empty() else 1)
