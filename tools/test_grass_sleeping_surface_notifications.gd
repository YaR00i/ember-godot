extends SceneTree
class Map extends EmberMapLoader:
 func _ready()->void:pass
class Patch extends "res://scripts/ember_grass_patch.gd":
 var area_queries:=0
 func _ready()->void:super._ready()
 func _world_area()->Rect2:
  area_queries+=1
  return Rect2(Vector2(position.x,position.z),Vector2.ONE*64)
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);printerr("GRASS_SURFACE_NOTICE_FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var map:=Map.new();root.add_child(map);map.set_process(false)
 var far:Array[Patch]=[]
 for i in 25000:
  var patch:=Patch.new();patch.painted_only=true;patch.position=Vector3(10000+i*64,0,10000)
  map.add_child(patch);patch.set_process(false);patch._detail_resident=false;patch._dirty=true
  far.append(patch)
 var near:=Patch.new();near.painted_only=true;map.add_child(near);near.set_process(false);near._detail_resident=true;near._dirty=false
 var outside:=Patch.new();outside.painted_only=true;outside.position.x=512;map.add_child(outside);outside.set_process(false);outside._detail_resident=true;outside._dirty=false
 for patch in [near,outside]:
  if patch.has_method("_watch_object_surface"):patch._watch_object_surface(map,true)
 var connections:=map.surface_object_changed.get_connections().size()
 check(connections==2,"only resident patches subscribe to object changes")
 var began:=Time.get_ticks_usec()
 map.surface_object_changed.emit(AABB(Vector3.ZERO,Vector3(64,10,64)))
 var elapsed:=Time.get_ticks_usec()-began;var queries:=0
 for patch in far:queries+=patch.area_queries
 check(queries==0,"sleeping patches do no surface-area queries for object notifications")
 check(near._dirty and not outside._dirty,"resident overlap still invalidates only affected patches")
 far[0]._detail_resident=true;far[0]._dirty=false;far[0].position=Vector3.ZERO
 if far[0].has_method("_watch_object_surface"):far[0]._watch_object_surface(map,true)
 map.surface_object_changed.emit(AABB(Vector3.ZERO,Vector3(64,10,64)))
 check(far[0]._dirty,"a returned resident receives object invalidation")
 print("GRASS_SURFACE_NOTIFICATIONS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"distant_queries":queries,"emit_us":elapsed,"connections":connections}))
 map.free();await process_frame;quit(0 if errors.is_empty() else 1)
