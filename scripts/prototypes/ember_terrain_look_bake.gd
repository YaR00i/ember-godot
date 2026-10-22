extends RefCounted
## LAB visual shells only. Source, physics and material channels stay owned by
## the terrain projection. Retain fine material vertices on broad planar faces.
const Smooth=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")

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

static func faceted(mesh: ArrayMesh,field: Dictionary,step:=8) -> Dictionary:
	var arrays:=mesh.surface_get_arrays(0).duplicate(true)
	# SmoothSurface emits unindexed triangles, retaining its palette/blend data.
	assert((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty() if arrays[Mesh.ARRAY_INDEX]!=null else true)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var max_delta:=0.0
	for i in range(0,vertices.size(),3):
		var top:=normals[i].y>0.0
		var centre:=(vertices[i]+vertices[i+1]+vertices[i+2])/3.0
		var flat:=plane(field,Vector2(centre.x,centre.z),step).normal as Vector3 if top else normals[i]
		for j in 3:
			var p:=vertices[i+j]
			if top or is_equal_approx(p.y,Smooth.corner(field,roundi(p.x),roundi(p.z))):
				var h: float=plane(field,Vector2(p.x,p.z),step).height
				max_delta=maxf(max_delta,absf(p.y-h));p.y=h
			vertices[i+j]=p;normals[i+j]=flat
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
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
