extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
class TestMap extends EmberMapLoader:
 var enabled:=true
 func _ready():pass
 func _process(_delta):pass
 func editor_object_detail_enabled()->bool:return enabled
class TestHost extends EmberVoxelProp:
 var base: ArrayMesh
 func _ready():pass
 func object_detail_safe()->bool:return true
 func object_far_material_mesh()->ArrayMesh:return base
class BlockedJob extends Materials.DepthPreparationJob:
 var entered:=Semaphore.new()
 var release:=Semaphore.new()
 func run():
  entered.post();release.wait()
  images["probe"]=Image.create(2,2,false,Image.FORMAT_R8)
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok:errors.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 for mode in ["publish","changed","disabled","exit"]:
  Materials._bank_height_images.clear()
  var map:=TestMap.new();root.add_child(map)
  var source:=ImageTexture.create_from_image(Image.create(2,2,false,Image.FORMAT_RGBA8))
  var job:=BlockedJob.new()
  map._object_depth_job=job;map._object_depth_sources.append(source)
  source.changed.connect(map._invalidate_object_depth)
  map._object_depth_task=WorkerThreadPool.add_task(job.run)
  job.entered.wait();map._finish_object_depth()
  check(map._object_depth_task>=0 and Materials._bank_height_images.is_empty(),"pending never blocks/publishes: "+mode)
  if mode=="changed":source.emit_changed()
  if mode=="disabled":map.enabled=false
  job.release.post()
  if mode=="exit":map.free();check(Materials._bank_height_images.is_empty(),"exit does not publish");continue
  while not WorkerThreadPool.is_task_completed(map._object_depth_task):await process_frame
  map._finish_object_depth()
  check(map._object_depth_task==-1 and map._object_depth_job==null and map._object_depth_sources.is_empty(),"task and source guards released: "+mode)
  check(not source.changed.is_connected(map._invalidate_object_depth),"signal disconnected: "+mode)
  check(Materials._bank_height_images.size()==(1 if mode=="publish" else 0),"stale/disabled result rejected: "+mode)
  map.free()
 for mode in ["consume","edit","remove"]:
  Materials._bank_height_images.clear()
  var map:=TestMap.new();root.add_child(map)
  var host:=TestHost.new();host.base=ArrayMesh.new();map.add_child(host)
  var source:=ImageTexture.create_from_image(Image.create(2,2,false,Image.FORMAT_RGBA8))
  var reference:WeakRef=weakref(source)
  var job:=BlockedJob.new()
  map._object_depth_job=job;map._object_depth_sources.append(source)
  map._object_depth_host=weakref(host);map._object_depth_mesh_id=host.base.get_instance_id()
  source.changed.connect(map._invalidate_object_depth)
  map._object_depth_task=WorkerThreadPool.add_task(job.run)
  job.entered.wait();job.release.post()
  while not WorkerThreadPool.is_task_completed(map._object_depth_task):await process_frame
  map._finish_object_depth()
  check(map._object_depth_sources.size()==1 and Materials._bank_height_images.has("probe"),"source identity survives CPU publication: "+mode)
  if mode=="consume":
   var material:=ShaderMaterial.new();material.set_meta("ember_depth_source_textures",[source])
   source=null
   map._release_object_depth_sources()
   check(reference.get_ref()!=null and map._object_depth_sources.is_empty(),"material owns source after handoff")
   material=null
   check(reference.get_ref()==null,"last consumer releases source; CPU image never pins GPU")
  elif mode=="edit":
   source.emit_changed()
   check(map._object_depth_sources.is_empty() and not Materials._bank_height_images.has("probe"),"edit during handoff invalidates prepared image")
  else:
   host.free();map._finish_object_depth()
   check(map._object_depth_sources.is_empty(),"removed waiting host releases held source")
  map.free()
 print("OBJECT_DEPTH_LIFETIME ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
 quit(0 if errors.is_empty() else 1)
