extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
const Storage=preload("res://scripts/prototypes/ember_derived_data_cache.gd")
class SlowDisk extends "res://scripts/prototypes/ember_derived_data_cache.gd":
	func read(key:String)->Dictionary:
		OS.delay_msec(80)
		return super.read(key)
class Host extends Node:
	var _detail_priority_pending:=false
class Heartbeat extends Node:
	var ticks:=0
	func _process(_delta:float)->void:ticks+=1
class QuietMap extends EmberMapLoader:
	func _ready()->void:pass
var errors:Array[String]=[]
var projection:Node3D
var context:RefCounted
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("DETAIL_CACHE_READ_FAIL ",label)
func _initialize()->void:run.call_deferred()
func request(key:String,host:Node,state:Dictionary,cancelled:Callable)->void:
	var result:Dictionary
	# The old synchronous path is an executable RED control for this regression.
	if context.has_method("read_async"):result=await context.read_async(key,host,cancelled)
	else:result=context.read(key)
	state.result=result;state.done=true
func wait_done(states:Array)->void:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		var done:=true
		for state:Dictionary in states:done=done and state.get("done",false)
		if done:return
		await process_frame
	check(false,"read consumers finish")
func run()->void:
	Engine.max_fps=240
	var map:=Node3D.new();root.add_child(map)
	projection=Node3D.new();map.add_child(projection);context=Preparation.for_projection(projection)
	context.disk=SlowDisk.new();context.disk.directory="user://ember-tests/detail-cache-read-%d"%OS.get_process_id()
	var directory:String=context.disk.directory
	var looks:Dictionary={0:[Transform3D.IDENTITY],1:[Transform3D.IDENTITY],2:[Transform3D.IDENTITY]}
	context.disk.write("valid",{"looks":looks},func():return false)
	var host:=Host.new();map.add_child(host)
	var heartbeat:=Heartbeat.new();root.add_child(heartbeat)
	var state:Dictionary={};var before:=heartbeat.ticks;var started:=Time.get_ticks_usec()
	request("valid",host,state,func():return false)
	var producer_us:=Time.get_ticks_usec()-started
	check(producer_us<40000,"slow cache read does not block its calling frame")
	await wait_done([state])
	check(heartbeat.ticks-before>=2,"frames continue while storage/decoding is pending")
	check(state.result==looks,"validated transforms roundtrip exactly")
	if not context.has_method("read_async"):
		Preparation.release_projection(projection);map.free();heartbeat.free()
		print("DETAIL_CACHE_READ ",JSON.stringify({"pass":false,"errors":errors,"producer_us":producer_us}));quit(1);return
	# All transport settings belong to the accepted request, even if a new map
	# or test cache changes the transport's directory before the read completes.
	state={};request("valid",host,state,func():return false)
	context.disk.directory=directory.path_join("other")
	context.disk.write("valid",{"looks":{0:[Transform3D(Basis.IDENTITY,Vector3(99,0,0))]}},func():return false)
	await wait_done([state]);check(state.result==looks,"reader owns a private settings snapshot")
	context.disk.directory=directory
	state={};request("valid",host,state,func():return true)
	await wait_done([state]);check(state.result.is_empty() and context._cache_reads.is_empty(),"pre-cancelled request schedules no read")
	var cancelled:Dictionary={"value":false}
	state={};request("valid",host,state,func():return cancelled.value)
	cancelled.value=true;await wait_done([state]);check(state.result.is_empty(),"source invalidation discards an in-flight hit")
	var bad:=Transform3D.IDENTITY;bad.origin.x=INF
	for entry in [{"key":"nonfinite","looks":{0:[bad]}},{"key":"wrongtype","looks":{0:[Vector3.ZERO]}},{"key":"wronglook","looks":{3:[Transform3D.IDENTITY]}}]:
		context.disk.write(entry.key,{"looks":entry.looks},func():return false)
		state={};request(entry.key,host,state,func():return false);await wait_done([state])
		check(state.result.is_empty(),"malformed payload rejected: "+entry.key)
	var packaged:=Storage.new();packaged.directory=directory.path_join("packaged")
	packaged.write("pack",{"looks":looks},func():return false)
	context.disk.directory=directory.path_join("empty")
	context.disk.packaged_directory=packaged.directory;context.disk.packaged_for_directory=context.disk.directory
	state={};request("pack",host,state,func():return false);await wait_done([state])
	check(state.result==looks and context.disk.packaged_hits>0,"packaged fallback settings survive worker transport")
	context.disk.directory=directory;context.disk.packaged_directory="";context.disk.packaged_for_directory=""
	var states:Array=[]
	for i in 8:
		var item:Dictionary={};states.append(item);request("valid",host,item,func():return false)
	check(context._cache_reads.size()<=2,"concurrent reads are bounded")
	# Finish the two workers without allowing a budget turn. Completed payloads
	# must still occupy those slots, rather than accumulating in waiting callers.
	for job in context._cache_reads:
		while not WorkerThreadPool.is_task_completed(job.task):OS.delay_msec(1)
	context._foreground_frame=Engine.get_process_frames();context._foreground_us=Preparation.FRAME_US
	context._frame=-1;context._finish_cache_reads()
	check(context._cache_reads.size()==2,"completed results retain slots until budgeted delivery")
	context._foreground_frame=-1;context._foreground_us=0;context._frame=-1
	await wait_done(states)
	for item:Dictionary in states:check(item.result==looks,"bounded queue eventually delivers exact results")
	state={};request("valid",host,state,func():return false)
	Preparation.cancel_patch(host);host.free()
	await wait_done([state]);check(state.result.is_empty(),"removed patch receives no stale hit")
	host=Host.new();map.add_child(host)
	states=[]
	for i in 6:
		var item:Dictionary={};states.append(item);request("valid",host,item,func():return false)
	Preparation.release_projection(projection)
	check(context._cache_reads.is_empty() and context._released,"teardown joins all readers")
	await wait_done(states)
	for item:Dictionary in states:check(item.result.is_empty(),"teardown wakes cancelled consumers")
	map.free();heartbeat.free();await process_frame
	# Ordinary unpainted scatter also snapshots voxel-object obstruction bounds.
	# Its existing currentness check must see object edits during a cache await.
	var obstruction_map:=QuietMap.new();root.add_child(obstruction_map)
	var patch=load("res://scripts/ember_grass_patch.gd").new();obstruction_map.add_child(patch);patch.set_process(false)
	patch.painted_only=false;patch._detail_resident=true;patch._dirty=false
	patch._watch_object_surface(obstruction_map,true)
	obstruction_map.surface_object_changed.emit(AABB(Vector3.ZERO,Vector3.ONE*16))
	check(patch._dirty,"object edits invalidate an unpainted patch's pending read")
	patch._dirty=false
	obstruction_map.surface_object_changed.emit(AABB(Vector3.ONE*10000,Vector3.ONE*16))
	check(not patch._dirty,"unrelated distant object edits retain a valid pending read")
	patch.detail_kind=3;patch._visual.material_override=ShaderMaterial.new()
	patch._dirty=false;patch._rebuilding=true
	patch._cover_changed() # No valid cover: the old in-flight candidate cannot publish.
	check(patch._dirty and not patch._visual.visible,"invalid cover invalidates pending publication")
	patch._rebuilding=false
	patch._dirty=false;patch._rebuilding=true
	check(not await patch._wait_preparation(obstruction_map,null),"removed projection cannot create a new preparation context")
	check(not patch._rebuilding and patch._pending_material==null,"cancel clears the candidate material")
	obstruction_map.free()
	print("DETAIL_CACHE_READ ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"producer_us":producer_us}))
	quit(0 if errors.is_empty() else 1)
