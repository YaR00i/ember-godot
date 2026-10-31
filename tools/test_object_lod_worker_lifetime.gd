extends SceneTree
const LOD = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
class TestMap extends EmberMapLoader:
 var enabled := true
 func _ready(): pass
 func _process(_delta): pass
 func editor_object_detail_enabled() -> bool: return enabled
class BlockedJob extends LOD.ObjectJob:
 var entered := Semaphore.new()
 var release := Semaphore.new()
 func run():
  entered.post()
  release.wait()
  super.run()
var errors: Array[String] = []
func check(value: bool, label: String):
 if not value: errors.append(label); push_error(label)
func _initialize(): run.call_deferred()
func run():
 for mode in ["publish", "changed", "disabled", "exit"]:
  var map := TestMap.new(); root.add_child(map)
  var source := ArrayMesh.new()
  source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
  source.set_meta("owner_probe", 17)
  var job := BlockedJob.new(); job.surfaces = LOD.object_job(source).surfaces
  map._object_lod_source = weakref(source); map._object_lod_job = job
  source.changed.connect(map._invalidate_object_lod.bind(source.get_instance_id()))
  map._object_lod_task = WorkerThreadPool.add_task(job.run)
  job.entered.wait()
  map._finish_object_lod()
  check(map._object_lod_task >= 0 and map._object_lod_cache.is_empty(), "active job never blocks frame or publishes: " + mode)
  if mode == "changed": source.emit_changed()
  if mode == "disabled": map.enabled = false
  job.release.post()
  if mode == "exit":
   map.free()
   continue
  while not WorkerThreadPool.is_task_completed(map._object_lod_task): await process_frame
  map._finish_object_lod()
  check(map._object_lod_task == -1 and map._object_lod_job == null and map._object_lod_source == null, "completed task released: " + mode)
  check(map._object_lod_cache.size() == (1 if mode == "publish" else 0), "stale or disabled output rejected: " + mode)
  if mode == "publish":
   var mesh: ArrayMesh = map._object_lod_cache[source.get_instance_id()].mesh
   check(mesh.get_meta("owner_probe") == 17 and mesh.get_faces() == source.get_faces(), "published geometry and metadata preserved")
  map.free()
 print("OBJECT_LOD_WORKER_LIFETIME ", JSON.stringify({"pass": errors.is_empty(), "errors": errors}))
 quit(0 if errors.is_empty() else 1)
