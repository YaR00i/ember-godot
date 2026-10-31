extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class Map extends Node3D:
 var imported_tile_size:=1.0
class Focus extends Node3D:
 var detail_policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd").new()
 var document:=Resource.new()
 var _live_brush_active:=false
 var revision:=0
 func column_revision()->int:return revision
 func editor_detail_active()->bool:return detail_policy.enabled
 func detail_world_anchor()->Vector3:return Vector3(detail_policy.anchor.x,0,detail_policy.anchor.y)
class Host extends "res://scripts/ember_grass_patch.gd":
 var focus:Focus
 var area_reads:=0
 var polls:=0
 func _ready()->void:pass
 func _world_area()->Rect2:
  area_reads+=1
  return Rect2(Vector2(global_position.x,global_position.z),size_blocks)
 func _process(_delta:float)->void:
  polls+=1;_detail_resident=focus.detail_policy.detail_resident(_world_area(),false)
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);printerr("DETAIL_SLEEPING_EPOCH_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var map:=Map.new();root.add_child(map)
 var focus:=Focus.new();map.add_child(focus)
 var context=Preparation.for_projection(focus)
 var hosts:Array[Host]=[]
 for i in 512:
  var host:=Host.new();host.focus=focus;host.size_blocks=Vector2.ONE*8
  host.position=Vector3(520+(i%16)*2,0,-16+(i/16)*2)
  map.add_child(host);context.sleep_patch(host);hosts.append(host)
 for i in 8:context.poll_sleeping()
 var before:=0
 for host in hosts:before+=host.area_reads
 var started:=Time.get_ticks_usec()
 for i in 128:context.poll_sleeping()
 var elapsed:=Time.get_ticks_usec()-started
 var repeated:=0
 for host in hosts:repeated+=host.area_reads
 repeated-=before
 check(repeated==0,"unchanged complete admission sweep does not read 512 footprints again")
 focus.detail_policy.anchor=Vector2(64,0);context.invalidate_detail_poll()
 for i in 8:context.poll_sleeping()
 check(hosts[0]._detail_resident,"moving anchor inside the same bin admits newly near patch")
 var resized:=Host.new();resized.focus=focus;resized.size_blocks=Vector2.ONE*8;resized.position=Vector3(0,0,-540)
 map.add_child(resized);context.sleep_patch(resized)
 for i in 8:context.poll_sleeping()
 check(not resized._detail_resident,"small footprint starts outside")
 resized.size_blocks=Vector2.ONE*128
 for i in 8:context.poll_sleeping()
 check(resized._detail_resident,"resizing a sleeping footprint invalidates completed sweep")
 var moved:=Host.new();moved.focus=focus;moved.position=Vector3(10000,0,10000)
 map.add_child(moved);context.sleep_patch(moved)
 for i in 8:context.poll_sleeping()
 moved.position=Vector3(64,0,0)
 await process_frame;await process_frame
 for i in 8:context.poll_sleeping()
 check(moved._detail_resident,"transform notification invalidates completed sweep")
 var paused:=Node3D.new();map.add_child(paused);paused.process_mode=Node.PROCESS_MODE_DISABLED
 var child:=Host.new();child.focus=focus;child.position=Vector3(64,0,0)
 paused.add_child(child);context.sleep_patch(child)
 for i in 8:context.poll_sleeping()
 check(not child._detail_resident,"disabled ancestor prevents admission")
 paused.process_mode=Node.PROCESS_MODE_INHERIT
 for i in 8:context.poll_sleeping()
 check(child._detail_resident,"resuming ancestor retries admission without a policy change")
 var changing:=Host.new();changing.focus=focus;changing.position=Vector3(2000,0,0)
 map.add_child(changing);context.sleep_patch(changing)
 for i in 8:context.poll_sleeping()
 focus.detail_policy.detail_prepare_m=2100;context.invalidate_detail_poll()
 for i in 8:context.poll_sleeping()
 check(changing._detail_resident,"distance policy change invalidates completed sweep")
 focus.detail_policy.enabled=false;context.invalidate_detail_poll()
 for i in 8:context.poll_sleeping()
 check(context._sleeping.is_empty(),"disabling policy drains sleeping hosts")
 Preparation.release_projection(focus);map.free();await process_frame
 print("DETAIL_SLEEPING_EPOCH ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"repeated_area_reads":repeated,"stable_128_polls_us":elapsed}))
 quit(0 if errors.is_empty() else 1)
