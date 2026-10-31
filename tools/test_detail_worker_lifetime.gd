extends SceneTree
const Detail=preload("res://scripts/ember_detail_scatter.gd")
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
class Host extends "res://scripts/ember_grass_patch.gd":
 func _ready()->void:pass
 func await_job(job:RefCounted,flags:Dictionary,index:int)->void:
  await job.ready
  if job.cancelled():flags[index]=true
class BlockedJob extends Detail.TerrainJob:
 var started:=Semaphore.new()
 var gate:=Semaphore.new()
 var completed:=Semaphore.new()
 func _init():input={"cells":{}}
 func run()->void:
  started.post();gate.wait();super.run();completed.post()
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);printerr("DETAIL_WORKER_FAIL ",label)
func _initialize():run.call_deferred()
func run():
 var map:=Node3D.new();root.add_child(map)
 var projection:=Node3D.new();map.add_child(projection)
 var context=Preparation.for_projection(projection)
 var hosts:Array[Host]=[];var jobs:Array[BlockedJob]=[];var signals:Dictionary={"count":0};var cleaned:Dictionary={}
 for i in 2:
  var host:=Host.new();map.add_child(host);host.set_process(false);host._detail_resident=true;host._dirty=false;hosts.append(host)
  var job:=BlockedJob.new();jobs.append(job);job.ready.connect(func():signals.count+=1)
  check(context.terrain_job_available(),"two admissions available")
  context.start_terrain_job(host,job);job.started.wait()
  host.await_job(job,cleaned,i)
 check(not context.terrain_job_available() and context._terrain_jobs.size()==2,"parallel work is bounded at two")
 jobs[0].gate.post();jobs[0].completed.wait()
 check(not jobs[0].result.is_empty(),"fixture completes before cancellation")
 map.remove_child(hosts[0]);map.add_child(hosts[0]);hosts[0].set_process(false)
 check(jobs[0].cancelled(),"remove/readd cancels an already completed job")
 check(cleaned.get(0,false),"cancel resumes cleanup before the removed host can be freed")
 hosts[1].free();jobs[1].gate.post();jobs[1].completed.wait()
 check(cleaned.get(1,false),"freed host finishes its await while still alive")
 for frame in 3:await process_frame
 check(context._terrain_jobs.is_empty() and context.terrain_job_available(),"removed/freed hosts release both admissions")
 check(signals.count==2,"each job signals cleanup exactly once")
 var last:=BlockedJob.new();last.ready.connect(func():signals.count+=1)
 context.start_terrain_job(hosts[0],last);last.started.wait();last.gate.post()
 Preparation.release_projection(projection)
 check(last.cancelled() and context._terrain_jobs.is_empty(),"projection release cancels and joins outstanding work")
 check(signals.count==3,"projection release signals once")
 map.free();await process_frame
 print("DETAIL_WORKER_LIFETIME ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
 quit(0 if errors.is_empty() else 1)
