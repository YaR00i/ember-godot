extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
class Host extends Node:
 var _detail_priority_pending:=false
 var band:=0
class SpatialHost extends Host:
 var _detail_resident:=true
 var queries:=0
 func _world_area()->Rect2:return Rect2(Vector2.ZERO,Vector2.ONE)
class SpatialContext extends Context:
 var order_calls:=0
 func _order_budget_waiters()->void:
  order_calls+=1
  super._order_budget_waiters()
 func _preparation_band(host:Node)->int:
  host.queries+=1
  return host.band
class Context extends Preparation:
 var retry_delay_us:=0
 func wait_for_turn(host:Node)->bool:
  var ok:=await super.wait_for_turn(host)
  if ok and host.band==0 and retry_delay_us>0:OS.delay_usec(retry_delay_us)
  return ok
 func _preparation_band(host:Node)->int:return host.band
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);printerr("DETAIL_TURN_FAIRNESS_FAIL ",label)
func blocked(context:Context,host:Host,state:Dictionary)->void:
 while not state.free:
  if not await context.wait_for_turn(host):state.cancelled=true;return
 state.near_done=true
func owner(context:Context,host:Host,state:Dictionary)->void:
 if await context.wait_for_turn(host):state.free=true;state.owner_done=true
func cancel_other(context:Context,host:Host,target:Host,state:Dictionary)->void:
 if await context.wait_for_turn(host):context._cancel_patch(target);state.owner_done=true
func close_context(context:Context,host:Host)->void:
 if await context.wait_for_turn(host):context._release()
func material(context:Context,host:Host,state:Dictionary)->void:
 state.ok=await context.bind_saved_material_roles_async(Materials.compact_flower_material(),PackedStringArray(),PackedStringArray(),PackedColorArray(),host,func():return false)
 state.done=true
func read_cache(context:Context,host:Host,state:Dictionary)->void:
 state.result=await context.read_async("valid",host,func():return false)
 state.done=true
func _initialize()->void:run.call_deferred()
func make_context(projection:Node3D)->Context:
 var context:=Context.new();context.projection_ref=weakref(projection);return context
func run()->void:
 var projection:=Node3D.new();root.add_child(projection)
 var near:=Host.new();var far:=Host.new();far.band=4;projection.add_child(near);projection.add_child(far)
 var context:=make_context(projection)
 var state:Dictionary={"free":false,"owner_done":false,"near_done":false,"cancelled":false}
 blocked(context,near,state);owner(context,far,state)
 for i in 8:context._poll_budget_waiters()
 check(state.owner_done and state.near_done,"near slot waiter cannot starve the far owner that releases the slot")
 context._release()
 var spatial:=SpatialHost.new();projection.add_child(spatial)
 var zero_context:=SpatialContext.new();zero_context.projection_ref=weakref(projection)
 var zero_state:Dictionary={"free":false,"owner_done":false}
 owner(zero_context,spatial,zero_state)
 var initial_queries:=spatial.queries
 zero_context._foreground_frame=Engine.get_process_frames();zero_context._foreground_us=zero_context.frame_budget_us()
 zero_context._poll_budget_waiters()
 check(not zero_state.owner_done and spatial.queries==initial_queries and zero_context.order_calls==0,"zero remaining budget skips nonempty spatial queue ordering")
 zero_context._cancel_patch(spatial)
 check(not zero_context.has_pending_work(),"explicit cancellation remains synchronous at zero remaining budget")
 zero_context._release()
 context=make_context(projection);state={"free":false,"owner_done":false,"near_done":false,"cancelled":false}
 blocked(context,near,state);cancel_other(context,far,near,state);context._poll_budget_waiters()
 check(state.owner_done and state.cancelled,"patch cancellation reaches a turn requeued during dispatch")
 check(not context.has_pending_work(),"cancelled next-frame turns do not retain work")
 context._release()
 context=make_context(projection);state={"free":false,"owner_done":false,"near_done":false,"cancelled":false}
 blocked(context,near,state);close_context(context,far);context._poll_budget_waiters()
 check(context._released and state.cancelled and not context.has_pending_work(),"context teardown cancels current and next-frame consumers")
 context=make_context(projection)
 var distant:Dictionary={};var nearer:Dictionary={}
 material(context,far,distant);material(context,near,nearer)
 context._finish_material_digest(true)
 for i in 8:
  context._poll_budget_waiters();context._finish_material_digest(true)
 check(distant.get("done",false) and distant.get("ok",false) and nearer.get("done",false) and nearer.get("ok",false),"actual material digest owner releases its slot despite near waiters")
 context._release()
 context=make_context(projection)
 context.disk.directory="user://qa-turn-fairness-%d"%OS.get_process_id()
 context.disk.write("valid",{"looks":{0:[Transform3D.IDENTITY]}},func():return false)
 var second:=Host.new();second.band=5;projection.add_child(second)
 var first_read:Dictionary={};var second_read:Dictionary={};var near_read:Dictionary={}
 read_cache(context,far,first_read);read_cache(context,second,second_read);read_cache(context,near,near_read)
 context._finish_cache_reads(true)
 for i in 8:
  context._poll_budget_waiters();context._finish_cache_reads(true)
 for item in [first_read,second_read,near_read]:check(item.get("done",false) and item.get("result",{}).has(0),"actual far read result releases one of the two bounded slots")
 context._release()
 # More front-band retries than fit into one frame must not keep a completed
 # bounded result's owner waiting forever in a farther spatial band.
 context=make_context(projection);context.retry_delay_us=250
 distant={};material(context,far,distant)
 for i in 40:
  var waiter:=Host.new();projection.add_child(waiter);material(context,waiter,{})
 context._finish_material_digest(true)
 for i in 4:
  context._poll_budget_waiters();context._finish_material_digest(true)
 check(distant.get("done",false) and distant.get("ok",false),"dense near retries allow completed material owner to deliver")
 context._release()
 context=make_context(projection);context.retry_delay_us=250
 context.disk.directory="user://qa-turn-fairness-dense-%d"%OS.get_process_id()
 context.disk.write("valid",{"looks":{0:[Transform3D.IDENTITY]}},func():return false)
 first_read={};second_read={}
 read_cache(context,far,first_read);read_cache(context,second,second_read)
 for i in 40:
  var waiter:=Host.new();projection.add_child(waiter);read_cache(context,waiter,{})
 context._finish_cache_reads(true)
 for i in 4:
  context._poll_budget_waiters();context._finish_cache_reads(true)
 for item in [first_read,second_read]:check(item.get("done",false) and item.get("result",{}).has(0),"dense near retries allow completed cache owners to deliver")
 context._release()
 projection.free();await process_frame
 print("DETAIL_TURN_FAIRNESS ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
 quit(0 if errors.is_empty() else 1)
