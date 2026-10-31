@tool
extends RefCounted
## Disposable targets on the existing detailed topology. Equal source positions
## share their target, including UV/material seams. Physics and Source never change.
const Cache = preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const TerrainLook=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
const WIDTH := 2048
static var _ready: Dictionary = {}
static var builds := 0
static var cache_hits := 0
static var _carriers: Dictionary = {}


static func _valid(host: Node) -> bool:
	return is_instance_valid(host) and host.is_inside_tree() and (not host.has_method("anomaly_preparation_valid") or host.anomaly_preparation_valid())


## Closed voxel topology already contains every stair edge. Its reference
## positions lie on the detailed surface, so the field can unfold those edges.
static func carrier(reference: ArrayMesh, topology: ArrayMesh, host: Node, reference_uv := false) -> ArrayMesh:
	var layered:bool=reference.has_meta("solid_layer_faces")
	var inputs: Array = ["external-uv1" if reference_uv else 3 if layered else 2]
	for surface in topology.get_surface_count(): inputs.append([reference.surface_get_arrays(surface),topology.surface_get_arrays(surface)])
	var key := Cache.digest(inputs)
	if _carriers.has(key): return _carriers[key]
	var mesh := ArrayMesh.new()
	var cache := Cache.new(); cache.directory = "user://ember-anomaly-cache"; cache.max_bytes = 128*1024*1024
	var saved := cache.read(key)
	if saved.get("surfaces") is Array and saved.surfaces.size() == topology.get_surface_count():
		mesh.set("_surfaces",saved.surfaces)
		if mesh.get_surface_count() == topology.get_surface_count():
			_carriers[key] = mesh
			cache_hits += 1
			return mesh
	for surface in topology.get_surface_count():
		var arrays := topology.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var grid := _grid(reference.surface_get_arrays(surface))
		var shared: Dictionary = {}
		var started := Time.get_ticks_usec()
		for i in points.size():
			var sample := _sample(grid, points[i], shared)
			points[i] = sample[0]; normals[i] = sample[1]
			if i%256 == 0 and Time.get_ticks_usec()-started > 6000:
				await host.get_tree().process_frame
				if not _valid(host): return null
				started = Time.get_ticks_usec()
		arrays[Mesh.ARRAY_VERTEX] = points; arrays[Mesh.ARRAY_NORMAL] = normals
		if reference_uv:
			# A voxel face's UV is a palette lookup, never the imported UV atlas.
			# Keep each small carrier triangle in one atlas chart. Geometry targets
			# still share positions across seams; UV/normal splits are visual only.
			var original := reference.surface_get_arrays(surface)
			var vertices: PackedVector3Array = original[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = original[Mesh.ARRAY_TEX_UV]
			var reference_normals: PackedVector3Array = original[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = original[Mesh.ARRAY_INDEX] if original[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var mapped := PackedVector2Array(); mapped.resize(points.size())
			for triangle in range(0,points.size(),3):
				var hit := _sample(grid,(points[triangle]+points[triangle+1]+points[triangle+2])/3.0,shared)
				var face := int(hit[2])
				var a := indices[face] if not indices.is_empty() else face
				var b := indices[face+1] if not indices.is_empty() else face+1
				var c := indices[face+2] if not indices.is_empty() else face+2
				for k in 3:
					var weights := _barycentric(_closest(points[triangle+k],vertices[a],vertices[b],vertices[c]),vertices[a],vertices[b],vertices[c])
					mapped[triangle+k] = uv[a]*weights.x+uv[b]*weights.y+uv[c]*weights.z
					# Interpolate authored normals, not the carrier's voxel face normal.
					normals[triangle+k] = (reference_normals[a]*weights.x+reference_normals[b]*weights.y+reference_normals[c]*weights.z).normalized()
				if triangle%384==0 and Time.get_ticks_usec()-started>6000:
					await host.get_tree().process_frame
					if not _valid(host):return null
					started=Time.get_ticks_usec()
			arrays[Mesh.ARRAY_TEX_UV] = mapped
			arrays[Mesh.ARRAY_NORMAL] = normals
		if layered:
			# The closed voxel carrier keeps one face ID per triangle. IDs belong to the
			# detailed reference; do not interpolate unrelated labels across its vertices.
			var original:Array=reference.surface_get_arrays(surface)
			var labels:PackedVector2Array=original[Mesh.ARRAY_TEX_UV2]
			var indexed:PackedInt32Array=original[Mesh.ARRAY_INDEX] if original[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var mapped:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
			for triangle in range(0,points.size(),3):
				var hit:Array=_sample(grid,(points[triangle]+points[triangle+1]+points[triangle+2])/3.0,shared)
				var index:int=int(hit[2]);var id:float=labels[indexed[index] if not indexed.is_empty() else index].y
				for k in 3:mapped[triangle+k].y=id
				if triangle%384==0 and Time.get_ticks_usec()-started>6000:
					await host.get_tree().process_frame
					if not _valid(host):return null
					started=Time.get_ticks_usec()
			arrays[Mesh.ARRAY_TEX_UV2]=mapped
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},topology.surface_get_format(surface))
		mesh.surface_set_name(surface,reference.surface_get_name(surface))
	cache.write(key,{"surfaces":mesh.get("_surfaces")},func(): return false)
	cache.trim(256*1024*1024)
	if _carriers.size() >= 8: _carriers.erase(_carriers.keys()[0])
	_carriers[key] = mesh
	return mesh


static func _barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var u := b-a; var v := c-a; var w := p-a
	var determinant := u.length_squared()*v.length_squared()-u.dot(v)*u.dot(v)
	if absf(determinant)<0.00000001:return Vector3(1,0,0)
	var y := (v.length_squared()*w.dot(u)-u.dot(v)*w.dot(v))/determinant
	var z := (u.length_squared()*w.dot(v)-u.dot(v)*w.dot(u))/determinant
	return Vector3(1.0-y-z,y,z)


static func surface_mesh(mesh: ArrayMesh, surface: int) -> ArrayMesh:
	var result := ArrayMesh.new()
	append_surface(result,mesh,surface)
	return result


static func append_surface(result: ArrayMesh, mesh: ArrayMesh, surface: int) -> void:
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.surface_get_arrays(surface),[],{},mesh.surface_get_format(surface))
	result.surface_set_name(result.get_surface_count()-1,mesh.surface_get_name(surface))
	result.surface_set_material(result.get_surface_count()-1,mesh.surface_get_material(surface))


static func prepare(base: ArrayMesh, low: ArrayMesh, voxel: ArrayMesh, host: Node, aligned_low := false, aligned_voxel := false) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for surface in base.get_surface_count():
		if not _valid(host): return []
		var input := base.surface_get_arrays(surface)
		var a := low.surface_get_arrays(mini(surface, low.get_surface_count()-1))
		var b := voxel.surface_get_arrays(mini(surface, voxel.get_surface_count()-1))
		var key := Cache.digest([5, input[Mesh.ARRAY_VERTEX], input[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_INDEX], b[Mesh.ARRAY_VERTEX], b[Mesh.ARRAY_NORMAL], b[Mesh.ARRAY_INDEX], aligned_low, aligned_voxel])
		if _ready.has(key):
			result.append(_ready[key]); continue
		var cache := Cache.new()
		cache.directory = "user://ember-anomaly-cache"
		cache.max_bytes = 128*1024*1024
		var saved := cache.read(key)
		var points: PackedVector3Array = input[Mesh.ARRAY_VERTEX]
		var height := ceili(float(points.size()*4)/WIDTH)
		var bytes: PackedByteArray = saved.get("bytes", PackedByteArray())
		if bytes.size() == WIDTH*height*16:
			cache_hits += 1
		else:
			var values: PackedFloat32Array
			if aligned_low and aligned_voxel:
				values = _aligned_values(a,b,points.size())
			else:
				var normals: PackedVector3Array = input[Mesh.ARRAY_NORMAL]
				values = PackedFloat32Array(); values.resize(WIDTH*height*4)
				var low_grid := {} if aligned_low else _grid(a)
				var voxel_grid := {} if aligned_voxel else _grid(b)
				var shared_low: Dictionary = {}
				var shared_voxel: Dictionary = {}
				var started := Time.get_ticks_usec()
				for i in points.size():
					var p := points[i]
					var first_sample: Array = [(a[Mesh.ARRAY_VERTEX] as PackedVector3Array)[i], (a[Mesh.ARRAY_NORMAL] as PackedVector3Array)[i]] if aligned_low else _sample(low_grid, p, shared_low)
					var second_sample: Array = [(b[Mesh.ARRAY_VERTEX] as PackedVector3Array)[i], (b[Mesh.ARRAY_NORMAL] as PackedVector3Array)[i]] if aligned_voxel else _sample(voxel_grid, p, shared_voxel)
					var first: Vector3 = first_sample[0]
					var second: Vector3 = second_sample[0]
					var n1: Vector3 = first_sample[1]
					var n2: Vector3 = second_sample[1]
					for channel in 4:
						var v: Vector3 = [first, n1, second, n2][channel]
						var offset := (i*4+channel)*4
						values[offset] = v.x; values[offset+1] = v.y; values[offset+2] = v.z
					if i%256 == 0 and Time.get_ticks_usec()-started > 6000:
						await host.get_tree().process_frame
						if not _valid(host): return []
						started = Time.get_ticks_usec()
			bytes = values.to_byte_array()
			cache.write(key, {"bytes": bytes}, func(): return false)
			cache.trim(256*1024*1024)
			builds += 1
		var texture := ImageTexture.create_from_image(Image.create_from_data(WIDTH, height, false, Image.FORMAT_RGBAF, bytes))
		if _ready.size() >= 128: _ready.erase(_ready.keys()[0])
		_ready[key] = texture
		result.append(texture)
	return result


static func _aligned_values(low: Array, voxel: Array, count: int) -> PackedFloat32Array:
	var a: PackedVector3Array = low[Mesh.ARRAY_VERTEX]
	var an: PackedVector3Array = low[Mesh.ARRAY_NORMAL]
	var b: PackedVector3Array = voxel[Mesh.ARRAY_VERTEX]
	var bn: PackedVector3Array = voxel[Mesh.ARRAY_NORMAL]
	var values := PackedFloat32Array(); values.resize(WIDTH*ceili(float(count*4)/WIDTH)*4)
	for i in count:
		var offset := i*16
		values[offset]=a[i].x;values[offset+1]=a[i].y;values[offset+2]=a[i].z
		values[offset+4]=an[i].x;values[offset+5]=an[i].y;values[offset+6]=an[i].z
		values[offset+8]=b[i].x;values[offset+9]=b[i].y;values[offset+10]=b[i].z
		values[offset+12]=bn[i].x;values[offset+13]=bn[i].y;values[offset+14]=bn[i].z
	return values


## Pure scatter transport: preserve the original 3x4 transforms and prepare
## only the height deltas used by the existing grass shader.
static func scatter_values(cancelled:Callable, original:PackedFloat32Array,stride:int,roots:PackedVector3Array,local_roots:PackedVector3Array,fixed:PackedByteArray,fields:Dictionary,source,frame:Transform3D)->Dictionary:
	var values:=PackedFloat32Array();values.resize(roots.size()*16)
	var extent:=0.0
	for i in roots.size():
		if i%128==0 and cancelled.call():return {}
		for column in 12:values[i*16+column]=original[i*stride+column]
		if fixed[i]!=0:continue
		var local:=local_roots[i]
		var cell:=Vector2i(clampi(floori(local.x),0,source.width-1),clampi(floori(local.z),0,source.depth-1))
		var low:float=TerrainLook.plane(fields[Vector2i(cell.x/64,cell.y/64)],Vector2(local.x,local.z)).height
		var voxel:=float(source.origin_y+source.column_value("heights",source.column_index(cell.x,cell.y)))
		var low_delta:float=(frame*Vector3(local.x,low,local.z)).y-roots[i].y
		var voxel_delta:float=(frame*Vector3(local.x,voxel,local.z)).y-roots[i].y
		extent=maxf(extent,maxf(absf(low_delta),absf(voxel_delta)))
		values[i*16+12]=low_delta;values[i*16+13]=voxel_delta
	return {"buffer":values,"extent":extent}


static func _grid(arrays: Array) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var faces := vertices
	if not indices.is_empty():
		faces = PackedVector3Array(); faces.resize(indices.size())
		for i in indices.size(): faces[i] = vertices[indices[i]]
	var bounds := AABB(vertices[0], Vector3.ZERO)
	for p in vertices: bounds = bounds.expand(p)
	var cell := maxf(bounds.size[bounds.get_longest_axis_index()]/32.0, 0.0625)
	var buckets: Dictionary = {}
	for i in range(0, faces.size(), 3):
		var a := faces[i]; var b := faces[i+1]; var c := faces[i+2]
		var lo := Vector3i((a.min(b).min(c)/cell).floor())
		var hi := Vector3i((a.max(b).max(c)/cell).floor())
		for z in range(lo.z, hi.z+1):
			for y in range(lo.y, hi.y+1):
				for x in range(lo.x, hi.x+1):
					var key := Vector3i(x,y,z)
					if not buckets.has(key): buckets[key] = PackedInt32Array()
					buckets[key].append(i)
	return {"faces": faces, "buckets": buckets, "cell": cell}


static func _sample(grid: Dictionary, point: Vector3, shared: Dictionary) -> Array:
	if shared.has(point): return shared[point]
	var faces: PackedVector3Array = grid.faces
	var cell: float = grid.cell
	var origin := Vector3i((point/cell).floor())
	var best := point
	var normal := Vector3.UP
	var distance := INF
	var best_index:=0
	var visited: Dictionary = {}
	for ring in 34:
		for z in range(-ring, ring+1):
			for y in range(-ring, ring+1):
				for x in range(-ring, ring+1):
					if maxi(abs(x),maxi(abs(y),abs(z))) != ring: continue
					for index: int in grid.buckets.get(origin+Vector3i(x,y,z), PackedInt32Array()):
						if visited.has(index): continue
						visited[index] = true
						var candidate := _closest(point, faces[index], faces[index+1], faces[index+2])
						var d := point.distance_squared_to(candidate)
						if d < distance:
							best = candidate; distance = d; best_index=index
							normal = (faces[index+2]-faces[index]).cross(faces[index+1]-faces[index]).normalized()
		var lo := Vector3(origin-Vector3i.ONE*ring)*cell
		var hi := Vector3(origin+Vector3i.ONE*(ring+1))*cell
		var edge := minf(minf(point.x-lo.x,hi.x-point.x),minf(minf(point.y-lo.y,hi.y-point.y),minf(point.z-lo.z,hi.z-point.z)))
		if distance <= edge*edge: break
	var result := [best, normal, best_index]
	shared[point] = result
	return result


static func _closest(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b-a; var ac := c-a; var ap := p-a
	var d1 := ab.dot(ap); var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0: return a
	var bp := p-b
	var d3 := ab.dot(bp); var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3: return b
	var vc := d1*d4-d3*d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0: return a+ab*(d1/(d1-d3))
	var cp := p-c
	var d5 := ab.dot(cp); var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6: return c
	var vb := d5*d2-d1*d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0: return a+ac*(d2/(d2-d6))
	var va := d3*d6-d5*d4
	if va <= 0.0 and d4-d3 >= 0.0 and d5-d6 >= 0.0: return b+(c-b)*((d4-d3)/((d4-d3)+(d5-d6)))
	var denominator := va+vb+vc
	if absf(denominator) < 0.00000001: return a
	return a+ab*(vb/denominator)+ac*(vc/denominator)

