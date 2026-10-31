extends SceneTree
const Layers=preload("res://scripts/ember_solid_material_layers.gd")
const Grove=preload("res://addons/ember_import/ember_grove_planner.gd")
class TestMap extends EmberMapLoader:
 func _ready(): pass
 func _process(_delta): pass
 func editor_object_detail_enabled() -> bool:return true
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 Engine.max_fps=0;OS.low_processor_usage_mode=false;OS.low_processor_usage_mode_sleep_usec=0
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 var results:Array=[]
 for id in ["vox_painted_rock_group","vox_earth_cliff_straight","vox_merge_20548286_0","vox_coastal_house"]:
  Layers._prepared.clear();EmberVoxelProp._solid_sources.clear()
  var map:=TestMap.new()
  var prop:EmberVoxelProp=load("res://prefabs/voxels/"+id+".tscn").instantiate();map.add_child(prop);prop.owner=map;root.add_child(map)
  var visual:MeshInstance3D=prop.get_node("Mesh")
  var base := visual.mesh as ArrayMesh
  var volume := bool(base.get_meta("solid_volume_boundary",false))
  var authored:=Grove.fingerprint(prop,map)
  var shape:=prop.authoring_collision_shape()
  check(base!=null,"far solid identified: "+id)
  if base == null: map.free();continue
  var original:Array=base.get("_surfaces").duplicate(true)
  var queued:=not map._prepare_object_far(prop)
  check((map._object_far_loading.is_empty()) if volume else queued,"preparation follows actual far needs: "+id)
  var deadline:=Time.get_ticks_msec()+20000
  while queued and Time.get_ticks_msec()<deadline:
   await process_frame
   map._finish_object_depth()
   map._finish_object_far()
   queued=not map._prepare_object_far(prop)
  check(not queued,"far preflight completes: "+id)
  var entry:Dictionary=Layers._prepared.get(base.get_instance_id(),{})
  var source := prop._solid_source() if not volume else null
  if not volume and not base.has_meta("solid_layer_faces"):
   check(not entry.is_empty(),"CPU worker prewarmed cache: "+id)
   if not entry.is_empty():
    var legacy:=Layers._prepare_data(base.surface_get_arrays(0),EmberVoxelPrefab.model_of(source.to_definition()))
    var actual:Dictionary=entry.data
    check(legacy.arrays==actual.arrays and legacy.image.get_data()==actual.image.get_data(),"legacy face arrays and image byte exact: "+id)
    check(legacy.faces==actual.faces and legacy.seams==actual.seams and legacy.cracks==actual.cracks,"face descriptors exact: "+id)
  prop.apply_object_detail(false)
  if volume: check(EmberVoxelProp._solid_sources.is_empty(),"volume far path never loads unused source: "+id)
  check(base.get("_surfaces")==original,"source unchanged: "+id)
  check(prop.authoring_collision_shape()==shape and Grove.fingerprint(prop,map)==authored,"physics and authored state unchanged: "+id)
  var far:=prop.object_detail_base()
  check(far.get_faces()==base.get_faces(),"far base physical positions unchanged: "+id)
  prop.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
  check(Grove.fingerprint(prop,map)==authored,"save strips derived state: "+id)
  prop.set_world_look(0)
  prop.apply_object_detail(true)
  check(prop.authoring_collision_shape()==shape and Grove.fingerprint(prop,map)==authored,"near return preserves object: "+id)
  if source != null: source.emit_changed()
  check(not Layers._prepared.has(base.get_instance_id()),"source change invalidates worker data: "+id)
  results.append({"id":id,"worker_data":not entry.is_empty()})
  map.free()
 print("FAR_PREPARATION_PARITY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"results":results}))
 quit(0 if errors.is_empty() else 1)
