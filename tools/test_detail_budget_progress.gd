extends SceneTree
## Background scatter must progress even when unrelated editor/UI work takes
## longer than the shared preparation allowance between producer and timer.
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class GroundProducer extends Node:
	var context:RefCounted
	var full_budget:=false
	func _process(_dt):
		var began:=Time.get_ticks_usec()
		context.remaining_us()
		OS.delay_usec(10000 if full_budget else 500)
		if context.has_method("finish_ground"):context.finish_ground(began)
class UnrelatedWork extends Node:
	func _process(_dt):OS.delay_msec(12)
class Consumer extends Node:
	var _detail_priority_pending:=false
	var done:=false
	func work(context:RefCounted):
		if await context.wait_for_turn(self):done=true
func _initialize():run.call_deferred()
func run():
	var projection:=Node3D.new();root.add_child(projection)
	var context=Preparation.for_projection(projection)
	var producer:=GroundProducer.new();producer.context=context;projection.add_child(producer)
	var unrelated:=UnrelatedWork.new();projection.add_child(unrelated)
	var consumer:=Consumer.new();projection.add_child(consumer);consumer.work(context)
	for i in 8:
		await process_frame
		if consumer.done:break
	var passed:=consumer.done
	producer.full_budget=true
	var blocked:=Consumer.new();projection.add_child(blocked);blocked.work(context)
	for i in 4:await process_frame
	var ground_priority:=not blocked.done
	producer.full_budget=false
	for i in 8:
		await process_frame
		if blocked.done:break
	passed=passed and ground_priority and blocked.done
	print("DETAIL_BUDGET_PROGRESS ",JSON.stringify({"pass":passed,"consumer_finished":consumer.done,"ground_priority":ground_priority,"resumed_after_ground":blocked.done}))
	Preparation.release_projection(projection);projection.free();await process_frame
	quit(0 if passed else 1)
