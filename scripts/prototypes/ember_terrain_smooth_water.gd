extends RefCounted
## Derived shoreline for the existing smooth heightfield, not new water data.
## A bounded collar of authored wet cells reaches the filtered ground contour.
const Smooth = preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const NEIGHBOURS = [Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1)]

static func append(source, bounds: Rect2i, field: Dictionary, triangles) -> void:
	var region := bounds.grow(Smooth.HALO).intersection(Rect2i(0,0,source.width,source.depth))
	var count := region.size.x * region.size.y
	var seeds := PackedInt32Array(); seeds.resize(count); seeds.fill(-1)
	var distances := PackedByteArray(); distances.resize(count)
	var queue := PackedInt32Array()
	# Row order resolves equal-distance contacts consistently in adjacent tiles.
	for z in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var index: int = source.column_index(x,z)
			if source.water_materials[index] <= 0 or source.water_levels[index] <= source.heights[index]: continue
			var local := x-region.position.x+(z-region.position.y)*region.size.x
			seeds[local]=index; queue.append(local)
	var cursor := 0
	while cursor < queue.size():
		var local := queue[cursor]; cursor+=1
		if distances[local] >= Smooth.HALO: continue
		var p := region.position+Vector2i(local%region.size.x,local/region.size.x)
		var seed := seeds[local]; var level: int = source.water_levels[seed]
		for delta: Vector2i in NEIGHBOURS:
			var next := p+delta
			if not region.has_point(next): continue
			var target := next.x-region.position.x+(next.y-region.position.y)*region.size.x
			if seeds[target] >= 0: continue
			var index: int = source.column_index(next.x,next.y)
			# Do not fill authored dry depressions, holes or a different water body.
			if source.heights[index] < level or source.top_materials[index] <= 0 or source.water_materials[index] > 0: continue
			seeds[target]=seed; distances[target]=distances[local]+1; queue.append(target)
	for z in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var seed := seeds[x-region.position.x+(z-region.position.y)*region.size.x]
			if seed < 0: continue
			var level := float(source.origin_y+source.water_levels[seed])
			var a := Vector3(x,Smooth.corner(field,x,z),z)
			var b := Vector3(x+1,Smooth.corner(field,x+1,z),z)
			var c := Vector3(x,Smooth.corner(field,x,z+1),z+1)
			var d := Vector3(x+1,Smooth.corner(field,x+1,z+1),z+1)
			var color: Color = source.palette[source.water_materials[seed]]
			# Same diagonal and heights as ground, collision and picking.
			_emit([a,b,c],level,color,triangles)
			_emit([b,d,c],level,color,triangles)

static func _emit(points: Array, level: float, color: Color, triangles) -> void:
	if minf(points[0].y,minf(points[1].y,points[2].y)) >= level: return
	var polygon: Array[Vector3] = []
	for i in 3:
		var a: Vector3 = points[i]; var b: Vector3 = points[(i+1)%3]
		if a.y < level: polygon.append(a)
		if (a.y < level) != (b.y < level):
			# Canonical endpoint order gives identical floating-point intersections
			# on either side of a triangle/tile edge, including section windows.
			var low := a if a.y < b.y else b
			var high := b if a.y < b.y else a
			var crossing := low.lerp(high,(level-low.y)/(high.y-low.y))
			crossing.y=level; polygon.append(crossing)
	for i in range(1,polygon.size()-1):
		var face: Array[Vector3] = [polygon[0],polygon[i],polygon[i+1]]
		if (face[1]-face[0]).cross(face[2]-face[0]).length_squared() < 0.0000000001: continue
		for point: Vector3 in face:
			var depth := maxf(0.0,level-point.y)
			triangles.vertices.append(Vector3(point.x,level+0.02,point.z))
			triangles.normals.append(Vector3.UP)
			var vertex_color := color; vertex_color.a=clampf(depth/64.0,0.0,1.0)
			triangles.colors.append(vertex_color)
			triangles.uvs.append(Vector2((clampf(depth,1.0,4.0)-0.5)/4.0,0.0))
