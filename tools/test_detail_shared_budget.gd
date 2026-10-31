extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class Foreground extends Node:
 var context:RefCounted
 var heavy:=true
 func _process(_dt):
  context.begin_ground()
  # Nested sleeping admission is already inside the outer ground slice.
  context.finish_detail(Time.get_ticks_usec()-Preparation.FRAME_US*2)
  context.finish_ground(Time.get_ticks_usec()-Preparation.FRAME_US/2)
  # This callback runs outside ground and must debit the same allowance.
  context.finish_detail(Time.get_ticks_usec()-(Preparation.FRAME_US+1000 if heavy else Preparation.FRAME_US/8))
class Consumer extends Node:
 var _detail_priority_pending:=false
 var done:=false
 func wait_turn(context:RefCounted):
  if await context.wait_for_turn(self):done=true
func _initialize():run.call_deferred()
func run():
 var precharged:=Node3D.new();root.add_child(precharged)
 var earlier=Preparation.for_projection(precharged)
 earlier.finish_detail(Time.get_ticks_usec()-Preparation.FRAME_US*2)
 var earlier_charged:bool=earlier.remaining_us()==0
 Preparation.release_projection(precharged);precharged.free()
 var projection:=Node3D.new();root.add_child(projection)
 var context=Preparation.for_projection(projection)
 var foreground:=Foreground.new();foreground.context=context;projection.add_child(foreground)
 var consumer:=Consumer.new();projection.add_child(consumer);consumer.wait_turn(context)
 for i in 4:await process_frame
 var charged:=not consumer.done
 foreground.heavy=false
 for i in 8:
  await process_frame
  if consumer.done:break
 var passed:bool=earlier_charged and charged and consumer.done
 print("DETAIL_SHARED_BUDGET ",JSON.stringify({"pass":passed,"active_detail_charged":charged,"nested_detail_counted_once":consumer.done}))
 Preparation.release_projection(projection);projection.free();await process_frame;quit(0 if passed else 1)
