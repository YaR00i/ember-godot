extends SceneTree
const LOD=preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
class QuietMap extends EmberMapLoader:
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func editor_object_detail_enabled()->bool:return true
var errors:Array[String]=[]
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("RESIDENT_LOD_FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var map:=QuietMap.new();root.add_child(map)
	var source:=ArrayMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().get_mesh_arrays())
	source.surface_set_name(0,"tree_bark")
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,QuadMesh.new().get_mesh_arrays())
	source.surface_set_name(1,"tree_leaves")
	var prop:=EmberVoxelProp.new()
	var visual:=MeshInstance3D.new();visual.name="Mesh";visual.mesh=source;prop.add_child(visual)
	var body:=StaticBody3D.new();body.name="Collision";prop.add_child(body)
	var shape:=CollisionShape3D.new();shape.name="Shape";shape.shape=BoxShape3D.new();body.add_child(shape)
	var physical:=shape.shape
	prop._tree_meshes={0:source,1:source};prop._world_look=0
	prop._distance_managed=true;prop._distance_resident=true;prop._distance_ready=true
	map.add_child(prop);prop.owner=map
	map._object_details[prop.get_instance_id()]=weakref(prop)
	var job:=LOD.object_job(source)
	map._object_lod_source=weakref(source);map._object_lod_job=job
	map._object_lod_task=WorkerThreadPool.add_task(job.run)
	while not WorkerThreadPool.is_task_completed(map._object_lod_task):await process_frame
	map._finish_object_lod()
	check(map._object_lod_attach.size()==1,"completed worker queues resident tree publication")
	var carrier:ArrayMesh=map._object_lod_cache[source.get_instance_id()].mesh
	map._request_object_lod(prop)
	check(visual.mesh==carrier,"resident tree receives the existing camera-selected native LOD")
	check(prop._distance_resident and prop.object_detail_base()==source and shape.shape==physical,"render LOD preserves residency, source and collision")
	check(carrier.get_faces()==source.get_faces(),"LOD0 preserves full geometry")
	prop.set_world_look(0)
	check(visual.mesh==carrier,"detailed-look refresh retains camera-selected LOD")
	prop.restore_object_detail(0)
	check(visual.mesh==source and prop._distance_mesh==null and shape.shape==physical,"leaving streaming restores editable source")
	prop._distance_managed=true;prop._distance_resident=true
	var preview:=Node3D.new();root.add_child(preview);prop.authoring_preview=weakref(preview)
	map._request_object_lod(prop)
	check(visual.mesh==source,"live authoring preview keeps the source representation")
	preview.free()
	var replacement:=ArrayMesh.new();replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().get_mesh_arrays())
	visual.mesh=replacement
	map._request_object_lod(prop)
	check(visual.mesh==replacement,"authored mesh replacement rejects stale render carrier")
	for look in [1,2]:
		visual.mesh=source;prop._tree_meshes={0:source,1:source,2:source};prop._world_look=0
		prop._distance_managed=true
		prop.set_world_look(look)
		check(not prop._distance_managed and visual.mesh==source,"other world looks keep their existing owner")
	map.free()
	print("OBJECT_RESIDENT_LOD ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
