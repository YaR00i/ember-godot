extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
const GrassPatch=preload("res://scripts/ember_grass_patch.gd")
class ProbePatch extends Node3D:
	var _detail_poll_projection_id:=0
	var _detail_resident:=false
	var _dirty:=false
	var near:=false
	var calls:=0
	var _detail_priority_pending:=false
	var finished:=false
	func budget_job(context:RefCounted,label:int,order:Array):
		while await context.wait_for_turn(self):
			order.append(label)
			context._deadline=0 # Simulate one job using the rest of this frame.
		finished=true
	func _process(_dt:float):
		calls+=1
		_detail_resident=near
var errors:Array[String]=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("DETAIL_SLEEP_FAIL ",label)
func run():
	var projection:=Node3D.new();root.add_child(projection)
	var context=Preparation.for_projection(projection)
	var patches:Array[ProbePatch]=[]
	for i in 1500:
		var patch:=ProbePatch.new();projection.add_child(patch);patches.append(patch);context.sleep_patch(patch)
	check(not patches[0].is_processing() and patches[0].can_process(),"sleep stops callbacks without disabling ancestry")
	await process_frame;await process_frame
	var calls:=0
	for patch in patches:calls+=patch.calls
	check(calls==0,"distant nodes get no per-frame callbacks")
	context.poll_sleeping()
	calls=0
	for patch in patches:calls+=patch.calls
	check(calls>0 and calls<=512,"one bounded sweep, not a whole-map traversal")
	patches[-1].near=true
	for i in 20:context.poll_sleeping()
	check(patches[-1].is_processing() and patches[-1]._detail_resident,"round-robin wakes the new near area")
	var paused:=Node3D.new();projection.add_child(paused);paused.process_mode=Node.PROCESS_MODE_DISABLED
	var child:=ProbePatch.new();paused.add_child(child);context.sleep_patch(child)
	for i in 10:context.poll_sleeping()
	check(child.calls==0,"disabled parent is respected")
	paused.process_mode=Node.PROCESS_MODE_INHERIT;child.near=true
	for i in 10:context.poll_sleeping()
	check(child.is_processing(),"resuming parent allows normal wake")
	patches[10].free()
	for i in 10:context.poll_sleeping()
	check(context._sleeping_order.size()<1500,"freed weak nodes are removed")
	var order:Array=[];var jobs:Array[ProbePatch]=[]
	for i in 3:
		var patch:=ProbePatch.new();projection.add_child(patch);jobs.append(patch);patch.budget_job(context,i,order)
	for i in 6:
		context._frame=Engine.get_process_frames();context._deadline=Time.get_ticks_usec()+8000;context._poll_budget_waiters()
	check(order==[0,1,2,0,1,2],"exhausted jobs rejoin the tail, without signal-order starvation")
	context.prioritize(jobs[2]);context._deadline=Time.get_ticks_usec()+8000;context._poll_budget_waiters()
	check(order[-1]==2,"an author's change takes the next available turn")
	var cancelled:=ProbePatch.new();projection.add_child(cancelled);cancelled.budget_job(context,99,order);cancelled.free()
	context._deadline=Time.get_ticks_usec()+8000;context._poll_budget_waiters()
	var real_patch:=GrassPatch.new();projection.add_child(real_patch);context.sleep_patch(real_patch)
	real_patch._detail_preview={"cells":{}}
	check(real_patch.is_processing(),"brush preview immediately wakes a real grass patch")
	context.sleep_patch(real_patch);real_patch.density_cells={Vector2i(1,1):64.0}
	check(real_patch.is_processing(),"mask edit immediately wakes a real grass patch")
	context.sleep_patch(real_patch);projection.remove_child(real_patch)
	check(real_patch.is_processing() and real_patch._detail_poll_projection_id==0,"Undo removal clears sleeping state")
	projection.add_child(real_patch)
	check(real_patch.is_processing(),"Redo reattachment works without another ready callback")
	Preparation.release_projection(projection)
	check(patches[0].is_processing() and patches[0]._dirty,"projection replacement wakes and invalidates surviving nodes")
	for patch in jobs:check(patch.finished,"projection release cancels queued coroutine turns")
	projection.free();await process_frame
	print("DETAIL_SLEEPING ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)
