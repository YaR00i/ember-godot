extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class World extends Node3D:
 var complete:=false
 func is_world_preparation_complete()->bool:return complete
class Host extends Node:
 var _detail_priority_pending:=false
class Focus extends Node3D:
 var _live_brush_active:=false
 func begin_live_brush()->void:_live_brush_active=true
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
 if not ok:errors.append(label);printerr("DETAIL_FRAME_BUDGET_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var world:=World.new();root.add_child(world)
 var map:=Node3D.new();world.add_child(map)
 var projection:=Focus.new();map.add_child(projection)
 var context=Preparation.for_projection(projection)
 check(context.frame_budget_us()==5000,"covered startup keeps the existing five ms allowance")
 world.complete=true
 check(context.frame_budget_us()==3000,"revealed world uses the proven three ms allowance")
 projection.begin_live_brush()
 check(context.frame_budget_us()==5000,"active authoring keeps room for the existing four ms brush slice")
 projection._live_brush_active=false
 context._foreground_frame=Engine.get_process_frames();context._foreground_us=1000
 var started:=Time.get_ticks_usec();context._poll_budget_waiters()
 var remaining:int=context._deadline-Time.get_ticks_usec()
 check(remaining>1000 and remaining<=2000,"gameplay deadline subtracts already charged ground/detail work")
 check(context._deadline<=started+3000,"mode query cannot add a fresh allowance on top")
 Preparation.release_projection(projection)
 context=Preparation.for_projection(projection)
 check(context.frame_budget_us()==3000,"replacement projection context reads the same world readiness")
 var other:=Node3D.new();root.add_child(other);map.reparent(other)
 check(context.frame_budget_us()==5000,"reparent cannot retain an unrelated world phase")
 var canvas=load("res://scripts/world_canvas.gd").new()
 check(not canvas.is_world_preparation_complete(),"actual WorldCanvas starts behind its barrier")
 canvas._startup_complete=true;check(canvas.is_world_preparation_complete(),"actual owner exposes its existing completion state")
 canvas.free();Preparation.release_projection(projection);world.free();other.free();await process_frame
 print("DETAIL_FRAME_BUDGET ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
 quit(0 if errors.is_empty() else 1)
