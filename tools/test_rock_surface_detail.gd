extends "res://tools/capture_rock_surface_detail.gd"
## Focused geometry check using the saved disposable voxel fixture, no scene.
func run() -> void:
	var original=load(OS.get_cmdline_user_args()[0])
	check(original.validation_errors().is_empty(),"saved fixture validates")
	var fingerprint: String=original.voxels.hex_encode().sha256_text()
	var clouds: Array[PackedVector3Array]=[]
	for id in 6:clouds.append(mass_data(original,id).points)
	var model=source_volume(clouds)
	var repeated=source_volume(clouds)
	check(repeated.voxels==model.voxels and repeated.voxel_part_ids==model.voxel_part_ids,"source cuts reproduce deterministically")
	if OS.get_cmdline_user_args().size()>1:
		var captured=load(OS.get_cmdline_user_args()[1])
		check(captured.voxels==model.voxels and captured.voxel_part_ids==model.voxel_part_ids,"captured source equals independently regenerated fixture")
	check(original.voxels.hex_encode().sha256_text()==fingerprint,"original fixture remains unchanged")
	check(model.voxels!=original.voxels,"macro cuts change the common Source")
	for i in original.voxels.size():
		if original.voxels[i]==model.voxels[i]:continue
		check(original.voxel_part_ids[i] in [1,2] and model.voxels[i]==0,"only the two intended source masses are cut")
	for id in 6:
		var mass:=mass_data(model,id)
		var old_mass:=mass_data(original,id)
		var old_bounds:=point_bounds(old_mass.points);var bounds:=point_bounds(mass.points)
		var delta_min: Vector3=(old_bounds.position-bounds.position).abs()
		var delta_max: Vector3=(old_bounds.end-bounds.end).abs()
		var extent_delta:=maxf(maxf(delta_min.x,maxf(delta_min.y,delta_min.z)),maxf(delta_max.x,maxf(delta_max.y,delta_max.z)))
		check(extent_delta<=2.0,"source outer extents change at most two fine voxels")
		print("SOURCE_EXTENT_DELTA ",id," metres=",extent_delta/16.0)
		var result:=ordinary_look(model,mass,id)
		var coarse:=faceted_look(model,mass,id)
		check(result.side_angles_degrees==coarse.side_angles_degrees,"both fits retain the same principal slopes")
		closed_mesh(result.mesh)
		closed_mesh(coarse.mesh)
		print("DETAIL_GEOMETRY ",id," triangles=",result.triangles)
	print("DETAIL_STATS ",JSON.stringify(detail_stats))
	print("ROCK_DETAIL_TEST ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)

func point_bounds(points: PackedVector3Array) -> AABB:
	var result:=AABB(points[0],Vector3.ZERO)
	for p in points:result=result.expand(p)
	return result

func closed_mesh(mesh: ArrayMesh) -> void:
	var vertices: PackedVector3Array=mesh.get_faces();var edges: Dictionary={}
	for i in range(0,vertices.size(),3):
		for j in 3:
			var a: String=str(vertices[i+j].snapped(Vector3.ONE*0.001))
			var b: String=str(vertices[i+(j+1)%3].snapped(Vector3.ONE*0.001))
			var key:=a+"/"+b if a<b else b+"/"+a
			if not edges.has(key):edges[key]=[0,0]
			edges[key][0]+=1;edges[key][1]+=1 if a<b else -1
	for value in edges.values():check(value[0]==2 and value[1]==0,"mesh edges pair in opposite directions without holes")
