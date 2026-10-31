extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class FocusProjection extends Node3D:
	var focus:=Vector3.ZERO
	func detail_world_anchor()->Vector3:return focus
	func detail_preparation_band(area:Rect2)->int:return int(absf(area.position.x-focus.x))
class Consumer extends Node3D:
	var rank:=0
	var _detail_priority_pending:=false
	var _detail_resident:=true
	var finished:=false
	func _world_area()->Rect2:return Rect2(Vector2(rank,0),Vector2.ONE)
	func work(context:RefCounted,label:int,order:Array,steps:=2):
		for i in steps:
			if not await context.wait_for_turn(self):finished=true;return
			order.append(label);context._deadline=0
		finished=true
var errors:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("DETAIL_VISIBLE_FAIL ",label)
func _initialize():run.call_deferred()
func run():
	var policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd").new()
	check(policy.preparation_band(Rect2(Vector2(128,0),Vector2.ONE*64))==2,"distance bands use source metres")
	policy.enabled=false
	check(policy.preparation_band(Rect2(Vector2(128,0),Vector2.ONE*64))==0,"disabled distance policy keeps one fair band")
	var projection:=FocusProjection.new();root.add_child(projection)
	var context=Preparation.for_projection(projection);var order:Array=[];var jobs:Array[Consumer]=[]
	for rank in [20,0,0]:
		var job:=Consumer.new();job.rank=rank;projection.add_child(job);jobs.append(job);job.work(context,jobs.size()-1,order)
	for i in 6:context._poll_budget_waiters()
	check(order==[1,2,1,2,0,0],"near bands finish before distant work; equal-band jobs remain fair")
	var far:=Consumer.new();far.rank=20;projection.add_child(far);far.work(context,3,order,1)
	var near:=Consumer.new();projection.add_child(near);near.work(context,4,order,1)
	context.prioritize(far);context._poll_budget_waiters()
	check(order[-1]==3,"author edit wins over distance")
	context._poll_budget_waiters()
	near.work(context,5,order,1);far.work(context,6,order,1);projection.focus.x=20
	context._poll_budget_waiters();check(order[-1]==6,"camera change reranks queued work")
	context._poll_budget_waiters()
	far.work(context,7,order,1);far._detail_resident=false;context._poll_budget_waiters()
	check(far.finished and not 7 in order,"leaving residency cancels stale queued scatter")
	near.work(context,8,order,1);projection.remove_child(near);context._poll_budget_waiters()
	check(near.finished and not 8 in order,"Undo removal cancels queued work before querying its old world area")
	near.free()
	far._detail_resident=true;far.work(context,9,order,1)
	Preparation.cancel_patch(far)
	check(far.finished and not 9 in order and not context.has_pending_work(),"explicit unload releases a waiting coroutine immediately without another budget turn")
	Preparation.release_projection(projection);projection.free();await process_frame
	print("DETAIL_VISIBLE_PRIORITY ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"order":order}));quit(0 if errors.is_empty() else 1)
