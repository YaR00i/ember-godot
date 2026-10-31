extends RefCounted
## Derived visual shells only. Source, physics and material channels stay owned by
## the terrain projection. Retain fine material vertices on broad planar faces.
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const ANOMALY_CACHE_VERSION := 2 # Bump when changing carrier topology/math.

## Common topology for a moving field. Internal voxel risers are present from
## preparation onward, collapsed exactly onto the detailed/low-poly top. They
## unfold with the same weight as both neighbouring tops; no cut can open.
class AnomalyJob extends RefCounted:
	var work: Callable
	var cancellation := preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd").Cancellation.new()
	var result: Dictionary = {}
	func run() -> void: result = work.call(cancellation.is_cancelled)

static func anomaly_carrier(base: ArrayMesh, low: ArrayMesh, source, field: Dictionary, bounds: Rect2i, host: Node) -> Dictionary:
	# CPU arrays use the same immutable terrain snapshot as ordinary preparation.
	# Waiting per tiny inner loop used a full rendered frame for ~3 ms of work.
	var tree := host.get_tree()
	var job := AnomalyJob.new()
	job.work = _anomaly_arrays.bind(base.surface_get_arrays(0),low.surface_get_arrays(0),source.working_copy(),field,bounds)
	var task := WorkerThreadPool.add_task(job.run,false,"Ember anomaly terrain")
	if task < 0: return {}
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
		if not is_instance_valid(host) or not host.is_inside_tree() or not host.anomaly_preparation_valid():
			job.cancellation.set_cancelled(true)
			WorkerThreadPool.wait_for_task_completion(task)
			return {}
	WorkerThreadPool.wait_for_task_completion(task)
	if not is_instance_valid(host) or not host.is_inside_tree() or not host.anomaly_preparation_valid(): return {}
	var result: Dictionary = {}
	for look in job.result:
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,job.result[look])
		result[look] = mesh
	return result

static func _anomaly_arrays(cancelled: Callable, input: Array, low_arrays: Array, source, field: Dictionary, bounds: Rect2i) -> Dictionary:
	var arrays := _unindexed(input)
	low_arrays = _unindexed(low_arrays)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var low_points: PackedVector3Array = low_arrays[Mesh.ARRAY_VERTEX]
	var low_normals: PackedVector3Array = low_arrays[Mesh.ARRAY_NORMAL]
	var voxel_points := points.duplicate()
	var voxel_normals := normals.duplicate()
	for triangle in range(0, points.size(), 3):
		if triangle%768 == 0 and cancelled.call(): return {}
		var centre := (points[triangle]+points[triangle+1]+points[triangle+2])/3.0
		var cell := Vector2i(clampi(floori(centre.x),0,source.width-1),clampi(floori(centre.z),0,source.depth-1))
		var height := float(source.origin_y+source.column_value("heights",source.column_index(cell.x,cell.y)))
		for k in 3:
			var i := triangle+k
			if normals[i].y > 0.0 or points[i].y > source.origin_y:
				voxel_points[i].y = height
			if normals[i].y > 0.0: voxel_normals[i] = Vector3.UP
	var mesher = load("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
	var risers = mesher.Triangles.new()
	for z in range(bounds.position.y,bounds.end.y):
		if cancelled.call(): return {}
		for x in range(bounds.position.x,bounds.end.x):
			var height: int = source.column_value("heights",source.column_index(x,z))
			if height <= 0: continue
			for side in 4:
				var next: Vector2i = Vector2i(x,z)+[Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN][side]
				if not source.has_column(next.x,next.y): continue
				var other: int = source.column_value("heights",source.column_index(next.x,next.y))
				if other <= 0 or other >= height: continue
				mesher._add_side(source,risers,x,z,height,other,side)
	var material_cache: Dictionary = {}
	for triangle in range(0, risers.vertices.size(), 3):
		if triangle%192 == 0 and cancelled.call(): return {}
		var ps: Array = []; var ns: Array = []; var masks: Array = []
		for k in 3:
			var p: Vector3 = risers.vertices[triangle+k]
			var x := roundi(p.x); var z := roundi(p.z)
			ps.append(Vector3(p.x,Smooth.corner(field,x,z),p.z))
			ns.append(Smooth.normal(field,x,z))
			masks.append(Smooth.material_weights(source,Vector2i(x,z),material_cache))
			var flat := plane(field,Vector2(p.x,p.z))
			low_points.append(Vector3(p.x,flat.height,p.z)); low_normals.append(flat.normal)
			voxel_points.append(p); voxel_normals.append(risers.normals[triangle+k])
		Smooth._emit_blended(ps,ns,masks,1,points,normals,colours,uv,uv2)
	arrays[Mesh.ARRAY_VERTEX] = points; arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours; arrays[Mesh.ARRAY_TEX_UV] = uv; arrays[Mesh.ARRAY_TEX_UV2] = uv2
	# Imported/rendered surfaces can carry generated tangents for the original
	# vertex count. The bank uses its own projection frame, including on risers.
	arrays[Mesh.ARRAY_TANGENT] = null
	var result: Dictionary = {}
	for look in 3:
		var geometry := arrays.duplicate()
		geometry[Mesh.ARRAY_VERTEX] = [points,low_points,voxel_points][look]
		geometry[Mesh.ARRAY_NORMAL] = [normals,low_normals,voxel_normals][look]
		result[look] = geometry
	return result

static func plane(field: Dictionary,p: Vector2,step:=8) -> Dictionary:
	var a:=Vector2(floor(p.x/step)*step,floor(p.y/step)*step)
	var t:=(p-a)/step
	var h00:=Smooth.corner(field,int(a.x),int(a.y))
	var h10:=Smooth.corner(field,int(a.x)+step,int(a.y))
	var h01:=Smooth.corner(field,int(a.x),int(a.y)+step)
	var h11:=Smooth.corner(field,int(a.x)+step,int(a.y)+step)
	var dx:=(h10-h00)/step if t.x+t.y<=1.0 else (h11-h01)/step
	var dz:=(h01-h00)/step if t.x+t.y<=1.0 else (h11-h10)/step
	var h:=h00+(h10-h00)*t.x+(h01-h00)*t.y if t.x+t.y<=1.0 else h11+(h01-h11)*(1.0-t.x)+(h10-h11)*(1.0-t.y)
	return {"height":h,"normal":Vector3(-dx,1,-dz).normalized()}

## Expand only the base topology; native render LOD indices are presentation.
static func _unindexed(input:Array)->Array:
	var indices:Variant=input[Mesh.ARRAY_INDEX]
	if indices==null or indices.is_empty():return input.duplicate()
	var arrays:=input.duplicate()
	for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
		if input[channel]==null:continue
		arrays[channel]=input[channel].slice(0,0)
		for i in indices:arrays[channel].append(input[channel][i])
	if input[Mesh.ARRAY_TANGENT]!=null:
		var tangents:=PackedFloat32Array()
		for index in indices:
			for component in 4:tangents.append(input[Mesh.ARRAY_TANGENT][index*4+component])
		arrays[Mesh.ARRAY_TANGENT]=tangents
	arrays[Mesh.ARRAY_INDEX]=null
	return arrays

static func faceted(mesh: ArrayMesh,field: Dictionary,step:=8,source=null) -> Dictionary:
	var original:=_unindexed(mesh.surface_get_arrays(0))
	var arrays:=original.duplicate(true)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var max_delta:=0.0
	var heights: Dictionary={}
	var plane_normals: Dictionary={}
	for i in range(0,vertices.size(),3):
		var top:=normals[i].y>0.0
		var centre:=(vertices[i]+vertices[i+1]+vertices[i+2])/3.0
		var flat:=normals[i]
		if top:
			var a:=Vector2(floor(centre.x/step)*step,floor(centre.z/step)*step)
			var t:=(Vector2(centre.x,centre.z)-a)/step
			var key:=Vector3i(int(a.x),int(a.y),0 if t.x+t.y<=1.0 else 1)
			if not plane_normals.has(key):plane_normals[key]=plane(field,Vector2(centre.x,centre.z),step).normal
			flat=plane_normals[key]
		for j in 3:
			var p:=vertices[i+j]
			if top or is_equal_approx(p.y,Smooth.corner(field,roundi(p.x),roundi(p.z))):
				var key:=Vector2(p.x,p.z)
				if not heights.has(key):heights[key]=plane(field,key,step).height
				var h: float=heights[key]
				max_delta=maxf(max_delta,absf(p.y-h));p.y=h
			vertices[i+j]=p;normals[i+j]=flat
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	if source!=null:arrays=Smooth.faceted_side_arrays(source,original,arrays)
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return {"mesh":result,"max_delta_m":max_delta/16.0}

static func pixel_image(source: Image,cells:=32) -> Image:
	# Paired albedo/height use identical centres; original resources are untouched.
	var image:=source.duplicate() as Image
	if image.is_compressed():image.decompress()
	image.clear_mipmaps();image.resize(cells,cells,Image.INTERPOLATE_NEAREST)
	image.resize(source.get_width(),source.get_height(),Image.INTERPOLATE_NEAREST)
	image.generate_mipmaps();return image

static func adaptive_heights(field: Dictionary,bounds: Rect2i,tolerance:=0.6) -> Dictionary:
	# Error is in fine16 units: 0.6 = 3.75cm. All boundary samples are anchors,
	# so independently baked neighbouring tiles share exactly the same edge.
	var points:=PackedVector2Array();var known: Dictionary={}
	var size:=bounds.size;var stride:=size.x+1
	for z in range(size.y+1):
		for x in range(size.x+1):
			if x==0 or z==0 or x==size.x or z==size.y or (x%8==0 and z%8==0):
				var p:=Vector2i(x,z);known[p]=true;points.append(Vector2(p))
	var result:=PackedFloat32Array();result.resize(stride*(size.y+1))
	var largest:=INF;var triangles:=PackedInt32Array()
	for iteration in 24:
		triangles=Geometry2D.triangulate_delaunay(points)
		var additions: Dictionary={};largest=0.0
		for t in range(0,triangles.size(),3):
			var a:=points[triangles[t]];var b:=points[triangles[t+1]];var c:=points[triangles[t+2]]
			var h:=Vector3(Smooth.corner(field,int(a.x)+bounds.position.x,int(a.y)+bounds.position.y),Smooth.corner(field,int(b.x)+bounds.position.x,int(b.y)+bounds.position.y),Smooth.corner(field,int(c.x)+bounds.position.x,int(c.y)+bounds.position.y))
			var determinant:=(b-a).cross(c-a)
			if absf(determinant)<0.00001:continue
			var lo:=Vector2i(a.min(b).min(c));var hi:=Vector2i(a.max(b).max(c))
			var worst:=0.0;var chosen:=Vector2i(-1,-1)
			for z in range(lo.y,hi.y+1):
				for x in range(lo.x,hi.x+1):
					var p:=Vector2(x,z);var u:=(p-a).cross(c-a)/determinant;var v:=(b-a).cross(p-a)/determinant
					if u< -0.00001 or v< -0.00001 or u+v>1.00001:continue
					var predicted:=h.x+(h.y-h.x)*u+(h.z-h.x)*v
					result[x+z*stride]=predicted
					var error:=absf(predicted-Smooth.corner(field,x+bounds.position.x,z+bounds.position.y))
					largest=maxf(largest,error)
					if error>worst and not known.has(Vector2i(x,z)):worst=error;chosen=Vector2i(x,z)
			if worst>tolerance and chosen.x>=0:additions[chosen]=true
		if additions.is_empty():break
		for p: Vector2i in additions:known[p]=true;points.append(Vector2(p))
	# Fail closed rather than ship a shape outside the requested error budget.
	assert(largest<=tolerance+0.001)
	# Fine topology retains paint channels; light uses each actual adaptive
	# supporting plane, avoiding thin shading slivers where the two grids cross.
	var plane_normals:=PackedVector3Array();plane_normals.resize(size.x*size.y*2)
	for t in range(0,triangles.size(),3):
		var a:=points[triangles[t]];var b:=points[triangles[t+1]];var c:=points[triangles[t+2]]
		var h:=Vector3(Smooth.corner(field,int(a.x)+bounds.position.x,int(a.y)+bounds.position.y),Smooth.corner(field,int(b.x)+bounds.position.x,int(b.y)+bounds.position.y),Smooth.corner(field,int(c.x)+bounds.position.x,int(c.y)+bounds.position.y))
		var determinant:=(b-a).cross(c-a)
		if absf(determinant)<0.00001:continue
		var n:=Vector3(b.x-a.x,h.y-h.x,b.y-a.y).cross(Vector3(c.x-a.x,h.z-h.x,c.y-a.y)).normalized()
		if n.y<0:n=-n
		var lo:=Vector2i(a.min(b).min(c));var hi:=Vector2i(a.max(b).max(c))
		for z in range(lo.y,mini(hi.y+1,size.y)):
			for x in range(lo.x,mini(hi.x+1,size.x)):
				for half in 2:
					var p:=Vector2(x,z)+Vector2.ONE*(float(half+1)/3.0)
					var u:=(p-a).cross(c-a)/determinant;var v:=(b-a).cross(p-a)/determinant
					if u>= -0.00001 and v>= -0.00001 and u+v<=1.00001:plane_normals[(x+z*size.x)*2+half]=n
	return {"heights":result,"stride":stride,"max_error_m":largest/16.0,"control_points":points.size(),"planes":triangles.size()/3,"normals":plane_normals}

static func soften_within_stone_planes(mesh: ArrayMesh,crease_degrees:=30.0) -> ArrayMesh:
	# Smooth small triangulation changes within a geological face; do not
	# average across its major crease. Positions/material channels stay exact.
	var arrays:=mesh.surface_get_arrays(0)
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var original: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var normals:=original.duplicate()
	var colors: PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
	var neighbors: Dictionary={}
	for i in points.size():
		var c:=colors[i]
		var stone: float=(c.r if roundi(uv[i].x*255.0)==1 else 0.0)+(c.g if roundi(uv[i].y*255.0)==1 else 0.0)+(c.b if roundi(uv2[i].x*255.0)==1 else 0.0)
		if stone<0.85:continue
		var point:=points[i].snapped(Vector3.ONE*0.0001)
		if not neighbors.has(point):neighbors[point]=[]
		neighbors[point].append(i)
	var threshold:=cos(deg_to_rad(crease_degrees))
	for members: Array in neighbors.values():
		for i: int in members:
			var sum:=Vector3.ZERO
			for j: int in members:
				if original[i].dot(original[j])>=threshold:sum+=original[j]
			normals[i]=sum.normalized()
	arrays[Mesh.ARRAY_NORMAL]=normals
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	result.surface_set_material(0,mesh.surface_get_material(0));return result

static func rock_faceted(original: ArrayMesh,previous: ArrayMesh,field: Dictionary,bounds: Rect2i) -> Dictionary:
	var approximation:=adaptive_heights(field,bounds)
	var source:=original.surface_get_arrays(0)
	var arrays:=previous.surface_get_arrays(0).duplicate(true)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var input: PackedVector3Array=source[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray=source[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array=source[Mesh.ARRAY_TEX_UV];var uv2: PackedVector2Array=source[Mesh.ARRAY_TEX_UV2]
	var changed:=PackedByteArray();changed.resize(vertices.size())
	for i in input.size():
		var colour:=colours[i]
		var weight:=(colour.r if roundi(uv[i].x*255.0)==1 else 0.0)+(colour.g if roundi(uv[i].y*255.0)==1 else 0.0)+(colour.b if roundi(uv2[i].x*255.0)==1 else 0.0)
		if weight<=0.001:continue
		var p:=input[i];var x:=roundi(p.x)-bounds.position.x;var z:=roundi(p.z)-bounds.position.y
		if not is_equal_approx(p.y,Smooth.corner(field,roundi(p.x),roundi(p.z))):continue
		var h: float=approximation.heights[x+z*approximation.stride]
		vertices[i].y=lerpf(vertices[i].y,h,smoothstep(0.0,0.15,weight));changed[i]=1
	for i in range(0,vertices.size(),3):
		if changed[i]+changed[i+1]+changed[i+2]==0:continue
		var normal:=(vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).normalized()
		if normal.dot(normals[i])<0.0:normal=-normal
		if (source[Mesh.ARRAY_NORMAL] as PackedVector3Array)[i].y>0.0:
			var centre:=(input[i]+input[i+1]+input[i+2])/3.0
			var p:=Vector2(centre.x,centre.z)-Vector2(bounds.position)
			var cell:=Vector2i(p);var half:=0 if (p-Vector2(cell)).x+(p-Vector2(cell)).y<1.0 else 1
			normal=approximation.normals[(cell.x+cell.y*bounds.size.x)*2+half]
		for j in 3:normals[i+j]=normal
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	approximation.mesh=mesh;return approximation
