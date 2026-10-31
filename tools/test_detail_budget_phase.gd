extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class Marker extends Node:
	var frame:=-1
	func _process(_dt):frame=Engine.get_process_frames()
class Consumer extends Node:
	var _detail_priority_pending:=false
	var done:=false
	var after_nodes:=false
	func wait_budget(context:RefCounted,marker:Node):
		if await context.wait_for_turn(self):after_nodes=marker.frame==Engine.get_process_frames()
		done=true
func _initialize():run.call_deferred()
func run():
	var projection:=Node3D.new();root.add_child(projection)
	var marker:=Marker.new();projection.add_child(marker)
	var consumer:=Consumer.new();projection.add_child(consumer)
	var context=Preparation.for_projection(projection)
	consumer.wait_budget(context,marker)
	var deadline:=Time.get_ticks_msec()+3000
	while not consumer.done and Time.get_ticks_msec()<deadline:await process_frame
	var passed:=consumer.done and consumer.after_nodes
	print("DETAIL_BUDGET_PHASE ",JSON.stringify({"pass":passed,"after_node_processing":consumer.after_nodes}))
	Preparation.release_projection(projection);projection.free();await process_frame;quit(0 if passed else 1)
