extends RefCounted
## Canonical fine surface for physics/picking; a bounded far render mesh may
## use fewer triangles. Source columns, collision and floor heights stay exact.
const FIELD_BORDER := 10
const HALO := FIELD_BORDER + 1 # Three radius-3 passes, normal neighbour and corner column.
const MAX_COLUMNS := 262144 # First exact-detail slice: at most 32x32 blocks.
const KERNEL := [1.0, 6.0, 15.0, 20.0, 15.0, 6.0, 1.0]
const MATERIAL_KERNEL := [1.0,7.0,21.0,35.0,35.0,21.0,7.0,1.0]
const SurfaceRules=preload("res://scripts/prototypes/ember_terrain_surface_rules.gd")

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
	var _pass_limit := 3
	var _profile: Dictionary
	var _original := PackedFloat32Array()
	var _radius := 3
	var _kernel: Array=KERNEL
	var _threshold := 2.0
	var _preserve_edges := false
	var _rules: Dictionary={}
	var _bounds: Rect2i
	var _dense_heights := PackedInt32Array()
	var _source_width := 0
	var _source_depth := 0
	var _source_origin := 0
	func _init(source, bounds: Rect2i, filter_passes := 3, profile: Dictionary={},apply_rules:=true) -> void:
		_pass_limit=clampi(filter_passes,1,3)
		_profile=profile.duplicate(true)
		_radius=clampi(int(profile.get("radius_cells",3)),1,3)
		_kernel=[1.0,2.0,1.0] if _radius==1 else [1.0,4.0,6.0,4.0,1.0] if _radius==2 else KERNEL
		_threshold=maxf(0.001,float(profile.get("edge_threshold_m",0.125))*16.0)
		_preserve_edges=profile.get("preserve_edges",false)
		_source=source;_start=bounds.position-Vector2i.ONE*FIELD_BORDER;_size=bounds.size+Vector2i.ONE*(FIELD_BORDER*2+1)
		_source_width=source.width;_source_depth=source.depth;_source_origin=source.origin_y
		if not source.is_sectioned() and source.heights.size()==_source_width*_source_depth:
			_dense_heights=source.heights
		_bounds=bounds
		if apply_rules:_rules=source.surface_rules.duplicate()
		_heights.resize(_size.x*_size.y)
	func step(budget_us := 4000) -> void:
		var started:=Time.get_ticks_usec()
		while not finished and Time.get_ticks_usec()-started<budget_us:
			var z:=_row
			for x in _size.x:
				var h:=0.0
				if _phase==0:
					var p:=_start+Vector2i(x,z)
					if not _dense_heights.is_empty():
						# The immutable dense snapshot needs no per-corner Resource calls.
						var left:=clampi(p.x-1,0,_source_width-1);var right:=clampi(p.x,0,_source_width-1)
						var above:=clampi(p.y-1,0,_source_depth-1)*_source_width;var below:=clampi(p.y,0,_source_depth-1)*_source_width
						h=float(_dense_heights[left+above])+float(_dense_heights[right+above])+float(_dense_heights[left+below])+float(_dense_heights[right+below])
					else:
						for oz in [-1,0]:
							for ox in [-1,0]:
								var sx:=clampi(p.x+ox,0,_source.width-1)
								var sz:=clampi(p.y+oz,0,_source.depth-1)
								h+=float(_source.column_value("heights",_source.column_index(sx,sz)))
					_heights[x+z*_size.x]=h*0.25+_source_origin
				elif _phase==1:
					if _profile.is_empty():
						for tap in 7:h+=_heights[clampi(x+tap-3,0,_size.x-1)+z*_size.x]*KERNEL[tap]/64.0
					else:h=_filtered(x,z,true)
					_horizontal[x+z*_size.x]=h
				else:
					if _profile.is_empty():
						for tap in 7:h+=_horizontal[x+clampi(z+tap-3,0,_size.y-1)*_size.x]*KERNEL[tap]/64.0
					else:h=_filtered(x,z,false)
					_heights[x+z*_size.x]=h
			_row+=1
			if _row<_size.y:continue
			_row=0
			if _phase==2:
				_pass+=1
				if _pass==_pass_limit:
					if not _profile.is_empty():_apply_strength()
					if not _rules.is_empty():_apply_source_rules()
					result={"start":_start,"size":_size,"heights":_heights};finished=true
					_source=null;_horizontal=PackedFloat32Array();_original=PackedFloat32Array();continue
				_phase=1
			else:_phase+=1
			if _phase==1:
				_horizontal=_heights.duplicate()
				if (not _profile.is_empty() or not _rules.is_empty()) and _original.is_empty():_original=_heights.duplicate()

	func _apply_source_rules() -> void:
		var variants: Dictionary={3:_heights.duplicate()}
		var radii: Dictionary={}
		for key: Vector2i in _rules:
			if not Rect2i(key*64,Vector2i(64,64)).intersects(_bounds.grow(HALO)):continue
			var bytes: PackedByteArray=_rules[key]
			for code in bytes:
				if code>0 and code<=64:radii[(code-1)/32+1]=true
		for radius: int in radii:
			var job:=FieldJob.new(_source,_bounds,_pass_limit,{"radius_cells":radius},false)
			while not job.finished:job.step(1000000)
			variants[radius]=job.result.heights
		for z in _size.y:
			for x in _size.x:
				var i:=x+z*_size.x;var total:=0.0
				var corner:=_start+Vector2i(x,z)
				for oz in [-1,0]:
					for ox in [-1,0]:
						var cell:=Vector2i(clampi(corner.x+ox,0,_source.width-1),clampi(corner.y+oz,0,_source.depth-1))
						var code:=SurfaceRules.read(_rules,cell)
						if code==0:total+=variants[3][i]
						elif code>=128:total+=lerpf(variants[3][i],_original[i],float(code-127)/128.0)
						else:
							var radius: int=(code-1)/32+1
							total+=lerpf(_original[i],variants[radius][i],float((code-1)%32)/31.0)
				_heights[i]=total*0.25

	func _filtered(x: int,z: int,horizontal: bool) -> float:
		var values:=_heights if horizontal else _horizontal
		var centre:=values[x+z*_size.x]
		var ahead:=values[clampi(x+1,0,_size.x-1)+z*_size.x] if horizontal else values[x+clampi(z+1,0,_size.y-1)*_size.x]
		var behind:=values[clampi(x-1,0,_size.x-1)+z*_size.x] if horizontal else values[x+clampi(z-1,0,_size.y-1)*_size.x]
		var gradient:=(ahead-behind)*0.5
		var total:=0.0;var weight_sum:=0.0
		for offset in range(-_radius,_radius+1):
			var sx:=clampi(x+offset,0,_size.x-1) if horizontal else x
			var sz:=z if horizontal else clampi(z+offset,0,_size.y-1)
			var height:=values[sx+sz*_size.x]
			var weight: float=_kernel[offset+_radius]
			if _preserve_edges:
				# Remove the local plane's slope from edge detection. Otherwise a
				# steep quantized face is mistaken for dozens of protected breaks.
				var difference:=(height-centre-gradient*offset)/_threshold
				weight*=exp(-0.5*difference*difference)
			total+=height*weight;weight_sum+=weight
		return total/weight_sum

	func _apply_strength() -> void:
		var strength:=clampf(float(_profile.get("strength",1.0)),0.0,1.0)
		var feather:=maxf(0.001,float(_profile.get("protection_feather_m",0.15)))
		for z in _size.y:
			for x in _size.x:
				var point:=Vector2(_start+Vector2i(x,z))/16.0
				var protection:=0.0
				for region: Rect2 in _profile.get("protected_regions",[]):
					var nearest:=Vector2(clampf(point.x,region.position.x,region.end.x),clampf(point.y,region.position.y,region.end.y))
					protection=maxf(protection,1.0-smoothstep(0.0,feather,point.distance_to(nearest)))
				var i:=x+z*_size.x
				_heights[i]=lerpf(_original[i],_heights[i],strength*(1.0-protection))

static func field(source, bounds: Rect2i, filter_passes := 3) -> Dictionary:
	var job:=FieldJob.new(source,bounds,filter_passes)
	while not job.finished:job.step(1000000)
	return job.result

static func controlled_field(source,bounds: Rect2i,profile: Dictionary) -> Dictionary:
	# Opt-in derived LAB settings, not Resource metadata or a material policy.
	# Existing default callers retain the exact original three-pass result.
	var job:=FieldJob.new(source,bounds,clampi(int(profile.get("passes",3)),1,3),profile)
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
	# Read the same four fine-grid corners. Floor/scatter probes call this
	# millions of times; unpack the immutable field once instead of four times.
	var offset:=Vector2i(x,z)-Vector2i(data.start)
	var width:int=data.size.x
	var heights:PackedFloat32Array=data.heights
	var index:=offset.x+offset.y*width
	var a:=float(heights[index]);var b:=float(heights[index+1])
	var c:=float(heights[index+width]);var d:=float(heights[index+width+1])
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

static func contact_cell(source,point:Vector3,surface_normal:Vector3,search_radius:=1) -> Vector2i:
	var inward:=Vector3(surface_normal.x,0,surface_normal.z)
	var sample:=point-inward.normalized()*0.51 if surface_normal.y<0.8 else point
	var cell:=Vector2i(clampi(floori(sample.x),0,source.width-1),clampi(floori(sample.z),0,source.depth-1))
	if surface_normal.y>=0.8:return cell
	if source.has_column(cell.x,cell.y) and source.column_value("heights",source.column_index(cell.x,cell.y))+source.origin_y>point.y:return cell
	if search_radius>1:
		for step in range(1,search_radius+1):
			var q:=point-inward.normalized()*(float(step)+0.51)
			var candidate:=Vector2i(floori(q.x),floori(q.z))
			if source.has_column(candidate.x,candidate.y) and source.column_value("heights",source.column_index(candidate.x,candidate.y))+source.origin_y>point.y:return candidate
	var best:=INF;var chosen:=cell
	for z in range(maxi(0,cell.y-1),mini(source.depth,cell.y+2)):
		for x in range(maxi(0,cell.x-1),mini(source.width,cell.x+2)):
			if not source.has_column(x,z) or source.column_value("heights",source.column_index(x,z))+source.origin_y<=point.y:continue
			var distance:=Vector2(point.x-x-0.5,point.z-z-0.5).length_squared()
			if distance<best:best=distance;chosen=Vector2i(x,z)
	return chosen


static func faceted_side_arrays(source,original:Array,faceted:Array) -> Array:
	var points:PackedVector3Array=faceted[Mesh.ARRAY_VERTEX]
	if points.is_empty():return faceted
	var begin:=Vector2(points[0].x,points[0].z);var end:=begin
	for p in points:begin=begin.min(Vector2(p.x,p.z));end=end.max(Vector2(p.x,p.z))
	var window=source.dense_window(Rect2i(Vector2i(begin)-Vector2i(8,8),Vector2i(end-begin)+Vector2i(17,17)).intersection(Rect2i(0,0,source.width,source.depth)))
	if window.column_material_overrides.is_empty():return faceted
	var normals:PackedVector3Array=faceted[Mesh.ARRAY_NORMAL]
	var old_points:PackedVector3Array=original[Mesh.ARRAY_VERTEX]
	var old_normals:PackedVector3Array=original[Mesh.ARRAY_NORMAL]
	var colors:PackedColorArray=faceted[Mesh.ARRAY_COLOR]
	var uv:PackedVector2Array=faceted[Mesh.ARRAY_TEX_UV];var uv2:PackedVector2Array=faceted[Mesh.ARRAY_TEX_UV2]
	for i in range(0,points.size(),3):
		var ids:Array[int]=[];var changed:=false
		for j in 3:
			var at:=i+j;var p:=points[at];var old:=old_points[at]
			var old_cell:=contact_cell(source,old,old_normals[at])
			var old_values:Dictionary=source.side_overrides(source.column_index(old_cell.x,old_cell.y))
			var inherited:=old_normals[at].y<0.8 and old_values.has(floori(old.y-source.origin_y))
			var cell:=contact_cell(source,p,normals[at],8)
			var values:Dictionary=source.side_overrides(source.column_index(cell.x,cell.y))
			var slot:int=values.get(floori(p.y-source.origin_y),0) if normals[at].y<0.8 else 0
			if slot>0:changed=true
			elif inherited:slot=source.column_value("top_materials",source.column_index(old_cell.x,old_cell.y));changed=true
			else:
				var weights:=Vector3(colors[at].r,colors[at].g,colors[at].b)
				slot=roundi((uv[at].x if weights.x>=weights.y and weights.x>=weights.z else uv[at].y if weights.y>=weights.z else uv2[at].x)*255.0)
			ids.append(slot)
		if not changed:continue
		for j in 3:
			colors[i+j]=Color(1.0 if j==0 else 0.0,1.0 if j==1 else 0.0,1.0 if j==2 else 0.0,float(ids[0])/255.0)
			uv[i+j]=Vector2(ids[0],ids[1])/255.0;uv2[i+j]=Vector2(float(ids[2])/255.0,0)
	faceted[Mesh.ARRAY_COLOR]=colors;faceted[Mesh.ARRAY_TEX_UV]=uv;faceted[Mesh.ARRAY_TEX_UV2]=uv2
	return faceted


static func _clip_height(polygon:Array,height:float,above:bool) -> Array:
	var result:Array=[]
	for i in polygon.size():
		var a:Array=polygon[i];var b:Array=polygon[(i+1)%polygon.size()]
		var inside_a:bool=a[0].y>=height if above else a[0].y<=height
		var inside_b:bool=b[0].y>=height if above else b[0].y<=height
		if inside_a:result.append(a)
		if inside_a!=inside_b:
			var t:float=(height-a[0].y)/(b[0].y-a[0].y)
			result.append([a[0].lerp(b[0],t),a[1].lerp(b[1],t).normalized()])
	return result


static func _emit_side_paint(source,ps:Array,ns:Array,points:PackedVector3Array,normals:PackedVector3Array,colors:PackedColorArray,uv:PackedVector2Array,uv2:PackedVector2Array,fallback: int=-1) -> bool:
	var n:Vector3=(ps[2]-ps[0]).cross(ps[1]-ps[0]).normalized()
	if n.y<0:n=-n
	if absf((ns[0]+ns[1]+ns[2]).y)<0.00001:n=(ns[0]+ns[1]+ns[2]).normalized()
	if n.y>0.8:return false
	var centre:Vector3=(ps[0]+ps[1]+ps[2])/3.0
	var cell:=contact_cell(source,centre,n);var index:int=source.column_index(cell.x,cell.y)
	var overrides:Dictionary=source.side_overrides(index)
	if overrides.is_empty():return false
	var low:float=minf(ps[0].y,minf(ps[1].y,ps[2].y));var high:float=maxf(ps[0].y,maxf(ps[1].y,ps[2].y))
	var levels:Array[float]=[low,high]
	var cap:int=source.column_value("heights",index)-source.column_value("cap_depths",index)
	for y:int in overrides:
		for edge in [float(source.origin_y+y),float(source.origin_y+y+1)]:
			if edge>low and edge<high and not levels.has(edge):levels.append(edge)
	var cap_y:=float(source.origin_y+cap)
	if cap_y>low and cap_y<high and not levels.has(cap_y):levels.append(cap_y)
	levels.sort()
	for band in range(levels.size()-1):
		var polygon:=_clip_height([[ps[0],ns[0]],[ps[1],ns[1]],[ps[2],ns[2]]],levels[band],true)
		polygon=_clip_height(polygon,levels[band+1],false)
		var y:=floori((levels[band]+levels[band+1])*0.5-source.origin_y)
		var slot:int=overrides.get(y,fallback if fallback>=0 else source.column_value("top_materials",index))
		for j in range(1,polygon.size()-1):
			var a:Vector3=polygon[0][0];var b:Vector3=polygon[j][0];var c:Vector3=polygon[j+1][0]
			if (b-a).cross(c-a).length_squared()<0.00000001:continue
			_emit_uniform([a,b,c],[polygon[0][1],polygon[j][1],polygon[j+1][1]],slot,points,normals,colors,uv,uv2)
	return true


static func palette_at(source,x: int,z: int,fallback: int) -> int:
	var sx := clampi(x,0,source.width-1);var sz := clampi(z,0,source.depth-1)
	if not source.has_column(sx,sz):return fallback
	var value: int=source.column_value("top_materials",source.column_index(sx,sz))
	return value if value>0 else fallback

static func material_weights(source,p: Vector2i,cache: Dictionary) -> Dictionary:
	if cache.has(p):return cache[p]
	var weights: Dictionary={}
	for z in 8:
		# The separable integer kernel is exact. Adjacent corners reuse each
		# horizontal row instead of reading the same 8x8 palette window again.
		var row_key:=Vector3i(p.x,p.y+z-4,1)
		if not cache.has(row_key):
			var row: Dictionary={}
			for x in 8:
				var slot:=palette_at(source,p.x+x-4,row_key.y,0)
				if slot>0:row[slot]=int(row.get(slot,0))+MATERIAL_KERNEL[x]
			cache[row_key]=row
		for slot: int in cache[row_key]:
			weights[slot]=float(weights.get(slot,0.0))+cache[row_key][slot]*MATERIAL_KERNEL[z]/16384.0
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

static func build(source,bounds: Rect2i,blend_materials:=false,uniform_fastpath:=true,prepared_field: Dictionary={},capture_layout:=false) -> Dictionary:
	return publish_arrays(build_arrays(source,bounds,blend_materials,uniform_fastpath,prepared_field,capture_layout))

static func publish_arrays(data:Dictionary)->Dictionary:
	if data.is_empty():return {}
	var result:=data.duplicate()
	var upload:Dictionary=data.get("render_upload",{})
	result.terrain=publish_render_mesh(upload.get("arrays",data.arrays),upload.get("detail",data.get("render_detail",{})))
	result.erase("render_upload")
	return result

## Fine arrays/layout/field remain the editable and physical surface. Only the
## disposable GPU mesh receives indices chosen by native screen-error LOD.
static func publish_render_mesh(input:Array,detail:Dictionary={})->ArrayMesh:
	var mesh:=ArrayMesh.new()
	if input[Mesh.ARRAY_VERTEX].is_empty():return mesh
	var arrays:=input
	var indices:PackedInt32Array=detail.get("indices",PackedInt32Array())
	if not indices.is_empty():
		arrays=input.duplicate()
		if detail.get("planar",false):
			for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
				arrays[channel]=input[channel].slice(0,0)
				for i in indices:arrays[channel].append(input[channel][i])
		else:arrays[Mesh.ARRAY_INDEX]=indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],detail.get("lods",{}))
	return mesh


## CPU-only indexing of disposable render data. Canonical fine arrays, palette
## seams, collision, and every native LOD triangle retain their exact attributes.
static func prepare_render_upload(input:Array,detail:Dictionary,cancelled:=Callable())->Dictionary:
	if cancelled.is_valid() and cancelled.call():return {}
	var original:Dictionary={"arrays":input,"detail":detail}
	var indices:PackedInt32Array=detail.get("indices",PackedInt32Array())
	if input.is_empty() or detail.get("planar",false):return original
	# Keep unsupported formats/indexed callers on the existing path.
	for channel in range(Mesh.ARRAY_MAX):
		if channel not in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2] and input[channel]!=null:return original
	var tool:=SurfaceTool.new();tool.create_from_arrays(input);tool.index()
	var arrays:=tool.commit_to_arrays()
	if cancelled.is_valid() and cancelled.call():return {}
	var remap:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	if remap.size()!=input[Mesh.ARRAY_VERTEX].size() or arrays[Mesh.ARRAY_VERTEX].size()>=input[Mesh.ARRAY_VERTEX].size():return original
	var mapped:=detail.duplicate();var base:=remap.duplicate() if indices.is_empty() else indices.duplicate()
	if not indices.is_empty():
		for i in base.size():base[i]=remap[base[i]]
	mapped.indices=base
	var lods:Dictionary={}
	for error in detail.get("lods",{}):
		if cancelled.is_valid() and cancelled.call():return {}
		var level:PackedInt32Array=detail.lods[error].duplicate()
		for i in level.size():level[i]=remap[level[i]]
		lods[error]=level
	mapped.lods=lods
	return {"arrays":arrays,"detail":mapped}


static func build_arrays(source,bounds: Rect2i,blend_materials:=false,uniform_fastpath:=true,prepared_field: Dictionary={},capture_layout:=false,cancelled:=Callable(),far_stride:=1) -> Dictionary:
	# Explicit studies may supply an already derived field. Render, collision
	# and returned floor data still consume this single set of heights.
	if cancelled.is_valid() and cancelled.call():return {}
	var data := field(source,bounds) if prepared_field.is_empty() else prepared_field
	var uniform:=_uniform_material(source,bounds) if blend_materials and uniform_fastpath else 0
	var material_cache: Dictionary={}
	var has_side_paint:bool=not source.column_material_overrides.is_empty()
	if source.is_sectioned():
		for part in source.sections.values():
			if not part.column_material_overrides.is_empty():has_side_paint=true;break
	var points := PackedVector3Array();var normals := PackedVector3Array()
	var colors := PackedColorArray();var uv := PackedVector2Array();var uv2 := PackedVector2Array()

	for z in range(bounds.position.y,bounds.end.y):
		if cancelled.is_valid() and cancelled.call():return {}
		for x in range(bounds.position.x,bounds.end.x):
			if not source.has_column(x,z):continue
			var index: int=source.column_index(x,z)
			var top: int=source.column_value("top_materials",index)
			if top<=0 or source.column_value("heights",index)<=0:continue
			var a:=Vector3(x,corner(data,x,z),z);var b:=Vector3(x+1,corner(data,x+1,z),z)
			var c:=Vector3(x,corner(data,x,z+1),z+1);var d:=Vector3(x+1,corner(data,x+1,z+1),z+1)
			var ns: Array[Vector3]=[normal(data,x,z),normal(data,x+1,z),normal(data,x,z+1),normal(data,x+1,z+1)]
			var painted_a:=_emit_side_paint(source,[a,b,c],[ns[0],ns[1],ns[2]],points,normals,colors,uv,uv2) if has_side_paint else false
			var masks:Array=[];var ids:Array=[]
			if uniform>0:
				if not painted_a:_emit_uniform([a,b,c],[ns[0],ns[1],ns[2]],uniform,points,normals,colors,uv,uv2)
			elif blend_materials:
				masks=[material_weights(source,Vector2i(x,z),material_cache),material_weights(source,Vector2i(x+1,z),material_cache),material_weights(source,Vector2i(x,z+1),material_cache),material_weights(source,Vector2i(x+1,z+1),material_cache)]
				if not painted_a:_emit_blended([a,b,c],[ns[0],ns[1],ns[2]],[masks[0],masks[1],masks[2]],top,points,normals,colors,uv,uv2)
			else:
				ids=[palette_at(source,x,z,top),palette_at(source,x+1,z,top),palette_at(source,x,z+1,top),palette_at(source,x+1,z+1,top)]
				if not painted_a:_emit([a,b,c],[ns[0],ns[1],ns[2]],[ids[0],ids[1],ids[2]],points,normals,colors,uv,uv2)
			if has_side_paint and _emit_side_paint(source,[b,d,c],[ns[1],ns[3],ns[2]],points,normals,colors,uv,uv2):pass
			elif uniform>0:_emit_uniform([b,d,c],[ns[1],ns[3],ns[2]],uniform,points,normals,colors,uv,uv2)
			elif blend_materials:_emit_blended([b,d,c],[ns[1],ns[3],ns[2]],[masks[1],masks[3],masks[2]],top,points,normals,colors,uv,uv2)
			else:_emit([b,d,c],[ns[1],ns[3],ns[2]],[ids[1],ids[3],ids[2]],points,normals,colors,uv,uv2)
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
				if not _emit_side_paint(source,[left,low_left,right],[n,n,n],points,normals,colors,uv,uv2,base):_emit([left,low_left,right],[n,n,n],[base,base,base],points,normals,colors,uv,uv2)
				if not _emit_side_paint(source,[right,low_left,low_right],[n,n,n],points,normals,colors,uv,uv2,base):_emit([right,low_left,low_right],[n,n,n],[base,base,base],points,normals,colors,uv,uv2)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_TEX_UV2]=uv2
	var result: Dictionary={"arrays":arrays,"collision_faces":points,"smooth_field":data}
	result.render_detail=render_detail(arrays,bounds,data,cancelled,not blend_materials)
	if cancelled.is_valid() and cancelled.call():return {}
	if capture_layout:
		var render_points:PackedVector3Array=result.arrays[Mesh.ARRAY_VERTEX]
		var render_normals:PackedVector3Array=result.arrays[Mesh.ARRAY_NORMAL]
		var kinds:=PackedByteArray();kinds.resize(render_points.size())
		for i in render_points.size():
			# Each wall quad emits [upper,base,upper, upper,base,base].
			# Explicit roles also work when high world origins round an upper
			# height onto the same float32 value as the base.
			kinds[i]=1 if render_normals[i].y>0.0 else 2 if i%6 in [0,2,3] else 0
		result.layout={"key":layout_key(source,bounds,blend_materials),"arrays":result.arrays,"kinds":kinds,"side_paint":has_side_paint}
		if not blend_materials:result.layout.uniform_palette_lod=true
	return result


## ImporterMesh/meshoptimizer preserves native mesh/material boundaries. Its
## error also includes normal/pigment importance. Calibrate it upward with the
## actual vertical error against the canonical piecewise-linear fine surface.
static func render_detail(input:Array,bounds:Rect2i,field:Dictionary,cancelled:=Callable(),uniform_palette_lod:=false)->Dictionary:
	var start:=Time.get_ticks_usec()
	var result:Dictionary={"indices":PackedInt32Array(),"lods":{},"base_triangles":input[0].size()/3,"planar":false}
	var analysis:=_render_uniform_palette_input(input) if uniform_palette_lod else input
	var plane:=_render_plane_indices(analysis,bounds)
	if not plane.is_empty():
		result.indices=plane;result.base_triangles=2;result.planar=true;result.cpu_us=Time.get_ticks_usec()-start;return result
	if input[0].size()<96:return result
	var arrays:=analysis.duplicate();var indices:=PackedInt32Array();indices.resize(input[0].size())
	for i in indices.size():indices[i]=i
	arrays[Mesh.ARRAY_INDEX]=indices
	var importer:=ImporterMesh.new();importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays);importer.generate_lods(60.0,0.0,[])
	for level in importer.get_surface_lod_count(0):
		if cancelled.is_valid() and cancelled.call():return {}
		var lod:=importer.get_surface_lod_indices(0,level)
		if not _render_palette_ids_valid(arrays,lod):continue
		var measured:=_render_height_error(input[0],lod,bounds,field) if not field.is_empty() else 0.0
		var error:=maxf(measured+0.00001,maxf(0.000001,importer.get_surface_lod_size(0,level)))
		result.lods[error]=lod
	if not result.lods.is_empty():result.indices=indices
	result.cpu_us=Time.get_ticks_usec()-start
	return result
## Nonblend triangles encode barycentric RGB even when all three palette
## IDs are identical. Those weights are semantically interchangeable, but
## native welding treats them as seams. Normalize only the simplifier input;
## published indices still refer to untouched canonical fine attributes.
static func _render_uniform_palette_input(input:Array)->Array:
	var arrays:=input.duplicate()
	var uv:PackedVector2Array=input[Mesh.ARRAY_TEX_UV]
	var uv2:PackedVector2Array=input[Mesh.ARRAY_TEX_UV2]
	var colours:PackedColorArray=input[Mesh.ARRAY_COLOR].duplicate()
	for i in colours.size():
		if uv[i].x==uv[i].y and uv[i].x==uv2[i].x:
			colours[i]=Color(1,0,0,colours[i].a)
	arrays[Mesh.ARRAY_COLOR]=colours
	return arrays

static func _render_palette_ids_valid(arrays:Array,indices:PackedInt32Array)->bool:
	var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV];var uv2:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2]
	var colours:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	for i in range(0,indices.size(),3):
		var a:=indices[i];var b:=indices[i+1];var c:=indices[i+2]
		if uv[a]!=uv[b] or uv[a]!=uv[c] or uv2[a]!=uv2[b] or uv2[a]!=uv2[c]:return false
		if colours[a].a!=colours[b].a or colours[a].a!=colours[c].a:return false
	return true
static func _render_plane_indices(arrays:Array,bounds:Rect2i)->PackedInt32Array:
	var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	if points.size()!=bounds.get_area()*6:return PackedInt32Array()
	var corners:Dictionary={};var wanted:Array=[bounds.position,bounds.position+Vector2i(bounds.size.x,0),bounds.position+Vector2i(0,bounds.size.y),bounds.end]
	for i in points.size():
		var p:=Vector2i(roundi(points[i].x),roundi(points[i].z))
		if p in wanted:corners[p]=i
	if corners.size()!=4:return PackedInt32Array()
	var a:int=corners[wanted[0]];var b:int=corners[wanted[1]];var c:int=corners[wanted[2]];var d:int=corners[wanted[3]]
	var n:Vector3=(points[b]-points[a]).cross(points[c]-points[a]).normalized()
	for i in points.size():
		if absf((points[i]-points[a]).dot(n))>0.0001:return PackedInt32Array()
		if (arrays[Mesh.ARRAY_NORMAL][i] as Vector3).distance_to(arrays[Mesh.ARRAY_NORMAL][a])>0.000001:return PackedInt32Array()
		for channel in [Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
			if arrays[channel][i]!=arrays[channel][a]:return PackedInt32Array()
	return PackedInt32Array([a,b,c,b,d,c])

static func _render_fine_height(heights:PackedFloat32Array,width:int,start:Vector2i,x:float,z:float)->float:
	var cx:=floori(x);var cz:=floori(z);var fx:=x-cx;var fz:=z-cz;var i:=(cz-start.y)*width+cx-start.x
	if fx+fz<=1.0:return heights[i]+(heights[i+1]-heights[i])*fx+(heights[i+width]-heights[i])*fz
	return heights[i+width+1]+(heights[i+width]-heights[i+width+1])*(1-fx)+(heights[i+1]-heights[i+width+1])*(1-fz)
static func _render_height_error(points:PackedVector3Array,indices:PackedInt32Array,bounds:Rect2i,field:Dictionary)->float:
	var heights:PackedFloat32Array=field.heights;var width:int=field.size.x;var start:Vector2i=field.start;var largest:=0.0
	for i in range(0,indices.size(),3):
		var a:=points[indices[i]];var b:=points[indices[i+1]];var c:=points[indices[i+2]]
		var bx:=b.x-a.x;var bz:=b.z-a.z;var cx:=c.x-a.x;var cz:=c.z-a.z;var den:=bx*cz-bz*cx
		if absf(den)<0.000001:continue
		for z in range(floori(minf(a.z,minf(b.z,c.z))),ceili(maxf(a.z,maxf(b.z,c.z)))+1):
			for x in range(floori(minf(a.x,minf(b.x,c.x))),ceili(maxf(a.x,maxf(b.x,c.x)))+1):
				var u:=((x-a.x)*cz-(z-a.z)*cx)/den;var v:=(bx*(z-a.z)-bz*(x-a.x))/den
				if u < -0.00001 or v < -0.00001 or u+v>1.00001:continue
				var expected:=heights[(z-start.y)*width+x-start.x]
				largest=maxf(largest,absf(a.y+(b.y-a.y)*u+(c.y-a.y)*v-expected))
		for edge in 3:
			var p:Vector3=a if edge==0 else b if edge==1 else c;var q:Vector3=b if edge==0 else c if edge==1 else a
			for axis in 3:
				var f:float=p.x if axis==0 else p.z if axis==1 else p.x+p.z;var t:float=q.x if axis==0 else q.z if axis==1 else q.x+q.z
				if absf(t-f)<0.000001:continue
				for line in range(ceili(minf(f,t)),floori(maxf(f,t))+1):
					var alpha:float=(line-f)/(t-f)
					if alpha<0 or alpha>1:continue
					var x:float=lerpf(p.x,q.x,alpha);var z:float=lerpf(p.z,q.z,alpha)
					largest=maxf(largest,absf(lerpf(p.y,q.y,alpha)-_render_fine_height(heights,width,start,x,z)))
	return largest

static func layout_key(source,bounds: Rect2i,blend_materials: bool) -> PackedByteArray:
	# Paint/holes/base walls affect attributes or topology. Ordinary height
	# changes do not. Include the material kernel and neighbouring hole walls.
	var part=source.dense_window(bounds.grow(4).intersection(Rect2i(0,0,source.width,source.depth)))
	var occupied:=PackedByteArray();occupied.resize(part.heights.size())
	for i in occupied.size():occupied[i]=1 if part.heights[i]>0 else 0
	var hash_context:=HashingContext.new();hash_context.start(HashingContext.HASH_SHA256)
	var values:Array=[bounds,source.width,source.depth,source.origin_y,blend_materials,part.top_materials,part.base_materials,occupied]
	if not part.column_material_overrides.is_empty():values.append([part.column_material_overrides,part.heights])
	hash_context.update(var_to_bytes(values))
	return hash_context.finish()


## CPU-only shape job. The layout/paint arrays are immutable shared input;
## RenderingServer, Mesh and collision publication stay on the main thread.
class HeightUpdateJob extends RefCounted:
	var result: Dictionary={}
	var _source
	var _bounds: Rect2i
	var _layout: Dictionary
	var _normal_sample: Callable
	var _render_detail: Callable
	var _render_upload:Callable
	func _init(source,bounds: Rect2i,layout: Dictionary,normal_sample: Callable, detail: Callable,upload:Callable) -> void:
		_source=source;_bounds=bounds;_layout=layout;_normal_sample=normal_sample;_render_detail=detail;_render_upload=upload
	func run(cancelled: Callable) -> void:
		var field_job:=FieldJob.new(_source,_bounds)
		while not field_job.finished:
			if cancelled.call():return
			field_job.step(2000)
		var data: Dictionary=field_job.result
		var arrays: Array=_layout.arrays.duplicate()
		var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var samples: Dictionary={}
		var heights: PackedFloat32Array=data.heights
		var kinds: PackedByteArray=_layout.kinds
		for i in points.size():
			if i%256==0 and cancelled.call():return
			var p:=points[i]
			var top:=kinds[i]==1
			if kinds[i]==0:continue
			var cell:=Vector2i(roundi(p.x),roundi(p.z))
			var local: Vector2i=cell-data.start
			p.y=heights[local.x+local.y*data.size.x];points[i]=p
			if top:
				if not samples.has(cell):samples[cell]=_normal_sample.call(data,cell.x,cell.y)
				normals[i]=samples[cell]
		arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals
		result={"arrays":arrays,"collision_faces":points,"smooth_field":data,"layout":_layout}
		result.render_detail=_render_detail.call(arrays,_bounds,data,cancelled,_layout.get("uniform_palette_lod",false))
		result.render_upload=_render_upload.call(arrays,result.render_detail,cancelled)
		if cancelled.call():result={};return
		_source=null


static func height_update_job(source,bounds: Rect2i,layout: Dictionary) -> HeightUpdateJob:
	return HeightUpdateJob.new(source,bounds,layout,normal,render_detail,prepare_render_upload)

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
