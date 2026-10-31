extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class SlowDisk extends "res://scripts/prototypes/ember_derived_data_cache.gd":
	func write(key:String,payload:Dictionary,cancelled:Callable)->void:
		OS.delay_msec(80)
		super.write(key,payload,cancelled)
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("DETAIL_CACHE_WRITE_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var context:=Preparation.new();context.disk=SlowDisk.new()
	context.disk.directory="user://ember-tests/async-scatter-write-%d"%OS.get_process_id()
	var looks:Dictionary={0:[Transform3D.IDENTITY],1:[Transform3D.IDENTITY],2:[Transform3D.IDENTITY]}
	var started:=Time.get_ticks_usec()
	context.write("snapshot",looks,func():return false)
	var producer_us:=Time.get_ticks_usec()-started
	check(producer_us<40000,"a slow cache device does not block the publishing caller")
	looks[0][0]=Transform3D(Basis.IDENTITY,Vector3(99,0,0))
	context.write("cancelled",looks,func():return true)
	var node:=Node.new()
	context.write("live-object",{0:[node]},func():return false)
	context._release()
	node.free()
	var saved:Dictionary=context.disk.read("snapshot")
	check(saved.has("looks") and saved.looks[0][0].origin==Vector3.ZERO,"writer owns the immutable accepted snapshot")
	check(context.disk.read("cancelled").is_empty(),"cancelled producer schedules no persistence")
	check(context.disk.read("live-object").is_empty(),"live objects cannot cross the writer boundary")
	var bounded:=Preparation.new();bounded.disk=SlowDisk.new()
	bounded.disk.directory=context.disk.directory.path_join("bounded")
	for i in 32:bounded.write("item-%d"%i,looks,func():return false)
	check(bounded.cache_writes_skipped>0,"a slow writer cannot grow an unbounded queue")
	check(bounded._cache_writes.size()+int(bounded._cache_write_job!=null)<=Preparation.WRITE_QUEUE_LIMIT,"active and pending jobs share one count limit")
	check(bounded._cache_write_bytes<=Preparation.WRITE_QUEUE_BYTES,"in-flight payload estimate respects its byte limit")
	bounded._release()
	check(bounded._cache_write_task<0 and bounded._cache_write_job==null and bounded._cache_writes.is_empty() and bounded._cache_write_bytes==0,"teardown joins accepted writes without a late callback")
	var byte_limited:=Preparation.new();byte_limited.disk=SlowDisk.new()
	byte_limited.disk.directory=context.disk.directory.path_join("bytes")
	var many:Array[Transform3D]=[];many.resize(12000);many.fill(Transform3D.IDENTITY)
	var large:Dictionary={0:many,1:many,2:many}
	byte_limited.write("large-a",large,func():return false)
	byte_limited.write("large-b",large,func():return false)
	check(byte_limited.cache_writes_skipped==1,"large snapshots hit the byte limit before the job count limit")
	byte_limited._release()
	print("DETAIL_CACHE_WRITE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"producer_us":producer_us}))
	quit(0 if errors.is_empty() else 1)
