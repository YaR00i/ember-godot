extends "res://tools/capture_rock_three_looks.gd"
## LAB recipe: cut the common voxel Source first, then fit both polygon looks.
## Directions guide the fit; every plane distance comes from saved voxel corners.
var detail_stats: Array=[]
var source_edit_stats: Array=[]

func feature_directions(id: int) -> Array[Vector3]:
	if id>1:return []
	var angle: float=SPECS[id][3]
	return [Vector3(-0.38,0.32,1).normalized().rotated(Vector3.UP,angle),Vector3(0.44,-0.28,1).normalized().rotated(Vector3.UP,angle)]

func source_volume(clouds: Array[PackedVector3Array]):
	var model=super.source_volume(clouds)
	for id in 2:
		var mass:=mass_data(model,id);var planes: Array[Plane]=[]
		for normal in feature_directions(id):
			var lo:=INF;var hi:=-INF
			for p in mass.points:lo=minf(lo,normal.dot(p));hi=maxf(hi,normal.dot(p))
			planes.append(Plane(normal,hi-minf((hi-lo)*0.15,5.0)))
		var size: Vector3i=model.grid_size();var removed:=0
		for z in size.z:
			for y in size.y:
				for x in size.x:
					var index:=Mesher.cell_index(x,y,z,size.x,size.z)
					if model.voxel_part_ids[index]!=id+1:continue
					for plane in planes:
						if plane.distance_to(Vector3(x+0.5,y+0.5,z+0.5))>0:
							model.voxels[index]=0;model.voxel_part_ids[index]=0;removed+=1;break
		check(removed>0 and float(removed)/mass.count<0.15,"bounded macro cuts are present in voxel Source")
		source_edit_stats.append({"rock":id,"removed_voxels":removed,"before_voxels":mass.count,"removed_fraction":float(removed)/mass.count})
	check(model.validation_errors().is_empty(),"cut common Source validates")
	return model

func mesh_planes(mesh: ArrayMesh) -> Array[Plane]:
	var arrays:=mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var result: Array[Plane]=[]
	for i in range(0,vertices.size(),3):
		var plane:=Plane(normals[i],normals[i].dot(vertices[i]));var found:=false
		for other in result:
			if other.normal.dot(plane.normal)>0.999999 and absf(other.d-plane.d)<0.001:found=true;break
		if not found:result.append(plane)
	return result

func corners_of(planes: Array[Plane]) -> PackedVector3Array:
	var result:=PackedVector3Array()
	for p in Geometry3D.compute_convex_mesh_points(planes):
		var found:=false
		for q in result:
			if p.distance_squared_to(q)<0.000001:found=true;break
		if not found:result.append(p)
	return result

func face_of(corners: PackedVector3Array,plane: Plane) -> PackedVector3Array:
	var face:=PackedVector3Array();var centre:=Vector3.ZERO
	for p in corners:
		if absf(plane.distance_to(p))<0.003:face.append(p);centre+=p
	if face.size()<3:return PackedVector3Array()
	centre/=face.size()
	var u: Vector3=(face[0]-centre).normalized();var v:=plane.normal.cross(u)
	var ordered: Array[Vector3]=[]
	for p in face:ordered.append(p)
	ordered.sort_custom(func(a: Vector3,b: Vector3):return atan2((a-centre).dot(v),(a-centre).dot(u))<atan2((b-centre).dot(v),(b-centre).dot(u)))
	return PackedVector3Array(ordered)

func face_area(face: PackedVector3Array) -> float:
	var result:=0.0
	for i in range(1,face.size()-1):result+=(face[i]-face[0]).cross(face[i+1]-face[0]).length()*0.5
	return result


func fitted_look(mass: Dictionary,id: int,detailed: bool) -> Dictionary:
	var base:=solid(mass.points,SPECS[id][3],true,detailed)
	var planes:=mesh_planes(base.mesh)
	for normal in feature_directions(id):
		# No analytic cut depth enters the mesh: remeasure the actual voxel form.
		var d:=-INF
		for p in mass.points:d=maxf(d,normal.dot(p))
		planes.append(Plane(normal,d))
	var corners:=corners_of(planes)
	var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
	var polygons:=0;var side_counts: Dictionary={}
	for plane in planes:
		for p in mass.points:check(plane.distance_to(p)<0.004,"reconstructed planes retain source corners")
		var face:=face_of(corners,plane)
		if face.size()<3:continue
		polygons+=1;side_counts[face.size()]=int(side_counts.get(face.size(),0))+1
		for i in range(1,face.size()-1):
			if (face[i]-face[0]).cross(face[i+1]-face[0]).length_squared()<0.000001:continue
			for p in [face[0],face[i+1],face[i]]:vertices.append(p);normals.append(plane.normal)
	var colours:=PackedColorArray();colours.resize(vertices.size());colours.fill(Color(1,0,0,1.0/255.0))
	var uv:=PackedVector2Array();uv.resize(vertices.size());uv.fill(Vector2.ONE/255.0)
	var uv2:=PackedVector2Array();uv2.resize(vertices.size());uv2.fill(Vector2(1.0/255.0,0))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colours;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	if detailed:detail_stats.append({"rock":id,"polygons":polygons,"polygon_sides":side_counts,"triangles":vertices.size()/3})
	base.mesh=mesh;base.triangles=vertices.size()/3;base.faces=polygons
	return base

func ordinary_look(_model,mass: Dictionary,id: int) -> Dictionary:
	return fitted_look(mass,id,true)

func faceted_look(_model,mass: Dictionary,id: int) -> Dictionary:
	return fitted_look(mass,id,false)

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var result:=await super.capture_looks(source,clouds,nodes)
	result["surface_detail"]=detail_stats;result["source_edits"]=source_edit_stats
	result["scope"]="authorized two macro cuts in common voxel Source; all three looks regenerated; recipe-guided convex LAB; no physics integration"
	return result
