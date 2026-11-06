extends SceneTree
## Real assets through the shared preparation owners, without author-map writes.
const Lod = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
const Patch = preload("res://scripts/ember_grass_patch.gd")
var errors: Array[String]=[]
var report: Dictionary={}

func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);push_error(label)

func run() -> void:
	for kind in ["oak","birch","maple_autumn"]:
		var prefab:Node=load("res://prefabs/voxels/vox_painted_"+kind+".tscn").instantiate()
		var source: ArrayMesh=prefab.get_node("Mesh").mesh
		prefab.free()
		var original:=source.surface_get_arrays(0).duplicate(true)
		var job=Lod.object_job(source,true)
		var task:=WorkerThreadPool.add_task(job.run)
		while not WorkerThreadPool.is_task_completed(task):await process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		var result: Dictionary=Lod.publish_object(job,source)
		var before:=0
		var after:=0
		for s in source.get_surface_count():
			before+=source.surface_get_array_index_len(s)/3 if source.surface_get_array_index_len(s)>0 else source.surface_get_array_len(s)/3
			after+=result.mesh.surface_get_array_index_len(s)/3
			check(result.mesh.surface_get_name(s)==source.surface_get_name(s),kind+" surface names")
			check(result.mesh.surface_get_material(s)==source.surface_get_material(s),kind+" original materials")
		check(source.surface_get_arrays(0)==original,kind+" author geometry retained")
		check(after<before*0.65 and after>before*0.3,kind+" near simplification")
		check(result.levels>0,kind+" distant native LOD")
		report[kind]={"before":before,"after":after,"levels":result.levels}
	var mesh:=Patch.grass_render_mesh()
	check(mesh==Patch.grass_render_mesh(),"grass shares one derived mesh")
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_COLOR,Mesh.ARRAY_INDEX]:
		check(mesh.surface_get_arrays(0)[channel]==Patch.GRASS_CARD_MESH.surface_get_arrays(0)[channel],"grass near geometry and artwork exact channel "+str(channel))
	# Native tangent packing can round decoded tangents by one quantization step.
	var tangents:PackedFloat32Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_TANGENT]
	var original_tangents:PackedFloat32Array=Patch.GRASS_CARD_MESH.surface_get_arrays(0)[Mesh.ARRAY_TANGENT]
	for i in tangents.size():check(absf(tangents[i]-original_tangents[i])<0.0001,"tangent precision")
	var stage:=Node3D.new()
	root.add_child(stage)
	var carrier:=MultiMeshInstance3D.new()
	var mm:=MultiMesh.new()
	mm.transform_format=MultiMesh.TRANSFORM_3D
	mm.instance_count=1
	mm.set_instance_transform(0,Transform3D(Basis.IDENTITY,Vector3(1,0,1)))
	carrier.multimesh=mm
	stage.add_child(carrier)
	var cam:=Camera3D.new()
	cam.near=0.01
	cam.far=1000
	stage.add_child(cam)
	cam.make_current()
	var values: Dictionary={}
	for distance in [2.,500.]:
		cam.position=Vector3(1.,0.2,distance)
		cam.look_at(Vector3(1.,0.08,1.))
		for variant in ["original","derived"]:
			mm.mesh=Patch.GRASS_CARD_MESH if variant=="original" else mesh
			for i in 8:await process_frame
			await RenderingServer.frame_post_draw
			values[str(distance)+variant]=root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
	check(values["2.0derived"]==values["2.0original"],"grass keeps near draw")
	check(values["500.0derived"]<values["500.0original"] and values["500.0derived"]>0,"native far draw uses fewer triangles")
	report["grass_draw"]=values
	report["errors"]=errors
	print("MAIN_READY_LODS ",JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
