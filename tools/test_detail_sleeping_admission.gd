extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class Focus extends Node3D:
 var detail_policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd").new()
 func editor_detail_active()->bool:return detail_policy.enabled
class Host extends "res://scripts/ember_grass_patch.gd":
 var focus:Focus
 var polls:=0
 var span:=64.0
 func _ready()->void:pass
 func _world_area()->Rect2:return Rect2(Vector2(global_position.x,global_position.z),Vector2.ONE*span)
 func _process(_delta:float)->void:
  polls+=1;_detail_resident=focus.detail_policy.detail_resident(_world_area(),false)
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);printerr("DETAIL_ADMISSION_FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var map:=Node3D.new();root.add_child(map)
 var projection:=Focus.new();map.add_child(projection)
 var context=Preparation.for_projection(projection);var hosts:Array[Host]=[]
 for i in 25000:
  var host:=Host.new();host.focus=projection;host.position=Vector3(10000+(i%160)*64,0,10000+(i/160)*64)
  map.add_child(host);host._detail_resident=false;context.sleep_patch(host);hosts.append(host)
 var outside:=Host.new();outside.focus=projection;outside.position=Vector3(640,0,528)
 map.add_child(outside);outside._detail_resident=false;context.sleep_patch(outside)
 var target:=Host.new();target.focus=projection;target.position=Vector3(640,0,0)
 map.add_child(target);target._detail_resident=false;context.sleep_patch(target)
 projection.detail_policy.anchor=Vector2(640,0)
 for i in 4:context.poll_sleeping()
 check(target._detail_resident and target.is_processing(),"new near patch wakes without scanning 25000 distant patches first")
 check(outside.polls==0,"broad-bin neighbour outside exact prepare radius does no patch work")
 projection.detail_policy.anchor=Vector2(640,64)
 for i in 4:context.poll_sleeping()
 check(outside._detail_resident and outside.is_processing(),"neighbour wakes immediately on entering exact prepare radius")
 projection.detail_policy.anchor=Vector2(640,0)
 var resized:=Host.new();resized.focus=projection;resized.span=8;resized.position=Vector3(640,0,-528)
 map.add_child(resized);resized._detail_resident=false;context.sleep_patch(resized)
 for i in 4:context.poll_sleeping()
 check(resized.polls==0,"small sleeping footprint remains outside prepare radius")
 resized.span=128
 for i in 4:context.poll_sleeping()
 check(resized._detail_resident,"live footprint enlargement bypasses the old distant bounds")
 var far_polls:=0
 for host in hosts:far_polls+=host.polls
 check(far_polls==0,"far admission does no repeated surface work")
 hosts[0].position=Vector3(648,0,8)
 await process_frame;await process_frame
 for i in 4:context.poll_sleeping()
 check(hosts[0]._detail_resident,"moving a sleeping patch updates its admission cell")
 var large:=Host.new();large.focus=projection;large.span=20000;large.position=Vector3(-10000,0,-10000)
 map.add_child(large);large._detail_resident=false;context.sleep_patch(large)
 check(context._sleeping_large.has(large.get_instance_id()),"oversized patches avoid unbounded bin expansion")
 for i in 4:context.poll_sleeping()
 check(large._detail_resident,"oversized patch still uses exact residency")
 var remaining:int=context._sleeping.size();hosts[1].free()
 check(context._sleeping.size()==remaining-1,"removed sleeping patch unregisters immediately")
 projection.detail_policy.enabled=false
 for i in 4:context.poll_sleeping()
 check(hosts[2].is_processing(),"disabled distance policy can wake the full field")
 Preparation.release_projection(projection);map.free();await process_frame
 print("DETAIL_SLEEPING_ADMISSION ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"distant_polls":far_polls}))
 quit(0 if errors.is_empty() else 1)
