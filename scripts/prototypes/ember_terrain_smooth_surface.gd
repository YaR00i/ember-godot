extends RefCounted
## Derived fine-grid surface. Source columns are read only; the same triangles
## supply rendering, collision, editor picking and floor-height queries.
const HALO := 11 # Three radius-3 passes, normal neighbour and corner column.
const MAX_COLUMNS := 262144 # First exact-detail slice: at most 32x32 blocks.
const KERNEL := [1.0, 6.0, 15.0, 20.0, 15.0, 6.0, 1.0]
const MATERIAL_KERNEL := [1.0,7.0,21.0,35.0,35.0,21.0,7.0,1.0]

class FieldJob extends RefCounted:
	# Rendering and placement share the exact float32 passes. Authoring jobs
	# may yield between rows instead of blocking while preparing a whole tile.
	var finished := false
	var result: Dictionary
	var _source
	var _start: Vector2i
	var _size: Vector2i
	var _heights := PackedFloat32Array()
	var _horizontal := PackedFloat32Array()
	var _phase := 0
	var _row := 0
	var _pass := 0
	func _init(source, bounds: Rect2i) -> void:
		_source=source;_start=bounds.position-Vector2i(10,10);_size=bounds.size+Vector2i(21,21)
		_heights.resize(_size.x*_size.y)
	func step(budget_us := 4000) -> void:
		var started:=Time.get_ticks_usec()
		while not finished and Time.get_ticks_usec()-started<budget_us:
			var z:=_row
			for x in _size.x:
				var h:=0.0
				if _phase==0:
					var p:=_start+Vector2i(x,z)
					for oz in [-1,0]:
						for ox in [-1,0]:
							var sx:=clampi(p.x+ox,0,_source.width-1)
							var sz:=clampi(p.y+oz,0,_source.depth-1)
							h+=float(_source.column_value("heights",_source.column_index(sx,sz)))
					_heights[x+z*_size.x]=h*0.25+_source.origin_y
				elif _phase==1:
					for tap in 7:h+=_heights[clampi(x+tap-3,0,_size.x-1)+z*_size.x]*KERNEL[tap]/64.0
					_horizontal[x+z*_size.x]=h
				else:
					for tap in 7:h+=_horizontal[x+clampi(z+tap-3,0,_size.y-1)*_size.x]*KERNEL[tap]/64.0
					_heights[x+z*_size.x]=h
			_row+=1
			if _row<_size.y:continue
			_row=0
			if _phase==2:
				_pass+=1
				if _pass==3:
					result={"start":_start,"size":_size,"heights":_heights};finished=true
					_source=null;_horizontal=PackedFloat32Array();continue
				_phase=1
			else:_phase+=1
			if _phase==1:_horizontal=_heights.duplicate()

static func field(source, bounds: Rect2i) -> Dictionary:
	var job:=FieldJob.new(source,bounds)
	while not job.finished:job.step(1000000)
	return job.result

static func corner(data: Dictionary,x: int,z: int) -> float:
	var p: Vector2i = Vector2i(x,z)-data.start
	return data.heights[p.x+p.y*data.size.x]

static func normal(data: Dictionary,x: int,z: int) -> Vector3:
	return Vector3((corner(data,x-1,z)-corner(data,x+1,z))*0.5,1.0,(corner(data,x,z-1)-corner(data,x,z+1))*0.5).normalized()

static func sample(data: Dictionary,p: Vector2) -> float:
	var x := floori(p.x); var z := floori(p.y)
	var t := p-Vector2(x,z)
	var a := corner(data,x,z);var b := corner(data,x+1,z)
	var c := corner(data,x,z+1);var d := corner(data,x+1,z+1)
	return a+(b-a)*t.x+(c-a)*t.y if t.x+t.y<=1.0 else d+(c-d)*(1.0-t.x)+(b-d)*(1.0-t.y)

# Presentation experiment: derive two stepped targets from the same field.
# Zones are (centre x/z, radius, feather) in metres; no source writes.
static func anomaly_targets(data: Dictionary,bounds: Rect2i,zones: Array[Vector4],origin_y: int,coarse_data: Dictionary) -> Array[Dictionary]:
	var results: Array[Dictionary]=[]
	for mode in 2:
		var target: Dictionary=data.duplicate()
		target.heights=(data.heights as PackedFloat32Array).duplicate()
		var cell:=8 if mode==0 else 16
		var quantum:=4 if mode==0 else 16
		for z in range(bounds.position.y-1,bounds.end.y+2):
			for x in range(bounds.position.x-1,bounds.end.x+2):
				var mask:=0.0
				for zone in zones:
					var distance:=Vector2(x/16.0-zone.x,z/16.0-zone.y).length()
					mask=maxf(mask,1.0-smoothstep(zone.z-zone.w,zone.z,distance))
				if mask<=0.0:continue
				var centre:=Vector2(floori(float(x)/cell)*cell+cell*0.5,floori(float(z)/cell)*cell+cell*0.5)
				var quantized:=roundf((sample(coarse_data,centre)-origin_y)/quantum)*quantum+origin_y
				var p: Vector2i=Vector2i(x,z)-data.start
				target.heights[p.x+p.y*data.size.x]=lerpf(corner(data,x,z),quantized,mask)
		results.append(target)
	return results

static func anomaly_weights(phase: float) -> Vector2:
	var p:=clampf(phase,0.0,1.0)
	return Vector2(p*2.0,0.0) if p<=0.5 else Vector2(2.0-p*2.0,p*2.0-1.0)

static func anomaly_mesh_target(mesh: ArrayMesh,data: Dictionary) -> Array:
	var original:=mesh.surface_get_arrays(0)
	var points: PackedVector3Array=original[Mesh.ARRAY_VERTEX].duplicate()
	var normals: PackedVector3Array=original[Mesh.ARRAY_NORMAL].duplicate()
	var cache: Dictionary={}
	for i in points.size():
		if normals[i].y<=0.0:continue # Outer vertical walls are outside dry zones.
		var p:=Vector2i(roundi(points[i].x),roundi(points[i].z))
		if not cache.has(p):cache[p]=[corner(data,p.x,p.y),normal(data,p.x,p.y)]
		points[i].y=cache[p][0];normals[i]=cache[p][1]
	var result:=[];result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX]=points;result[Mesh.ARRAY_NORMAL]=normals
	return result

static func palette_at(source,x: int,z: int,fallback: int) -> int:
	var sx := clampi(x,0,source.width-1);var sz := clampi(z,0,source.depth-1)
	if not source.has_column(sx,sz):return fallback
	var value: int=source.column_value("top_materials",source.column_index(sx,sz))
	return value if value>0 else fallback

static func material_weights(source,p: Vector2i,cache: Dictionary) -> Dictionary:
	if cache.has(p):return cache[p]
	var weights: Dictionary={}
	for z in 8:
		for x in 8:
			var slot:=palette_at(source,p.x+x-4,p.y+z-4,0)
			if slot<=0:continue
			weights[slot]=float(weights.get(slot,0.0))+MATERIAL_KERNEL[x]*MATERIAL_KERNEL[z]/16384.0
	cache[p]=weights
	return weights

static func _uniform_material(source,bounds: Rect2i) -> int:
	var slot:=0
	# The whole material kernel, including corners on the neighbouring tile.
	for z in range(bounds.position.y-4,bounds.end.y+4):
		for x in range(bounds.position.x-4,bounds.end.x+4):
			var value:=palette_at(source,x,z,0)
			if value<=0:return 0
			if slot==0:slot=value
			elif value!=slot:return 0
	return slot

static func build(source,bounds: Rect2i,blend_materials:=false,uniform_fastpath:=true) -> Dictionary:
	var data := field(source,bounds)
	var uniform:=_uniform_material(source,bounds) if blend_materials and uniform_fastpath else 0
	var material_cache: Dictionary={}
	var points := PackedVector3Array();var normals := PackedVector3Array()
	var colors := PackedColorArray();var uv := PackedVector2Array();var uv2 := PackedVector2Array()
	for z in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			if not source.has_column(x,z):continue
			var index: int=source.column_index(x,z)
			var top: int=source.column_value("top_materials",index)
			if top<=0 or source.column_value("heights",index)<=0:continue
			var a:=Vector3(x,corner(data,x,z),z);var b:=Vector3(x+1,corner(data,x+1,z),z)
			var c:=Vector3(x,corner(data,x,z+1),z+1);var d:=Vector3(x+1,corner(data,x+1,z+1),z+1)
			var ns: Array[Vector3]=[normal(data,x,z),normal(data,x+1,z),normal(data,x,z+1),normal(data,x+1,z+1)]
			if uniform>0:
				_emit_uniform([a,b,c],[ns[0],ns[1],ns[2]],uniform,points,normals,colors,uv,uv2)
				_emit_uniform([b,d,c],[ns[1],ns[3],ns[2]],uniform,points,normals,colors,uv,uv2)
			elif blend_materials:
				var masks: Array=[material_weights(source,Vector2i(x,z),material_cache),material_weights(source,Vector2i(x+1,z),material_cache),material_weights(source,Vector2i(x,z+1),material_cache),material_weights(source,Vector2i(x+1,z+1),material_cache)]
				_emit_blended([a,b,c],[ns[0],ns[1],ns[2]],[masks[0],masks[1],masks[2]],top,points,normals,colors,uv,uv2)
				_emit_blended([b,d,c],[ns[1],ns[3],ns[2]],[masks[1],masks[3],masks[2]],top,points,normals,colors,uv,uv2)
			else:
				var ids: Array[int]=[palette_at(source,x,z,top),palette_at(source,x+1,z,top),palette_at(source,x,z+1,top),palette_at(source,x+1,z+1,top)]
				_emit([a,b,c],[ns[0],ns[1],ns[2]],[ids[0],ids[1],ids[2]],points,normals,colors,uv,uv2)
				_emit([b,d,c],[ns[1],ns[3],ns[2]],[ids[1],ids[3],ids[2]],points,normals,colors,uv,uv2)
			# Only outer/hole walls remain; no internal voxel steps.
			var base: int=source.column_value("base_materials",index)
			for side in 4:
				var ncell: Vector2i = Vector2i(x,z)+[Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN][side]
				if source.has_column(ncell.x,ncell.y) and source.column_value("heights",source.column_index(ncell.x,ncell.y))>0:continue
				var left: Vector3;var right: Vector3;var n: Vector3
				match side:
					0:left=c;right=a;n=Vector3.LEFT
					1:left=b;right=d;n=Vector3.RIGHT
					2:left=a;right=b;n=Vector3.FORWARD
					3:left=d;right=c;n=Vector3.BACK
				var low_left:=Vector3(left.x,source.origin_y,left.z)
				var low_right:=Vector3(right.x,source.origin_y,right.z)
				_emit([left,low_left,right],[n,n,n],[base,base,base],points,normals,colors,uv,uv2)
				_emit([right,low_left,low_right],[n,n,n],[base,base,base],points,normals,colors,uv,uv2)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	var mesh:=ArrayMesh.new()
	if not points.is_empty():mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return {"terrain":mesh,"collision_faces":points,"smooth_field":data}

static func _emit_uniform(ps: Array,ns: Array,slot: int,points: PackedVector3Array,normals: PackedVector3Array,colors: PackedColorArray,uv: PackedVector2Array,uv2: PackedVector2Array) -> void:
	# Exactly the one-slot output of _emit_blended, not barycentric _emit.
	for i in 3:
		points.append(ps[i]);normals.append(ns[i]);colors.append(Color(1,0,0,float(slot)/255.0))
		uv.append(Vector2(slot,slot)/255.0);uv2.append(Vector2(float(slot)/255.0,0))

static func _emit_blended(ps: Array,ns: Array,masks: Array,fallback: int,points: PackedVector3Array,normals: PackedVector3Array,colors: PackedColorArray,uv: PackedVector2Array,uv2: PackedVector2Array) -> void:
	var total: Dictionary={}
	for mask: Dictionary in masks:
		for slot: int in mask:total[slot]=float(total.get(slot,0.0))+mask[slot]
	var ids: Array=total.keys()
	ids.sort_custom(func(a,b):return total[a]>total[b] if total[a]!=total[b] else a<b)
	if ids.is_empty():ids=[fallback]
	if ids.size()>3:ids.resize(3) # Existing shader has three slots per triangle.
	var active:=ids.size()
	while ids.size()<3:ids.append(ids[0])
	for i in 3:
		var weights:=Vector3.ZERO
		for j in active:weights[j]=float(masks[i].get(ids[j],0.0))
		if weights.length_squared()<0.00000001:weights=Vector3(1,0,0)
		weights/=weights.x+weights.y+weights.z
		points.append(ps[i]);normals.append(ns[i])
		colors.append(Color(weights.x,weights.y,weights.z,float(ids[0])/255.0))
		uv.append(Vector2(ids[0],ids[1])/255.0);uv2.append(Vector2(float(ids[2])/255.0,0.0))

static func _emit(ps: Array,ns: Array,ids: Array,points: PackedVector3Array,normals: PackedVector3Array,colors: PackedColorArray,uv: PackedVector2Array,uv2: PackedVector2Array) -> void:
	for i in 3:
		points.append(ps[i]);normals.append(ns[i])
		colors.append(Color(1.0 if i==0 else 0.0,1.0 if i==1 else 0.0,1.0 if i==2 else 0.0,float(ids[0])/255.0))
		uv.append(Vector2(ids[0],ids[1])/255.0);uv2.append(Vector2(float(ids[2])/255.0,0.0))
