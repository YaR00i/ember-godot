extends SceneTree
## Run with native Forward+ (material defaults require a real renderer).
const LOD=preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
const Policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd")
const Grove=preload("res://addons/ember_import/ember_grove_planner.gd")
var errors:Array[String]=[]
func check(ok:bool,label:String):
	if not ok:errors.append(label);push_error(label)
func _initialize():run.call_deferred()
func run():
	var policy:=Policy.new();policy.anchor=Vector2.ZERO
	var area:=Rect2(Vector2(38*16,0),Vector2.ONE*16)
	check(not policy.object_resident(area,false) and policy.object_resident(area,true),"object hysteresis retains without thrashing")
	check(policy.object_resident(area,false,true),"selected/draft protection")
	var stage:=Node3D.new();root.add_child(stage)
	var results:Array[Dictionary]=[]
	for id in ["vox_painted_oak","vox_painted_rock_group","vox_external_coastal_rock"]:
		var prop:EmberVoxelProp=load("res://prefabs/voxels/"+id+".tscn").instantiate();stage.add_child(prop);prop.owner=stage
		prop.apply_object_detail(true)
		var authored:=Grove.fingerprint(prop,stage)
		var shape:Shape3D=prop.authoring_collision_shape()
		var living:WeakRef=weakref(prop._living_mesh) if prop._living_mesh!=null else null
		var before:Transform3D=prop.transform
		prop.apply_object_detail(false)
		check(prop.visible and prop.get_node("Mesh").visible,"far object stays visible: "+id)
		check(not prop.is_processing(),"far object stops detailed material polling: "+id)
		check(prop._living_mesh==null and prop._voxel_mesh==null,"unused generated carriers released: "+id)
		if living!=null:check(living.get_ref()==null,"generated detailed geometry actually dies: "+id)
		var base:=prop.object_detail_base();var original_surfaces:Array=base.get("_surfaces").duplicate(true)
		var job := LOD.object_job(base)
		var task := WorkerThreadPool.add_task(job.run)
		while not WorkerThreadPool.is_task_completed(task): await process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		var baked := LOD.publish_object(job, base)
		var mesh: ArrayMesh = baked.mesh
		check(base.get("_surfaces")==original_surfaces,"LOD never mutates authored surfaces: "+id)
		check(base.get_faces()==mesh.get_faces(),"indexed base triangles stay exactly equal: "+id)
		check(same_channels(base,mesh),"indexed base preserves normals, pigment, UVs and custom channels: "+id)
		check(base.get_surface_count()==mesh.get_surface_count(),"surface boundaries preserved: "+id)
		for s in base.get_surface_count():
			check(base.surface_get_name(s)==mesh.surface_get_name(s) and base.surface_get_material(s)==mesh.surface_get_material(s),"material owner preserved: "+id)
		prop.install_object_lod(base,mesh)
		check(prop.get_node("Mesh").mesh==mesh and Grove.fingerprint(prop,stage)==authored,"LOD and far material never become manual edits: "+id)
		check(prop.transform==before and prop.authoring_collision_shape()==shape,"physical surface and pose stay canonical: "+id)
		prop.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
		check(prop.get_node("Mesh").mesh!=mesh,"native save strips distance mesh: "+id)
		prop.set_world_look(0)
		check(prop.get_node("Mesh").mesh==mesh,"far appearance restored after save: "+id)
		prop.apply_object_detail(true)
		check(prop._distance_mesh==null and Grove.fingerprint(prop,stage)==authored,"return restores same authored object: "+id)
		if id=="vox_painted_oak":
			for look in [1,2,0]:
				prop.restore_object_detail(look)
				check(Grove.fingerprint(prop,stage)==authored,"alternate look keeps author state")
			var unused:WeakRef=weakref(prop._tree_meshes[2])
			prop.apply_object_detail(true)
			check(unused.get_ref()==null,"last distance consumer releases inactive tree world geometry")
			var replacement:=ArrayMesh.new();replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().get_mesh_arrays())
			prop.get_node("Mesh").mesh=replacement
			check(not prop.object_detail_safe(),"manual mesh replacement is protected from automatic distance changes")
			prop.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
			check(prop.get_node("Mesh").mesh==replacement,"native save preserves unknown authored mesh replacement")
		results.append({"id":id,"lods":baked.levels,"bake_us":baked.us})
		prop.free()
	stage.free();await process_frame
	print("OBJECT_DETAIL ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"results":results}));quit(0 if errors.is_empty() else 1)

func same_channels(source:ArrayMesh,mesh:ArrayMesh)->bool:
	for surface in source.get_surface_count():
		var a:=source.surface_get_arrays(surface);var b:=mesh.surface_get_arrays(surface)
		var count:int=a[Mesh.ARRAY_VERTEX].size()
		var ai:PackedInt32Array=a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var bi:PackedInt32Array=b[Mesh.ARRAY_INDEX]
		for channel in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3]:
			if a[channel]==null or a[channel].is_empty():continue
			if b[channel]==null or b[channel].is_empty():return false
			var stride:int=a[channel].size()/count
			for i in range(0,bi.size(),97):
				var original:int=ai[i] if not ai.is_empty() else i
				for k in stride:
					var av:Variant=a[channel][original*stride+k];var bv:Variant=b[channel][bi[i]*stride+k]
					# ArrayMesh repacks octahedral 16-bit normals. Bound that
					# quantisation explicitly; UV/pigment/custom data keep their checks.
					if channel==Mesh.ARRAY_NORMAL:
						if av.distance_to(bv)>0.0002:return false
						continue
					if av is Vector2 or av is Vector3 or av is Color:
						if not av.is_equal_approx(bv):
							print("CHANNEL_DIFF ",channel," av=",av," bv=",bv);return false
					elif av!=bv:
						print("CHANNEL_DIFF ",channel," av=",av," bv=",bv);return false
	return true
