extends SceneTree
const Layers=preload("res://scripts/ember_solid_material_layers.gd")
class TestMap extends EmberMapLoader:
 var enabled := true
 func _ready(): pass
 func _process(_delta): pass
 func editor_object_detail_enabled() -> bool: return enabled
class BlockedJob extends Layers.PreparationJob:
 var entered := Semaphore.new()
 var release := Semaphore.new()
 func run():
  entered.post();release.wait();super.run()
var errors:Array[String]=[]
func check(ok:bool,label:String):
 if not ok: errors.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
 for mode in ["publish","changed","disabled","exit"]:
  Layers._prepared.clear()
  var map:=TestMap.new();root.add_child(map)
  var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().get_mesh_arrays())
  var resource:=EmberVoxelModelResource.new()
  var job:=BlockedJob.new()
  job.builder=func(_arrays:Array,_model:Dictionary):return {"probe":17}
  map._object_far_job=job;map._object_far_source=weakref(mesh);map._object_far_resource=resource
  mesh.changed.connect(map._invalidate_object_far.bind(mesh.get_instance_id()))
  resource.changed.connect(map._invalidate_object_far.bind(mesh.get_instance_id()))
  map._object_far_task=WorkerThreadPool.add_task(job.run)
  job.entered.wait()
  map._finish_object_far()
  check(map._object_far_task>=0 and Layers._prepared.is_empty(),"pending nonblocking/no premature publish: "+mode)
  if mode=="changed":resource.emit_changed()
  if mode=="disabled":map.enabled=false
  job.release.post()
  if mode=="exit":map.free();check(Layers._prepared.is_empty(),"exit joins without publication");continue
  while not WorkerThreadPool.is_task_completed(map._object_far_task):await process_frame
  map._finish_object_far()
  check(map._object_far_job==null and map._object_far_resource==null and map._object_far_source==null and map._object_far_task==-1,"flight references released: "+mode)
  check(Layers._prepared.size()==(1 if mode=="publish" else 0),"stale/disabled result rejected: "+mode)
  if mode=="publish":
   check(Layers._prepared[mesh.get_instance_id()].mesh==null,"CPU prewarm does not pin GPU carrier")
   mesh.emit_changed();check(Layers._prepared.is_empty(),"published cache invalidates on mesh edit")
  map.free()
 var loader := TestMap.new();root.add_child(loader)
 var path := "res://content/voxel_models/vox_coastal_house.tres"
 check(ResourceLoader.load_threaded_request(path)==OK,"source read starts asynchronously")
 loader._object_far_loading=path
 loader.free() # Exit must consume the loader request as well as CPU worker tasks.
 print("FAR_PREPARATION_LIFETIME ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
 quit(0 if errors.is_empty() else 1)
